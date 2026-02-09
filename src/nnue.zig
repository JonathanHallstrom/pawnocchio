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
pub const Q = arch.Q;
pub const Q0 = arch.Q0;
pub const Q1 = arch.Q1;
pub const Q_BITS = std.math.log2_int_ceil(u32, Q);
pub const Q0_BITS = std.math.log2_int_ceil(u32, Q0);
pub const Q1_BITS = std.math.log2_int_ceil(u32, Q1);
pub const INPUT_BUCKET_LAYOUT = arch.INPUT_BUCKET_LAYOUT;

pub const VEC_BYTES = arch.vecBytes(@import("builtin").cpu);

pub fn vecSize(comptime T: type) comptime_int {
    return VEC_BYTES / @sizeOf(T);
}

const builtin = @import("builtin");
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
var mapper: @import("MappedFile.zig") = undefined;
const net = @embedFile("net");
const verbatim_weights: [net.len:0]u8 align(64) = net.*;

pub var weights = @as(*const Weights, @ptrCast(&verbatim_weights));

inline fn hiddenLayerWeightsVector() []const @Vector(vecSize(i16), i16) {
    return @as([*]const @Vector(vecSize(i16), i16), @ptrCast(&weights.ft_w))[0 .. weights.ft_w.len / vecSize(i16)];
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
            .white = weights.ft_b,
            .black = weights.ft_b,
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
        std.debug.assert(board.stm == stm);
        // if (true)
        //     return 0;
        const stm_acc = self.accFor(stm);
        const ntm_acc = self.accFor(stm.flipped());
        // const stm_vec = self.vecAccFor(stm);
        // const ntm_vec = self.vecAccFor(stm.flipped());
        // //             vvvvvvvv annotation to help zls
        const i8Vec = @as(type, @Vector(vecSize(i8), i8));
        const i16Vec = @as(type, @Vector(vecSize(i16), i16));
        const i32Vec = @as(type, @Vector(vecSize(i32), i32));
        const u8Vec = @as(type, @Vector(vecSize(u8), u8));
        // const u16Vec = @as(type, @Vector(vecSize(u16), u16));
        // const u32Vec = @as(type, @Vector(vecSize(u32), u32));

        const c = struct {
            fn maddubs(u: u8Vec, i: i8Vec) i16Vec {
                return asm ("vpmaddubsw %[i], %[u], %[ret]"
                    : [ret] "=x" (-> i16Vec),
                    : [u] "x" (u),
                      [i] "x" (i),
                );
            }

            fn maddwd(a: i16Vec, b: i16Vec) i32Vec {
                return asm ("vpmaddwd %[b], %[a], %[ret]"
                    : [ret] "=x" (-> i32Vec),
                    : [a] "x" (a),
                      [b] "x" (b),
                );
            }

            fn dpbusd(sum: i32Vec, u: u8Vec, i: i8Vec) i32Vec {
                if (builtin.cpu.has(.x86, .avx512vnni) and false) {
                    var s = sum;
                    asm ("vpdpbusd %[i], %[u], %[s]"
                        : [s] "+x" (s),
                        : [u] "x" (u),
                          [i] "x" (i),
                    );
                    return s;
                } else {
                    const partial_sums = maddubs(u, i);

                    const ones: i16Vec = @splat(1);
                    const dot_products = maddwd(partial_sums, ones);

                    return sum + dot_products;
                }
            }

            fn mulhi(a: i16Vec, b: i16Vec) i16Vec {
                return asm ("vpmulhw %[b], %[a], %[ret]"
                    : [ret] "=x" (-> i16Vec),
                    : [a] "x" (a),
                      [b] "x" (b),
                );
            }
            fn packus(a: i16Vec, b: i16Vec) u8Vec {
                return asm ("vpackuswb %[b], %[a], %[ret]"
                    : [ret] "=x" (-> u8Vec),
                    : [a] "x" (a),
                      [b] "x" (b),
                );
            }
        };
        const clamp = struct {
            fn impl(comptime T: type, x: T, lo: T, hi: T) T {
                return @min(@max(x, lo), hi);
            }
        }.impl;

        const output_bucket = whichOutputBucket(board);

        // in Q0² / 2⁹
        var activated_ft: [L1_SIZE]u8 align(64) = undefined;
        {
            const items_per_iter = vecSize(i16) * 2;
            var i: usize = 0;
            const LO: i16Vec = @splat(0);
            const HI: i16Vec = @splat(arch.Q0);
            while (i < L1_SIZE / 2) : (i += items_per_iter) {
                var s1: i16Vec = stm_acc[i..][0..vecSize(i16)].*;
                var s2: i16Vec = stm_acc[i + L1_SIZE / 2 ..][0..vecSize(i16)].*;
                var s3: i16Vec = stm_acc[i + vecSize(i16) ..][0..vecSize(i16)].*;
                var s4: i16Vec = stm_acc[i + vecSize(i16) + L1_SIZE / 2 ..][0..vecSize(i16)].*;

                var n1: i16Vec = ntm_acc[i..][0..vecSize(i16)].*;
                var n2: i16Vec = ntm_acc[i + L1_SIZE / 2 ..][0..vecSize(i16)].*;
                var n3: i16Vec = ntm_acc[i + vecSize(i16) ..][0..vecSize(i16)].*;
                var n4: i16Vec = ntm_acc[i + vecSize(i16) + L1_SIZE / 2 ..][0..vecSize(i16)].*;

                s1 = clamp(i16Vec, s1, LO, HI);
                s2 = @min(s2, HI);
                s3 = clamp(i16Vec, s3, LO, HI);
                s4 = @min(s4, HI);

                n1 = clamp(i16Vec, n1, LO, HI);
                n2 = @min(n2, HI);
                n3 = clamp(i16Vec, n3, LO, HI);
                n4 = @min(n4, HI);

                const sp1 = c.mulhi(s1 << @splat(7), s2);
                const sp2 = c.mulhi(s3 << @splat(7), s4);

                const np1 = c.mulhi(n1 << @splat(7), n2);
                const np2 = c.mulhi(n3 << @splat(7), n4);

                const p1: [vecSize(u8)]u8 = c.packus(sp1, sp2);
                const p2: [vecSize(u8)]u8 = c.packus(np1, np2);

                @memcpy(activated_ft[i..][0..vecSize(i8)], &p1);
                @memcpy(activated_ft[i + L1_SIZE / 2 ..][0..vecSize(i8)], &p2);
            }
        }

        const L2_UNROLL = 4;
        // in Q0² / 2⁹ * Q1
        var l1_intermediate: [L2_SIZE / vecSize(i32)][L2_UNROLL]i32Vec = @splat(@splat(@splat(0)));
        {
            const w: [*]const i8 = &(&weights.l1w)[output_bucket];
            const ft_i32: [*]i32 = @ptrCast(&activated_ft);

            const nonzero_indices, const num_nonzero_indices = @import("sparse.zig").findNonZeroIndices(&activated_ft);

            var i_outer: usize = 0;

            while (i_outer + L2_UNROLL <= num_nonzero_indices) : (i_outer += L2_UNROLL) {
                for (0..L2_SIZE / vecSize(i32)) |j| {
                    for (0..L2_UNROLL) |i_inner| {
                        const i = nonzero_indices[i_outer + i_inner];
                        const ft_vec: u8Vec = @bitCast(@as(i32Vec, @splat(ft_i32[i])));
                        l1_intermediate[j][i_inner] = c.dpbusd(
                            l1_intermediate[j][i_inner],
                            ft_vec,
                            w[i * L2_SIZE * 4 + j * vecSize(i8) ..][0..vecSize(i8)].*,
                        );
                    }
                }
            }
            while (i_outer < num_nonzero_indices) : (i_outer += 1) {
                const i = nonzero_indices[i_outer];
                const ft_vec: u8Vec = @bitCast(@as(i32Vec, @splat(ft_i32[i])));

                for (0..L2_SIZE / vecSize(i32)) |j| {
                    l1_intermediate[j][0] = c.dpbusd(
                        l1_intermediate[j][0],
                        ft_vec,
                        w[i * L2_SIZE * 4 + j * vecSize(i8) ..][0..vecSize(i8)].*,
                    );
                }
            }
        }

        // in Q²
        var l1_out_vec: [L2_SIZE / vecSize(i32)]i32Vec = undefined;
        {
            const l1_bias_vec: [*]const i32Vec = @ptrCast(@alignCast(&(&weights.l1b)[output_bucket]));
            const SHIFT = comptime Q0_BITS * 2 - 9 + Q1_BITS - Q_BITS;
            for (0..L2_SIZE / vecSize(i32)) |i| {
                const biases: i32Vec = l1_bias_vec[i];

                var intermediate: i32Vec = @splat(0);
                for (l1_intermediate[i]) |e| {
                    intermediate += e;
                }

                // NOTE: PLEASE BE CAREFUL WITH THE QUANTISATION OF THESE BIASES
                const shifted = intermediate >> @splat(SHIFT);

                const crelu = clamp(i32Vec, shifted + biases, @splat(0), @splat(arch.Q));

                l1_out_vec[i] = crelu * crelu;
            }
        }

        // in Q³
        var l2_intermediate: [L3_SIZE / vecSize(i32)]i32Vec = @bitCast((&weights.l2b)[output_bucket]);
        {
            const l1_out: *const [L2_SIZE]i32 = @ptrCast(&l1_out_vec);
            const l2_weight_vec: *const [L2_SIZE][L3_SIZE / vecSize(i32)]i32Vec = @ptrCast(@alignCast(&(&weights.l2w)[output_bucket]));
            for (0..L2_SIZE) |i| {
                const l1_vec: i32Vec = @splat(l1_out[i]);
                for (0..L3_SIZE / vecSize(i32)) |j| {
                    l2_intermediate[j] += l1_vec * (&l2_weight_vec[i])[j];
                }
            }
        }

        // in Q⁴
        var l3_sum: i32Vec = @splat(0);
        {
            const l3_weight_vec: *const [L3_SIZE / vecSize(i32)]i32Vec = @ptrCast(@alignCast(&(&weights.l3w)[output_bucket]));
            for (0..L3_SIZE / vecSize(i32)) |i| {
                const activated = clamp(i32Vec, l2_intermediate[i], @splat(0), @splat(arch.Q * arch.Q * arch.Q));
                l3_sum += activated * l3_weight_vec[i];
            }
        }

        const bias = (&weights.l3b)[output_bucket];
        const scaled = (@reduce(.Add, l3_sum) + bias) * SCALE;

        return evaluation.clampScore(@divTrunc(scaled, arch.Q * arch.Q * arch.Q * arch.Q));
    }
};

pub const State = Accumulator;

pub fn evaluate(comptime stm: Colour, board: *const Board, eval_state: *State, refresh_cache: anytype) i16 {
    return eval_state.forward(stm, board, refresh_cache);
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
