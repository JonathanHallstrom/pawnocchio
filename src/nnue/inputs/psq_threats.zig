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
    pp_w: [arch.TOTAL_PAWN_PAIRS]arch.ThreatWeight align(ALIGNMENT),
    threat_w: [arch.TOTAL_THREATS]arch.ThreatWeight align(ALIGNMENT),
    ft_b: [arch.L1_SIZE]i16 align(ALIGNMENT),

    pub fn transform(self: *Weights, target_kind: simd.Target, endian: std.builtin.Endian) void {
        if (arch.needsPermutingFor(target_kind)) {
            const order = arch.permuteOrderFor(target_kind);
            arch.permuteBuffer(&self.ft_w, order);
            arch.permuteBuffer(&self.ft_b, order);
            arch.permuteBufferI8(&self.pp_w, order);
            arch.permuteBufferI8(&self.threat_w, order);
        }
        if (endian != .little) {
            arch.endianSwap(&self.ft_w);
            arch.endianSwap(&self.pp_w);
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

    pub inline fn read(self: Resolved, comptime perspective: Perspective, i: usize) simd.Vector(i16) {
        const V = simd.Vector(i16);
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
        self.resolvePending(ply, weights);
        self.psq.ensureUpToDate(ply, weights);

        if (std.debug.runtime_safety) {
            const board = self.psq.frames[ply].board_ref.?;
            var white_oracle: Accumulator align(64) = undefined;
            var black_oracle: Accumulator align(64) = undefined;
            buildThreatAccumulator(&white_oracle, board, .white, weights);
            buildThreatAccumulator(&black_oracle, board, .black, weights);
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
            self.pending[cursor] = false;
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
    }

    fn needsThreatRefresh(self: *Context, parent_ply: u16, col: Colour, king_sq: Square) bool {
        if (!arch.HORIZONTAL_MIRRORING) return false;
        const parent_mirrored = self.threat_frames[parent_ply].threatMirrorFor(col).read();
        const current_mirrored = king_sq.getFile().toInt() >= 4;
        return parent_mirrored != current_mirrored;
    }

    const Bitboard = root.Bitboard;
    const File = root.File;
    const IdVec = @Vector(16, u16);
    const IdVec32 = @Vector(32, u16);

    const FIRST_PAWN: u8 = 8;
    const PAWN_SQUARES: u8 = 48;

    fn refreshThreatHalf(self: *Context, ply: u16, col: Colour, board: *const Board, weights: *const arch.Weights) void {
        const timer = root.engine.time("threat_refresh");
        defer timer.register();
        const buf = &self.threat_accumulator_stack[ply][col.toInt()];
        buildThreatAccumulator(buf, board, col, weights);
        const tf = &self.threat_frames[ply];
        tf.threatHalf(col).* = .{ .ptr = buf };
        tf.threatMirrorPtrFor(col).write(Square.fromBitboard(board.kingFor(col)).getFile().toInt() >= 4);
    }

    fn PPIndexType(comptime T: type) type {
        const i = @typeInfo(T);

        if (i == .int) {
            return u16;
        } else {
            const len = switch (i) {
                inline else => |t| t.len,
            };
            return @Vector(len, u16);
        }
    }

    fn ppIndex(id_a: anytype, id_b: anytype) PPIndexType(@TypeOf(id_a)) {
        const T = PPIndexType(@TypeOf(id_a));
        const ONE: T = if (T == u16) 1 else @splat(1);
        const a: T = id_a;
        const b: T = id_b;
        const lo: T = @min(a, b);
        const hi: T = @max(a, b);
        return (hi *% (hi -% ONE) >> ONE) +% lo;
    }

    const INTERLEAVE_MASK: @Vector(64, u8) = blk: {
        var res: [64]u8 = @splat(17);
        for (0..16) |i| {
            res[4 * i] = i;
            res[4 * i + 2] = i;
        }
        break :blk res;
    };

    const WIDEN_AND_DUP_MASK: @Vector(64, u8) = blk: {
        var res: [64]u8 = undefined;
        for (0..32) |i| {
            res[2 * i] = i % 16;
            res[2 * i + 1] = 16;
        }
        break :blk res;
    };

    inline fn collectPawnIdsVBMI2(board: *const Board, col: Colour, sq_mask: u8, exclude: u64) @Vector(64, u8) {
        const timer = root.engine.time("pp_collect_ids");
        defer timer.register();
        // const adjusted = (std.simd.iota(u8, 64) ^ @as(@Vector(64, u8), @splat(sq_mask))) -% @as(@Vector(64, u8), @splat(8));
        const ADJUSTED_SQUARES: [256]@Vector(64, u8) = comptime blk: {
            @setEvalBranchQuota(1 << 20);
            var table: [256]@Vector(64, u8) = undefined;
            for (0..256) |mask| {
                var v: [64]u8 = undefined;
                for (0..64) |i| v[i] = @as(u8, @intCast(i ^ mask)) -% 8;
                table[mask] = v;
            }
            break :blk table;
        };
        const adjusted = ADJUSTED_SQUARES[sq_mask];
        const enemy_offset: @Vector(64, u8) = @splat(48);
        const mask: @Vector(64, bool) = @bitCast(board.pawnsFor(col));
        const ids = @select(u8, mask, adjusted, adjusted +% enemy_offset);
        return simd.vpcompress(ids, board.pawns() & ~exclude);
    }

    inline fn collectPawnIdsScalar(board: *const Board, col: Colour, sq_mask: u8, exclude: u64) [16]u8 {
        const friendly_bb = board.pawnsFor(col) & ~exclude;
        const enemy_bb = board.pawnsFor(col.flipped()) & ~exclude;
        var ids: [16]u8 = @splat(0);
        var i: usize = 0;
        var fp = Bitboard.iterator(friendly_bb);
        while (fp.next()) |sq| {
            ids[i] = (sq.toInt() ^ sq_mask) -% FIRST_PAWN;
            i += 1;
        }
        var ep = Bitboard.iterator(enemy_bb);
        while (ep.next()) |sq| {
            ids[i] = PAWN_SQUARES +% (sq.toInt() ^ sq_mask) -% FIRST_PAWN;
            i += 1;
        }
        return ids;
    }

    fn pawnId(sq: Square, enemy_offset: u8, sq_mask: u8) u16 {
        return enemy_offset +% (@as(u16, sq.toInt() ^ sq_mask) -% FIRST_PAWN);
    }

    fn collectPawnPairs(board: *const Board, col: Colour, sq_mask: u8, exclude: u64, indices: []u16) usize {
        const friendly_bb = board.pawnsFor(col) & ~exclude;
        const enemy_bb = board.pawnsFor(col.flipped()) & ~exclude;
        var n: usize = 0;
        n += pairBBs(friendly_bb, friendly_bb, 0, 0, sq_mask, indices[n..]);
        n += pairBBs(friendly_bb, enemy_bb, 0, PAWN_SQUARES, sq_mask, indices[n..]);
        n += pairBBs(enemy_bb, enemy_bb, PAWN_SQUARES, PAWN_SQUARES, sq_mask, indices[n..]);
        return n;
    }

    fn pairBBs(bb_a: u64, bb_b: u64, offset_a: u8, offset_b: u8, sq_mask: u8, out: []u16) usize {
        const same = offset_a == offset_b;
        var n: usize = 0;
        var outer = Bitboard.iterator(bb_a);
        while (outer.next()) |sq| {
            const id = pawnId(sq, offset_a, sq_mask);
            const inner_bb = (if (same) outer.state else bb_b) & arch.PP_MASK[sq.toInt()];
            var inner = Bitboard.iterator(inner_bb);
            while (inner.next()) |sq2| {
                out[n] = ppIndex(id, pawnId(sq2, offset_b, sq_mask));
                n += 1;
            }
        }
        return n;
    }

    fn writePairIndices(fixed_id: u16, fixed_sq: Square, friendly_bb: u64, enemy_bb: u64, sq_mask: u8, out: []u16) usize {
        const band = arch.PP_MASK[fixed_sq.toInt()];
        var n: usize = 0;
        var friendly = Bitboard.iterator(friendly_bb & band);
        while (friendly.next()) |sq| {
            out[n] = ppIndex(fixed_id, pawnId(sq, 0, sq_mask));
            n += 1;
        }
        var enemy = Bitboard.iterator(enemy_bb & band);
        while (enemy.next()) |sq| {
            out[n] = ppIndex(fixed_id, pawnId(sq, PAWN_SQUARES, sq_mask));
            n += 1;
        }
        return n;
    }

    fn collectAllPawnPairs(out: []u16, board: *const Board, col: Colour) usize {
        const sq_mask = ppSqMask(board, col);
        const total: usize = @popCount(board.pawns());
        const all_mask: u64 = simd.prefixMask(16, total);

        var mask = all_mask;
        var n: usize = undefined;
        const pairs = total -| 1;

        if (comptime simd.TARGET == .avx512vbmi) {
            const FIXED_INIT: @Vector(64, u8) = comptime blk: {
                var v: [64]u8 = @splat(17);
                for (0..16) |k| {
                    v[4 * k] = 0;
                    v[4 * k + 2] = 1;
                }
                break :blk v;
            };
            const FIXED_INC: @Vector(64, u8) = comptime blk: {
                var v: [64]u8 = @splat(0);
                for (0..16) |k| {
                    v[4 * k] = 2;
                    v[4 * k + 2] = 2;
                }
                break :blk v;
            };

            const pawn_bb = board.pawns();
            const pawns = collectPawnIdsVBMI2(board, col, sq_mask, 0);
            const others_il: IdVec32 = @bitCast(simd.vpermb(INTERLEAVE_MASK, pawns));

            const real_sqs: [16]u8 = std.simd.extract(simd.vpcompress(std.simd.iota(u8, 64), pawn_bb), 0, 16);

            n = 0;
            var fixed_idx = FIXED_INIT;
            var i: usize = 0;
            while (i < pairs) : ({
                i += 2;
                fixed_idx += FIXED_INC;
            }) {
                mask &= mask - 1;
                const m0 = mask & Bitboard.pext(arch.PP_MASK[real_sqs[i]] & pawn_bb, pawn_bb);
                mask &= mask - 1;
                const m1 = mask & Bitboard.pext(arch.PP_MASK[real_sqs[i + 1]] & pawn_bb, pawn_bb);

                const fixed: IdVec32 = @bitCast(simd.vpermb(fixed_idx, pawns));
                const pair_indices = ppIndex(fixed, others_il);
                const interleaved: u32 = @intCast(Bitboard.pdep(m0, 0x55555555) | Bitboard.pdep(m1, 0xAAAAAAAA));
                out[n..][0..32].* = simd.vpcompress(pair_indices, interleaved);
                n += @popCount(interleaved);
            }
        } else {
            n = collectPawnPairs(board, col, sq_mask, 0, out);
        }

        return n;
    }

    noinline fn buildThreatAccumulator(buf: *Accumulator, board: *const Board, col: Colour, weights: *const arch.Weights) void {
        @branchHint(.cold);
        var indices: [256]u16 = undefined;

        var n = nnue_threats.collectRefreshThreats(&indices, board, col);
        n += collectAllPawnPairs(indices[n..], board, col);
        @memset(&buf.data, 0);
        applyAllRows(buf, buf, weights, indices[0..n], &.{});
    }

    fn materialiseThreatHalf(self: *Context, ply: u16, col: Colour, board: *const Board, weights: *const arch.Weights) void {
        const timer = root.engine.time("materialise_threat");
        defer timer.register();
        const tf = &self.threat_frames[ply];
        const parent_tf = &self.threat_frames[ply - 1];

        if (tf.threat_updates.refresh[col.toInt()]) {
            @branchHint(.unlikely);
            self.refreshThreatHalf(ply, col, board, weights);
            return;
        }

        const adds_raw = tf.threat_updates.addSlice(&self.threat_add_stack);
        const subs_raw = tf.threat_updates.subSlice(&self.threat_sub_stack);

        const dp = dirtyPawns(self.psq.frames[ply].dirty_piece, col);
        const has_pp = dp.n_removed + dp.n_added > 0;

        if (adds_raw.len == 0 and subs_raw.len == 0 and !has_pp) {
            tf.threatHalf(col).* = parent_tf.threatHalf(col).*;
            tf.threatMirrorPtrFor(col).* = parent_tf.threatMirrorFor(col);
            return;
        }

        const king_sq = Square.fromBitboard(board.kingFor(col));
        const src = parent_tf.threatHalf(col).ptr;
        const dst = &self.threat_accumulator_stack[ply][col.toInt()];

        var add_indices: [nnue_threat_updates.UpdateBuffer.MaxAdds]u16 = undefined;
        var add_count: usize = 0;
        for (adds_raw) |upd| {
            const idx, const valid = nnue_threats.threatIndex(
                col,
                king_sq,
                .fromInt(upd.attacker),
                .fromInt(upd.from),
                .fromInt(upd.victim),
                .fromInt(upd.to),
            );
            add_indices[add_count] = @intCast(idx +% arch.TOTAL_PAWN_PAIRS & 0xffff);
            add_count += @intFromBool(valid);
        }

        var sub_indices: [nnue_threat_updates.UpdateBuffer.MaxSubs]u16 = undefined;
        var sub_count: usize = 0;
        for (subs_raw) |upd| {
            const idx, const valid = nnue_threats.threatIndex(
                col,
                king_sq,
                .fromInt(upd.attacker),
                .fromInt(upd.from),
                .fromInt(upd.victim),
                .fromInt(upd.to),
            );
            sub_indices[sub_count] = @intCast(idx +% arch.TOTAL_PAWN_PAIRS & 0xffff);
            sub_count += @intFromBool(valid);
        }

        if (has_pp and anyMaskedPair(board, dp)) {
            @branchHint(.unlikely);
            const pp = computePairs(board, col, dp, add_indices[add_count..], sub_indices[sub_count..]);
            add_count += pp.n_adds;
            sub_count += pp.n_subs;
        }

        // only iterate the accumulator once to save memory bandwidth, instead of adding the features one by one reloading the accumulator each time
        applyAllRows(dst, src, weights, add_indices[0..add_count], sub_indices[0..sub_count]);
        tf.threatHalf(col).* = .{ .ptr = dst };
        tf.threatMirrorPtrFor(col).* = parent_tf.threatMirrorFor(col);
    }

    fn ppSqMask(board: *const Board, col: Colour) u8 {
        return nnue_threats.perspectiveSquareMask(col, .fromBitboard(board.kingFor(col)));
    }

    const PawnRef = struct {
        sq: Square,
        enemy_offset: u8,

        fn init(sq: Square, pawn_col: Colour, perspective: Colour) PawnRef {
            return .{
                .sq = sq,
                .enemy_offset = PAWN_SQUARES * @intFromBool(pawn_col != perspective),
            };
        }

        fn from(feat: root.PSQTFeature, perspective: Colour) PawnRef {
            return init(feat.square(), feat.col(), perspective);
        }

        fn dummy() PawnRef {
            return comptime init(Square.fromInt(FIRST_PAWN), .white, .white);
        }
    };

    const DirtyPawns = struct {
        removed: [2]PawnRef = @splat(PawnRef.dummy()),
        added: PawnRef = PawnRef.dummy(),
        n_removed: u8 = 0,
        n_added: u8 = 0,
        exclude: u64 = 0,
    };

    fn dirtyPawns(dirty: psq.DirtyPiece, col: Colour) DirtyPawns {
        const DUMMY_FEATURE: root.PSQTFeature = .init(.white, .pawn, .fromInt(FIRST_PAWN));

        const do_add = switch (dirty) {
            .clean, .castle => false,
            .move, .capture => true,
        };

        const from = switch (dirty) {
            .clean, .castle => DUMMY_FEATURE,
            inline .move, .capture => |d| d.from,
        };

        const to = switch (dirty) {
            .clean, .castle => DUMMY_FEATURE,
            inline .move, .capture => |d| d.to,
        };

        const captured = switch (dirty) {
            .capture => |c| c.captured,
            else => DUMMY_FEATURE,
        };

        const from_is_pawn: u8 = @intFromBool(from.piece() == .pawn and do_add);
        const to_is_pawn: u8 = @intFromBool(to.piece() == .pawn and do_add);
        const cap_is_pawn: u8 = @intFromBool(captured.piece() == .pawn and dirty == .capture);

        const from_ref = PawnRef.from(from, col);
        const to_ref = PawnRef.from(to, col);
        const cap_ref = PawnRef.from(captured, col);

        return .{
            .removed = .{ if (from_is_pawn == 1) from_ref else cap_ref, cap_ref },
            .added = to_ref,
            .n_removed = from_is_pawn + cap_is_pawn,
            .n_added = to_is_pawn,
            .exclude = to.square().toBitboard() * @as(u64, to_is_pawn),
        };
    }

    fn anyMaskedPair(board: *const Board, dp: DirtyPawns) bool {
        const r0m = arch.PP_MASK[dp.removed[0].sq.toInt()];
        const r1m = arch.PP_MASK[dp.removed[1].sq.toInt()];
        const am = arch.PP_MASK[dp.added.sq.toInt()];
        const diff_bb = board.pawns() & ~dp.exclude | dp.removed[0].sq.toBitboard();
        return (r0m | r1m | am) & diff_bb != 0;
    }

    const PPCounts = struct { n_adds: usize, n_subs: usize };

    fn computePairs(board: *const Board, col: Colour, dp: DirtyPawns, add_out: []u16, sub_out: []u16) PPCounts {
        const sq_mask = ppSqMask(board, col);
        const r0_id = pawnId(dp.removed[0].sq, dp.removed[0].enemy_offset, sq_mask);
        const r1_id = pawnId(dp.removed[1].sq, dp.removed[1].enemy_offset, sq_mask);
        const a_id = pawnId(dp.added.sq, dp.added.enemy_offset, sq_mask);

        if (comptime simd.TARGET == .avx512vbmi) {
            return computePairsVBMI2(board, col, dp, sq_mask, r0_id, r1_id, a_id, add_out, sub_out);
        } else {
            return computePairsScalar(board, col, dp, sq_mask, r0_id, r1_id, a_id, add_out, sub_out);
        }
    }

    fn computePairsVBMI2(board: *const Board, col: Colour, dp: DirtyPawns, sq_mask: u8, r0_id: u16, r1_id: u16, a_id: u16, add_out: []u16, sub_out: []u16) PPCounts {
        const r0 = dp.removed[0];
        const r1 = dp.removed[1];
        const a = dp.added;

        const unch_bb = board.pawns() & ~dp.exclude;
        const unch_mask: u16 = simd.prefixMask(16, @popCount(unch_bb));
        const unch_doubled: IdVec32 = @bitCast(simd.vpermb(WIDEN_AND_DUP_MASK, collectPawnIdsVBMI2(board, col, sq_mask, dp.exclude)));

        const r0_band: u16 = @intCast(Bitboard.pext(arch.PP_MASK[r0.sq.toInt()] & unch_bb, unch_bb));
        const r1_band: u16 = @intCast(Bitboard.pext(arch.PP_MASK[r1.sq.toInt()] & unch_bb, unch_bb));

        const r0_mask = unch_mask & r0_band * @intFromBool(dp.n_removed >= 1);
        const r1_mask = unch_mask & r1_band * @intFromBool(dp.n_removed >= 2);
        const r_mask = @as(u32, r0_mask) | (@as(u32, r1_mask) << 16);

        const rv = std.simd.join(@as(IdVec, @splat(r0_id)), @as(IdVec, @splat(r1_id)));
        const ri = ppIndex(rv, unch_doubled);

        sub_out[0..32].* = simd.vpcompress(ri, r_mask);
        var n_subs: usize = @popCount(r_mask);

        const in_band = arch.PP_MASK[r0.sq.toInt()] >> @intCast(r1.sq.toInt()) & 1 != 0;
        sub_out[n_subs] = ppIndex(r0_id, r1_id);
        n_subs += @intFromBool(dp.n_removed >= 2 and in_band);

        const a_band: u16 = @intCast(Bitboard.pext(arch.PP_MASK[a.sq.toInt()] & unch_bb, unch_bb));
        const a_mask = unch_mask & a_band * @intFromBool(dp.n_added != 0);

        const ai = ppIndex(@as(IdVec, @splat(a_id)), std.simd.extract(unch_doubled, 0, 16));
        add_out[0..16].* = simd.vpcompress(ai, a_mask);

        return .{ .n_adds = @popCount(a_mask), .n_subs = n_subs };
    }

    fn computePairsScalar(board: *const Board, col: Colour, dp: DirtyPawns, sq_mask: u8, r0_id: u16, r1_id: u16, a_id: u16, add_out: []u16, sub_out: []u16) PPCounts {
        const r0 = dp.removed[0];
        const r1 = dp.removed[1];
        const a = dp.added;
        const friendly_bb = board.pawnsFor(col) & ~dp.exclude;
        const enemy_bb = board.pawnsFor(col.flipped()) & ~dp.exclude;

        var n_subs: usize = 0;
        var n_adds: usize = 0;
        if (dp.n_removed >= 1) {
            n_subs = writePairIndices(r0_id, r0.sq, friendly_bb, enemy_bb, sq_mask, sub_out);
            if (dp.n_removed >= 2) {
                n_subs += writePairIndices(r1_id, r1.sq, friendly_bb, enemy_bb, sq_mask, sub_out[n_subs..]);
                if (arch.PP_MASK[r0.sq.toInt()] >> @intCast(r1.sq.toInt()) & 1 != 0) {
                    sub_out[n_subs] = ppIndex(r0_id, r1_id);
                    n_subs += 1;
                }
            }
        }

        if (dp.n_added != 0) {
            n_adds = writePairIndices(a_id, a.sq, friendly_bb, enemy_bb, sq_mask, add_out);
        }
        return .{ .n_adds = n_adds, .n_subs = n_subs };
    }

    fn applyAllRows(
        noalias dst: *Accumulator,
        src: *const Accumulator,
        weights: *const arch.Weights,
        adds: []const u16,
        subs: []const u16,
    ) void {
        const timer = root.engine.time("apply_rows");
        defer timer.register();
        const combined: [*]const arch.ThreatWeight = @ptrCast(&weights.input.pp_w);
        var i: usize = 0;
        const TILE = arch.ACCUMULATOR_TILE;
        for (subs) |idx| @prefetch(&combined[idx], .{ .rw = .read });
        for (adds) |idx| @prefetch(&combined[idx], .{ .rw = .read });
        while (i < arch.ACCUMULATOR_VECTOR_COUNT) : (i += TILE) {
            var v: [TILE]arch.AccumulatorVec = src.vecs()[i..][0..TILE].*;
            for (subs) |idx| inline for (0..TILE) |t| {
                v[t] -= combined[idx][i + t];
            };
            for (adds) |idx| inline for (0..TILE) |t| {
                v[t] += combined[idx][i + t];
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
