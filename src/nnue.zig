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

pub const TARGET = arch.target(@import("builtin").cpu);
pub const VEC_BYTES = arch.vecBytes(@import("builtin").cpu);

pub fn vecSize(comptime T: type) comptime_int {
    return VEC_BYTES / @sizeOf(T);
}

const build_options = @import("build_options");

pub inline fn whichInputBucket(stm: Colour, king_square: Square) usize {
    if (INPUT_BUCKET_COUNT == 1) {
        return 0;
    }
    return INPUT_BUCKET_LAYOUT[(if (stm == .white) king_square else king_square.flipRank()).toInt()];
}

pub inline fn whichOutputBucket(board: *const Board) usize {
    const max_piece_count = 32;
    const divisor = (max_piece_count + OUTPUT_BUCKET_COUNT - 1) / OUTPUT_BUCKET_COUNT;
    return @min(OUTPUT_BUCKET_COUNT - 1, (@popCount(board.occupancy()) - 2) / divisor);
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

const DirtyPiece = union(enum) {
    clean,
    add_sub: struct {
        add: SquarePieceType,
        sub: SquarePieceType,
    },
    add_sub_sub: struct {
        add: SquarePieceType,
        sub1: SquarePieceType,
        sub2: SquarePieceType,
    },
    add_add_sub_sub: struct {
        add1: SquarePieceType,
        add2: SquarePieceType,
        sub1: SquarePieceType,
        sub2: SquarePieceType,
    },

    inline fn clear(self: *DirtyPiece) void {
        self.* = .clean;
    }

    inline fn isClean(self: DirtyPiece) bool {
        return switch (self) {
            .clean => true,
            else => false,
        };
    }
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

pub const Accumulator = struct {
    white: [L1_SIZE]i16 align(std.atomic.cache_line),
    black: [L1_SIZE]i16 align(std.atomic.cache_line),

    dirty_piece: DirtyPiece,
    pending_parent: bool,
    board_ref: ?*const Board,

    white_mirrored: MirroringType,
    black_mirrored: MirroringType,

    pub inline fn default() Accumulator {
        return .{
            .white = weights.ft_b,
            .black = weights.ft_b,
            .white_mirrored = .{},
            .black_mirrored = .{},
            .dirty_piece = .clean,
            .pending_parent = false,
            .board_ref = null,
        };
    }

    pub inline fn accFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *align(std.atomic.cache_line) [L1_SIZE]i16) {
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

    pub fn setMirrored(self: *Accumulator, board: *const Board) void {
        self.white_mirrored.write(Square.fromBitboard(board.kingFor(.white)).getFile().toInt() >= 4);
        self.black_mirrored.write(Square.fromBitboard(board.kingFor(.black)).getFile().toInt() >= 4);
    }

    pub fn initInPlace(self: *Accumulator, board: *const Board) void {
        self.* = default();
        self.setMirrored(board);
        self.dirty_piece = .clean;
        self.pending_parent = false;
        self.board_ref = board;

        const white_king_sq = Square.fromBitboard(board.kingFor(.white));
        const black_king_sq = Square.fromBitboard(board.kingFor(.black));
        for (PieceType.all) |tp| {
            {
                var iter = Bitboard.iterator(board.pieceFor(.white, tp));
                while (iter.next()) |sq| {
                    self.doAddCopy(self, .white, .white, white_king_sq, tp, sq);
                    self.doAddCopy(self, .black, .white, black_king_sq, tp, sq);
                }
            }
            {
                var iter = Bitboard.iterator(board.pieceFor(.black, tp));
                while (iter.next()) |sq| {
                    self.doAddCopy(self, .white, .black, white_king_sq, tp, sq);
                    self.doAddCopy(self, .black, .black, black_king_sq, tp, sq);
                }
            }
        }
    }

    pub fn update(noalias self: *Accumulator, other: *Accumulator, board: *const Board, refresh_cache: anytype) void {
        _ = board;
        _ = refresh_cache;
        std.debug.assert(@intFromPtr(other) + @sizeOf(Accumulator) == @intFromPtr(self));
        self.pending_parent = true;
        self.board_ref = null;
        self.dirty_piece = .clean;
    }

    pub fn bindBoard(noalias self: *Accumulator, board: *const Board) void {
        self.board_ref = board;
    }

    fn resolvePending(noalias self: *Accumulator, refresh_cache: anytype) void {
        if (!self.pending_parent) {
            return;
        }
        const parent: *Accumulator = @ptrFromInt(@intFromPtr(self) - @sizeOf(Accumulator));
        parent.resolvePending(refresh_cache);
        const board = self.board_ref orelse unreachable;
        switch (board.stm) {
            inline else => |stm| {
                self.applyUpdate(.copy, parent, stm.flipped(), board, refresh_cache);
            },
        }
        self.pending_parent = false;
    }

    pub fn init(board: *const Board) Accumulator {
        var acc = default();
        acc.initInPlace(board);
        return acc;
    }

    inline fn doCopy(self: *Accumulator, other: *const Accumulator, comptime acc: Colour) void {
        for (0..L1_SIZE / vecSize(i16)) |i| {
            self.vecAccFor(acc)[i] = other.vecAccFor(acc)[i];
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
        }
        if (self.dirty_piece.isClean()) {
            if (mode == .copy) {
                self.doCopy(other, .white);
                self.doCopy(other, .black);
            }
            return;
        }
        defer self.dirty_piece.clear();
        const copy = if (mode == .inplace) self else other;
        const us_king_sq = Square.fromBitboard(board.kingFor(stm));
        const them_king_sq = Square.fromBitboard(board.kingFor(stm.flipped()));
        switch (self.dirty_piece) {
            .clean => unreachable,
            .add_sub => |state| {
                self.doAddSubCopy(copy, stm.flipped(), stm, them_king_sq, state.add.pt, state.add.sq, state.sub.pt, state.sub.sq);
                if (state.add.pt == .king and needsRefresh(stm, state.add.sq, state.sub.sq)) {
                    @branchHint(.unlikely);
                    self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                    refresh_cache.refresh(stm, board, self.accFor(stm));
                } else {
                    self.doAddSubCopy(copy, stm, stm, us_king_sq, state.add.pt, state.add.sq, state.sub.pt, state.sub.sq);
                }
            },
            .add_sub_sub => |state| {
                self.doAddSubSubCopy(copy, stm.flipped(), stm, them_king_sq, state.add.pt, state.add.sq, state.sub1.pt, state.sub1.sq, state.sub2.pt, state.sub2.sq);
                if (state.add.pt == .king and needsRefresh(stm, state.add.sq, state.sub1.sq)) {
                    @branchHint(.unlikely);
                    self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                    refresh_cache.refresh(stm, board, self.accFor(stm));
                } else {
                    self.doAddSubSubCopy(copy, stm, stm, us_king_sq, state.add.pt, state.add.sq, state.sub1.pt, state.sub1.sq, state.sub2.pt, state.sub2.sq);
                }
            },
            .add_add_sub_sub => |state| {
                self.doAddAddSubSubCopy(copy, stm.flipped(), stm, them_king_sq, state.add1.pt, state.add1.sq, state.add2.pt, state.add2.sq, state.sub1.pt, state.sub1.sq, state.sub2.pt, state.sub2.sq);
                if (needsRefresh(stm, state.add1.sq, state.sub1.sq)) {
                    @branchHint(.unlikely);
                    self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                    refresh_cache.refresh(stm, board, self.accFor(stm));
                } else {
                    self.doAddAddSubSubCopy(copy, stm, stm, us_king_sq, state.add1.pt, state.add1.sq, state.add2.pt, state.add2.sq, state.sub1.pt, state.sub1.sq, state.sub2.pt, state.sub2.sq);
                }
            },
        }
    }

    pub fn addSub(self: *State, comptime add_col: Colour, add_pt: PieceType, add_square: Square, comptime sub_col: Colour, sub_pt: PieceType, sub_square: Square) void {
        _ = add_col;
        _ = sub_col;
        std.debug.assert(self.dirty_piece.isClean());
        self.dirty_piece = .{ .add_sub = .{
            .add = .{ .pt = add_pt, .sq = add_square },
            .sub = .{ .pt = sub_pt, .sq = sub_square },
        } };
    }

    pub fn addSubSub(self: *State, comptime add_col: Colour, add_pt: PieceType, add_square: Square, comptime sub1_col: Colour, sub1_pt: PieceType, sub1_square: Square, comptime sub2_col: Colour, sub2_pt: PieceType, sub2_square: Square) void {
        _ = add_col;
        _ = sub1_col;
        _ = sub2_col;
        std.debug.assert(self.dirty_piece.isClean());
        self.dirty_piece = .{ .add_sub_sub = .{
            .add = .{ .pt = add_pt, .sq = add_square },
            .sub1 = .{ .pt = sub1_pt, .sq = sub1_square },
            .sub2 = .{ .pt = sub2_pt, .sq = sub2_square },
        } };
    }

    pub fn addAddSubSub(self: *State, comptime add1_col: Colour, add1_pt: PieceType, add1_square: Square, comptime add2_col: Colour, add2_pt: PieceType, add2_square: Square, comptime sub1_col: Colour, sub1_pt: PieceType, sub1_square: Square, comptime sub2_col: Colour, sub2_pt: PieceType, sub2_square: Square) void {
        _ = add1_col;
        _ = add2_col;
        _ = sub1_col;
        _ = sub2_col;
        std.debug.assert(self.dirty_piece.isClean());
        self.dirty_piece = .{ .add_add_sub_sub = .{
            .add1 = .{ .pt = add1_pt, .sq = add1_square },
            .add2 = .{ .pt = add2_pt, .sq = add2_square },
            .sub1 = .{ .pt = sub1_pt, .sq = sub1_square },
            .sub2 = .{ .pt = sub2_pt, .sq = sub2_square },
        } };
    }

    pub fn forward(noalias self: *Accumulator, comptime stm: Colour, board: *const Board, refresh_cache: anytype) i16 {
        self.resolvePending(refresh_cache);
        if (!self.dirty_piece.isClean()) {
            self.applyUpdate(.inplace, null, stm.flipped(), board, refresh_cache);
        }
        std.debug.assert(board.stm == stm);
        const stm_acc = self.accFor(stm);
        const ntm_acc = self.accFor(stm.flipped());
        const i8Vec = @as(type, @Vector(vecSize(i8), i8));
        const i16Vec = @as(type, @Vector(vecSize(i16), i16));
        const i32Vec = @as(type, @Vector(vecSize(i32), i32));
        const u8Vec = @as(type, @Vector(vecSize(u8), u8));

        const c = struct {
            fn maddubs(u: u8Vec, i: i8Vec) i16Vec {
                switch (TARGET) {
                    .avx512vnni, .avx512, .avx2 => return asm ("vpmaddubsw %[i], %[u], %[ret]"
                        : [ret] "=x" (-> i16Vec),
                        : [u] "x" (u),
                          [i] "x" (i),
                    ),
                    .ssse3 => return asm ("pmaddubsw %[i], %[u]"
                        : [ret] "=x" (-> i16Vec),
                        : [u] "0" (u),
                          [i] "x" (i),
                    ),
                    .aarch64 => {
                        // Widen u8 to u16 (unsigned)
                        const u_lo: @Vector(8, u16) = asm (
                            \\ushll %[ret].8h, %[v].8b, #0
                            : [ret] "=w" (-> @Vector(8, u16)),
                            : [v] "w" (u),
                        );
                        const u_hi: @Vector(8, u16) = asm (
                            \\ushll2 %[ret].8h, %[v].16b, #0
                            : [ret] "=w" (-> @Vector(8, u16)),
                            : [v] "w" (u),
                        );
                        // Widen i8 to i16 (signed)
                        const i_lo: @Vector(8, i16) = asm (
                            \\sshll %[ret].8h, %[v].8b, #0
                            : [ret] "=w" (-> @Vector(8, i16)),
                            : [v] "w" (i),
                        );
                        const i_hi: @Vector(8, i16) = asm (
                            \\sshll2 %[ret].8h, %[v].16b, #0
                            : [ret] "=w" (-> @Vector(8, i16)),
                            : [v] "w" (i),
                        );
                        // Multiply: reinterpret u16 as i16 for mul instruction; products fit in i16
                        const prod_lo: @Vector(8, i16) = @as(@Vector(8, i16), @bitCast(u_lo)) * i_lo;
                        const prod_hi: @Vector(8, i16) = @as(@Vector(8, i16), @bitCast(u_hi)) * i_hi;
                        // Pairwise add adjacent i16 pairs -> 8 x i16
                        return asm (
                            \\addp %[ret].8h, %[lo].8h, %[hi].8h
                            : [ret] "=w" (-> i16Vec),
                            : [lo] "w" (prod_lo),
                              [hi] "w" (prod_hi),
                        );
                    },
                    .sse2, .fallback => {
                        const u_parts = std.simd.deinterlace(2, u);
                        const i_parts = std.simd.deinterlace(2, i);

                        const products_even =
                            @as(i16Vec, u_parts[0]) *
                            @as(i16Vec, i_parts[0]);
                        const products_odd =
                            @as(i16Vec, u_parts[1]) *
                            @as(i16Vec, i_parts[1]);

                        return products_even +| products_odd;
                    },
                }
            }

            fn maddwd(a: i16Vec, b: i16Vec) i32Vec {
                switch (TARGET) {
                    .avx512vnni, .avx512, .avx2 => return asm ("vpmaddwd %[b], %[a], %[ret]"
                        : [ret] "=x" (-> i32Vec),
                        : [a] "x" (a),
                          [b] "x" (b),
                    ),
                    .ssse3, .sse2 => return asm ("pmaddwd %[b], %[a]"
                        : [ret] "=x" (-> i32Vec),
                        : [a] "0" (a),
                          [b] "x" (b),
                    ),
                    .aarch64 => {
                        // vmull_s16(low, low) + vmull_high_s16(full, full) then pairwise add
                        // Equivalent to vpmaddwd: multiply pairs of i16 and add adjacent products to i32
                        const lo: @Vector(4, i32) = asm (
                            \\smull %[ret].4s, %[a].4h, %[b].4h
                            : [ret] "=w" (-> @Vector(4, i32)),
                            : [a] "w" (a),
                              [b] "w" (b),
                        );
                        const hi: @Vector(4, i32) = asm (
                            \\smull2 %[ret].4s, %[a].8h, %[b].8h
                            : [ret] "=w" (-> @Vector(4, i32)),
                            : [a] "w" (a),
                              [b] "w" (b),
                        );
                        return asm (
                            \\addp %[ret].4s, %[lo].4s, %[hi].4s
                            : [ret] "=w" (-> i32Vec),
                            : [lo] "w" (lo),
                              [hi] "w" (hi),
                        );
                    },
                    .fallback => {
                        const u_parts = std.simd.deinterlace(2, a);
                        const i_parts = std.simd.deinterlace(2, b);

                        const products_even =
                            @as(i32Vec, u_parts[0]) *
                            @as(i32Vec, i_parts[0]);
                        const products_odd =
                            @as(i32Vec, u_parts[1]) *
                            @as(i32Vec, i_parts[1]);

                        return products_even + products_odd;
                    },
                }
            }

            fn mulhi(a: i16Vec, b: i16Vec) i16Vec {
                switch (TARGET) {
                    .avx512vnni, .avx512, .avx2 => return asm ("vpmulhw %[b], %[a], %[ret]"
                        : [ret] "=x" (-> i16Vec),
                        : [a] "x" (a),
                          [b] "x" (b),
                    ),
                    .ssse3, .sse2 => return asm ("pmulhw %[b], %[a]"
                        : [ret] "=x" (-> i16Vec),
                        : [a] "0" (a),
                          [b] "x" (b),
                    ),
                    .aarch64 => {
                        // smull -> multiply low 4 i16 pairs, widening to 4 i32
                        const lo: @Vector(4, i32) = asm (
                            \\smull %[ret].4s, %[a].4h, %[b].4h
                            : [ret] "=w" (-> @Vector(4, i32)),
                            : [a] "w" (a),
                              [b] "w" (b),
                        );
                        // smull2 -> multiply high 4 i16 pairs, widening to 4 i32
                        const hi: @Vector(4, i32) = asm (
                            \\smull2 %[ret].4s, %[a].8h, %[b].8h
                            : [ret] "=w" (-> @Vector(4, i32)),
                            : [a] "w" (a),
                              [b] "w" (b),
                        );
                        const lo_as_i16: i16Vec = @bitCast(lo);
                        const hi_as_i16: i16Vec = @bitCast(hi);
                        // uzp2 -> extract high 16 bits from each i32 lane and combine back to 8 i16
                        return asm (
                            \\uzp2 %[ret].8h, %[lo].8h, %[hi].8h
                            : [ret] "=w" (-> i16Vec),
                            : [lo] "w" (lo_as_i16),
                              [hi] "w" (hi_as_i16),
                        );
                    },
                    .fallback => {
                        const WideVec = @Vector(vecSize(i16), i32);
                        const products: WideVec =
                            @as(WideVec, @intCast(a)) * @as(WideVec, @intCast(b));
                        return @as(i16Vec, @intCast(products >> @as(WideVec, @splat(16))));
                    },
                }
            }

            fn packus(a: i16Vec, b: i16Vec) u8Vec {
                switch (TARGET) {
                    .avx512vnni, .avx512, .avx2 => return asm ("vpackuswb %[b], %[a], %[ret]"
                        : [ret] "=x" (-> u8Vec),
                        : [a] "x" (a),
                          [b] "x" (b),
                    ),
                    .aarch64 => {
                        // NEON: vqmovun_s16 (saturating move unsigned narrow)
                        // packus(a, b) packs two i16 vecs into one u8 vec with unsigned saturation
                        // x86 vpackuswb packs a in low half, b in high half
                        const lo: @Vector(8, u8) = asm (
                            \\sqxtun %[ret].8b, %[v].8h
                            : [ret] "=w" (-> @Vector(8, u8)),
                            : [v] "w" (a),
                        );
                        const result: u8Vec = asm (
                            \\sqxtun2 %[ret].16b, %[v].8h
                            : [ret] "=w" (-> u8Vec),
                            : [v] "w" (b),
                              [_] "0" (lo),
                        );
                        return result;
                    },
                    .ssse3, .sse2 => return asm ("packuswb %[b], %[a]"
                        : [ret] "=x" (-> u8Vec),
                        : [a] "0" (a),
                          [b] "x" (b),
                    ),
                    .fallback => {
                        const LO: i16Vec = @splat(0);
                        const a_packed: @Vector(vecSize(i16), u8) = @intCast(@max(a, LO));
                        const b_packed: @Vector(vecSize(i16), u8) = @intCast(@max(b, LO));
                        const halves: [2]@Vector(vecSize(i16), u8) = .{ a_packed, b_packed };
                        return @bitCast(halves);
                    },
                }
            }

            fn dpbusd(sum: i32Vec, u: u8Vec, i: i8Vec) i32Vec {
                switch (TARGET) {
                    .avx512vnni => {
                        var s = sum;
                        asm ("vpdpbusd %[i], %[u], %[s]"
                            : [s] "+x" (s),
                            : [u] "x" (u),
                              [i] "x" (i),
                        );
                        return s;
                    },
                    .avx512, .avx2, .ssse3, .sse2, .fallback => {
                        const partial_sums = maddubs(u, i);

                        const ones: i16Vec = @splat(1);
                        const dot_products = maddwd(partial_sums, ones);
                        return sum + dot_products;
                    },
                    .aarch64 => {
                        // Re-interpret u8 as i8
                        const u_i8: i8Vec = @bitCast(u);

                        // smull: signed multiply low 8 bytes -> 8 x i16
                        const lo: @Vector(8, i16) = asm (
                            \\smull %[ret].8h, %[u].8b, %[i].8b
                            : [ret] "=w" (-> @Vector(8, i16)),
                            : [u] "w" (u_i8),
                              [i] "w" (i),
                        );

                        // smull2: signed multiply high 8 bytes -> 8 x i16
                        const hi: @Vector(8, i16) = asm (
                            \\smull2 %[ret].8h, %[u].16b, %[i].16b
                            : [ret] "=w" (-> @Vector(8, i16)),
                            : [u] "w" (u_i8),
                              [i] "w" (i),
                        );

                        // addp: pairwise add i16 pairs
                        const pairwise: @Vector(8, i16) = asm (
                            \\addp %[ret].8h, %[lo].8h, %[hi].8h
                            : [ret] "=w" (-> @Vector(8, i16)),
                            : [lo] "w" (lo),
                              [hi] "w" (hi),
                        );

                        // sadalp: pairwise add-accumulate i16 into i32
                        return asm (
                            \\sadalp %[s].4s, %[p].8h
                            : [s] "=w" (-> i32Vec),
                            : [p] "w" (pairwise),
                              [_] "0" (sum),
                        );
                    },
                }
            }

            fn dpbusdx2(sum: i32Vec, u_1: u8Vec, i_1: i8Vec, u_2: u8Vec, i_2: i8Vec) i32Vec {
                switch (TARGET) {
                    .avx512vnni => return dpbusd(dpbusd(sum, u_1, i_1), u_2, i_2),
                    .avx512, .avx2, .aarch64, .ssse3, .sse2, .fallback => {
                        const partial_sums_1 = maddubs(u_1, i_1);
                        const partial_sums_2 = maddubs(u_2, i_2);

                        const ones: i16Vec = @splat(1);
                        const dot_products = maddwd(partial_sums_1 + partial_sums_2, ones);

                        return sum + dot_products;
                    },
                }
            }
        };
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

                s1 = std.math.clamp(s1, LO, HI);
                s2 = @min(s2, HI);
                s3 = std.math.clamp(s3, LO, HI);
                s4 = @min(s4, HI);

                n1 = std.math.clamp(n1, LO, HI);
                n2 = @min(n2, HI);
                n3 = std.math.clamp(n3, LO, HI);
                n4 = @min(n4, HI);

                const sp1 = c.mulhi(s1 << @splat(7), s2);
                const sp2 = c.mulhi(s3 << @splat(7), s4);

                const np1 = c.mulhi(n1 << @splat(7), n2);
                const np2 = c.mulhi(n3 << @splat(7), n4);

                const p1: u8Vec = c.packus(sp1, sp2);
                const p2: u8Vec = c.packus(np1, np2);

                @as(*u8Vec, @ptrCast(@alignCast(activated_ft[i..].ptr))).* = p1;
                @as(*u8Vec, @ptrCast(@alignCast(activated_ft[i + L1_SIZE / 2 ..].ptr))).* = p2;
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

            while (i_outer + 2 * L2_UNROLL <= num_nonzero_indices) : (i_outer += 2 * L2_UNROLL) {
                for (0..L2_SIZE / vecSize(i32)) |j| {
                    for (0..L2_UNROLL) |i_inner| {
                        const i_1 = nonzero_indices[i_outer + 2 * i_inner];
                        const i_2 = nonzero_indices[i_outer + 2 * i_inner + 1];
                        const ft_vec_1: u8Vec = @bitCast(@as(i32Vec, @splat(ft_i32[i_1])));
                        const ft_vec_2: u8Vec = @bitCast(@as(i32Vec, @splat(ft_i32[i_2])));
                        l1_intermediate[j][i_inner] = c.dpbusdx2(
                            l1_intermediate[j][i_inner],
                            ft_vec_1,
                            w[i_1 * L2_SIZE * 4 + j * vecSize(i8) ..][0..vecSize(i8)].*,
                            ft_vec_2,
                            w[i_2 * L2_SIZE * 4 + j * vecSize(i8) ..][0..vecSize(i8)].*,
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
        var l1_out_vec: [2 * L2_SIZE / vecSize(i32)]i32Vec = undefined;
        {
            const l1_bias_vec: [*]const i32Vec = @ptrCast(@alignCast(&(&weights.l1b)[output_bucket]));
            const SHIFT = comptime Q0_BITS * 2 - 9 + Q1_BITS - Q_BITS;
            const LO: i32Vec = @splat(0);
            const HI: i32Vec = @splat(Q);
            const HI2: i32Vec = @splat(Q * Q);
            for (0..L2_SIZE / vecSize(i32)) |i| {
                const biases: i32Vec = l1_bias_vec[i];

                var intermediate: i32Vec = @splat(0);
                for (l1_intermediate[i]) |e| {
                    intermediate += e;
                }

                // NOTE: PLEASE BE CAREFUL WITH THE QUANTISATION OF THESE BIASES
                const shifted = intermediate + biases >> @splat(SHIFT);

                const crelu = std.math.clamp(shifted, LO, HI) << @splat(Q_BITS);
                const csrelu = std.math.clamp(shifted * shifted, LO, HI2);

                l1_out_vec[i] = crelu;
                l1_out_vec[i + L2_SIZE / vecSize(i32)] = csrelu;
            }
        }

        // in Q³
        var l2_intermediate: [L3_SIZE / vecSize(i32)]i32Vec = @bitCast((&weights.l2b)[output_bucket]);
        {
            const l1_out: *const [2 * L2_SIZE]i32 = @ptrCast(&l1_out_vec);
            const l2_weight_vec: *const [2 * L2_SIZE][L3_SIZE / vecSize(i32)]i32Vec = @ptrCast(@alignCast(&(&weights.l2w)[output_bucket]));
            for (0..L2_SIZE * 2) |i| {
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
            const LO: i32Vec = @splat(0);
            const HI3: i32Vec = @splat(Q * Q * Q);
            for (0..L3_SIZE / vecSize(i32)) |i| {
                const activated = std.math.clamp(l2_intermediate[i], LO, HI3);
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
