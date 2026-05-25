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
const ColouredPieceType = root.ColouredPieceType;
const evaluation = root.evaluation;
const Move = root.Move;
const CastlingRights = root.CastlingRights;

const arch = @import("nnue_arch.zig");
const numa = @import("numa.zig");
const simd = @import("simd.zig");
const nnue_threats = @import("nnue_threats.zig");
const nnue_threat_updates = @import("nnue_threat_updates.zig");
const ThreatUpdateBuffer = nnue_threat_updates.ThreatUpdateBuffer;

const Q_BITS: comptime_int = std.math.log2_int_ceil(u32, arch.Q);
const Q0_BITS: comptime_int = std.math.log2_int_ceil(u32, arch.Q0);
const Q1_BITS: comptime_int = std.math.log2_int_ceil(u32, arch.Q1);

pub const Accumulator = struct {
    data: [arch.L1_SIZE]i16 align(64),

    pub inline fn vecs(self: anytype) root.inheritConstness(@TypeOf(self), *align(64) arch.RawAccumulator) {
        return @ptrCast(&self.data);
    }

    inline fn addImpl(
        self: *Accumulator,
        noalias src: *const Accumulator,
        adds: anytype,
        subs: anytype,
    ) void {
        for (0..arch.ACCUMULATOR_VECTOR_COUNT) |i| {
            var vals: arch.AccumulatorVec = src.vecs()[i];

            inline for (adds) |a| {
                vals += a[i];
            }
            inline for (subs) |s| {
                vals -= s[i];
            }

            self.vecs()[i] = vals;
        }
    }

    pub fn copyAddSubMany(
        self: *Accumulator,
        noalias src: *const Accumulator,
        adds: anytype,
        subs: anytype,
    ) void {
        self.addImpl(src, adds, subs);
    }

    pub fn addSubMany(
        self: *Accumulator,
        adds: anytype,
        subs: anytype,
    ) void {
        self.addImpl(self, adds, subs);
    }

    pub fn add(
        self: *Accumulator,
        weights: *const arch.RawAccumulator,
    ) void {
        self.addImpl(self, .{weights}, .{});
    }

    pub fn sub(
        self: *Accumulator,
        weights: *const arch.RawAccumulator,
    ) void {
        self.addImpl(self, .{}, .{weights});
    }

    pub fn addMany(
        self: *Accumulator,
        comptime N: usize,
        adds: [N]*const arch.RawAccumulator,
    ) void {
        self.addImpl(self, adds, .{});
    }

    pub fn subMany(
        self: *Accumulator,
        comptime N: usize,
        subs: [N]*const arch.RawAccumulator,
    ) void {
        self.addImpl(self, .{}, subs);
    }

    pub fn copyAdd(
        self: *Accumulator,
        noalias src: *const Accumulator,
        weights: *const arch.RawAccumulator,
    ) void {
        self.addImpl(src, .{weights}, .{});
    }

    pub fn addThreat(
        self: *Accumulator,
        weights: *const arch.ThreatWeight,
    ) void {
        self.addImpl(self, .{weights}, .{});
    }
};

pub const AccumulatorHalf = struct {
    pub const Generation = u64;

    ptr: *const Accumulator,
    generation: Generation = 0,
};

pub const zero_accumulator: Accumulator align(64) = .{
    .data = [_]i16{0} ** arch.L1_SIZE,
};

const build_options = @import("build_options");
const use_numa = build_options.use_numa and builtin.os.tag == .linux and builtin.link_libc;

const net = @embedFile("net");
const verbatim_backing: [net.len:0]u8 align(64) = net.*;

pub var verbatim_weights: *const arch.Weights = @ptrCast(&verbatim_backing);
var weights_by_node: numa.PerNode(arch.Weights) = .{};

pub export fn setWeights(w: *const arch.Weights) void {
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

pub fn weightsForNode(node: usize) *const arch.Weights {
    if (!use_numa) {
        return verbatim_weights;
    }

    std.debug.assert(numa.isActive());
    return weights_by_node.getConst(node) orelse unreachable;
}

const DirtyPiece = union(enum) {
    clean,
    move: struct {
        to: PSQTFeature,
        from: PSQTFeature,
    },
    capture: struct {
        to: PSQTFeature,
        from: PSQTFeature,
        captured: PSQTFeature,
    },
    castle: struct {
        k_to: Square,
        k_from: Square,
        r_to: Square,
        r_from: Square,
        col: Colour,
    },

    pub inline fn initMove(to_feat: PSQTFeature, from_feat: PSQTFeature) DirtyPiece {
        return .{ .move = .{
            .to = to_feat,
            .from = from_feat,
        } };
    }

    pub inline fn initCapture(to_feat: PSQTFeature, from_feat: PSQTFeature, captured: PSQTFeature) DirtyPiece {
        return .{ .capture = .{
            .to = to_feat,
            .from = from_feat,
            .captured = captured,
        } };
    }

    pub inline fn initCastle(king_to: PSQTFeature, rook_to: PSQTFeature, king_from: PSQTFeature, rook_from: PSQTFeature) DirtyPiece {
        return .{ .castle = .{
            .k_to = king_to.s,
            .k_from = king_from.s,
            .r_to = rook_to.s,
            .r_from = rook_from.s,
            .col = king_to.col(),
        } };
    }

    inline fn clear(self: *DirtyPiece) void {
        self.* = .clean;
    }

    inline fn isClean(self: DirtyPiece) bool {
        return self == .clean;
    }

    inline fn to(self: DirtyPiece) PSQTFeature {
        return switch (self) {
            .clean => unreachable,
            .move => |state| state.to,
            .capture => |state| state.to,
            .castle => |state| .init(state.col, .king, state.k_to),
        };
    }

    inline fn from(self: DirtyPiece) PSQTFeature {
        return switch (self) {
            .clean => unreachable,
            .move => |state| state.from,
            .capture => |state| state.from,
            .castle => |state| .init(state.col, .king, state.k_from),
        };
    }
};

inline fn crossesMiddle(from: Square, to: Square) bool {
    return (from.getFile().toInt() >= 4) != (to.getFile().toInt() >= 4);
}

pub const MirroringType = if (arch.HORIZONTAL_MIRRORING) struct {
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

const FeatureKind = root.FeatureKind;
const PSQTFeature = root.PSQTFeature;

pub inline fn feature(
    weights: *const arch.Weights,
    perspective: Colour,
    king_sq: Square,
    comptime kind: FeatureKind,
    f: PSQTFeature,
    mirror: MirroringType,
) *const arch.RawAccumulator {
    _ = kind;
    const bucket = arch.whichInputBucket(perspective, king_sq);

    const side_idx: usize = if (perspective == f.col()) 0 else 1;

    var sq = f.square();
    if (perspective == .black) {
        @branchHint(.unpredictable);
        sq = sq.flipRank();
    }
    if (mirror.read()) {
        @branchHint(.unpredictable);
        sq = sq.flipFile();
    }

    return &weights.ft_w[bucket][side_idx][f.piece().toInt()][sq.toInt()];
}

const State = struct {
    white: AccumulatorHalf,
    black: AccumulatorHalf,
    white_threat: AccumulatorHalf,
    black_threat: AccumulatorHalf,
    ply: u16,

    dirty_piece: DirtyPiece,
    threat_updates: ThreatUpdateBuffer,
    pending_parent: bool,
    board_ref: ?*const Board,

    white_mirrored: MirroringType,
    black_mirrored: MirroringType,
    white_threat_mirrored: MirroringType,
    black_threat_mirrored: MirroringType,

    pub inline fn default(weights: *const arch.Weights) State {
        return .{
            .white = .{ .ptr = @ptrCast(&weights.ft_b) },
            .black = .{ .ptr = @ptrCast(&weights.ft_b) },
            .white_threat = .{ .ptr = &zero_accumulator },
            .black_threat = .{ .ptr = &zero_accumulator },
            .ply = 0,
            .white_mirrored = .{},
            .black_mirrored = .{},
            .white_threat_mirrored = .{},
            .black_threat_mirrored = .{},
            .dirty_piece = .clean,
            .threat_updates = .{},
            .pending_parent = false,
            .board_ref = null,
        };
    }

    inline fn vecAccFor(self: anytype, col: Colour) *align(64) const arch.RawAccumulator {
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

    inline fn threatMirrorFor(self: anytype, col: Colour) MirroringType {
        return if (col == .white) self.white_threat_mirrored else self.black_threat_mirrored;
    }

    inline fn threatMirrorPtrFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *MirroringType) {
        return if (col == .white) &self.white_threat_mirrored else &self.black_threat_mirrored;
    }

    pub fn initInPlace(
        self: *State,
        board: *const Board,
        weights: *const arch.Weights,
        ctx: *Context,
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
                    self.writeFeature(.white, white_king_sq, .init(.white, tp, sq), ctx);
                    self.writeFeature(.black, black_king_sq, .init(.white, tp, sq), ctx);
                }
            }
            {
                var iter = Bitboard.iterator(board.pieceFor(.black, tp));
                while (iter.next()) |sq| {
                    self.writeFeature(.white, white_king_sq, .init(.black, tp, sq), ctx);
                    self.writeFeature(.black, black_king_sq, .init(.black, tp, sq), ctx);
                }
            }
        }

        self.refreshThreatHalf(ctx, .white, board);
        self.refreshThreatHalf(ctx, .black, board);
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
        self.dirty_piece.clear();
        self.threat_updates.clear();
    }

    fn resolvePending(noalias self: *State, stm: Colour, ctx: *Context) bool {
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

    inline fn refreshStale(self: *State, ctx: *Context) void {
        if (self.white.generation != 0 and self.white.generation != ctx.refresh_cache.currentGeneration(.white)) {
            const board = self.board_ref orelse unreachable;
            self.refreshHalf(ctx, .white, board);
        }
        if (self.black.generation != 0 and self.black.generation != ctx.refresh_cache.currentGeneration(.black)) {
            const board = self.board_ref orelse unreachable;
            self.refreshHalf(ctx, .black, board);
        }
    }

    pub fn init(board: *const Board, weights: *const arch.Weights, ctx: *Context) State {
        var acc = default(weights);
        acc.initInPlace(board, weights, ctx);
        return acc;
    }

    inline fn buffer(self: *State, col: Colour, ctx: *Context) *Accumulator {
        return &ctx.accumulator_stack[self.ply][col.toInt()];
    }

    inline fn half(self: anytype, acc: Colour) root.inheritConstness(@TypeOf(self), *AccumulatorHalf) {
        return if (acc == .white) &self.white else &self.black;
    }

    inline fn setHalf(self: *State, acc: Colour, ptr: *const Accumulator) void {
        self.half(acc).* = .{ .ptr = ptr };
    }

    pub fn refreshHalf(self: *State, ctx: *Context, acc: Colour, board: *const Board) void {
        self.mirrorPtrFor(acc).write(Square.fromBitboard(board.kingFor(acc)).getFile().toInt() >= 4);
        const refreshed = ctx.refresh_cache.refresh(ctx.weights, acc, board);
        self.half(acc).* = refreshed;
    }

    pub inline fn markClean(self: *State, board: *const Board) void {
        self.pending_parent = false;
        self.dirty_piece.clear();
        self.threat_updates.clear();
        self.board_ref = board;
    }

    inline fn writeFeature(self: *State, acc: Colour, king_sq: Square, piece: PSQTFeature, ctx: *Context) void {
        const self_buf = self.buffer(acc, ctx);
        self_buf.copyAdd(
            self.half(acc).ptr,
            feature(ctx.weights, acc, king_sq, .psqt, piece, self.mirrorFor(acc)),
        );
        self.setHalf(acc, self_buf);
    }

    inline fn threatBuffer(self: *State, col: Colour, ctx: *Context) *Accumulator {
        return &ctx.threat_accumulator_stack[self.ply][col.toInt()];
    }

    inline fn threatHalf(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *AccumulatorHalf) {
        return if (col == .white) &self.white_threat else &self.black_threat;
    }

    fn refreshThreatHalf(self: *State, ctx: *Context, col: Colour, board: *const Board) void {
        const buf = self.threatBuffer(col, ctx);
        nnue_threats.refreshThreats(buf, board, col, ctx.weights);
        self.threatHalf(col).* = .{ .ptr = buf };
        self.threatMirrorPtrFor(col).write(Square.fromBitboard(board.kingFor(col)).getFile().toInt() >= 4);
    }

    fn materialiseThreatHalf(
        self: *State,
        noalias parent: *State,
        col: Colour,
        board: *const Board,
        ctx: *Context,
    ) void {
        if (self.threat_updates.refresh[col.toInt()]) {
            self.refreshThreatHalf(ctx, col, board);
            return;
        }

        const adds_raw = self.threat_updates.add.slice();
        const subs_raw = self.threat_updates.sub.slice();

        if (adds_raw.len == 0 and subs_raw.len == 0) {
            self.threatHalf(col).* = parent.threatHalf(col).*;
            self.threatMirrorPtrFor(col).* = parent.threatMirrorFor(col);
            return;
        }

        const king_sq = Square.fromBitboard(board.kingFor(col));
        const weights = ctx.weights;

        const src = parent.threatHalf(col).ptr;
        const dst = self.threatBuffer(col, ctx);

        var add_indices: [ThreatUpdateBuffer.MaxAdds]u32 = undefined;
        var add_count: usize = 0;
        for (adds_raw) |upd| {
            if (nnue_threats.threatIndex(
                col,
                king_sq,
                ColouredPieceType.fromInt(upd.attacker),
                Square.fromInt(upd.from),
                ColouredPieceType.fromInt(upd.victim),
                Square.fromInt(upd.to),
            )) |idx| {
                add_indices[add_count] = idx;
                add_count += 1;
            }
        }

        var sub_indices: [ThreatUpdateBuffer.MaxSubs]u32 = undefined;
        var sub_count: usize = 0;
        for (subs_raw) |upd| {
            if (nnue_threats.threatIndex(
                col,
                king_sq,
                ColouredPieceType.fromInt(upd.attacker),
                Square.fromInt(upd.from),
                ColouredPieceType.fromInt(upd.victim),
                Square.fromInt(upd.to),
            )) |idx| {
                sub_indices[sub_count] = idx;
                sub_count += 1;
            }
        }

        applyThreatRows(dst, src, weights, add_indices[0..add_count], sub_indices[0..sub_count]);
        self.threatHalf(col).* = .{ .ptr = dst };
        self.threatMirrorPtrFor(col).* = parent.threatMirrorFor(col);
    }

    fn applyThreatRows(
        noalias dst: *Accumulator,
        src: *const Accumulator,
        weights: *const arch.Weights,
        adds: []const u32,
        subs: []const u32,
    ) void {
        if (adds.len + subs.len == 0) {
            @memcpy(std.mem.asBytes(&dst.data), std.mem.asBytes(&src.data));
            return;
        }
        applyThreatRowsInner(dst, src, weights, adds, subs);
    }

    fn applyThreatRowsInner(
        noalias dst: *Accumulator,
        src: *const Accumulator,
        weights: *const arch.Weights,
        adds: []const u32,
        subs: []const u32,
    ) void {
        var i: usize = 0;
        const TILE = 8;
        while (i < arch.ACCUMULATOR_VECTOR_COUNT) : (i += TILE) {
            var v: [TILE]arch.AccumulatorVec = src.vecs()[i..][0..TILE].*;
            for (subs) |idx| inline for (0..TILE) |t| {
                v[t] -= weights.threat_w[idx][i + t];
            };
            for (adds) |idx| inline for (0..TILE) |t| {
                v[t] += weights.threat_w[idx][i + t];
            };
            dst.vecs()[i..][0..TILE].* = v;
        }
    }

    fn resolvePendingThreats(self: *State, stm: Colour, ctx: *Context) void {
        if (!self.pending_parent) return;

        const parent: *State = @ptrFromInt(@intFromPtr(self) - @sizeOf(State));
        parent.resolvePendingThreats(stm.flipped(), ctx);

        const board = self.board_ref orelse unreachable;

        inline for ([_]Colour{ .white, .black }) |col| {
            const king_sq = Square.fromBitboard(board.kingFor(col));
            if (needsThreatRefresh(col, parent, king_sq)) {
                self.refreshThreatHalf(ctx, col, board);
            } else {
                self.materialiseThreatHalf(parent, col, board, ctx);
            }
        }
    }

    fn needsThreatRefresh(col: Colour, parent: *State, king_sq: Square) bool {
        if (!arch.HORIZONTAL_MIRRORING) return false;
        const parent_mirrored = parent.threatMirrorFor(col).read();
        const current_mirrored = king_sq.getFile().toInt() >= 4;
        return parent_mirrored != current_mirrored;
    }

    inline fn needsRefresh(stm: Colour, from: Square, to: Square) bool {
        if (arch.HORIZONTAL_MIRRORING and crossesMiddle(from, to)) {
            return true;
        }
        return arch.whichInputBucket(stm, from) != arch.whichInputBucket(stm, to);
    }

    inline fn applyDirty(
        noalias self: *State,
        comptime mode: enum { copy, inplace },
        noalias other: if (mode == .inplace) @TypeOf(null) else *State,
        parent_fresh: if (mode == .inplace) void else bool,
        stm: Colour,
        board: *const Board,
        ctx: *Context,
    ) bool {
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
        const copy: *State = if (mode == .inplace) self else other;
        self.applyDirtyImpl(copy, stm, board, ctx);
        return true;
    }

    inline fn updateHalf(self: *State, copy: *State, acc: Colour, king_sq: Square, dirty: DirtyPiece, ctx: *Context) void {
        const mir = self.mirrorFor(acc);
        const buf = self.buffer(acc, ctx);
        const src = copy.half(acc).ptr;
        const weights = ctx.weights;

        switch (dirty) {
            .move => |state| buf.copyAddSubMany(
                src,
                .{feature(weights, acc, king_sq, .psqt, state.to, mir)},
                .{feature(weights, acc, king_sq, .psqt, state.from, mir)},
            ),
            .capture => |state| buf.copyAddSubMany(
                src,
                .{feature(weights, acc, king_sq, .psqt, state.to, mir)},
                .{
                    feature(weights, acc, king_sq, .psqt, state.from, mir),
                    feature(weights, acc, king_sq, .psqt, state.captured, mir),
                },
            ),
            .castle => |state| buf.copyAddSubMany(
                src,
                .{
                    feature(weights, acc, king_sq, .psqt, .init(state.col, .king, state.k_to), mir),
                    feature(weights, acc, king_sq, .psqt, .init(state.col, .rook, state.r_to), mir),
                },
                .{
                    feature(weights, acc, king_sq, .psqt, .init(state.col, .king, state.k_from), mir),
                    feature(weights, acc, king_sq, .psqt, .init(state.col, .rook, state.r_from), mir),
                },
            ),
            .clean => unreachable,
        }
        self.setHalf(acc, buf);
    }

    fn applyDirtyImpl(
        noalias self: *State,
        copy: *State,
        stm: Colour,
        board: *const Board,
        ctx: *Context,
    ) void {
        const dirty = self.dirty_piece;
        defer self.dirty_piece.clear();

        copy.refreshStale(ctx);

        const them = stm.flipped();
        const them_king_sq = Square.fromBitboard(board.kingFor(them));
        self.updateHalf(copy, them, them_king_sq, dirty, ctx);

        const to_feat = dirty.to();
        const from_feat = dirty.from();

        const us_king_sq = Square.fromBitboard(board.kingFor(stm));
        if (to_feat.piece() == .king and needsRefresh(stm, to_feat.square(), from_feat.square())) {
            @branchHint(.unlikely);
            self.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
            self.refreshHalf(ctx, stm, board);
        } else {
            self.updateHalf(copy, stm, us_king_sq, dirty, ctx);
        }
    }

    pub fn addSub(self: *State, add: PSQTFeature, sub: PSQTFeature) void {
        std.debug.assert(self.dirty_piece.isClean());
        self.dirty_piece = .initMove(add, sub);
    }

    pub fn addSubSub(self: *State, add: PSQTFeature, sub1: PSQTFeature, sub2: PSQTFeature) void {
        std.debug.assert(self.dirty_piece.isClean());
        self.dirty_piece = .initCapture(add, sub1, sub2);
    }

    pub fn addAddSubSub(self: *State, add1: PSQTFeature, add2: PSQTFeature, sub1: PSQTFeature, sub2: PSQTFeature) void {
        std.debug.assert(self.dirty_piece.isClean());
        self.dirty_piece = .initCastle(add1, add2, sub1, sub2);
    }

    pub fn forward(noalias self: *State, board: *const Board, ctx: *Context) i16 {
        const stm = board.stm;
        const weights: *const arch.Weights = ctx.weights;

        self.resolvePendingThreats(stm, ctx);

        if (std.debug.runtime_safety) {
            var white_oracle: Accumulator align(64) = undefined;
            var black_oracle: Accumulator align(64) = undefined;
            nnue_threats.refreshThreats(&white_oracle, board, .white, weights);
            nnue_threats.refreshThreats(&black_oracle, board, .black, weights);
            std.debug.assert(std.mem.eql(i16, &self.white_threat.ptr.data, &white_oracle.data));
            std.debug.assert(std.mem.eql(i16, &self.black_threat.ptr.data, &black_oracle.data));
        }

        var fresh: bool = self.resolvePending(stm, ctx);
        if (!self.dirty_piece.isClean()) {
            fresh = self.applyDirty(.inplace, null, {}, stm.flipped(), board, ctx);
        }
        if (!fresh) {
            self.refreshStale(ctx);
        }

        const stm_acc: *const Accumulator = if (stm == .white) self.white.ptr else self.black.ptr;
        const ntm_acc: *const Accumulator = if (stm == .white) self.black.ptr else self.white.ptr;

        const stm_threat: *const Accumulator = if (stm == .white) self.white_threat.ptr else self.black_threat.ptr;
        const ntm_threat: *const Accumulator = if (stm == .white) self.black_threat.ptr else self.white_threat.ptr;

        const output_bucket: usize = arch.whichOutputBucket(board);

        // in Q0² / 2⁹
        var activated_ft: [arch.L1_SIZE]u8 align(64) = undefined;
        {
            const items_per_iter: usize = simd.vecSize(i16) * 2;
            var i: usize = 0;
            const LO: simd.vector(i16) = @splat(0);
            const HI: simd.vector(i16) = @splat(arch.Q0);
            while (i < arch.L1_SIZE / 2) : (i += items_per_iter) {
                var s1 = readAccs(stm_acc, stm_threat, i);
                var s2 = readAccs(stm_acc, stm_threat, i + arch.L1_SIZE / 2);
                var s3 = readAccs(stm_acc, stm_threat, i + simd.vecSize(i16));
                var s4 = readAccs(stm_acc, stm_threat, i + simd.vecSize(i16) + arch.L1_SIZE / 2);

                var n1 = readAccs(ntm_acc, ntm_threat, i);
                var n2 = readAccs(ntm_acc, ntm_threat, i + arch.L1_SIZE / 2);
                var n3 = readAccs(ntm_acc, ntm_threat, i + simd.vecSize(i16));
                var n4 = readAccs(ntm_acc, ntm_threat, i + simd.vecSize(i16) + arch.L1_SIZE / 2);

                s1 = std.math.clamp(s1, LO, HI);
                s2 = @min(s2, HI);
                s3 = std.math.clamp(s3, LO, HI);
                s4 = @min(s4, HI);

                n1 = std.math.clamp(n1, LO, HI);
                n2 = @min(n2, HI);
                n3 = std.math.clamp(n3, LO, HI);
                n4 = @min(n4, HI);

                const sp1: simd.vector(i16) = simd.mulhiShift(s1, s2, 7);
                const sp2: simd.vector(i16) = simd.mulhiShift(s3, s4, 7);

                const np1: simd.vector(i16) = simd.mulhiShift(n1, n2, 7);
                const np2: simd.vector(i16) = simd.mulhiShift(n3, n4, 7);

                const p1: simd.vector(u8) = simd.packus(sp1, sp2);
                const p2: simd.vector(u8) = simd.packus(np1, np2);

                activated_ft[i..][0..simd.vecSize(u8)].* = p1;
                activated_ft[i + arch.L1_SIZE / 2 ..][0..simd.vecSize(u8)].* = p2;
            }
        }

        const L2_UNROLL = 4;
        // in Q0² / 2⁹ * Q1
        var l1_intermediate: [arch.L2_SIZE / simd.vecSize(i32)][L2_UNROLL]simd.vector(i32) = @splat(@splat(@splat(0)));
        {
            const w: [*]const i8 = &weights.l1w[output_bucket];
            const ft_i32: [*]i32 = @ptrCast(&activated_ft);

            const nonzero_indices: [arch.L1_SIZE / 4]u16, const num_nonzero_indices: usize = @import("sparse.zig").findNonZeroIndices(&activated_ft);

            var i_outer: usize = 0;

            while (i_outer + 2 * L2_UNROLL <= num_nonzero_indices) : (i_outer += 2 * L2_UNROLL) {
                for (0..arch.L2_SIZE / simd.vecSize(i32)) |j| {
                    for (0..L2_UNROLL) |i_inner| {
                        const i_1: u16 = nonzero_indices[i_outer + 2 * i_inner];
                        const i_2: u16 = nonzero_indices[i_outer + 2 * i_inner + 1];
                        const ft_vec_1: simd.vector(u8) = @bitCast(@as(simd.vector(i32), @splat(ft_i32[i_1])));
                        const ft_vec_2: simd.vector(u8) = @bitCast(@as(simd.vector(i32), @splat(ft_i32[i_2])));
                        l1_intermediate[j][i_inner] = simd.dpbusdx2(
                            l1_intermediate[j][i_inner],
                            ft_vec_1,
                            w[i_1 * arch.L2_SIZE * 4 + j * simd.vecSize(i8) ..][0..simd.vecSize(i8)].*,
                            ft_vec_2,
                            w[i_2 * arch.L2_SIZE * 4 + j * simd.vecSize(i8) ..][0..simd.vecSize(i8)].*,
                        );
                    }
                }
            }
            while (i_outer < num_nonzero_indices) : (i_outer += 1) {
                const i = nonzero_indices[i_outer];
                const ft_vec: simd.vector(u8) = @bitCast(@as(simd.vector(i32), @splat(ft_i32[i])));

                for (0..arch.L2_SIZE / simd.vecSize(i32)) |j| {
                    l1_intermediate[j][0] = simd.dpbusd(
                        l1_intermediate[j][0],
                        ft_vec,
                        w[i * arch.L2_SIZE * 4 + j * simd.vecSize(i8) ..][0..simd.vecSize(i8)].*,
                    );
                }
            }
        }

        // in arch.Q²
        var l1_out_vec: [2 * arch.L2_SIZE / simd.vecSize(i32)]simd.vector(i32) = undefined;
        {
            const l1_bias_vec: [*]const simd.vector(i32) = @ptrCast(@alignCast(&weights.l1b[output_bucket]));

            const EXPLICIT_MULHI_SHIFT_UP = 7;
            const IMPLIED_MULHI_SHIFT_DOWN = 16;
            const MULHI_SHIFT = EXPLICIT_MULHI_SHIFT_UP - IMPLIED_MULHI_SHIFT_DOWN;

            const SHIFT = Q0_BITS * 2 + MULHI_SHIFT + Q1_BITS - Q_BITS;
            const LO: simd.vector(i32) = @splat(0);
            const HI: simd.vector(i32) = @splat(arch.Q);
            const HI2: simd.vector(i32) = @splat(arch.Q * arch.Q);
            for (0..arch.L2_SIZE / simd.vecSize(i32)) |i| {
                const biases: simd.vector(i32) = l1_bias_vec[i];

                var intermediate: simd.vector(i32) = @splat(0);
                for (l1_intermediate[i]) |e| {
                    intermediate += e;
                }

                // NOTE: PLEASE BE CAREFUL WITH THE QUANTISATION OF THESE BIASES
                const biased = intermediate + biases;
                const shifted = biased >> @splat(SHIFT);

                const crelu: simd.vector(i32) = std.math.clamp(biased, LO, HI << @splat(SHIFT)) >> @splat(SHIFT - Q_BITS);
                const csrelu: simd.vector(i32) = std.math.clamp(shifted * shifted, LO, HI2);

                l1_out_vec[i] = crelu;
                l1_out_vec[i + arch.L2_SIZE / simd.vecSize(i32)] = csrelu;
            }
        }

        // in arch.Q³
        var l2_intermediate: [arch.L3_SIZE / simd.vecSize(i32)]simd.vector(i32) = @bitCast(weights.l2b[output_bucket]);
        {
            const l1_out: *const [2 * arch.L2_SIZE]i32 = @ptrCast(&l1_out_vec);
            const l2_weight_vec: *const [2 * arch.L2_SIZE][arch.L3_SIZE / simd.vecSize(i32)]simd.vector(i32) = @ptrCast(@alignCast(&weights.l2w[output_bucket]));
            for (0..arch.L2_SIZE * 2) |i| {
                const l1_vec: simd.vector(i32) = @splat(l1_out[i]);
                for (0..arch.L3_SIZE / simd.vecSize(i32)) |j| {
                    l2_intermediate[j] += l1_vec * l2_weight_vec[i][j];
                }
            }
        }

        // in arch.Q⁴
        var l3_sum: simd.vector(i32) = @splat(0);
        {
            const l3_weight_vec: *const [arch.L3_SIZE / simd.vecSize(i32)]simd.vector(i32) = @ptrCast(@alignCast(&weights.l3w[output_bucket]));
            const LO: simd.vector(i32) = @splat(0);
            const HI3: simd.vector(i32) = @splat(arch.Q * arch.Q * arch.Q);
            for (0..arch.L3_SIZE / simd.vecSize(i32)) |i| {
                const activated: simd.vector(i32) = std.math.clamp(l2_intermediate[i], LO, HI3);
                l3_sum += activated * l3_weight_vec[i];
            }
        }

        const bias: i32 = weights.l3b[output_bucket];
        const scaled: i64 = (@reduce(.Add, l3_sum) + bias) * arch.SCALE;

        return evaluation.clampScore(@divTrunc(scaled, arch.Q * arch.Q * arch.Q * arch.Q));
    }
};

const RawHandle = struct {
    ctx: *Context,
    state: *State,

    pub fn addSub(self: RawHandle, add: PSQTFeature, sub: PSQTFeature) void {
        self.state.addSub(add, sub);
    }

    pub fn addSubSub(self: RawHandle, add: PSQTFeature, sub1: PSQTFeature, sub2: PSQTFeature) void {
        self.state.addSubSub(add, sub1, sub2);
    }

    pub fn addAddSubSub(self: RawHandle, add1: PSQTFeature, add2: PSQTFeature, sub1: PSQTFeature, sub2: PSQTFeature) void {
        self.state.addAddSubSub(add1, add2, sub1, sub2);
    }

    pub fn threatOnChange(self: RawHandle, board: *const Board, piece: ColouredPieceType, sq: Square, comptime is_add: bool) void {
        nnue_threat_updates.onChange(&self.state.threat_updates, board, piece, sq, is_add);
    }

    pub fn threatOnMove(self: RawHandle, board: *const Board, old_piece: ColouredPieceType, src: Square, new_piece: ColouredPieceType, dst: Square) void {
        nnue_threat_updates.onMove(&self.state.threat_updates, board, old_piece, src, new_piece, dst);
    }

    pub fn threatOnMutate(self: RawHandle, board: *const Board, old_piece: ColouredPieceType, new_piece: ColouredPieceType, sq: Square) void {
        nnue_threat_updates.onMutate(&self.state.threat_updates, board, old_piece, new_piece, sq);
    }

    pub fn eval(self: RawHandle, board: *const Board) i16 {
        return self.state.forward(board, self.ctx);
    }
};

pub const Context = struct {
    weights: *const arch.Weights = undefined,
    refresh_cache: root.refreshCache(arch.HORIZONTAL_MIRRORING, arch.INPUT_BUCKET_COUNT) = undefined,
    accumulator_stack: [root.SEARCH_MAX_PLY][2]Accumulator = undefined,
    threat_accumulator_stack: [root.SEARCH_MAX_PLY][2]Accumulator = undefined,
    frames: [root.SEARCH_MAX_PLY]State = undefined,

    pub fn initForThread(self: *Context, thread_idx: usize) void {
        const node: usize = if (root.numa.enabled) numa.nodeForThread(thread_idx) else 0;
        self.weights = weightsForNode(node);
        self.refresh_cache.initInPlace(self.weights);
    }

    pub fn initRoot(self: *Context, board: *const Board) void {
        self.frames[0].initInPlace(board, self.weights, self);
    }

    pub fn prepareChild(self: *Context, child_ply: usize, child_board: *const Board) void {
        self.frames[child_ply].update(&self.frames[child_ply - 1], child_board);
    }

    pub fn handle(self: *Context, ply: usize) evaluation.Handle(RawHandle) {
        return evaluation.wrapHandle(RawHandle{
            .ctx = self,
            .state = &self.frames[ply],
        });
    }
};

inline fn readAccs(acc: *const Accumulator, threat: *const Accumulator, i: usize) simd.vector(i16) {
    const V = simd.vector(i16);
    return @as(V, acc.data[i..][0..simd.vecSize(i16)].*) + @as(V, threat.data[i..][0..simd.vecSize(i16)].*);
}

pub fn evalPosition(board: *const Board) i16 {
    const ctx = std.heap.page_allocator.create(Context) catch @panic("OOM");
    defer std.heap.page_allocator.destroy(ctx);
    ctx.initForThread(0);
    ctx.initRoot(board);
    return ctx.handle(0).eval(board);
}
