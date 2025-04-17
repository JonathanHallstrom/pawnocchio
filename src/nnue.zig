// pawnocchio, UCI chess engine
// Copyright (C) 2025 Jonathan Hallström
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const root = @import("root.zig");
const Board = root.Board;
const Square = root.Square;
const PieceType = root.PieceType;
const Bitboard = root.Bitboard;
const Colour = root.Colour;
const evaluation = root.evaluation;
const Move = root.Move;

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
    return @min(BUCKET_COUNT - 1, (@popCount(board.white | board.black) - 2) / divisor);
}

var weights: Weights = undefined;

const SquarePieceType = struct {
    sq: Square,
    pt: PieceType,
};

const DirtyPiece = struct {
    adds: std.BoundedArray(SquarePieceType, 2) = .{},
    subs: std.BoundedArray(SquarePieceType, 2) = .{},
};

const Accumulator = struct {
    white: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),
    black: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),

    dirty_piece: DirtyPiece = .{},

    white_mirrored: MirroringType,
    black_mirrored: MirroringType,

    added: std.BoundedArray(usize, 256) = .{},
    subed: std.BoundedArray(usize, 256) = .{},

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

    fn idx(comptime perspective: Colour, comptime side: Colour, tp: PieceType, sq: Square, mirror: MirroringType) usize {
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

    pub fn initInPlace(self: *Accumulator, board: *const Board) void {
        self.* = default();
        self.white_mirrored.write(Square.fromBitboard(board.kingFor(.white)).getFile().toInt() >= 4);
        self.black_mirrored.write(Square.fromBitboard(board.kingFor(.black)).getFile().toInt() >= 4);
        self.dirty_piece = .{};
        // std.debug.print("init {}\n", .{acc.white_mirrored.read()});
        // std.debug.print("init {}\n", .{acc.black_mirrored.read()});

        for (PieceType.all) |tp| {
            {
                var iter = Bitboard.iterator(board.pieceFor(.white, tp));
                while (iter.next()) |sq| {
                    // std.debug.print("{} {}\n", .{ tp, sq });
                    self.doAdd(.white, tp, sq);
                }
            }
            {
                var iter = Bitboard.iterator(board.pieceFor(.black, tp));
                while (iter.next()) |sq| {
                    // std.debug.print("{} {}\n", .{ tp, sq });
                    self.doAdd(.black, tp, sq);
                }
            }
        }
    }

    pub fn update(self: *Accumulator, board: *const Board) void {
        switch (board.stm) {
            inline else => |stm| {
                self.applyUpdate(stm, board);
            },
        }
    }

    pub fn init(board: *const Board) Accumulator {
        var acc = default();
        acc.initInPlace(board);
        return acc;
    }

    fn doAdd(self: *Accumulator, comptime side: Colour, tp: PieceType, sq: Square) void {
        const white_idx = idx(.white, side, tp, sq, self.white_mirrored);
        const black_idx = idx(.black, side, tp, sq, self.black_mirrored);
        self.added.appendAssumeCapacity(black_idx);
        for (0..HIDDEN_SIZE) |i| {
            self.white[i] += weights.hidden_layer_weights[white_idx * HIDDEN_SIZE + i];
        }
        for (0..HIDDEN_SIZE) |i| {
            self.black[i] += weights.hidden_layer_weights[black_idx * HIDDEN_SIZE + i];
        }
    }

    fn doAddSub(noalias self: *Accumulator, comptime side: Colour, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square) void {
        const add_white_idx = idx(.white, side, add_tp, add_sq, self.white_mirrored);
        const add_black_idx = idx(.black, side, add_tp, add_sq, self.black_mirrored);
        const sub_white_idx = idx(.white, side, sub_tp, sub_sq, self.white_mirrored);
        const sub_black_idx = idx(.black, side, sub_tp, sub_sq, self.black_mirrored);
        self.added.appendAssumeCapacity(add_black_idx);
        self.subed.appendAssumeCapacity(sub_black_idx);

        for (0..HIDDEN_SIZE) |i| {
            self.white[i] += weights.hidden_layer_weights[add_white_idx * HIDDEN_SIZE + i] - weights.hidden_layer_weights[sub_white_idx * HIDDEN_SIZE + i];
        }
        for (0..HIDDEN_SIZE) |i| {
            self.black[i] += weights.hidden_layer_weights[add_black_idx * HIDDEN_SIZE + i] - weights.hidden_layer_weights[sub_black_idx * HIDDEN_SIZE + i];
        }
    }

    fn doAddSubSub(noalias self: *Accumulator, comptime side: Colour, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square, opp_sub_tp: PieceType, opp_sub_sq: Square) void {
        const add_white_idx = idx(.white, side, add_tp, add_sq, self.white_mirrored);
        const add_black_idx = idx(.black, side, add_tp, add_sq, self.black_mirrored);
        const sub_white_idx = idx(.white, side, sub_tp, sub_sq, self.white_mirrored);
        const sub_black_idx = idx(.black, side, sub_tp, sub_sq, self.black_mirrored);
        const opp_sub_white_idx = idx(.white, side.flipped(), opp_sub_tp, opp_sub_sq, self.white_mirrored);
        const opp_sub_black_idx = idx(.black, side.flipped(), opp_sub_tp, opp_sub_sq, self.black_mirrored);
        self.added.appendAssumeCapacity(add_black_idx);
        self.subed.appendAssumeCapacity(sub_black_idx);
        self.subed.appendAssumeCapacity(opp_sub_black_idx);
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

    fn doAddAddSubSub(noalias self: *Accumulator, comptime side: Colour, add1_tp: PieceType, add1_sq: Square, add2_tp: PieceType, add2_sq: Square, sub1_tp: PieceType, sub1_sq: Square, sub2_tp: PieceType, sub2_sq: Square) void {
        const add1_white_idx = idx(.white, side, add1_tp, add1_sq, self.white_mirrored);
        const add1_black_idx = idx(.black, side, add1_tp, add1_sq, self.black_mirrored);
        const sub1_white_idx = idx(.white, side, sub1_tp, sub1_sq, self.white_mirrored);
        const sub1_black_idx = idx(.black, side, sub1_tp, sub1_sq, self.black_mirrored);

        const add2_white_idx = idx(.white, side, add2_tp, add2_sq, self.white_mirrored);
        const add2_black_idx = idx(.black, side, add2_tp, add2_sq, self.black_mirrored);
        const sub2_white_idx = idx(.white, side, sub2_tp, sub2_sq, self.white_mirrored);
        const sub2_black_idx = idx(.black, side, sub2_tp, sub2_sq, self.black_mirrored);
        self.added.appendAssumeCapacity(add1_black_idx);
        self.subed.appendAssumeCapacity(sub1_black_idx);
        self.added.appendAssumeCapacity(add2_black_idx);
        self.subed.appendAssumeCapacity(sub2_black_idx);

        for (0..HIDDEN_SIZE) |i| {
            self.white[i] +=
                weights.hidden_layer_weights[add1_white_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub1_white_idx * HIDDEN_SIZE + i] +
                weights.hidden_layer_weights[add2_white_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub2_white_idx * HIDDEN_SIZE + i];
        }
        for (0..HIDDEN_SIZE) |i| {
            self.black[i] +=
                weights.hidden_layer_weights[add1_black_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub1_black_idx * HIDDEN_SIZE + i] +
                weights.hidden_layer_weights[add2_black_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub2_black_idx * HIDDEN_SIZE + i];
        }
    }

    pub fn forward(noalias self: *Accumulator, comptime stm: Colour, board: *const Board) i16 {
        // std.debug.print("{any}\n", .{weights.hidden_layer_biases[0..10]});
        // std.debug.print("{any}\n", .{weights.output_biases[0..BUCKET_COUNT]});
        self.applyUpdate(stm, board);
        // std.debug.print("{any}\n", .{self.white[0..10]});
        // std.debug.print("{any}\n", .{self.black[0..10]});
        // if (std.debug.runtime_safety) {
        //     const from_scratch = Accumulator.init(board);
        //     std.testing.expectEqualDeep(from_scratch, self) catch |e| {
        //         @import("main.zig").writeLog("{} {s}\n", .{ board.fullmove_clock * 2 + @intFromBool(board.turn == .black), board.toFen().slice() });
        //         std.debug.panic("{} {s}\n", .{ e, board.toFen().slice() });
        //     };
        //     if (board.turn == .white) {
        //         std.debug.assert(std.meta.eql(self.white, from_scratch.white));
        //     } else {
        //         std.debug.assert(std.meta.eql(self.black, from_scratch.black));
        //     }
        // }
        const us_acc = if (board.stm == .white) &self.white else &self.black;
        const them_acc = if (board.stm == .white) &self.black else &self.white;

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
        const scaled = @divTrunc(res * SCALE, QA * QB);

        const fifty_move_rule_scaled = @divTrunc(scaled * (200 - board.halfmove), 200);
        return evaluation.clampScore(fifty_move_rule_scaled);
    }

    fn refresh(noalias self: *Accumulator, comptime side: Colour, board: *const Board) void {
        if (side == .white) {
            self.white_mirrored.flip();
        } else {
            self.black_mirrored.flip();
        }
        {
            self.initInPlace(board);
            return;
        }
        const us_mirror = if (side == .white)
            self.white_mirrored
        else
            self.black_mirrored;

        const them_mirror = if (side == .white)
            self.black_mirrored
        else
            self.white_mirrored;

        const from = self.dirty_piece.subs.slice()[0];
        const to = self.dirty_piece.adds.slice()[0];

        const us_arr = if (side == .white) &self.white else &self.black;
        const them_arr = if (side == .white) &self.black else &self.white;
        var dont_add_mask: u64 = to.sq.toBitboard();
        if (self.dirty_piece.adds.len == 2) {
            const king_from_sq: Square = from.sq;
            const king_to_sq: Square = to.sq;
            const rook_from_sq: Square = self.dirty_piece.subs.slice()[1].sq;
            const rook_to_sq: Square = self.dirty_piece.adds.slice()[1].sq;
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
            const king_from_sq = self.dirty_piece.subs.slice()[0].sq;
            const king_to_sq = self.dirty_piece.adds.slice()[0].sq;
            const us_add_king_idx = idx(side, side, .king, king_to_sq, us_mirror);
            const them_add_king_idx = idx(side.flipped(), side, .king, king_to_sq, them_mirror);
            const them_sub_king_idx = idx(side.flipped(), side, .king, king_from_sq, them_mirror);
            for (0..HIDDEN_SIZE) |i| {
                us_arr[i] =
                    weights.hidden_layer_biases[i] +
                    weights.hidden_layer_weights[us_add_king_idx * HIDDEN_SIZE + i];
                them_arr[i] +=
                    weights.hidden_layer_weights[them_add_king_idx * HIDDEN_SIZE + i] -
                    weights.hidden_layer_weights[them_sub_king_idx * HIDDEN_SIZE + i];
            }
            if (self.dirty_piece.subs.len == 2) {
                const captured_tp = self.dirty_piece.subs.slice()[1].pt;
                const sub_idx = idx(side.flipped(), side.flipped(), captured_tp, king_to_sq, them_mirror);
                for (0..HIDDEN_SIZE) |i| {
                    them_arr[i] -= weights.hidden_layer_weights[sub_idx * HIDDEN_SIZE + i];
                }
            }
        }
        for (PieceType.all) |tp| {
            {
                var iter = Bitboard.iterator(board.pieceFor(side.flipped(), tp));
                while (iter.next()) |sq| {
                    const add_idx = idx(side, side.flipped(), tp, sq, us_mirror);
                    for (0..HIDDEN_SIZE) |i| {
                        us_arr[i] += weights.hidden_layer_weights[add_idx * HIDDEN_SIZE + i];
                    }
                }
            }
            {
                var iter = Bitboard.iterator(board.pieceFor(side, tp) & ~dont_add_mask);
                while (iter.next()) |sq| {
                    const add_idx = idx(side, side, tp, sq, us_mirror);

                    for (0..HIDDEN_SIZE) |i| {
                        us_arr[i] += weights.hidden_layer_weights[add_idx * HIDDEN_SIZE + i];
                    }
                }
            }
        }
    }

    fn needsRefresh(from: Square, to: Square) bool {
        if (!HORIZONTAL_MIRRORING) return false;
        // std.debug.print("{} {}\n", .{from.getFile(), to.getFile()});
        return (from.getFile().toInt() >= 4) != (to.getFile().toInt() >= 4);
    }

    fn applyUpdate(noalias self: *Accumulator, comptime stm: Colour, board: *const Board) void {
        if (self.dirty_piece.adds.len | self.dirty_piece.subs.len == 0) {
            return;
        }
        defer self.dirty_piece = .{};
        // {
        //     self.initInPlace(board);
        //     return;
        // }
        if (self.dirty_piece.adds.len == 1 and self.dirty_piece.subs.len == 1) {
            const add1 = self.dirty_piece.adds.slice()[0];
            const sub1 = self.dirty_piece.subs.slice()[0];
            if (add1.pt == .king and needsRefresh(add1.sq, sub1.sq)) {
                self.refresh(stm.flipped(), board);
            } else {
                self.doAddSub(stm.flipped(), add1.pt, add1.sq, sub1.pt, sub1.sq);
            }
        } else if (self.dirty_piece.adds.len == 1 and self.dirty_piece.subs.len == 2) {
            const add1 = self.dirty_piece.adds.slice()[0];
            const sub1 = self.dirty_piece.subs.slice()[0];
            const sub2 = self.dirty_piece.subs.slice()[1];
            if (add1.pt == .king and needsRefresh(add1.sq, sub1.sq)) {
                self.refresh(stm.flipped(), board);
            } else {
                self.doAddSubSub(stm.flipped(), add1.pt, add1.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
            }
        } else if (self.dirty_piece.adds.len == 2 and self.dirty_piece.subs.len == 2) {
            const add1 = self.dirty_piece.adds.slice()[0];
            const add2 = self.dirty_piece.adds.slice()[1];
            const sub1 = self.dirty_piece.subs.slice()[0];
            const sub2 = self.dirty_piece.subs.slice()[1];
            // std.debug.print("{} {}\n", .{ add1.sq, sub1.sq });
            if (needsRefresh(add1.sq, sub1.sq)) {
                // std.debug.print("castling refresh\n", .{});
                self.refresh(stm.flipped(), board);
            } else {
                self.doAddAddSubSub(stm.flipped(), add1.pt, add1.sq, add2.pt, add2.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
            }
        } else {
            unreachable;
        }
    }

    pub fn add(self: *State, comptime col: Colour, pt: PieceType, square: Square) void {
        _ = col;
        self.dirty_piece.adds.appendAssumeCapacity(.{ .pt = pt, .sq = square });
    }

    pub fn sub(self: *State, comptime col: Colour, pt: PieceType, square: Square) void {
        _ = col;
        self.dirty_piece.subs.appendAssumeCapacity(.{ .pt = pt, .sq = square });
    }

    pub fn addSub(self: *State, comptime add_col: Colour, add_pt: PieceType, add_square: Square, comptime sub_col: Colour, sub_pt: PieceType, sub_square: Square) void {
        _ = add_col;
        _ = sub_col;
        self.dirty_piece.adds.appendAssumeCapacity(.{ .pt = add_pt, .sq = add_square });
        self.dirty_piece.subs.appendAssumeCapacity(.{ .pt = sub_pt, .sq = sub_square });
    }

    pub fn addSubSub(self: *State, comptime add_col: Colour, add_pt: PieceType, add_square: Square, comptime sub1_col: Colour, sub1_pt: PieceType, sub1_square: Square, comptime sub2_col: Colour, sub2_pt: PieceType, sub2_square: Square) void {
        _ = add_col;
        _ = sub1_col;
        _ = sub2_col;
        self.dirty_piece.adds.appendAssumeCapacity(.{ .pt = add_pt, .sq = add_square });
        self.dirty_piece.subs.appendAssumeCapacity(.{ .pt = sub1_pt, .sq = sub1_square });
        self.dirty_piece.subs.appendAssumeCapacity(.{ .pt = sub2_pt, .sq = sub2_square });
    }

    pub fn addAddSubSub(self: *State, comptime add1_col: Colour, add1_pt: PieceType, add1_square: Square, comptime add2_col: Colour, add2_pt: PieceType, add2_square: Square, comptime sub1_col: Colour, sub1_pt: PieceType, sub1_square: Square, comptime sub2_col: Colour, sub2_pt: PieceType, sub2_square: Square) void {
        _ = add1_col;
        _ = add2_col;
        _ = sub1_col;
        _ = sub2_col;
        self.dirty_piece.adds.appendAssumeCapacity(.{ .pt = add1_pt, .sq = add1_square });
        self.dirty_piece.adds.appendAssumeCapacity(.{ .pt = add2_pt, .sq = add2_square });
        self.dirty_piece.subs.appendAssumeCapacity(.{ .pt = sub1_pt, .sq = sub1_square });
        self.dirty_piece.subs.appendAssumeCapacity(.{ .pt = sub2_pt, .sq = sub2_square });
    }
};

// export fn addExp(self: *Accumulator, tp: *PieceType, sq: *Square) void {
//     const ptr = &weights;
//     std.mem.doNotOptimizeAway(ptr);
//     self.add(.white, tp.*, sq.*);
// }
// export fn addSubExp(self: *Accumulator, addtp: *PieceType, addsq: *Square, subtp: *PieceType, subsq: *Square) void {
//     const ptr = &weights;
//     std.mem.doNotOptimizeAway(ptr);
//     self.addSub(.white, addtp.*, addsq.*, subtp.*, subsq.*);
// }

pub const State = Accumulator;

pub fn evaluate(comptime stm: Colour, board: *const Board, eval_state: *State) i16 {
    return eval_state.forward(stm, board);
}

fn screlu(x: i32) i32 {
    const clamped = std.math.clamp(x, 0, QA);
    return clamped * clamped;
}

pub fn init() void {
    var fbs = std.io.fixedBufferStream(@embedFile("net"));

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
    switch (board.stm) {
        inline else => |stm| {
            return acc.forward(stm, board);
        },
    }
}
const vec_size = @min(HIDDEN_SIZE & -%HIDDEN_SIZE, 2 * (std.simd.suggestVectorLength(i16) orelse 8));

pub const HORIZONTAL_MIRRORING = true;
pub const BUCKET_COUNT: usize = 8;
pub const INPUT_SIZE: usize = 768;
pub const HIDDEN_SIZE: usize = 1024;
pub const SCALE = 400;
pub const QA = 255;
pub const QB = 64;
