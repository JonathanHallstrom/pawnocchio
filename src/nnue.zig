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
    hidden_layer_weights: [HIDDEN_SIZE * INPUT_SIZE * INPUT_BUCKET_COUNT]i16 align(std.atomic.cache_line),
    hidden_layer_biases: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),
    output_weights: [HIDDEN_SIZE * 2 * OUTPUT_BUCKET_COUNT]i16 align(std.atomic.cache_line),
    output_biases: [OUTPUT_BUCKET_COUNT]i16 align(std.atomic.cache_line),
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

pub var weights: Weights = undefined;

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

const Accumulator = struct {
    white: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),
    black: [HIDDEN_SIZE]i16 align(std.atomic.cache_line),

    dirty_piece: DirtyPiece = .{},

    white_mirrored: MirroringType,
    black_mirrored: MirroringType,

    pub fn default() Accumulator {
        return .{
            .white = weights.hidden_layer_biases,
            .black = weights.hidden_layer_biases,
            .white_mirrored = .{},
            .black_mirrored = .{},
        };
    }

    inline fn accFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *[HIDDEN_SIZE]i16) {
        return if (col == .white) &self.white else &self.black;
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
        const add_idx = idx(acc, side, king_sq, tp, sq, self.mirrorFor(acc));
        if (acc == .black) {
            // std.debug.print("init bucket {}\n", .{whichInputBucket(side, king_sq)});
            // std.debug.print("init tp {} sq {}\n", .{ tp, sq });
            // std.debug.print("init add {} {}\n", .{ add_idx, weights.hidden_layer_weights[add_idx * HIDDEN_SIZE] });
        }

        for (0..HIDDEN_SIZE) |i| {
            self.accFor(acc)[i] += weights.hidden_layer_weights[add_idx * HIDDEN_SIZE + i];
        }
    }

    fn doAddSub(noalias self: *Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square) void {
        const add_idx = idx(acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc));
        const sub_idx = idx(acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc));
        if (acc == .black) {
            // std.debug.print("update bucket {}\n", .{whichInputBucket(side, king_sq)});
            // std.debug.print("update add tp {} sq {}\n", .{ add_tp, add_sq });
            // std.debug.print("update sub tp {} sq {}\n", .{ sub_tp, sub_sq });
            // std.debug.print("update add {} {}\n", .{ add_idx, weights.hidden_layer_weights[add_idx * HIDDEN_SIZE] });
            // std.debug.print("update sub {} {}\n", .{ sub_idx, weights.hidden_layer_weights[sub_idx * HIDDEN_SIZE] });
        }
        for (0..HIDDEN_SIZE) |i| {
            self.accFor(acc)[i] += weights.hidden_layer_weights[add_idx * HIDDEN_SIZE + i] - weights.hidden_layer_weights[sub_idx * HIDDEN_SIZE + i];
        }
    }

    fn doAddSubSub(noalias self: *Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square, opp_sub_tp: PieceType, opp_sub_sq: Square) void {
        const add_idx = idx(acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc));
        const sub_idx = idx(acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc));
        const opp_sub_idx = idx(acc, side.flipped(), king_sq, opp_sub_tp, opp_sub_sq, self.mirrorFor(acc));
        for (0..HIDDEN_SIZE) |i| {
            self.accFor(acc)[i] +=
                weights.hidden_layer_weights[add_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[opp_sub_idx * HIDDEN_SIZE + i];
        }
    }

    fn doAddAddSubSub(noalias self: *Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add1_tp: PieceType, add1_sq: Square, add2_tp: PieceType, add2_sq: Square, sub1_tp: PieceType, sub1_sq: Square, sub2_tp: PieceType, sub2_sq: Square) void {
        const add1_idx = idx(acc, side, king_sq, add1_tp, add1_sq, self.mirrorFor(acc));
        const sub1_idx = idx(acc, side, king_sq, sub1_tp, sub1_sq, self.mirrorFor(acc));
        const add2_idx = idx(acc, side, king_sq, add2_tp, add2_sq, self.mirrorFor(acc));
        const sub2_idx = idx(acc, side, king_sq, sub2_tp, sub2_sq, self.mirrorFor(acc));

        for (0..HIDDEN_SIZE) |i| {
            self.accFor(acc)[i] +=
                weights.hidden_layer_weights[add1_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub1_idx * HIDDEN_SIZE + i] +
                weights.hidden_layer_weights[add2_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub2_idx * HIDDEN_SIZE + i];
        }
    }

    pub fn forward(noalias self: *Accumulator, comptime stm: Colour, board: *const Board, old_board: *const Board) i16 {
        // std.debug.print("{any}\n", .{weights.hidden_layer_biases[0..10]});
        // std.debug.print("{any}\n", .{weights.output_biases[0..BUCKET_COUNT]});
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
        if (@import("builtin").mode == .Debug) {
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
        defer if (@import("builtin").mode == .Debug) {
            const correct = Accumulator.init(board);
            if (!std.meta.eql(correct.white, self.white)) {
                unreachable;
            }
            if (!std.meta.eql(correct.black, self.black)) {
                unreachable;
            }
        };
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

    // std.debug.print("{any}\n", .{weights.hidden_layer_biases});
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
pub const vec_size = @min(HIDDEN_SIZE & -%HIDDEN_SIZE, 2 * (std.simd.suggestVectorLength(i16) orelse 8));
pub const HORIZONTAL_MIRRORING = false;
pub const INPUT_BUCKET_COUNT: usize = 1;
pub const OUTPUT_BUCKET_COUNT: usize = 1;
pub const INPUT_SIZE: usize = 768;
pub const HIDDEN_SIZE: usize = 64;
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
