const std = @import("std");
const Board = @import("Board.zig");
const Square = @import("square.zig").Square;
const PieceType = @import("piece_type.zig").PieceType;
const Bitboard = @import("Bitboard.zig");
const Side = @import("side.zig").Side;
const eval = @import("eval.zig");
const Move = @import("Move.zig").Move;

fn madd(
    comptime N: comptime_int,
    a: @Vector(N, i16),
    b: @Vector(N, i16),
) @Vector(N / 2, i32) {
    const a0 = @as(@Vector(N / 2, i32), @intCast(std.simd.deinterlace(2, a)[0]));
    const a1 = @as(@Vector(N / 2, i32), @intCast(std.simd.deinterlace(2, a)[1]));
    const b0 = @as(@Vector(N / 2, i32), @intCast(std.simd.deinterlace(2, b)[0]));
    const b1 = @as(@Vector(N / 2, i32), @intCast(std.simd.deinterlace(2, b)[1]));
    return (a0 * b0 + a1 * b1);
}

fn mullo(
    comptime N: comptime_int,
    a: @Vector(N, i16),
    b: @Vector(N, i16),
) @Vector(N, i16) {
    return a *% b;
}

const Weights = struct {
    hidden_layer_weights: [HIDDEN_SIZE * INPUT_SIZE]i16 align(std.atomic.cache_line) = .{0} ** (HIDDEN_SIZE * INPUT_SIZE),
    hidden_layer_biases: [HIDDEN_SIZE]i16 align(std.atomic.cache_line) = .{0} ** HIDDEN_SIZE,
    output_weights: [HIDDEN_SIZE * 2 * BUCKET_COUNT]i16 align(std.atomic.cache_line) = .{0} ** (HIDDEN_SIZE * 2 * BUCKET_COUNT),
    output_biases: [BUCKET_COUNT]i16 align(std.atomic.cache_line) = .{0} ** BUCKET_COUNT,
};

fn whichOutputBucket(board: *const Board) usize {
    const max_piece_count = 32;
    const divisor = (max_piece_count + BUCKET_COUNT - 1) / BUCKET_COUNT;
    return @min(BUCKET_COUNT - 1, (@popCount(board.white.all | board.black.all) - 2) / divisor);
}

var weights: Weights = undefined;

pub const Accumulator = struct {
    white: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),
    black: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),

    white_mirrored: MirroringType,
    black_mirrored: MirroringType,

    const MirroringType = if (HORIZONTAL_MIRRORING) struct {
        data: bool = false,

        pub fn read(self: anytype) bool {
            return self.data;
        }

        pub fn write(self: anytype, val: bool) void {
            self.data = val;
        }

        pub fn flip(self: anytype) void {
            self.data = !self.data;
        }
    } else struct {
        pub fn read(_: anytype) bool {
            return false;
        }

        pub fn write(_: anytype, _: bool) void {}

        pub fn flip(_: anytype) void {}
    };

    fn idx(comptime perspective: Side, comptime side: Side, tp: PieceType, sq: Square, mirror: MirroringType) usize {
        const side_offs: usize = if (perspective == side) 0 else 1;
        const sq_offs: usize = (if (perspective == .black) sq.flipRank().toInt() else sq.toInt()) ^ 7 * @as(usize, @intFromBool(mirror.read()));
        const tp_offs: usize = tp.toInt();
        return side_offs * 64 * 6 + tp_offs * 64 + sq_offs;
    }

    pub fn default() Accumulator {
        return .{
            .white = weights.hidden_layer_biases,
            .black = weights.hidden_layer_biases,
            .white_mirrored = .{},
            .black_mirrored = .{},
        };
    }

    pub fn init(board: *const Board) Accumulator {
        var acc = default();
        acc.white_mirrored.write(Square.fromBitboard(board.white.getBoard(.king)).getFile().toInt() >= 4);
        acc.black_mirrored.write(Square.fromBitboard(board.black.getBoard(.king)).getFile().toInt() >= 4);

        // std.debug.print("init {}\n", .{acc.white_mirrored.read()});
        // std.debug.print("init {}\n", .{acc.black_mirrored.read()});

        for (PieceType.all) |tp| {
            {
                var iter = Bitboard.iterator(board.white.getBoard(tp));
                while (iter.next()) |sq| {
                    acc.add(.white, tp, sq);
                }
            }
            {
                var iter = Bitboard.iterator(board.black.getBoard(tp));
                while (iter.next()) |sq| {
                    acc.add(.black, tp, sq);
                }
            }
        }
        return acc;
    }

    pub fn add(self: *Accumulator, comptime side: Side, tp: PieceType, sq: Square) void {
        // std.debug.print("{s} {}\n", .{ @tagName(side), sq });
        const white_idx = idx(.white, side, tp, sq, self.white_mirrored);
        // std.debug.print("from add {}\n", .{white_idx});
        const black_idx = idx(.black, side, tp, sq, self.black_mirrored);
        // if (tp == .pawn) {
        //     std.debug.print("add {} {}\n", .{black_idx, self.black_mirrored.read()});
        // }
        // std.debug.print("from add {}\n", .{black_idx});
        for (0..HIDDEN_SIZE) |i| {
            self.white[i] += weights.hidden_layer_weights[white_idx * HIDDEN_SIZE + i];
        }
        for (0..HIDDEN_SIZE) |i| {
            self.black[i] += weights.hidden_layer_weights[black_idx * HIDDEN_SIZE + i];
        }
        // {
        //     var i: usize = 0;
        //     while (i + vec_size - 1 < HIDDEN_SIZE) : (i += vec_size) {
        //         const white_vals: @Vector(vec_size, i16) = self.white[i..][0..vec_size].*;
        //         const white_weights: @Vector(vec_size, i16) = weights.hidden_layer_weights[white_idx * HIDDEN_SIZE + i ..][0..vec_size].*;
        //         const white_sum: [vec_size]i16 = white_vals + white_weights;
        //         @memcpy(self.white[i..][0..vec_size], &white_sum);
        //     }
        // }
        // {
        //     var i: usize = 0;
        //     while (i + vec_size - 1 < HIDDEN_SIZE) : (i += vec_size) {
        //         const black_vals: @Vector(vec_size, i16) = self.black[i..][0..vec_size].*;
        //         const black_weights: @Vector(vec_size, i16) = weights.hidden_layer_weights[black_idx * HIDDEN_SIZE + i ..][0..vec_size].*;
        //         const black_sum: [vec_size]i16 = black_vals + black_weights;
        //         @memcpy(self.black[i..][0..vec_size], &black_sum);
        //     }
        // }
    }

    pub fn addSub(noalias self: *Accumulator, comptime side: Side, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square) void {
        const add_white_idx = idx(.white, side, add_tp, add_sq, self.white_mirrored);
        const add_black_idx = idx(.black, side, add_tp, add_sq, self.black_mirrored);
        const sub_white_idx = idx(.white, side, sub_tp, sub_sq, self.white_mirrored);
        const sub_black_idx = idx(.black, side, sub_tp, sub_sq, self.black_mirrored);

        for (0..HIDDEN_SIZE) |i| {
            self.white[i] += weights.hidden_layer_weights[add_white_idx * HIDDEN_SIZE + i] - weights.hidden_layer_weights[sub_white_idx * HIDDEN_SIZE + i];
        }
        for (0..HIDDEN_SIZE) |i| {
            self.black[i] += weights.hidden_layer_weights[add_black_idx * HIDDEN_SIZE + i] - weights.hidden_layer_weights[sub_black_idx * HIDDEN_SIZE + i];
        }
        // {
        //     var i: usize = 0;
        //     while (i + vec_size - 1 < HIDDEN_SIZE) : (i += vec_size) {
        //         const white_vals: @Vector(vec_size, i16) = self.white[i..][0..vec_size].*;
        //         const white_add_weights: @Vector(vec_size, i16) = weights.hidden_layer_weights[add_white_idx * HIDDEN_SIZE + i ..][0..vec_size].*;
        //         const white_sub_weights: @Vector(vec_size, i16) = weights.hidden_layer_weights[sub_white_idx * HIDDEN_SIZE + i ..][0..vec_size].*;
        //         const white_sum: [vec_size]i16 = white_vals + white_add_weights - white_sub_weights;
        //         @memcpy(self.white[i..][0..vec_size], &white_sum);
        //     }
        // }
        // {
        //     var i: usize = 0;
        //     while (i + vec_size - 1 < HIDDEN_SIZE) : (i += vec_size) {
        //         const black_vals: @Vector(vec_size, i16) = self.black[i..][0..vec_size].*;
        //         const black_add_weights: @Vector(vec_size, i16) = weights.hidden_layer_weights[add_black_idx * HIDDEN_SIZE + i ..][0..vec_size].*;
        //         const black_sub_weights: @Vector(vec_size, i16) = weights.hidden_layer_weights[sub_black_idx * HIDDEN_SIZE + i ..][0..vec_size].*;
        //         const black_sum: [vec_size]i16 = black_vals + black_add_weights - black_sub_weights;
        //         @memcpy(self.black[i..][0..vec_size], &black_sum);
        //     }
        // }
    }

    pub fn addSubSub(noalias self: *Accumulator, comptime side: Side, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square, opp_sub_tp: PieceType, opp_sub_sq: Square) void {
        const add_white_idx = idx(.white, side, add_tp, add_sq, self.white_mirrored);
        const add_black_idx = idx(.black, side, add_tp, add_sq, self.black_mirrored);
        const sub_white_idx = idx(.white, side, sub_tp, sub_sq, self.white_mirrored);
        const sub_black_idx = idx(.black, side, sub_tp, sub_sq, self.black_mirrored);
        const opp_sub_white_idx = idx(.white, side.flipped(), opp_sub_tp, opp_sub_sq, self.white_mirrored);
        const opp_sub_black_idx = idx(.black, side.flipped(), opp_sub_tp, opp_sub_sq, self.black_mirrored);
        for (0..HIDDEN_SIZE) |i| {
            self.white[i] +=
                weights.hidden_layer_weights[add_white_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub_white_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[opp_sub_white_idx * HIDDEN_SIZE + i];
        }
        for (0..HIDDEN_SIZE) |i| {
            self.black[i] +=
                weights.hidden_layer_weights[add_black_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub_black_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[opp_sub_black_idx * HIDDEN_SIZE + i];
        }
    }

    pub fn forward(self: Accumulator, board: *const Board) i16 {
        if (std.debug.runtime_safety) {
            const from_scratch = Accumulator.init(board);
            std.testing.expectEqualDeep(from_scratch, self) catch |e| {
                @import("main.zig").writeLog("{} {s}\n", .{ board.fullmove_clock * 2 + @intFromBool(board.turn == .black), board.toFen().slice() });
                std.debug.panic("{} {s}\n", .{ e, board.toFen().slice() });
            };
            if (board.turn == .white) {
                std.debug.assert(std.meta.eql(self.white, from_scratch.white));
            } else {
                std.debug.assert(std.meta.eql(self.black, from_scratch.black));
            }
        }
        const us_acc = if (board.turn == .white) &self.white else &self.black;
        const them_acc = if (board.turn == .white) &self.black else &self.white;

        //                  vvvvvvvv annotation to help zls
        const Vec16 = @as(type, @Vector(vec_size, i16));
        var acc: @Vector(vec_size / 2, i32) = @splat(0);
        const vz: Vec16 = @splat(0);
        const vqa: Vec16 = @splat(QA);
        var i: usize = 0;
        const which_bucket = whichOutputBucket(board);
        const bucket_offset = which_bucket * HIDDEN_SIZE * 2;
        while (i < HIDDEN_SIZE) : (i += vec_size) {
            const us: Vec16 = us_acc[i..][0..vec_size].*;
            const us_clamped: Vec16 = @max(@min(us, vqa), vz);
            const them: Vec16 = them_acc[i..][0..vec_size].*;
            const them_clamped: Vec16 = @max(@min(them, vqa), vz);

            const us_weights: Vec16 = weights.output_weights[bucket_offset..][i..][0..vec_size].*;
            const them_weights: Vec16 = weights.output_weights[bucket_offset..][i + HIDDEN_SIZE ..][0..vec_size].*;

            acc += madd(vec_size, mullo(vec_size, us_weights, us_clamped), us_clamped);
            acc += madd(vec_size, mullo(vec_size, them_weights, them_clamped), them_clamped);
        }

        var res: i32 = @reduce(std.builtin.ReduceOp.Add, acc);
        if (std.debug.runtime_safety) {
            var verify_res: i32 = 0;
            for (0..HIDDEN_SIZE) |j| {
                verify_res += screlu(us_acc[j]) * weights.output_weights[bucket_offset..][j];
                verify_res += screlu(them_acc[j]) * weights.output_weights[bucket_offset..][j + HIDDEN_SIZE];
            }
            std.debug.assert(res == verify_res);
        }
        res = @divTrunc(res, QA); // res /= QA

        res += weights.output_biases[which_bucket];

        return eval.clampScore(@divTrunc(res * SCALE, QA * QB)); // res * SCALE / (QA * QB)
    }

    pub fn needsRefresh(board: *const Board, move: Move) bool {
        if (!HORIZONTAL_MIRRORING) return false;
        const is_moving_across_middle = (move.getFrom().getFile().toInt() <= 3) != (move.getTo().getFile().toInt() <= 3);
        const is_king = board.mailbox[move.getFrom().toInt()] == .king;
        const is_king_moving_across_middle = is_king and is_moving_across_middle;
        return is_king_moving_across_middle;
    }

    pub fn refresh(noalias self: *Accumulator, comptime side: Side, board: *const Board, move: Move) void {
        if (side == .white) {
            self.white_mirrored.flip();
        } else {
            self.black_mirrored.flip();
        }
        const us_mirror = if (side == .white)
            self.white_mirrored
        else
            self.black_mirrored;

        const them_mirror = if (side == .white)
            self.black_mirrored
        else
            self.white_mirrored;

        const us_arr = if (side == .white) &self.white else &self.black;
        const them_arr = if (side == .white) &self.black else &self.white;
        var dont_add_mask: u64 = move.getTo().toBitboard();
        if (move.isCastlingMove()) {
            const king_from_sq = move.getFrom();
            std.debug.assert(board.mailbox[king_from_sq.toInt()] == .king);
            const king_to_sq = move.getCastlingKingDest(side);
            std.debug.assert(board.mailbox[king_to_sq.toInt()] == null);
            const rook_from_sq = move.getTo();
            std.debug.assert(board.mailbox[rook_from_sq.toInt()] == .rook);
            const rook_to_sq = move.getCastlingRookDest(side);
            dont_add_mask |= rook_from_sq.toBitboard();

            const us_add_king_idx = idx(side, side, .king, king_to_sq, us_mirror);
            const them_add_king_idx = idx(side.flipped(), side, .king, king_to_sq, them_mirror);
            const them_sub_king_idx = idx(side.flipped(), side, .king, king_from_sq, them_mirror);

            const us_add_rook_idx = idx(side, side, .rook, rook_to_sq, us_mirror);
            const them_add_rook_idx = idx(side.flipped(), side, .rook, rook_to_sq, them_mirror);
            const them_sub_rook_idx = idx(side.flipped(), side, .rook, rook_from_sq, them_mirror);
            for (0..HIDDEN_SIZE) |i| {
                us_arr[i] =
                    weights.hidden_layer_biases[i] +
                    weights.hidden_layer_weights[us_add_king_idx * HIDDEN_SIZE + i] +
                    weights.hidden_layer_weights[us_add_rook_idx * HIDDEN_SIZE + i];
                them_arr[i] +=
                    weights.hidden_layer_weights[them_add_king_idx * HIDDEN_SIZE + i] -
                    weights.hidden_layer_weights[them_sub_king_idx * HIDDEN_SIZE + i] +
                    weights.hidden_layer_weights[them_add_rook_idx * HIDDEN_SIZE + i] -
                    weights.hidden_layer_weights[them_sub_rook_idx * HIDDEN_SIZE + i];
            }
        } else {
            const king_from_sq = move.getFrom();
            const king_to_sq = move.getTo();
            // std.debug.print("{} {} {} {}\n", .{ king_from_sq, king_to_sq, us_mirror.read(), them_mirror.read() });
            const us_add_king_idx = idx(side, side, .king, king_to_sq, us_mirror);
            // std.debug.print("from refresh {}\n", .{us_add_king_idx});
            const them_add_king_idx = idx(side.flipped(), side, .king, king_to_sq, them_mirror);
            // std.debug.print("from refresh {}\n", .{them_add_king_idx});
            const them_sub_king_idx = idx(side.flipped(), side, .king, king_from_sq, them_mirror);
            for (0..HIDDEN_SIZE) |i| {
                us_arr[i] =
                    weights.hidden_layer_biases[i] +
                    weights.hidden_layer_weights[us_add_king_idx * HIDDEN_SIZE + i];
                them_arr[i] +=
                    weights.hidden_layer_weights[them_add_king_idx * HIDDEN_SIZE + i] -
                    weights.hidden_layer_weights[them_sub_king_idx * HIDDEN_SIZE + i];
            }
            if (move.isCapture()) {
                const captured_tp = board.mailbox[king_to_sq.toInt()].?;
                const sub_idx = idx(side.flipped(), side.flipped(), captured_tp, king_to_sq, them_mirror);
                for (0..HIDDEN_SIZE) |i| {
                    them_arr[i] -= weights.hidden_layer_weights[sub_idx * HIDDEN_SIZE + i];
                }
            }
        }
        const us = board.getSide(side);
        const them = board.getSide(side.flipped());
        for (PieceType.all) |tp| {
            {
                var iter = Bitboard.iterator(them.getBoard(tp) & ~dont_add_mask);
                while (iter.next()) |sq| {
                    const add_idx = idx(side, side.flipped(), tp, sq, us_mirror);
                    for (0..HIDDEN_SIZE) |i| {
                        us_arr[i] += weights.hidden_layer_weights[add_idx * HIDDEN_SIZE + i];
                    }
                }
            }
            {
                var iter = Bitboard.iterator(us.getBoard(tp) & ~dont_add_mask);
                while (iter.next()) |sq| {
                    const add_idx = idx(side, side, tp, sq, us_mirror);

                    for (0..HIDDEN_SIZE) |i| {
                        us_arr[i] += weights.hidden_layer_weights[add_idx * HIDDEN_SIZE + i];
                    }
                }
            }
        }
    }

    pub fn updateWith(self: Accumulator, comptime turn: Side, board: *const Board, move: Move) Accumulator {
        // @import("main.zig").writeLog("update: {s} ply: {} move: {s} needs refresh: {}\n", .{
        //     board.toFen().slice(),
        //     board.fullmove_clock * 2 + @intFromBool(board.turn == .black),
        //     move.toString(false).slice(),
        //     needsRefresh(board, move),
        // });
        const from = move.getFrom();
        const to = move.getTo();
        const from_type = board.mailbox[from.toInt()].?;
        const to_type = if (move.isPromotion()) move.getPromotedPieceType().? else from_type;
        var res = self;
        if (needsRefresh(board, move)) {
            res.refresh(turn, board, move);
            return res;
        }
        if (move.isCapture()) {
            if (move.isEnPassant()) {
                res.addSubSub(turn, .pawn, to, .pawn, from, .pawn, move.getEnPassantPawn(turn));
            } else {
                res.addSubSub(turn, to_type, to, from_type, from, board.mailbox[to.toInt()].?, to);
            }
        } else {
            if (move.isCastlingMove()) {
                res.addSub(turn, .king, move.getCastlingKingDest(turn), .king, from);
                res.addSub(turn, .rook, move.getCastlingRookDest(turn), .rook, to);
            } else {
                res.addSub(turn, to_type, to, from_type, from);
            }
        }

        return res;
    }

    pub fn negate(self: Accumulator) Accumulator {
        return self;
    }
};

// export fn addExp(self: *Accumulator, tp: *PieceType, sq: *Square) void {
//     const ptr = &weights;
//     std.mem.doNotOptimizeAway(ptr);
//     self.add(.white, tp.*, sq.*);
// }
export fn addSubExp(self: *Accumulator, addtp: *PieceType, addsq: *Square, subtp: *PieceType, subsq: *Square) void {
    const ptr = &weights;
    std.mem.doNotOptimizeAway(ptr);
    self.addSub(.white, addtp.*, addsq.*, subtp.*, subsq.*);
}

pub const EvalState = Accumulator;

pub fn evaluate(board: *const Board, eval_state: EvalState) i16 {
    return eval_state.forward(board);
}

fn screlu(x: i32) i32 {
    const clamped = std.math.clamp(x, 0, QA);
    return clamped * clamped;
}

pub fn init() void {
    var fbs = std.io.fixedBufferStream(@embedFile("networks/net13_01_640_200_8_mirrored.nnue"));

    // first read the weights for the first layer (there should be HIDDEN_SIZE * INPUT_SIZE of them)
    for (0..weights.hidden_layer_weights.len) |i| {
        weights.hidden_layer_weights[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then the biases for the first layer (there should be HIDDEN_SIZE of them)
    for (0..weights.hidden_layer_biases.len) |i| {
        weights.hidden_layer_biases[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then the weights for the second layer (there should be HIDDEN_SIZE * 2 of them)
    for (0..weights.output_weights.len) |i| {
        weights.output_weights[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then finally the bias(es)
    for (0..weights.output_biases.len) |i| {
        weights.output_biases[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }
}

pub fn nnEval(board: *const Board) i16 {
    var acc = Accumulator.init(board);

    return acc.forward(board);
}
const vec_size = @min(HIDDEN_SIZE & -%HIDDEN_SIZE, 2 * (std.simd.suggestVectorLength(i16) orelse 8));

pub const HORIZONTAL_MIRRORING = true;
pub const BUCKET_COUNT: usize = 8;
pub const INPUT_SIZE: usize = 768;
pub const HIDDEN_SIZE: usize = 640;
pub const SCALE = 400;
pub const QA = 255;
pub const QB = 64;
