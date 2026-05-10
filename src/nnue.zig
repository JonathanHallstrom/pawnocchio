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
const builtin = @import("builtin");
const Board = root.Board;
const Square = root.Square;
const PieceType = root.PieceType;
const Bitboard = root.Bitboard;
const Colour = root.Colour;
const evaluation = root.evaluation;
const Move = root.Move;

const arch = @import("nnue_arch.zig");
const numa = @import("numa.zig");

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
pub const VEC_BYTES = arch.VEC_BYTES;
pub const vecSize = arch.vecSize;
pub const AccumulatorVec = arch.AccumulatorVec;
pub const ACCUMULATOR_VECTOR_COUNT = arch.ACCUMULATOR_VECTOR_COUNT;
pub const RawAccumulator = arch.RawAccumulator;

pub const Accumulator = struct {
    data: [L1_SIZE]i16 align(64),

    pub inline fn vecs(self: anytype) root.inheritConstness(@TypeOf(self), *align(64) RawAccumulator) {
        return @ptrCast(&self.data);
    }

    inline fn addSubManyImpl(dest: *Accumulator, src: *const Accumulator, adds: anytype, subs: anytype) void {
        var i: usize = 0;

        const UNROLL = 1;
        while (i + UNROLL <= ACCUMULATOR_VECTOR_COUNT) : (i += UNROLL) {
            var vals: [UNROLL]AccumulatorVec = undefined;
            inline for (0..UNROLL) |j| {
                vals[j] = src.vecs()[i + j];
            }

            inline for (0..UNROLL) |j| {
                inline for (adds) |a| {
                    vals[j] += a[i + j];
                }
                inline for (subs) |s| {
                    vals[j] -= s[i + j];
                }
            }

            inline for (0..UNROLL) |j| {
                dest.vecs()[i + j] = vals[j];
            }
            std.mem.doNotOptimizeAway(i);
        }

        while (i + 1 <= ACCUMULATOR_VECTOR_COUNT) : (i += 1) {
            var vals: AccumulatorVec = src.vecs()[i];

            inline for (adds) |a| {
                vals += a[i];
            }
            inline for (subs) |s| {
                vals -= s[i];
            }

            dest.vecs()[i] = vals;
        }
    }

    pub inline fn addSubMany(
        self: *Accumulator,
        adds: anytype,
        subs: anytype,
    ) void {
        self.addSubManyImpl(self, adds, subs);
    }

    pub inline fn copyAddSubMany(
        self: *Accumulator,
        noalias src: *const Accumulator,
        adds: anytype,
        subs: anytype,
    ) void {
        self.addSubManyImpl(src, adds, subs);
    }

    pub inline fn add(
        self: *Accumulator,
        weights: *const RawAccumulator,
    ) void {
        self.addSubMany(.{weights}, .{});
    }

    pub inline fn copyAdd(
        self: *Accumulator,
        noalias src: *const Accumulator,
        weights: *const RawAccumulator,
    ) void {
        self.copyAddSubMany(src, .{weights}, .{});
    }

    pub inline fn sub(
        self: *Accumulator,
        weights: *const RawAccumulator,
    ) void {
        self.addSubMany(.{}, .{weights});
    }

    pub inline fn addMany(
        self: *Accumulator,
        comptime N: usize,
        adds: [N]*const RawAccumulator,
    ) void {
        self.addSubMany(adds, .{});
    }

    pub inline fn subMany(
        self: *Accumulator,
        comptime N: usize,
        subs: [N]*const RawAccumulator,
    ) void {
        self.addSubMany(.{}, subs);
    }
};

pub fn AccumulatorStack(comptime N: usize) type {
    return [N][2]Accumulator;
}

pub fn accumulatorStack(comptime N: usize) AccumulatorStack(N) {
    return undefined;
}

pub const AccumulatorHalf = struct {
    pub const Generation = u64;

    ptr: *const Accumulator,
    generation: Generation = 0,
};

const build_options = @import("build_options");
const use_numa = build_options.use_numa and builtin.os.tag == .linux and builtin.link_libc;

pub inline fn whichInputBucket(stm: Colour, king_square: Square) usize {
    return @min(INPUT_BUCKET_COUNT - 1, INPUT_BUCKET_LAYOUT[(if (stm == .white) king_square else king_square.flipRank()).toInt()]);
}

pub inline fn whichOutputBucket(board: *const Board) usize {
    const max_piece_count = 32;
    const divisor = (max_piece_count + OUTPUT_BUCKET_COUNT - 1) / OUTPUT_BUCKET_COUNT;
    return @min(OUTPUT_BUCKET_COUNT - 1, (@popCount(board.occupancy()) - 2) / divisor);
}

const net = @embedFile("net");
const verbatim_backing: [net.len:0]u8 align(64) = net.*;

pub var verbatim_weights: *const Weights = @ptrCast(&verbatim_backing);
var weights_by_node: numa.PerNode(Weights) = .{};

pub export fn setWeights(w: *const Weights) void {
    verbatim_weights = w;
}

pub fn init() !void {
    if (!use_numa) {
        return;
    }

    try weights_by_node.allocCopyToAll(verbatim_weights);
}

pub fn deinit() void {
    if (!use_numa) {
        return;
    }

    weights_by_node.deinit();
}

pub fn weightsForNode(node: usize) *const Weights {
    if (!use_numa) {
        return verbatim_weights;
    }

    std.debug.assert(numa.isActive());
    return weights_by_node.getConst(node) orelse unreachable;
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

pub inline fn feature(
    weights: *const Weights,
    perspective: Colour,
    side: Colour,
    king_sq: Square,
    tp: PieceType,
    sq_inp: Square,
    mirror: MirroringType,
) *const RawAccumulator {
    const bucket = whichInputBucket(perspective, king_sq);

    const side_idx: usize = if (perspective == side) 0 else 1;

    var sq = sq_inp;
    if (perspective == .black) {
        @branchHint(.unpredictable);
        sq = sq.flipRank();
    }
    if (mirror.read()) {
        @branchHint(.unpredictable);
        sq = sq.flipFile();
    }

    return &weights.ft_w[bucket][side_idx][tp.toInt()][sq.toInt()];
}

pub const State = struct {
    white: AccumulatorHalf,
    black: AccumulatorHalf,
    ply: u16,

    dirty_piece: DirtyPiece,
    pending_parent: bool,
    board_ref: ?*const Board,

    white_mirrored: MirroringType,
    black_mirrored: MirroringType,

    pub inline fn default(weights: *const Weights) State {
        return .{
            .white = .{ .ptr = @ptrCast(&weights.ft_b) },
            .black = .{ .ptr = @ptrCast(&weights.ft_b) },
            .ply = 0,
            .white_mirrored = .{},
            .black_mirrored = .{},
            .dirty_piece = .clean,
            .pending_parent = false,
            .board_ref = null,
        };
    }

    inline fn vecAccFor(self: anytype, col: Colour) *align(64) const RawAccumulator {
        return (if (col == .white) self.white.ptr else self.black.ptr).vecs();
    }

    inline fn mirrorFor(self: anytype, col: Colour) MirroringType {
        return if (col == .white) self.white_mirrored else self.black_mirrored;
    }

    inline fn mirrorPtrFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *MirroringType) {
        return if (col == .white) &self.white_mirrored else &self.black_mirrored;
    }

    fn setMirrored(self: *State, board: *const Board) void {
        self.white_mirrored.write(Square.fromBitboard(board.kingFor(.white)).getFile().toInt() >= 4);
        self.black_mirrored.write(Square.fromBitboard(board.kingFor(.black)).getFile().toInt() >= 4);
    }

    pub fn initInPlace(
        self: *State,
        board: *const Board,
        weights: *const Weights,
        ctx: evaluation.Context,
    ) void {
        self.* = default(weights);
        self.setMirrored(board);
        self.board_ref = board;

        const white_king_sq = Square.fromBitboard(board.kingFor(.white));
        const black_king_sq = Square.fromBitboard(board.kingFor(.black));
        for (PieceType.all) |tp| {
            {
                var iter = Bitboard.iterator(board.pieceFor(.white, tp));
                while (iter.next()) |sq| {
                    self.writeFeature(weights, .white, .white, white_king_sq, tp, sq, ctx);
                    self.writeFeature(weights, .black, .white, black_king_sq, tp, sq, ctx);
                }
            }
            {
                var iter = Bitboard.iterator(board.pieceFor(.black, tp));
                while (iter.next()) |sq| {
                    self.writeFeature(weights, .white, .black, white_king_sq, tp, sq, ctx);
                    self.writeFeature(weights, .black, .black, black_king_sq, tp, sq, ctx);
                }
            }
        }
    }

    pub fn update(
        noalias self: *State,
        other: *State,
        board: *const Board,
    ) void {
        std.debug.assert(@intFromPtr(other) + @sizeOf(State) == @intFromPtr(self));
        self.ply = other.ply + 1;
        self.pending_parent = true;
        self.board_ref = board;
        self.dirty_piece = .clean;
    }

    fn resolvePending(noalias self: *State, comptime stm: Colour, ctx: evaluation.Context) bool {
        if (!self.pending_parent) {
            return false;
        }
        const parent: *State = @ptrFromInt(@intFromPtr(self) - @sizeOf(State));
        const parent_fresh = parent.resolvePending(stm.flipped(), ctx);
        const board = self.board_ref orelse unreachable;
        std.debug.assert(board.stm == stm);
        const fresh = self.applyDirty(.copy, parent, parent_fresh, stm.flipped(), board, ctx);
        self.pending_parent = false;
        return fresh;
    }

    inline fn refreshStale(self: *State, weights: *const Weights, refresh_cache: anytype) void {
        if (self.white.generation != 0 and self.white.generation != refresh_cache.currentGeneration(.white)) {
            const board = self.board_ref orelse unreachable;
            self.refreshHalf(weights, refresh_cache, .white, board);
        }
        if (self.black.generation != 0 and self.black.generation != refresh_cache.currentGeneration(.black)) {
            const board = self.board_ref orelse unreachable;
            self.refreshHalf(weights, refresh_cache, .black, board);
        }
    }

    pub fn init(board: *const Board, weights: *const Weights, ctx: evaluation.Context) State {
        var acc = default(weights);
        acc.initInPlace(board, weights, ctx);
        return acc;
    }

    inline fn buffer(self: *State, col: Colour, ctx: evaluation.Context) *Accumulator {
        return &ctx.accumulator_stack[self.ply][col.toInt()];
    }

    inline fn half(self: anytype, comptime acc: Colour) root.inheritConstness(@TypeOf(self), *AccumulatorHalf) {
        return if (acc == .white) &self.white else &self.black;
    }

    inline fn setHalf(self: *State, comptime acc: Colour, ptr: *const Accumulator) void {
        self.half(acc).* = .{ .ptr = ptr };
    }

    pub inline fn refreshHalf(self: *State, weights: *const Weights, refresh_cache: anytype, comptime acc: Colour, board: *const Board) void {
        self.mirrorPtrFor(acc).write(Square.fromBitboard(board.kingFor(acc)).getFile().toInt() >= 4);
        const refreshed = refresh_cache.refresh(weights, acc, board);
        self.half(acc).* = refreshed;
    }

    pub inline fn markClean(self: *State, board: *const Board) void {
        self.pending_parent = false;
        self.dirty_piece = .clean;
        self.board_ref = board;
    }

    inline fn writeFeature(self: *State, weights: *const Weights, comptime acc: Colour, comptime side: Colour, king_sq: Square, tp: PieceType, sq: Square, ctx: evaluation.Context) void {
        const self_buf = self.buffer(acc, ctx);
        self_buf.copyAdd(
            self.half(acc).ptr,
            feature(weights, acc, side, king_sq, tp, sq, self.mirrorFor(acc)),
        );
        self.setHalf(acc, self_buf);
    }

    inline fn writeMove(self: *State, other: *const State, weights: *const Weights, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square, ctx: evaluation.Context) void {
        const self_buf = self.buffer(acc, ctx);
        self_buf.copyAddSubMany(
            other.half(acc).ptr,
            .{feature(weights, acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc))},
            .{feature(weights, acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc))},
        );
        self.setHalf(acc, self_buf);
    }

    inline fn writeCapture(self: *State, other: *const State, weights: *const Weights, comptime acc: Colour, comptime side: Colour, king_sq: Square, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square, opp_sub_tp: PieceType, opp_sub_sq: Square, ctx: evaluation.Context) void {
        const self_buf = self.buffer(acc, ctx);
        self_buf.copyAddSubMany(
            other.half(acc).ptr,
            .{
                feature(weights, acc, side, king_sq, add_tp, add_sq, self.mirrorFor(acc)),
            },
            .{
                feature(weights, acc, side, king_sq, sub_tp, sub_sq, self.mirrorFor(acc)),
                feature(weights, acc, side.flipped(), king_sq, opp_sub_tp, opp_sub_sq, self.mirrorFor(acc)),
            },
        );
        self.setHalf(acc, self_buf);
    }

    inline fn writeCastle(self: *State, other: *const State, weights: *const Weights, comptime acc: Colour, comptime side: Colour, king_sq: Square, add1_tp: PieceType, add1_sq: Square, add2_tp: PieceType, add2_sq: Square, sub1_tp: PieceType, sub1_sq: Square, sub2_tp: PieceType, sub2_sq: Square, ctx: evaluation.Context) void {
        const self_buf = self.buffer(acc, ctx);
        self_buf.copyAddSubMany(
            other.half(acc).ptr,
            .{
                feature(weights, acc, side, king_sq, add1_tp, add1_sq, self.mirrorFor(acc)),
                feature(weights, acc, side, king_sq, add2_tp, add2_sq, self.mirrorFor(acc)),
            },
            .{
                feature(weights, acc, side, king_sq, sub1_tp, sub1_sq, self.mirrorFor(acc)),
                feature(weights, acc, side, king_sq, sub2_tp, sub2_sq, self.mirrorFor(acc)),
            },
        );
        self.setHalf(acc, self_buf);
    }

    fn needsRefresh(stm: Colour, from: Square, to: Square) bool {
        if (HORIZONTAL_MIRRORING and (from.getFile().toInt() >= 4) != (to.getFile().toInt() >= 4)) {
            return true;
        }
        return whichInputBucket(stm, from) != whichInputBucket(stm, to);
    }

    fn applyDirty(
        noalias self: *State,
        comptime mode: enum { copy, inplace },
        noalias other: if (mode == .inplace) @TypeOf(null) else *State,
        parent_fresh: if (mode == .inplace) void else bool,
        comptime stm: Colour,
        board: *const Board,
        ctx: evaluation.Context,
    ) bool {
        const weights = ctx.weights;
        const refresh_cache = ctx.refresh_cache;
        if (mode == .copy) {
            self.white_mirrored = other.white_mirrored;
            self.black_mirrored = other.black_mirrored;
        }
        if (self.dirty_piece.isClean()) {
            if (mode == .copy) {
                self.white = other.white;
                self.black = other.black;
                return parent_fresh;
            }
            return false;
        }
        defer self.dirty_piece.clear();
        if (mode == .copy) {
            other.refreshStale(weights, refresh_cache);
        } else {
            self.refreshStale(weights, refresh_cache);
        }
        const copy = if (mode == .inplace) self else other;
        const us_king_sq = Square.fromBitboard(board.kingFor(stm));
        const them_king_sq = Square.fromBitboard(board.kingFor(stm.flipped()));
        switch (self.dirty_piece) {
            .clean => unreachable,
            .add_sub => |state| {
                self.writeMove(copy, weights, stm.flipped(), stm, them_king_sq, state.add.pt, state.add.sq, state.sub.pt, state.sub.sq, ctx);
                if (state.add.pt == .king and needsRefresh(stm, state.add.sq, state.sub.sq)) {
                    @branchHint(.unlikely);
                    self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                    self.refreshHalf(weights, refresh_cache, stm, board);
                } else {
                    self.writeMove(copy, weights, stm, stm, us_king_sq, state.add.pt, state.add.sq, state.sub.pt, state.sub.sq, ctx);
                }
            },
            .add_sub_sub => |state| {
                self.writeCapture(copy, weights, stm.flipped(), stm, them_king_sq, state.add.pt, state.add.sq, state.sub1.pt, state.sub1.sq, state.sub2.pt, state.sub2.sq, ctx);
                if (state.add.pt == .king and needsRefresh(stm, state.add.sq, state.sub1.sq)) {
                    @branchHint(.unlikely);
                    self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                    self.refreshHalf(weights, refresh_cache, stm, board);
                } else {
                    self.writeCapture(copy, weights, stm, stm, us_king_sq, state.add.pt, state.add.sq, state.sub1.pt, state.sub1.sq, state.sub2.pt, state.sub2.sq, ctx);
                }
            },
            .add_add_sub_sub => |state| {
                self.writeCastle(copy, weights, stm.flipped(), stm, them_king_sq, state.add1.pt, state.add1.sq, state.add2.pt, state.add2.sq, state.sub1.pt, state.sub1.sq, state.sub2.pt, state.sub2.sq, ctx);
                if (needsRefresh(stm, state.add1.sq, state.sub1.sq)) {
                    @branchHint(.unlikely);
                    self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
                    self.refreshHalf(weights, refresh_cache, stm, board);
                } else {
                    self.writeCastle(copy, weights, stm, stm, us_king_sq, state.add1.pt, state.add1.sq, state.add2.pt, state.add2.sq, state.sub1.pt, state.sub1.sq, state.sub2.pt, state.sub2.sq, ctx);
                }
            },
        }
        return true;
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

    pub fn forward(noalias self: *State, comptime stm: Colour, board: *const Board, ctx: evaluation.Context) i16 {
        const weights = ctx.weights;
        var fresh = self.resolvePending(stm, ctx);
        if (!self.dirty_piece.isClean()) {
            fresh = self.applyDirty(.inplace, null, {}, stm.flipped(), board, ctx);
        }
        std.debug.assert(board.stm == stm);
        if (!fresh) {
            self.refreshStale(weights, ctx.refresh_cache);
        }

        const stm_acc = if (stm == .white) self.white.ptr else self.black.ptr;
        const ntm_acc = if (stm == .white) self.black.ptr else self.white.ptr;

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
                var s1: i16Vec = stm_acc.data[i..][0..vecSize(i16)].*;
                var s2: i16Vec = stm_acc.data[i + L1_SIZE / 2 ..][0..vecSize(i16)].*;
                var s3: i16Vec = stm_acc.data[i + vecSize(i16) ..][0..vecSize(i16)].*;
                var s4: i16Vec = stm_acc.data[i + vecSize(i16) + L1_SIZE / 2 ..][0..vecSize(i16)].*;

                var n1: i16Vec = ntm_acc.data[i..][0..vecSize(i16)].*;
                var n2: i16Vec = ntm_acc.data[i + L1_SIZE / 2 ..][0..vecSize(i16)].*;
                var n3: i16Vec = ntm_acc.data[i + vecSize(i16) ..][0..vecSize(i16)].*;
                var n4: i16Vec = ntm_acc.data[i + vecSize(i16) + L1_SIZE / 2 ..][0..vecSize(i16)].*;

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
            const w: [*]const i8 = &weights.l1w[output_bucket];
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
            const l1_bias_vec: [*]const i32Vec = @ptrCast(@alignCast(&weights.l1b[output_bucket]));
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
        var l2_intermediate: [L3_SIZE / vecSize(i32)]i32Vec = @bitCast(weights.l2b[output_bucket]);
        {
            const l1_out: *const [2 * L2_SIZE]i32 = @ptrCast(&l1_out_vec);
            const l2_weight_vec: *const [2 * L2_SIZE][L3_SIZE / vecSize(i32)]i32Vec = @ptrCast(@alignCast(&weights.l2w[output_bucket]));
            for (0..L2_SIZE * 2) |i| {
                const l1_vec: i32Vec = @splat(l1_out[i]);
                for (0..L3_SIZE / vecSize(i32)) |j| {
                    l2_intermediate[j] += l1_vec * l2_weight_vec[i][j];
                }
            }
        }

        // in Q⁴
        var l3_sum: i32Vec = @splat(0);
        {
            const l3_weight_vec: *const [L3_SIZE / vecSize(i32)]i32Vec = @ptrCast(@alignCast(&weights.l3w[output_bucket]));
            const LO: i32Vec = @splat(0);
            const HI3: i32Vec = @splat(Q * Q * Q);
            for (0..L3_SIZE / vecSize(i32)) |i| {
                const activated = std.math.clamp(l2_intermediate[i], LO, HI3);
                l3_sum += activated * l3_weight_vec[i];
            }
        }

        const bias = weights.l3b[output_bucket];
        const scaled = (@reduce(.Add, l3_sum) + bias) * SCALE;

        return evaluation.clampScore(@divTrunc(scaled, arch.Q * arch.Q * arch.Q * arch.Q));
    }
};

pub fn evaluate(comptime stm: Colour, board: *const Board, eval_state: *State, ctx: evaluation.Context) i16 {
    return eval_state.forward(stm, board, ctx);
}

pub fn evalPosition(board: *const Board) i16 {
    const RefreshCache = @import("refresh_cache.zig").refreshCache(HORIZONTAL_MIRRORING, INPUT_BUCKET_COUNT);
    const weights = weightsForNode(0);
    var cache: RefreshCache = undefined;
    cache.initInPlace(weights);
    var accumulator_stack = accumulatorStack(1);
    var acc: State = State.default(weights);
    const ctx: evaluation.Context = .{
        .weights = weights,
        .refresh_cache = &cache,
        .accumulator_stack = &accumulator_stack,
    };
    acc.initInPlace(board, weights, ctx);
    switch (board.stm) {
        inline else => |stm| {
            return acc.forward(stm, board, ctx);
        },
    }
}
