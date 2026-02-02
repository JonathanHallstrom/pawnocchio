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
const BoundedArray = root.BoundedArray;
const Board = root.Board;
const Square = root.Square;
const PieceType = root.PieceType;
const Bitboard = root.Bitboard;
const Colour = root.Colour;
const evaluation = root.evaluation;
const Move = root.Move;

const arch = @import("nnue_arch.zig");

pub const Weights = arch.Weights;
pub const HORIZONTAL_MIRRORING = arch.HORIZONTAL_MIRRORING;
pub const INPUT_BUCKET_COUNT = arch.INPUT_BUCKET_COUNT;
pub const OUTPUT_BUCKET_COUNT = arch.OUTPUT_BUCKET_COUNT;
pub const INPUT_SIZE = arch.INPUT_SIZE;
pub const L1_SIZE = arch.L1_SIZE;
pub const L2_SIZE = arch.L2_SIZE;
pub const L3_SIZE = arch.L3_SIZE;
pub const SCALE = arch.SCALE;
pub const QA = arch.QA;
pub const QB = arch.QB;
pub const INPUT_BUCKET_LAYOUT = arch.INPUT_BUCKET_LAYOUT;

const cpu = builtin.cpu;
pub const IS_AVX512 = cpu.has(.x86, .avx512f);
pub const IS_AVX2 = cpu.has(.x86, .avx2);
pub const IS_NEON = cpu.has(.arm, .neon);
pub const VEC_BYTES = blk: {
    if (IS_AVX512) {
        break :blk 64;
    }
    if (IS_AVX2) {
        break :blk 32;
    }
    if (IS_NEON) {
        break :blk 16;
    }
    break :blk 1;
};

fn vecSize(comptime T: type) comptime_int {
    return VEC_BYTES / @sizeOf(T);
}

const builtin = @import("builtin");
const CAN_VERBATIM_NET = builtin.cpu.arch.endian() == .little and !build_options.runtime_net;
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
const net = @embedFile("net");
const verbatim_weights: [net.len:0]u8 align(64) = net.*;

pub var weights = if (CAN_VERBATIM_NET) @as(*const Weights, @ptrCast(&verbatim_weights)) else if (build_options.runtime_net) @as(*const Weights, undefined) else &(struct {
    var backing: Weights = undefined;
}).backing;
inline fn hiddenLayerWeightsVector() []const @Vector(vecSize(i16), i16) {
    return @as([*]const @Vector(vecSize(i16), i16), @ptrCast(&weights.hidden_layer_weights))[0 .. weights.hidden_layer_weights.len / vecSize(i16)];
}

const SquarePieceType = struct {
    sq: Square,
    pt: PieceType,
};

const DirtyPiece = struct {
    adds: BoundedArray(SquarePieceType, 2) = .{},
    subs: BoundedArray(SquarePieceType, 2) = .{},
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
    return idx(perspective, side, king_sq, tp, sq, mirror) * L1_SIZE / vecSize(i16);
}

const Accumulator = struct {
    white: [L1_SIZE]i16 align(std.atomic.cache_line),
    black: [L1_SIZE]i16 align(std.atomic.cache_line),

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

    inline fn accFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *align(std.atomic.cache_line) [L1_SIZE]i16) {
        return if (col == .white) &self.white else &self.black;
    }

    inline fn vecAccFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *[L1_SIZE / vecSize(i16)]@Vector(vecSize(i16), i16)) {
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

    pub fn update(noalias self: *Accumulator, other: *const Accumulator, board: *const Board, refresh_cache: anytype) void {
        switch (board.stm) {
            inline else => |stm| {
                self.applyUpdate(.copy, other, stm.flipped(), board, refresh_cache);
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

        for (0..L1_SIZE / vecSize(i16)) |i| {
            self.vecAccFor(acc)[i] += hiddenLayerWeightsVector()[add_idx + i];
        }
    }

    fn doAddSub(noalias self: *Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square) void {
        const add_idx = vecIdx(acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc));
        const sub_idx = vecIdx(acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc));

        for (0..L1_SIZE / vecSize(i16)) |i| {
            self.vecAccFor(acc)[i] += hiddenLayerWeightsVector()[add_idx + i] -
                hiddenLayerWeightsVector()[sub_idx + i];
        }
    }

    fn doAddSubSub(noalias self: *Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square, opp_sub_tp: PieceType, opp_sub_sq: Square) void {
        const add_idx = vecIdx(acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc));
        const sub_idx = vecIdx(acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc));
        const opp_sub_idx = vecIdx(acc, side.flipped(), king_sq, opp_sub_tp, opp_sub_sq, self.mirrorFor(acc));
        for (0..L1_SIZE / vecSize(i16)) |i| {
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

        for (0..L1_SIZE / vecSize(i16)) |i| {
            self.vecAccFor(acc)[i] +=
                hiddenLayerWeightsVector()[add1_idx + i] -
                hiddenLayerWeightsVector()[sub1_idx + i] +
                hiddenLayerWeightsVector()[add2_idx + i] -
                hiddenLayerWeightsVector()[sub2_idx + i];
        }
    }
    inline fn doAddCopy(self: *Accumulator, other: *const Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, tp: PieceType, sq: Square) void {
        const add_idx = vecIdx(acc, side, king_sq, tp, sq, self.mirrorFor(acc));

        for (0..L1_SIZE / vecSize(i16)) |i| {
            self.vecAccFor(acc)[i] = other.vecAccFor(acc)[i] +
                hiddenLayerWeightsVector()[add_idx + i];
        }
    }

    inline fn doAddSubCopy(self: *Accumulator, other: *const Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square) void {
        const add_idx = vecIdx(acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc));
        const sub_idx = vecIdx(acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc));

        for (0..L1_SIZE / vecSize(i16)) |i| {
            self.vecAccFor(acc)[i] = other.vecAccFor(acc)[i] +
                hiddenLayerWeightsVector()[add_idx + i] -
                hiddenLayerWeightsVector()[sub_idx + i];
        }
    }

    inline fn doAddSubSubCopy(self: *Accumulator, other: *const Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square, opp_sub_tp: PieceType, opp_sub_sq: Square) void {
        const add_idx = vecIdx(acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc));
        const sub_idx = vecIdx(acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc));
        const opp_sub_idx = vecIdx(acc, side.flipped(), king_sq, opp_sub_tp, opp_sub_sq, self.mirrorFor(acc));
        for (0..L1_SIZE / vecSize(i16)) |i| {
            self.vecAccFor(acc)[i] = other.vecAccFor(acc)[i] +
                hiddenLayerWeightsVector()[add_idx + i] -
                hiddenLayerWeightsVector()[sub_idx + i] -
                hiddenLayerWeightsVector()[opp_sub_idx + i];
        }
    }

    inline fn doAddAddSubSubCopy(self: *Accumulator, other: *const Accumulator, comptime acc: Colour, comptime side: Colour, king_sq: Square, add1_tp: PieceType, add1_sq: Square, add2_tp: PieceType, add2_sq: Square, sub1_tp: PieceType, sub1_sq: Square, sub2_tp: PieceType, sub2_sq: Square) void {
        const add1_idx = vecIdx(acc, side, king_sq, add1_tp, add1_sq, self.mirrorFor(acc));
        const sub1_idx = vecIdx(acc, side, king_sq, sub1_tp, sub1_sq, self.mirrorFor(acc));
        const add2_idx = vecIdx(acc, side, king_sq, add2_tp, add2_sq, self.mirrorFor(acc));
        const sub2_idx = vecIdx(acc, side, king_sq, sub2_tp, sub2_sq, self.mirrorFor(acc));

        for (0..L1_SIZE / vecSize(i16)) |i| {
            self.vecAccFor(acc)[i] = other.vecAccFor(acc)[i] +
                hiddenLayerWeightsVector()[add1_idx + i] -
                hiddenLayerWeightsVector()[sub1_idx + i] +
                hiddenLayerWeightsVector()[add2_idx + i] -
                hiddenLayerWeightsVector()[sub2_idx + i];
        }
    }

    fn needsRefresh(stm: Colour, from: Square, to: Square) bool {
        if (HORIZONTAL_MIRRORING and (from.getFile().toInt() >= 4) != (to.getFile().toInt() >= 4)) {
            return true;
        }
        return whichInputBucket(stm, from) != whichInputBucket(stm, to);
    }

    fn applyUpdate(
        noalias self: *Accumulator,
        comptime mode: enum { copy, inplace },
        noalias other: if (mode == .inplace) @TypeOf(null) else *const Accumulator,
        comptime stm: Colour,
        board: *const Board,
        refresh_cache: anytype,
    ) void {
        if (mode == .copy) {
            self.white_mirrored = other.white_mirrored;
            self.black_mirrored = other.black_mirrored;
            self.dirty_piece = other.dirty_piece;
            @memcpy(self.accFor(stm), other.accFor(stm));
        }
        if (self.dirty_piece.adds.len | self.dirty_piece.subs.len == 0) {
            if (mode == .copy) {
                @memcpy(self.accFor(stm.flipped()), other.accFor(stm.flipped()));
            }
            return;
        }
        defer self.dirty_piece = .{};
        const copy = if (mode == .inplace) self else other;
        const us_king_sq = Square.fromBitboard(board.kingFor(stm));
        const them_king_sq = Square.fromBitboard(board.kingFor(stm.flipped()));
        if (self.dirty_piece.adds.len == 1 and self.dirty_piece.subs.len == 1) {
            const add1 = self.dirty_piece.adds.slice()[0];
            const sub1 = self.dirty_piece.subs.slice()[0];
            // std.debug.print("{} {}\n", .{ add1, sub1 });
            self.doAddSubCopy(copy, stm.flipped(), stm, them_king_sq, add1.pt, add1.sq, sub1.pt, sub1.sq);
            if (add1.pt == .king and needsRefresh(stm, add1.sq, sub1.sq)) {
                // std.debug.print("refresh\n", .{});
                // self.mirrorFor(col: Colour)
                self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                refresh_cache.refresh(stm, board, self.accFor(stm));
            } else {
                self.doAddSubCopy(copy, stm, stm, us_king_sq, add1.pt, add1.sq, sub1.pt, sub1.sq);
            }
        } else if (self.dirty_piece.adds.len == 1 and self.dirty_piece.subs.len == 2) {
            const add1 = self.dirty_piece.adds.slice()[0];
            const sub1 = self.dirty_piece.subs.slice()[0];
            const sub2 = self.dirty_piece.subs.slice()[1];
            self.doAddSubSubCopy(copy, stm.flipped(), stm, them_king_sq, add1.pt, add1.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
            if (add1.pt == .king and needsRefresh(stm, add1.sq, sub1.sq)) {
                self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                refresh_cache.refresh(stm, board, self.accFor(stm));
            } else {
                self.doAddSubSubCopy(copy, stm, stm, us_king_sq, add1.pt, add1.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
            }
        } else if (self.dirty_piece.adds.len == 2 and self.dirty_piece.subs.len == 2) {
            const add1 = self.dirty_piece.adds.slice()[0];
            const add2 = self.dirty_piece.adds.slice()[1];
            const sub1 = self.dirty_piece.subs.slice()[0];
            const sub2 = self.dirty_piece.subs.slice()[1];
            // std.debug.print("{} {}\n", .{ add1.sq, sub1.sq });
            self.doAddAddSubSubCopy(copy, stm.flipped(), stm, them_king_sq, add1.pt, add1.sq, add2.pt, add2.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
            if (needsRefresh(stm, add1.sq, sub1.sq)) {
                // std.debug.print("castling refresh\n", .{});
                // std.debug.print("{} {s}\n", .{stm, old_board.toFen().slice()});
                self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                refresh_cache.refresh(stm, board, self.accFor(stm));
            } else {
                self.doAddAddSubSubCopy(copy, stm, stm, us_king_sq, add1.pt, add1.sq, add2.pt, add2.sq, sub1.pt, sub1.sq, sub2.pt, sub2.sq);
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

    pub fn forward(noalias self: *Accumulator, comptime stm: Colour, board: *const Board, refresh_cache: anytype) i16 {
        self.applyUpdate(.inplace, null, stm.flipped(), board, refresh_cache);
        // if (true)
        //     return 0;
        const stm_acc = if (board.stm == .white) &self.white else &self.black;
        const ntm_acc = if (board.stm == .white) &self.black else &self.white;
        // //             vvvvvvvv annotation to help zls
        // const i16Vec = @as(type, @Vector(vecSize(i16), i16));

        const output_bucket = whichOutputBucket(board);

        // accumulators are in 2^8 space
        var activated_ft: [L1_SIZE]u8 = undefined;
        for (0..L1_SIZE / 2) |i| {
            const s1: u8 = @intCast(std.math.clamp(stm_acc[i], 0, 255));
            const s2: u8 = @intCast(std.math.clamp(stm_acc[i + L1_SIZE / 2], 0, 255));

            const n1: u8 = @intCast(std.math.clamp(ntm_acc[i], 0, 255));
            const n2: u8 = @intCast(std.math.clamp(ntm_acc[i + L1_SIZE / 2], 0, 255));

            // now activated is in (2^8)^2/(2^9) = 2^7 space
            activated_ft[i] = @intCast(std.math.clamp(@as(i32, s1) * s2 << 7 >> 16, 0, 255));
            activated_ft[i + L1_SIZE / 2] = @intCast(std.math.clamp(@as(i32, n1) * n2 << 7 >> 16, 0, 255));
        }

        var l1_intermediate: [L2_SIZE]i32 = @splat(0);
        for (0..L2_SIZE) |j| {
            for (0..L1_SIZE) |i| {
                const ft = activated_ft[i];

                l1_intermediate[j] += @as(i32, (&(&(&weights.l1w)[output_bucket])[i])[j]) * ft;
            }
        }

        var l1_out: [L2_SIZE]i32 = undefined;
        for (0..L2_SIZE) |i| {
            const dequantised = l1_intermediate[i] >> 8;
            const clamped = std.math.clamp(dequantised + (&(&weights.l1b)[output_bucket])[i], 0, 1 << 6);
            const activated = clamped * clamped;
            l1_out[i] = activated;
        }

        var l2_intermediate: [L3_SIZE]i32 = weights.l2b[output_bucket];
        for (0..L2_SIZE) |i| {
            for (0..L3_SIZE) |j| {
                l2_intermediate[j] += l1_out[i] * (&(&(&weights.l2w)[output_bucket])[i])[j];
            }
        }

        var l2_out: [L3_SIZE]i32 = undefined;
        for (0..L3_SIZE) |i| {
            const value = l2_intermediate[i];
            const clamped = std.math.clamp(value, 0, 1 << 18);
            const activated = clamped;
            l2_out[i] = activated;
        }

        var l3_out: i32 = (&weights.l3b)[output_bucket];
        for (0..L3_SIZE) |i| {
            l3_out += l2_out[i] * ((&weights.l3w)[output_bucket])[i];
        }

        const scaled = l3_out * @as(i64, SCALE);

        return evaluation.clampScore(@divTrunc(scaled, 1 << 24));
    }
};

pub const State = Accumulator;

pub fn evaluate(comptime stm: Colour, board: *const Board, eval_state: *State, refresh_cache: anytype) i16 {
    return eval_state.forward(stm, board, refresh_cache);
}

fn crelu(x: i32) i32 {
    return std.math.clamp(x, 0, QA);
}

fn screlu(x: i32) i32 {
    const clamped = std.math.clamp(x, 0, QA);
    return clamped * clamped;
}

pub fn init() !void {
    if (build_options.runtime_net) {
        weights_file = std.fs.openFileAbsolute(build_options.net_path, .{}) catch try std.fs.cwd().openFile(build_options.net_name, .{});
        if (@import("builtin").target.os.tag == .windows) {
            @compileError("sorry mmap-ing the network manually is not supported on windows");
        }
        mapped_weights = try std.posix.mmap(null, Weights.WEIGHT_COUNT * @sizeOf(i16), std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, weights_file.handle, 0);

        weights = @ptrCast(mapped_weights.ptr);

        return;
    }
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

pub fn evalPosition(board: *const Board) i16 {
    const RC = @import("refresh_cache.zig").refreshCache(HORIZONTAL_MIRRORING, INPUT_BUCKET_COUNT);
    var cache: RC = undefined;
    cache.initInPlace();
    var acc = Accumulator.init(board);
    switch (board.stm) {
        inline else => |stm| {
            return acc.forward(stm, board, &cache);
        },
    }
}
