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

const builtin = @import("builtin");
const CAN_VERBATIM_NET = builtin.cpu.arch.endian() == .little and builtin.mode == .ReleaseFast and !build_options.runtime_net;
const build_options = @import("build_options");

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

const Weights = extern struct {
    hidden_layer_weights: [HIDDEN_SIZE * INPUT_SIZE * INPUT_BUCKET_COUNT]i16 align(std.atomic.cache_line),
    hidden_layer_biases: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),
    output_weights: [HIDDEN_SIZE * 2 * OUTPUT_BUCKET_COUNT]i16 align(std.atomic.cache_line),
    output_biases: [OUTPUT_BUCKET_COUNT]i16 align(std.atomic.cache_line),
    const WEIGHT_COUNT = blk: {
        var res = 0;
        for (std.meta.fields(Weights)) |field| {
            res += @typeInfo(field.type).array.len;
        }
        break :blk res;
    };
};

pub inline fn whichInputBucket(stm: Colour, king_square: Square) usize {
    if (INPUT_BUCKET_COUNT == 1) {
        return 0;
    }
    return INPUT_BUCKET_LAYOUT[(if (stm == .white) king_square else king_square.flipRank()).toInt()];
}

pub inline fn whichOutputBucket(board: *const Board) usize {
    const max_piece_count = 32;
    const divisor = (max_piece_count + OUTPUT_BUCKET_COUNT - 1) / OUTPUT_BUCKET_COUNT;
    return @min(OUTPUT_BUCKET_COUNT - 1, (@popCount(board.white | board.black) - 2) / divisor);
}

var weights_file: std.fs.File = undefined;
var mapped_weights: []align(std.heap.pageSize()) const u8 = undefined;
const verbatim_weights = if (CAN_VERBATIM_NET)
blk: {
    var res: Weights = undefined;
    @memcpy(std.mem.asBytes(&res)[0 .. Weights.WEIGHT_COUNT * @sizeOf(i16)], @embedFile("net")[0 .. Weights.WEIGHT_COUNT * @sizeOf(i16)]);
    break :blk res;
} else undefined;

pub var weights = if (CAN_VERBATIM_NET) &verbatim_weights else if (build_options.runtime_net) @as(*const Weights, undefined) else &(struct {
    var backing: Weights = undefined;
}).backing;
// @ptrCast(@alignCast(@as(*const anyopaque, @ptrCast(@embedFile("net")))));
inline fn hiddenLayerWeightsVector() []const @Vector(VEC_SIZE, i16) {
    return @as([*]const @Vector(VEC_SIZE, i16), @ptrCast(&weights.hidden_layer_weights))[0 .. weights.hidden_layer_weights.len / VEC_SIZE];
}

const SquarePieceType = struct {
    sq: Square,
    pt: PieceType,
};

const DirtyPiece = struct {
    adds: std.BoundedArray(SquarePieceType, 2) = .{},
    subs: std.BoundedArray(SquarePieceType, 2) = .{},
};

pub const MirroringType = if (HORIZONTAL_MIRRORING) struct {
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

pub fn idx(comptime perspective: Colour, comptime side: Colour, king_sq: Square, tp: PieceType, sq: Square, mirror: MirroringType) usize {
    const bucket_offs = whichInputBucket(perspective, king_sq) * INPUT_SIZE;
    const side_offs: usize = if (perspective == side) 0 else 1;
    const sq_offs: usize = (if (perspective == .black) sq.flipRank().toInt() else sq.toInt()) ^ 7 * @as(usize, @intFromBool(mirror.read()));
    const tp_offs: usize = tp.toInt();
    return bucket_offs + side_offs * 64 * 6 + tp_offs * 64 + sq_offs;
}

fn vecIdx(comptime perspective: Colour, comptime side: Colour, king_sq: Square, tp: PieceType, sq: Square, mirror: MirroringType) usize {
    return idx(perspective, side, king_sq, tp, sq, mirror) * HIDDEN_SIZE / VEC_SIZE;
}

const Accumulator = struct {
    white: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),
    black: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),

    dirty_piece: DirtyPiece,

    white_mirrored: MirroringType,
    black_mirrored: MirroringType,

    pub inline fn default() Accumulator {
        return .{
            .white = weights.hidden_layer_biases,
            .black = weights.hidden_layer_biases,
            .white_mirrored = .{},
            .black_mirrored = .{},
            .dirty_piece = .{},
        };
    }

    inline fn accFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *align(std.atomic.cache_line) [HIDDEN_SIZE]i16) {
        return if (col == .white) &self.white else &self.black;
    }

    inline fn vecAccFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *[HIDDEN_SIZE / VEC_SIZE]@Vector(VEC_SIZE, i16)) {
        return @ptrCast(if (col == .white) &self.white else &self.black);
    }

    inline fn mirrorFor(self: anytype, col: Colour) MirroringType {
        return if (col == .white) self.white_mirrored else self.black_mirrored;
    }

    inline fn mirrorPtrFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *MirroringType) {
        return if (col == .white) &self.white_mirrored else &self.black_mirrored;
    }

    pub fn initInPlace(self: *Accumulator, board: *const Board) void {
        self.* = default();
        self.white_mirrored.write(Square.fromBitboard(board.kingFor(.white)).getFile().toInt() >= 4);
        self.black_mirrored.write(Square.fromBitboard(board.kingFor(.black)).getFile().toInt() >= 4);
        self.dirty_piece = .{};

        const white_king_sq = Square.fromBitboard(board.kingFor(.white));
        const black_king_sq = Square.fromBitboard(board.kingFor(.black));
        for (PieceType.all) |tp| {
            {
                var iter = Bitboard.iterator(board.pieceFor(.white, tp));
                while (iter.next()) |sq| {
                    self.doAdd(.white, .white, white_king_sq, tp, sq);
                    self.doAdd(.black, .white, black_king_sq, tp, sq);
                }
            }
            {
                var iter = Bitboard.iterator(board.pieceFor(.black, tp));
                while (iter.next()) |sq| {
                    self.doAdd(.white, .black, white_king_sq, tp, sq);
                    self.doAdd(.black, .black, black_king_sq, tp, sq);
                }
            }
        }
    }

    pub fn update(self: *Accumulator, board: *const Board, old_board: *const Board) void {
        switch (board.stm) {
            inline else => |stm| {
                self.applyUpdate(stm.flipped(), board, old_board);
            },
        }
    }

    pub fn init(board: *const Board) Accumulator {
        var acc = default();
        acc.initInPlace(board);
        return acc;
    }

    fn doAdd(self: *Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, tp: PieceType, sq: Square) void {
        const add_idx = vecIdx(acc, side, king_sq, tp, sq, self.mirrorFor(acc));

        for (0..HIDDEN_SIZE / VEC_SIZE) |i| {
            self.vecAccFor(acc)[i] += hiddenLayerWeightsVector()[add_idx + i];
        }
    }

    fn doAddSub(noalias self: *Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square) void {
        const add_idx = vecIdx(acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc));
        const sub_idx = vecIdx(acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc));

        for (0..HIDDEN_SIZE / VEC_SIZE) |i| {
            self.vecAccFor(acc)[i] += hiddenLayerWeightsVector()[add_idx + i] -
                hiddenLayerWeightsVector()[sub_idx + i];
        }
    }

    fn doAddSubSub(noalias self: *Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square, opp_sub_tp: PieceType, opp_sub_sq: Square) void {
        const add_idx = vecIdx(acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc));
        const sub_idx = vecIdx(acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc));
        const opp_sub_idx = vecIdx(acc, side.flipped(), king_sq, opp_sub_tp, opp_sub_sq, self.mirrorFor(acc));
        for (0..HIDDEN_SIZE / VEC_SIZE) |i| {
            self.vecAccFor(acc)[i] +=
                hiddenLayerWeightsVector()[add_idx + i] -
                hiddenLayerWeightsVector()[sub_idx + i] -
                hiddenLayerWeightsVector()[opp_sub_idx + i];
        }
    }

    fn doAddAddSubSub(noalias self: *Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add1_tp: PieceType, add1_sq: Square, add2_tp: PieceType, add2_sq: Square, sub1_tp: PieceType, sub1_sq: Square, sub2_tp: PieceType, sub2_sq: Square) void {
        const add1_idx = vecIdx(acc, side, king_sq, add1_tp, add1_sq, self.mirrorFor(acc));
        const sub1_idx = vecIdx(acc, side, king_sq, sub1_tp, sub1_sq, self.mirrorFor(acc));
        const add2_idx = vecIdx(acc, side, king_sq, add2_tp, add2_sq, self.mirrorFor(acc));
        const sub2_idx = vecIdx(acc, side, king_sq, sub2_tp, sub2_sq, self.mirrorFor(acc));

        for (0..HIDDEN_SIZE / VEC_SIZE) |i| {
            self.vecAccFor(acc)[i] +=
                hiddenLayerWeightsVector()[add1_idx + i] -
                hiddenLayerWeightsVector()[sub1_idx + i] +
                hiddenLayerWeightsVector()[add2_idx + i] -
                hiddenLayerWeightsVector()[sub2_idx + i];
        }
    }

    pub fn forward(noalias self: *Accumulator, comptime stm: Colour, board: *const Board, old_board: *const Board) i16 {
        // std.debug.print("{any}\n", .{(&weights.hidden_layer_biases)[0..10]});
        // std.debug.print("{any}\n", .{(&weights.output_biases)[0..BUCKET_COUNT]});
        self.applyUpdate(stm.flipped(), board, old_board);
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

        //                vvvvvvvv annotation to help zls
        const Vec = @as(type, @Vector(VEC_SIZE, i16));

        const ACC_COUNT = comptime std.math.gcd(4, HIDDEN_SIZE / VEC_SIZE);
        var accs = std.mem.zeroes([ACC_COUNT]@Vector(VEC_SIZE / 2, i32));
        const ZERO: Vec = @splat(0);
        const ONE: Vec = @splat(QA);
        var i: usize = 0;
        const which_bucket = whichOutputBucket(board);
        const bucket_offset = which_bucket * HIDDEN_SIZE * 2;
        while (i < HIDDEN_SIZE) {
            inline for (&accs) |*acc| {
                defer i += VEC_SIZE;
                const us: Vec = us_acc[i..][0..VEC_SIZE].*;
                const us_clamped: Vec = @max(@min(us, ONE), ZERO);
                const them: Vec = them_acc[i..][0..VEC_SIZE].*;
                const them_clamped: Vec = @max(@min(them, ONE), ZERO);

                const us_weights: Vec = (&weights.output_weights)[bucket_offset..][i..][0..VEC_SIZE].*;
                const them_weights: Vec = (&weights.output_weights)[bucket_offset..][i + HIDDEN_SIZE ..][0..VEC_SIZE].*;

                acc.* +=
                    madd(VEC_SIZE, mullo(VEC_SIZE, us_weights, us_clamped), us_clamped) +
                    madd(VEC_SIZE, mullo(VEC_SIZE, them_weights, them_clamped), them_clamped);
            }
        }
        var acc = accs[0];
        for (accs[1..]) |tmp| acc += tmp;
        var res: i32 = @reduce(std.builtin.ReduceOp.Add, acc);
        if (@import("builtin").mode == .Debug) {
            var verify_res: i32 = 0;
            for (0..HIDDEN_SIZE) |j| {
                verify_res += screlu(us_acc[j]) * (&weights.output_weights)[bucket_offset..][j];
                verify_res += screlu(them_acc[j]) * (&weights.output_weights)[bucket_offset..][j + HIDDEN_SIZE];
            }
            std.debug.assert(res == verify_res);
        }
        res = @divTrunc(res, QA); // res /= QA

        res += (&weights.output_biases)[which_bucket];
        const scaled = @divTrunc(res * SCALE, QA * QB);

        return evaluation.clampScore(scaled);
    }

    fn needsRefresh(stm: Colour, from: Square, to: Square) bool {
        if (HORIZONTAL_MIRRORING and (from.getFile().toInt() >= 4) != (to.getFile().toInt() >= 4)) {
            return true;
        }
        return whichInputBucket(stm, from) != whichInputBucket(stm, to);
    }

    fn applyUpdate(noalias self: *Accumulator, comptime stm: Colour, board: *const Board, old_board: *const Board) void {
        if (self.dirty_piece.adds.len | self.dirty_piece.subs.len == 0) {
            return;
        }
        defer self.dirty_piece = .{};
        // std.debug.print("--------\n", .{});
        // std.debug.print("{}\n", .{stm});
        // defer if (@import("builtin").mode == .Debug) {
        //     const correct = Accumulator.init(board);
        //     if (!std.meta.eql(correct.white, self.white)) {
        //         unreachable;
        //     }
        //     if (!std.meta.eql(correct.black, self.black)) {
        //         unreachable;
        //     }
        // };
        // {
        //     self.initInPlace(board);
        //     return;
        // }
        const us_king_sq = Square.fromBitboard(board.kingFor(stm));
        const them_king_sq = Square.fromBitboard(board.kingFor(stm.flipped()));
        if (self.dirty_piece.adds.len == 1 and self.dirty_piece.subs.len == 1) {
            const add1 = self.dirty_piece.adds.slice()[0];
            const sub1 = self.dirty_piece.subs.slice()[0];
            // std.debug.print("{} {}\n", .{ add1, sub1 });
            self.doAddSub(stm.flipped(), stm, them_king_sq, add1.pt, add1.sq, sub1.pt, sub1.sq);
            if (add1.pt == .king and needsRefresh(stm, add1.sq, sub1.sq)) {
                // std.debug.print("refresh\n", .{});
                // self.mirrorFor(col: Colour)
                refresh_cache.store(stm, old_board, self.accFor(stm));
                self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                refresh_cache.refresh(stm, board, self.accFor(stm));
            } else {
                self.doAddSub(stm, stm, us_king_sq, add1.pt, add1.sq, sub1.pt, sub1.sq);
            }
        } else if (self.dirty_piece.adds.len == 1 and self.dirty_piece.subs.len == 2) {
            const add1 = self.dirty_piece.adds.slice()[0];
            const sub1 = self.dirty_piece.subs.slice()[0];
            const sub2 = self.dirty_piece.subs.slice()[1];
            self.doAddSubSub(stm.flipped(), stm, them_king_sq, add1.pt, add1.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
            if (add1.pt == .king and needsRefresh(stm, add1.sq, sub1.sq)) {
                refresh_cache.store(stm, old_board, self.accFor(stm));
                self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                refresh_cache.refresh(stm, board, self.accFor(stm));
            } else {
                self.doAddSubSub(stm, stm, us_king_sq, add1.pt, add1.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
            }
        } else if (self.dirty_piece.adds.len == 2 and self.dirty_piece.subs.len == 2) {
            const add1 = self.dirty_piece.adds.slice()[0];
            const add2 = self.dirty_piece.adds.slice()[1];
            const sub1 = self.dirty_piece.subs.slice()[0];
            const sub2 = self.dirty_piece.subs.slice()[1];
            // std.debug.print("{} {}\n", .{ add1.sq, sub1.sq });
            self.doAddAddSubSub(stm.flipped(), stm, them_king_sq, add1.pt, add1.sq, add2.pt, add2.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
            if (needsRefresh(stm, add1.sq, sub1.sq)) {
                // std.debug.print("castling refresh\n", .{});
                // std.debug.print("{} {s}\n", .{stm, old_board.toFen().slice()});
                refresh_cache.store(stm, old_board, self.accFor(stm));
                self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                refresh_cache.refresh(stm, board, self.accFor(stm));
            } else {
                self.doAddAddSubSub(stm, stm, us_king_sq, add1.pt, add1.sq, add2.pt, add2.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
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

pub fn evaluate(comptime stm: Colour, board: *const Board, old_board: *const Board, eval_state: *State) i16 {
    return eval_state.forward(stm, board, old_board);
}

fn screlu(x: i32) i32 {
    const clamped = std.math.clamp(x, 0, QA);
    return clamped * clamped;
}

pub fn init() !void {
    if (build_options.runtime_net) {
        weights_file = try std.fs.openFileAbsolute(build_options.net_path, .{});
        if (@import("builtin").target.os.tag == .windows) {
            @compileError("sorry mmap-ing the network manually is not supported on windows");
        }
        mapped_weights = try std.posix.mmap(null, Weights.WEIGHT_COUNT * @sizeOf(i16), std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, weights_file.handle, 0);

        weights = @ptrCast(mapped_weights.ptr);

        return;
    }

    if (CAN_VERBATIM_NET) {
        return;
    }

    var fbs = std.io.fixedBufferStream(@embedFile("net"));

    // first read the weights for the first layer (there should be HIDDEN_SIZE * INPUT_SIZE of them)
    for (0..(&weights.hidden_layer_weights).len) |i| {
        (&weights.hidden_layer_weights)[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then the biases for the first layer (there should be HIDDEN_SIZE of them)
    for (0..(&weights.hidden_layer_biases).len) |i| {
        (&weights.hidden_layer_biases)[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then the weights for the second layer (there should be HIDDEN_SIZE * 2 of them)
    for (0..(&weights.output_weights).len) |i| {
        (&weights.output_weights)[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then finally the bias(es)
    for (0..(&weights.output_biases).len) |i| {
        (&weights.output_biases)[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }
    // std.debug.print("{any}\n", .{(&weights.hidden_layer_biases)});
}

pub fn deinit() void {
    if (CAN_VERBATIM_NET) {
        return;
    }
    if (!build_options.runtime_net) {
        return;
    }

    weights_file.close();
    std.posix.munmap(mapped_weights);
}

pub fn initThreadLocals() void {
    refresh_cache.initInPlace();
}

pub fn nnEval(board: *const Board) i16 {
    var acc = Accumulator.init(board);
    switch (board.stm) {
        inline else => |stm| {
            return acc.forward(stm, board, &.{});
        },
    }
}

threadlocal var refresh_cache: root.refreshCache(HORIZONTAL_MIRRORING, INPUT_BUCKET_COUNT) = undefined;
pub const VEC_SIZE = @min(HIDDEN_SIZE & -%HIDDEN_SIZE, 2 * (std.simd.suggestVectorLength(i16) orelse 8));
pub const HORIZONTAL_MIRRORING = true;
pub const INPUT_BUCKET_COUNT: usize = 8;
pub const OUTPUT_BUCKET_COUNT: usize = 8;
pub const INPUT_SIZE: usize = 768;
pub const HIDDEN_SIZE: usize = 1280;
pub const SCALE = 400;
pub const QA = 255;
pub const QB = 64;
pub const INPUT_BUCKET_LAYOUT: [64]u8 = .{
    0, 0, 1, 2, 2, 1, 0, 0,
    3, 3, 4, 4, 4, 4, 3, 3,
    5, 5, 5, 5, 5, 5, 5, 5,
    6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6,
    7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7,
};
