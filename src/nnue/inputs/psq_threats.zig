const std = @import("std");
const root = @import("../../root.zig");
const arch = @import("../arch.zig");
const simd = @import("../../simd.zig");
const psq = @import("psq.zig");
const nnue_accumulator = @import("../accumulator.zig");
const nnue_threats = @import("../threats/index.zig");
const nnue_threat_updates = @import("../threats/updates.zig");
const Accumulator = nnue_accumulator.Accumulator;
const AccumulatorHalf = nnue_accumulator.AccumulatorHalf;
const Board = root.Board;
const Square = root.Square;
const Colour = root.Colour;
const ColouredPieceType = root.ColouredPieceType;
const evaluation = root.evaluation;

const ALIGNMENT = 64;

pub const HAS_THREATS = true;
pub const MirroringType = psq.MirroringType;
pub const DirtyPiece = psq.DirtyPiece;
pub const featureWeight = psq.featureWeight;
pub const whichInputBucket = psq.whichInputBucket;
pub const crossesMiddle = psq.crossesMiddle;
pub const needsRefresh = psq.needsRefresh;
pub const Perspective = psq.Perspective;

pub const Weights = extern struct {
    ft_w: [arch.INPUT_BUCKET_COUNT][2][6][64]arch.PSQTWeight align(ALIGNMENT),
    threat_w: [arch.TOTAL_THREATS]arch.ThreatWeight align(ALIGNMENT),
    ft_b: [arch.L1_SIZE]i16 align(ALIGNMENT),

    pub fn transform(self: *Weights, target_kind: simd.Target, endian: std.builtin.Endian) void {
        if (arch.needsPermutingFor(target_kind)) {
            const order = arch.permuteOrderFor(target_kind);
            arch.permuteBuffer(&self.ft_w, order);
            arch.permuteBuffer(&self.ft_b, order);
            arch.permuteBufferI8(&self.threat_w, order);
        }
        if (endian != .little) {
            arch.endianSwap(&self.ft_w);
            arch.endianSwap(&self.threat_w);
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

pub const Resolved = struct {
    stm_psq: *const Accumulator,
    ntm_psq: *const Accumulator,
    stm_threat: *const Accumulator,
    ntm_threat: *const Accumulator,

    pub inline fn read(self: Resolved, comptime perspective: Perspective, i: usize) simd.vector(i16) {
        const V = simd.vector(i16);
        const psq_ptr = if (perspective == .stm) self.stm_psq else self.ntm_psq;
        const threat_ptr = if (perspective == .stm) self.stm_threat else self.ntm_threat;
        const p: V = psq_ptr.data[i..][0..simd.vecSize(i16)].*;
        const t: V = threat_ptr.data[i..][0..simd.vecSize(i16)].*;
        return p + t;
    }
};

const ThreatState = struct {
    white_threat: AccumulatorHalf,
    black_threat: AccumulatorHalf,
    white_threat_mirrored: MirroringType,
    black_threat_mirrored: MirroringType,
    threat_updates: nnue_threat_updates.UpdateBuffer,

    inline fn threatHalf(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *AccumulatorHalf) {
        return if (col == .white) &self.white_threat else &self.black_threat;
    }

    inline fn threatMirrorFor(self: anytype, col: Colour) MirroringType {
        return if (col == .white) self.white_threat_mirrored else self.black_threat_mirrored;
    }

    inline fn threatMirrorPtrFor(self: anytype, col: Colour) root.inheritConstness(@TypeOf(self), *MirroringType) {
        return if (col == .white) &self.white_threat_mirrored else &self.black_threat_mirrored;
    }
};

pub const Context = struct {
    psq: psq.Context = undefined,
    threat_accumulator_stack: [root.SEARCH_MAX_PLY][2]Accumulator = undefined,
    threat_add_stack: nnue_threat_updates.FeatureStack align(4) = undefined,
    threat_sub_stack: nnue_threat_updates.FeatureStack align(4) = undefined,
    pending: [root.SEARCH_MAX_PLY]bool = undefined,
    threat_frames: [root.SEARCH_MAX_PLY]ThreatState = undefined,

    pub fn initRefreshCache(self: *Context, weights: *const arch.Weights) void {
        self.psq.initRefreshCache(weights);
    }

    pub fn initRoot(self: *Context, board: *const Board, weights: *const arch.Weights) void {
        self.psq.initRoot(board, weights);
        const tf = &self.threat_frames[0];
        tf.white_threat = .{ .ptr = &nnue_accumulator.zero_accumulator };
        tf.black_threat = .{ .ptr = &nnue_accumulator.zero_accumulator };
        tf.white_threat_mirrored = .{};
        tf.black_threat_mirrored = .{};
        tf.threat_updates = .{};
        self.pending[0] = false;
        self.refreshThreatHalf(0, .white, board, weights);
        self.refreshThreatHalf(0, .black, board, weights);
    }

    pub fn prepareChild(self: *Context, child_ply: u16, board: *const Board) void {
        self.psq.prepareChild(child_ply, board);
        self.threat_frames[child_ply].threat_updates.clearFrom(&self.threat_frames[child_ply - 1].threat_updates);
        self.pending[child_ply] = true;
    }

    pub fn ensureUpToDate(self: *Context, ply: u16, weights: *const arch.Weights) void {
        self.psq.ensureUpToDate(ply, weights);
        self.resolvePending(ply, weights);

        if (std.debug.runtime_safety) {
            const board = self.psq.frames[ply].board_ref.?;
            var white_oracle: Accumulator align(64) = undefined;
            var black_oracle: Accumulator align(64) = undefined;
            nnue_threats.refreshThreats(&white_oracle, board, .white, weights);
            nnue_threats.refreshThreats(&black_oracle, board, .black, weights);
            std.debug.assert(std.mem.eql(i16, &self.threat_frames[ply].white_threat.ptr.data, &white_oracle.data));
            std.debug.assert(std.mem.eql(i16, &self.threat_frames[ply].black_threat.ptr.data, &black_oracle.data));
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
            const board = self.psq.frames[cursor].board_ref orelse unreachable;
            inline for ([_]Colour{ .white, .black }) |col| {
                const king_sq = Square.fromBitboard(board.kingFor(col));
                if (self.needsThreatRefresh(cursor - 1, col, king_sq)) {
                    self.refreshThreatHalf(cursor, col, board, weights);
                } else {
                    self.materialiseThreatHalf(cursor, col, board, weights);
                }
            }
        }
        @memset(self.pending[first_pending..], false);
    }

    fn needsThreatRefresh(self: *Context, parent_ply: u16, col: Colour, king_sq: Square) bool {
        if (!arch.HORIZONTAL_MIRRORING) return false;
        const parent_mirrored = self.threat_frames[parent_ply].threatMirrorFor(col).read();
        const current_mirrored = king_sq.getFile().toInt() >= 4;
        return parent_mirrored != current_mirrored;
    }

    fn refreshThreatHalf(self: *Context, ply: u16, col: Colour, board: *const Board, weights: *const arch.Weights) void {
        const buf = &self.threat_accumulator_stack[ply][col.toInt()];
        nnue_threats.refreshThreats(buf, board, col, weights);
        const tf = &self.threat_frames[ply];
        tf.threatHalf(col).* = .{ .ptr = buf };
        tf.threatMirrorPtrFor(col).write(Square.fromBitboard(board.kingFor(col)).getFile().toInt() >= 4);
    }

    fn materialiseThreatHalf(self: *Context, ply: u16, col: Colour, board: *const Board, weights: *const arch.Weights) void {
        const tf = &self.threat_frames[ply];
        const parent_tf = &self.threat_frames[ply - 1];

        if (tf.threat_updates.refresh[col.toInt()]) {
            self.refreshThreatHalf(ply, col, board, weights);
            return;
        }

        const adds_raw = tf.threat_updates.addSlice(&self.threat_add_stack);
        const subs_raw = tf.threat_updates.subSlice(&self.threat_sub_stack);

        if (adds_raw.len == 0 and subs_raw.len == 0) {
            tf.threatHalf(col).* = parent_tf.threatHalf(col).*;
            tf.threatMirrorPtrFor(col).* = parent_tf.threatMirrorFor(col);
            return;
        }

        const king_sq = Square.fromBitboard(board.kingFor(col));
        const src = parent_tf.threatHalf(col).ptr;
        const dst = &self.threat_accumulator_stack[ply][col.toInt()];

        var add_indices: [nnue_threat_updates.UpdateBuffer.MaxAdds]u32 = undefined;
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

        var sub_indices: [nnue_threat_updates.UpdateBuffer.MaxSubs]u32 = undefined;
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
        tf.threatHalf(col).* = .{ .ptr = dst };
        tf.threatMirrorPtrFor(col).* = parent_tf.threatMirrorFor(col);
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
                v[t] -= weights.input.threat_w[idx][i + t];
            };
            for (adds) |idx| inline for (0..TILE) |t| {
                v[t] += weights.input.threat_w[idx][i + t];
            };
            dst.vecs()[i..][0..TILE].* = v;
        }
    }

    pub fn resolved(self: *const Context, ply: u16, stm: Colour) Resolved {
        const pf = &self.psq.frames[ply];
        const tf = &self.threat_frames[ply];
        return .{
            .stm_psq = if (stm == .white) pf.white.ptr else pf.black.ptr,
            .ntm_psq = if (stm == .white) pf.black.ptr else pf.white.ptr,
            .stm_threat = if (stm == .white) tf.white_threat.ptr else tf.black_threat.ptr,
            .ntm_threat = if (stm == .white) tf.black_threat.ptr else tf.white_threat.ptr,
        };
    }

    pub fn getHandle(self: *Context, ply: u16, weights: *const arch.Weights) Handle {
        return .{
            .ctx = self,
            .weights = weights,
            .ply = ply,
            .psq_frame = &self.psq.frames[ply],
            .threat_frame = &self.threat_frames[ply],
        };
    }

    fn threatStacks(self: *Context) nnue_threat_updates.Stacks {
        return .{ .add = &self.threat_add_stack, .sub = &self.threat_sub_stack };
    }
};

pub const Handle = struct {
    ctx: *Context,
    weights: *const arch.Weights,
    ply: u16,
    psq_frame: *psq.State,
    threat_frame: *ThreatState,

    pub fn addSub(self: Handle, add: root.PSQTFeature, sub: root.PSQTFeature) void {
        std.debug.assert(self.psq_frame.dirty_piece.isClean());
        self.psq_frame.dirty_piece = .initMove(add, sub);
    }

    pub fn addSubSub(self: Handle, add: root.PSQTFeature, sub1: root.PSQTFeature, sub2: root.PSQTFeature) void {
        std.debug.assert(self.psq_frame.dirty_piece.isClean());
        self.psq_frame.dirty_piece = .initCapture(add, sub1, sub2);
    }

    pub fn addAddSubSub(self: Handle, add1: root.PSQTFeature, add2: root.PSQTFeature, sub1: root.PSQTFeature, sub2: root.PSQTFeature) void {
        std.debug.assert(self.psq_frame.dirty_piece.isClean());
        self.psq_frame.dirty_piece = .initCastle(add1, add2, sub1, sub2);
    }

    pub fn threatOnChange(self: Handle, board: *const Board, piece: ColouredPieceType, sq: Square, comptime is_add: bool) void {
        nnue_threat_updates.onChange(&self.threat_frame.threat_updates, self.ctx.threatStacks(), board, piece, sq, is_add);
    }

    pub fn threatOnMove(self: Handle, board: *const Board, old_piece: ColouredPieceType, src: Square, new_piece: ColouredPieceType, dst: Square) void {
        nnue_threat_updates.onMove(&self.threat_frame.threat_updates, self.ctx.threatStacks(), board, old_piece, src, new_piece, dst);
    }

    pub fn threatOnMutate(self: Handle, board: *const Board, old_piece: ColouredPieceType, new_piece: ColouredPieceType, sq: Square) void {
        nnue_threat_updates.onMutate(&self.threat_frame.threat_updates, self.ctx.threatStacks(), board, old_piece, new_piece, sq);
    }

    pub fn eval(self: Handle, board: *const Board) i16 {
        self.ctx.ensureUpToDate(self.ply, self.weights);
        return arch.outputs.forward(self.ctx.resolved(self.ply, board.stm), self.weights, board);
    }
};
