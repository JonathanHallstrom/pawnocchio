const std = @import("std");
const root = @import("../../root.zig");
const arch = @import("../arch.zig");
const simd = @import("../../simd.zig");
const nnue_accumulator = @import("../accumulator.zig");
const Accumulator = nnue_accumulator.Accumulator;
const AccumulatorHalf = nnue_accumulator.AccumulatorHalf;
const Board = root.Board;
const Square = root.Square;
const Colour = root.Colour;
const PieceType = root.PieceType;
const Bitboard = root.Bitboard;
const ColouredPieceType = root.ColouredPieceType;
const FeatureKind = root.FeatureKind;
const PSQTFeature = root.PSQTFeature;
const evaluation = root.evaluation;

const ALIGNMENT = 64;

pub const HAS_THREATS = false;

pub const Weights = extern struct {
    ft_w: [arch.INPUT_BUCKET_COUNT][2][6][64]arch.PSQTWeight align(ALIGNMENT),
    ft_b: [arch.L1_SIZE]i16 align(ALIGNMENT),

    pub fn transform(self: *Weights, target_kind: simd.Target, endian: std.builtin.Endian) void {
        if (arch.needsPermutingFor(target_kind)) {
            const order = arch.permuteOrderFor(target_kind);
            arch.permuteBuffer(&self.ft_w, order);
            arch.permuteBuffer(&self.ft_b, order);
        }
        if (endian != .little) {
            arch.endianSwap(&self.ft_w);
            arch.endianSwap(&self.ft_b);
        }
    }

    pub const SIZE_BYTES = @sizeOf(Weights);
    pub const WEIGHT_COUNT = blk: {
        var res: usize = 0;
        for (std.meta.fields(Weights)) |field| {
            res += @typeInfo(field.type).array.len;
        }
        break :blk res;
    };
};

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

pub const DirtyPiece = union(enum) {
    clean,
    move: struct { to: PSQTFeature, from: PSQTFeature },
    capture: struct { to: PSQTFeature, from: PSQTFeature, captured: PSQTFeature },
    castle: struct { k_to: Square, k_from: Square, r_to: Square, r_from: Square, col: Colour },

    pub inline fn initMove(to_feat: PSQTFeature, from_feat: PSQTFeature) DirtyPiece {
        return .{ .move = .{ .to = to_feat, .from = from_feat } };
    }
    pub inline fn initCapture(to_feat: PSQTFeature, from_feat: PSQTFeature, captured: PSQTFeature) DirtyPiece {
        return .{ .capture = .{ .to = to_feat, .from = from_feat, .captured = captured } };
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
    pub inline fn clear(self: *DirtyPiece) void {
        self.* = .clean;
    }
    pub inline fn isClean(self: DirtyPiece) bool {
        return self == .clean;
    }

    pub inline fn to(self: DirtyPiece) PSQTFeature {
        return switch (self) {
            .clean => undefined,
            .move => |s| s.to,
            .capture => |s| s.to,
            .castle => |s| .init(s.col, .king, s.k_to),
        };
    }
    pub inline fn from(self: DirtyPiece) PSQTFeature {
        return switch (self) {
            .clean => undefined,
            .move => |s| s.from,
            .capture => |s| s.from,
            .castle => |s| .init(s.col, .king, s.k_from),
        };
    }
};

pub inline fn featureWeight(
    weights: *const arch.Weights,
    perspective: Colour,
    king_sq: Square,
    comptime kind: FeatureKind,
    f: PSQTFeature,
    mirror: MirroringType,
) *const arch.RawAccumulator {
    _ = kind;
    const bucket = whichInputBucket(perspective, king_sq);
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
    return &weights.input.ft_w[bucket][side_idx][f.piece().toInt()][sq.toInt()];
}

pub inline fn whichInputBucket(stm: Colour, king_square: Square) usize {
    return arch.whichInputBucket((if (stm == .white) king_square else king_square.flipRank()).toInt());
}

pub inline fn crossesMiddle(from_sq: Square, to_sq: Square) bool {
    return (from_sq.getFile().toInt() >= 4) != (to_sq.getFile().toInt() >= 4);
}

pub inline fn needsRefresh(stm: Colour, from_sq: Square, to_sq: Square) bool {
    if (arch.HORIZONTAL_MIRRORING and crossesMiddle(from_sq, to_sq)) return true;
    return whichInputBucket(stm, from_sq) != whichInputBucket(stm, to_sq);
}

pub const Perspective = enum { stm, ntm };

pub const Resolved = struct {
    stm: *const Accumulator,
    ntm: *const Accumulator,

    pub inline fn read(self: Resolved, comptime perspective: Perspective, i: usize) simd.Vector(i16) {
        return (if (perspective == .stm) self.stm else self.ntm).data[i..][0..simd.vecSize(i16)].*;
    }
};

pub const State = struct {
    white: AccumulatorHalf,
    black: AccumulatorHalf,
    white_mirrored: MirroringType,
    black_mirrored: MirroringType,
    dirty_piece: DirtyPiece,
    board_ref: ?*const Board,

    pub inline fn half(self: anytype, acc: Colour) root.inheritConstness(@TypeOf(self), *AccumulatorHalf) {
        return if (acc == .white) &self.white else &self.black;
    }

    pub inline fn setHalf(self: *State, acc: Colour, ptr: *const Accumulator) void {
        self.half(acc).* = .{ .ptr = ptr };
    }

    pub inline fn mirrorFor(self: anytype, col: Colour) MirroringType {
        return if (col == .white) self.white_mirrored else self.black_mirrored;
    }

    pub inline fn mirrorPtrFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *MirroringType) {
        return if (col == .white) &self.white_mirrored else &self.black_mirrored;
    }
};

pub const Context = struct {
    refresh_cache: root.refreshCache(arch.HORIZONTAL_MIRRORING, arch.INPUT_BUCKET_COUNT) = undefined,
    accumulator_stack: [root.SEARCH_MAX_PLY][2]Accumulator = undefined,
    pending: [root.SEARCH_MAX_PLY]bool = undefined,
    frames: [root.SEARCH_MAX_PLY]State = undefined,

    pub fn initRefreshCache(self: *Context, weights: *const arch.Weights) void {
        self.refresh_cache.initInPlace(weights);
    }

    pub fn initRoot(self: *Context, board: *const Board, weights: *const arch.Weights) void {
        const f = &self.frames[0];
        f.* = .{
            .white = .{ .ptr = @ptrCast(&weights.input.ft_b) },
            .black = .{ .ptr = @ptrCast(&weights.input.ft_b) },
            .white_mirrored = .{},
            .black_mirrored = .{},
            .dirty_piece = .clean,
            .board_ref = board,
        };
        self.pending[0] = false;
        f.white_mirrored.write(Square.fromBitboard(board.kingFor(.white)).getFile().toInt() >= 4);
        f.black_mirrored.write(Square.fromBitboard(board.kingFor(.black)).getFile().toInt() >= 4);

        const white_king_sq = Square.fromBitboard(board.kingFor(.white));
        const black_king_sq = Square.fromBitboard(board.kingFor(.black));
        for (PieceType.all) |tp| {
            inline for ([_]Colour{ .white, .black }) |piece_col| {
                var iter = Bitboard.iterator(board.pieceFor(piece_col, tp));
                while (iter.next()) |sq| {
                    self.writeFeature(0, f, .white, white_king_sq, .init(piece_col, tp, sq), weights);
                    self.writeFeature(0, f, .black, black_king_sq, .init(piece_col, tp, sq), weights);
                }
            }
        }
    }

    pub fn prepareChild(self: *Context, child_ply: u16, board: *const Board) void {
        self.pending[child_ply] = true;
        const f = &self.frames[child_ply];
        f.board_ref = board;
        f.dirty_piece.clear();
    }

    pub fn ensureUpToDate(self: *Context, ply: u16, weights: *const arch.Weights) void {
        self.resolvePending(ply, weights);
        const f = &self.frames[ply];
        if (!f.dirty_piece.isClean()) {
            self.applyDirtyInplace(ply, weights);
        }
    }

    fn resolvePending(self: *Context, ply: u16, weights: *const arch.Weights) void {
        if (!self.pending[ply]) return;

        var first_pending: usize = ply;
        while (first_pending > 0 and self.pending[first_pending - 1]) {
            @branchHint(.unlikely);
            first_pending -= 1;
        }

        var cursor: u16 = @intCast(first_pending);
        while (cursor <= ply) : (cursor += 1) {
            self.pending[cursor] = false;
            const board = self.frames[cursor].board_ref orelse unreachable;
            self.applyDirtyCopy(cursor, board.stm.flipped(), weights);
        }
    }

    fn applyDirtyCopy(self: *Context, ply: u16, stm: Colour, weights: *const arch.Weights) void {
        const f = &self.frames[ply];
        const parent = &self.frames[ply - 1];
        f.white_mirrored = parent.white_mirrored;
        f.black_mirrored = parent.black_mirrored;
        if (f.dirty_piece.isClean()) {
            f.white = parent.white;
            f.black = parent.black;
            return;
        }
        self.refreshStale(ply - 1, weights);
        self.applyDirtyImpl(ply, ply - 1, stm, weights);
    }

    fn applyDirtyInplace(self: *Context, ply: u16, weights: *const arch.Weights) void {
        const f = &self.frames[ply];
        const board = f.board_ref orelse unreachable;
        self.refreshStale(ply, weights);
        self.applyDirtyImpl(ply, ply, board.stm.flipped(), weights);
    }

    fn applyDirtyImpl(self: *Context, ply: u16, src_ply: u16, stm: Colour, weights: *const arch.Weights) void {
        const timer = root.engine.time("psq_update");
        defer timer.register();
        const f = &self.frames[ply];
        const src = &self.frames[src_ply];
        const dirty = f.dirty_piece;
        defer f.dirty_piece.clear();

        const board = f.board_ref orelse unreachable;
        const them = stm.flipped();
        const them_king_sq = Square.fromBitboard(board.kingFor(them));
        self.updateHalf(ply, src, them, them_king_sq, dirty, weights);

        const to_feat = dirty.to();
        const from_feat = dirty.from();
        const us_king_sq = Square.fromBitboard(board.kingFor(stm));
        if (to_feat.piece() == .king and needsRefresh(stm, to_feat.square(), from_feat.square())) {
            @branchHint(.unlikely);
            f.mirrorPtrFor(stm).write(us_king_sq.getFile().toInt() >= 4);
            self.refreshHalf(ply, stm, board, weights);
        } else {
            self.updateHalf(ply, src, stm, us_king_sq, dirty, weights);
        }
    }

    inline fn updateHalf(self: *Context, ply: u16, src: *const State, acc: Colour, king_sq: Square, dirty: DirtyPiece, weights: *const arch.Weights) void {
        const f = &self.frames[ply];
        const mir = f.mirrorFor(acc);
        const buf = &self.accumulator_stack[ply][acc.toInt()];
        const src_ptr = src.half(acc).ptr;

        switch (dirty) {
            .move => |state| buf.copyAddSubMany(
                src_ptr,
                .{featureWeight(weights, acc, king_sq, .psqt, state.to, mir)},
                .{featureWeight(weights, acc, king_sq, .psqt, state.from, mir)},
            ),
            .capture => |state| buf.copyAddSubMany(
                src_ptr,
                .{featureWeight(weights, acc, king_sq, .psqt, state.to, mir)},
                .{
                    featureWeight(weights, acc, king_sq, .psqt, state.from, mir),
                    featureWeight(weights, acc, king_sq, .psqt, state.captured, mir),
                },
            ),
            .castle => |state| buf.copyAddSubMany(
                src_ptr,
                .{
                    featureWeight(weights, acc, king_sq, .psqt, .init(state.col, .king, state.k_to), mir),
                    featureWeight(weights, acc, king_sq, .psqt, .init(state.col, .rook, state.r_to), mir),
                },
                .{
                    featureWeight(weights, acc, king_sq, .psqt, .init(state.col, .king, state.k_from), mir),
                    featureWeight(weights, acc, king_sq, .psqt, .init(state.col, .rook, state.r_from), mir),
                },
            ),
            .clean => unreachable,
        }
        f.setHalf(acc, buf);
    }

    fn refreshHalf(self: *Context, ply: u16, acc: Colour, board: *const Board, weights: *const arch.Weights) void {
        const timer = root.engine.time("psq_refresh");
        defer timer.register();
        const f = &self.frames[ply];
        f.mirrorPtrFor(acc).write(Square.fromBitboard(board.kingFor(acc)).getFile().toInt() >= 4);
        const refreshed = self.refresh_cache.refresh(weights, acc, board);
        f.half(acc).* = refreshed;
    }

    inline fn refreshStale(self: *Context, ply: u16, weights: *const arch.Weights) void {
        const f = &self.frames[ply];
        if (f.white.generation != 0 and f.white.generation != self.refresh_cache.currentGeneration(.white)) {
            self.refreshHalf(ply, .white, f.board_ref.?, weights);
        }
        if (f.black.generation != 0 and f.black.generation != self.refresh_cache.currentGeneration(.black)) {
            self.refreshHalf(ply, .black, f.board_ref.?, weights);
        }
    }

    inline fn writeFeature(self: *Context, ply: u16, f: *State, acc: Colour, king_sq: Square, piece: PSQTFeature, weights: *const arch.Weights) void {
        const buf = &self.accumulator_stack[ply][acc.toInt()];
        buf.copyAdd(f.half(acc).ptr, featureWeight(weights, acc, king_sq, .psqt, piece, f.mirrorFor(acc)));
        f.setHalf(acc, buf);
    }

    pub fn resolved(self: *const Context, ply: u16, stm: Colour) Resolved {
        const f = &self.frames[ply];
        return .{
            .stm = if (stm == .white) f.white.ptr else f.black.ptr,
            .ntm = if (stm == .white) f.black.ptr else f.white.ptr,
        };
    }

    pub fn getHandle(self: *Context, ply: u16, weights: *const arch.Weights) Handle {
        return .{ .ctx = self, .weights = weights, .ply = ply, .frame = &self.frames[ply] };
    }
};

pub const Handle = struct {
    ctx: *Context,
    weights: *const arch.Weights,
    ply: u16,
    frame: *State,

    pub fn addSub(self: Handle, add: PSQTFeature, sub: PSQTFeature) void {
        std.debug.assert(self.frame.dirty_piece.isClean());
        self.frame.dirty_piece = .initMove(add, sub);
    }

    pub fn addSubSub(self: Handle, add: PSQTFeature, sub1: PSQTFeature, sub2: PSQTFeature) void {
        std.debug.assert(self.frame.dirty_piece.isClean());
        self.frame.dirty_piece = .initCapture(add, sub1, sub2);
    }

    pub fn addAddSubSub(self: Handle, add1: PSQTFeature, add2: PSQTFeature, sub1: PSQTFeature, sub2: PSQTFeature) void {
        std.debug.assert(self.frame.dirty_piece.isClean());
        self.frame.dirty_piece = .initCastle(add1, add2, sub1, sub2);
    }

    pub fn threatOnChange(_: Handle, _: *const Board, _: ColouredPieceType, _: Square, comptime _: bool) void {}
    pub fn threatOnMove(_: Handle, _: *const Board, _: ColouredPieceType, _: Square, _: ColouredPieceType, _: Square) void {}
    pub fn threatOnMutate(_: Handle, _: *const Board, _: ColouredPieceType, _: ColouredPieceType, _: Square) void {}

    pub fn eval(self: Handle, board: *const Board) i16 {
        self.ctx.ensureUpToDate(self.ply, self.weights);
        return arch.outputs.forward(self.ctx.resolved(self.ply, board.stm), self.weights, board);
    }
};
