const std = @import("std");
const root = @import("root.zig");
const Board = root.Board;
const Square = root.Square;
const Colour = root.Colour;
const PieceType = root.PieceType;
const ColouredPieceType = root.ColouredPieceType;
const Bitboard = root.Bitboard;
pub const ThreatFeature = extern struct {
    attacker: u8,
    from: u8,
    victim: u8,
    to: u8,

    comptime {
        if (@sizeOf(ThreatFeature) != 4) @compileError("ThreatFeatureUpdate must be 4 bytes");
        if (@offsetOf(ThreatFeature, "attacker") != 0) @compileError("bad layout");
        if (@offsetOf(ThreatFeature, "from") != 1) @compileError("bad layout");
        if (@offsetOf(ThreatFeature, "victim") != 2) @compileError("bad layout");
        if (@offsetOf(ThreatFeature, "to") != 3) @compileError("bad layout");
    }
};

pub const FEATURE_STACK_SIZE = root.SEARCH_MAX_PLY * UpdateBuffer.MaxAdds + 16;
pub const FeatureStack = [FEATURE_STACK_SIZE]ThreatFeature;

const FeatureBuffer = [*]align(4) ThreatFeature;

pub const Stacks = struct {
    add: FeatureBuffer,
    sub: FeatureBuffer,
};

pub const UpdateBuffer = struct {
    pub const MaxAdds = 128;
    pub const MaxSubs = 128;
    add_start: u16 = 0,
    add_end: u16 = 0,
    sub_start: u16 = 0,
    sub_end: u16 = 0,
    refresh: [2]bool = .{ false, false },

    pub fn addSlice(self: *const UpdateBuffer, noalias add_stack: []const ThreatFeature) []const ThreatFeature {
        return add_stack[self.add_start..self.add_end];
    }

    pub fn subSlice(self: *const UpdateBuffer, noalias sub_stack: []const ThreatFeature) []const ThreatFeature {
        return sub_stack[self.sub_start..self.sub_end];
    }

    pub fn clearFrom(self: *UpdateBuffer, noalias parent: *const UpdateBuffer) void {
        self.add_start = parent.add_end;
        self.add_end = parent.add_end;
        self.sub_start = parent.sub_end;
        self.sub_end = parent.sub_end;
        self.refresh = .{ false, false };
    }

    pub fn clearRoot(self: *UpdateBuffer) void {
        self.add_start = 0;
        self.add_end = 0;
        self.sub_start = 0;
        self.sub_end = 0;
        self.refresh = .{ false, false };
    }

    inline fn addPtr(self: *const UpdateBuffer, noalias add_stack: FeatureBuffer) FeatureBuffer {
        return add_stack + self.add_end;
    }

    inline fn subPtr(self: *const UpdateBuffer, noalias sub_stack: FeatureBuffer) FeatureBuffer {
        return sub_stack + self.sub_end;
    }

    inline fn pushAdd(self: *UpdateBuffer, noalias add_stack: FeatureBuffer, update: ThreatFeature) void {
        std.debug.assert(self.add_end - self.add_start < MaxAdds);
        (add_stack + self.add_end)[0] = update;
        self.add_end += 1;
    }

    inline fn pushSub(self: *UpdateBuffer, noalias sub_stack: FeatureBuffer, update: ThreatFeature) void {
        std.debug.assert(self.sub_end - self.sub_start < MaxSubs);
        (sub_stack + self.sub_end)[0] = update;
        self.sub_end += 1;
    }
};

inline fn emitTuple(buf: *UpdateBuffer, stacks: Stacks, comptime is_add: bool, attacker: u8, from: u8, victim: u8, to: u8) void {
    const update = ThreatFeature{
        .attacker = attacker,
        .from = from,
        .victim = victim,
        .to = to,
    };
    if (is_add) buf.pushAdd(stacks.add, update) else buf.pushSub(stacks.sub, update);
}

const scalar = struct {
    const RayEntry = struct {
        squares: [7]Square,
        len: u8 = 0,

        fn slice(self: *const RayEntry) []const Square {
            return self.squares[0..self.len];
        }
    };

    const RAY_D_RANKS = [_]comptime_int{ 1, 1, 0, -1, -1, -1, 0, 1 };
    const RAY_D_FILES = [_]comptime_int{ 0, 1, 1, 1, 0, -1, -1, -1 };

    const RAY_TABLE: [64][8]RayEntry = blk: {
        @setEvalBranchQuota(1 << 16);
        var table: [64][8]RayEntry = undefined;
        for (0..64) |sq_idx| {
            const rank = sq_idx / 8;
            const file = sq_idx % 8;
            for (RAY_D_RANKS, RAY_D_FILES, 0..) |dr, df, dir| {
                var entry = RayEntry{};
                var r = rank + dr;
                var f = file + df;
                while (r >= 0 and r < 8 and f >= 0 and f < 8) {
                    entry.squares[entry.len] = r * 8 + f;
                    entry.len += 1;
                    r += dr;
                    f += df;
                }
                table[sq_idx][dir] = entry;
            }
        }
        break :blk table;
    };

    const KnightEntry = struct {
        squares: [8]Square,
        len: u8 = 0,

        fn slice(self: *const KnightEntry) []const Square {
            return self.squares[0..self.len];
        }
    };

    const KNIGHT_TABLE: [64]KnightEntry = blk: {
        var table: [64]KnightEntry = undefined;
        for (0..64) |sq_idx| {
            const rank = sq_idx / 8;
            const file = sq_idx % 8;
            var entry = KnightEntry{};
            for (Bitboard.KNIGHT_D_RANKS, Bitboard.KNIGHT_D_FILES) |dr, df| {
                const r = rank + dr;
                const f = file + df;
                if (r >= 0 and r < 8 and f >= 0 and f < 8) {
                    entry.squares[entry.len] = r * 8 + f;
                    entry.len += 1;
                }
            }
            table[sq_idx] = entry;
        }
        break :blk table;
    };

    fn outgoingRayMask(pt: PieceType, col: Colour) u8 {
        return switch (pt) {
            .pawn => if (col == .white) (1 << 1) | (1 << 7) else (1 << 3) | (1 << 5),
            .bishop => (1 << 1) | (1 << 3) | (1 << 5) | (1 << 7),
            .rook => (1 << 0) | (1 << 2) | (1 << 4) | (1 << 6),
            .queen => 0xFF,
            .knight, .king => 0,
        };
    }

    fn canAttackFocus(pt: PieceType, col: Colour, dir: u3, dist: u8) bool {
        return switch (pt) {
            .rook => dir & 1 == 0,
            .bishop => dir & 1 == 1,
            .queen => true,
            .pawn => dist == 1 and switch (col) {
                .white => dir == 3 or dir == 5,
                .black => dir == 1 or dir == 7,
            },
            .knight, .king => false,
        };
    }

    fn sliderAttacksDir(pt: PieceType, dir: u3) bool {
        return switch (pt) {
            .bishop => dir & 1 == 1,
            .rook => dir & 1 == 0,
            .queen => true,
            else => false,
        };
    }

    fn isSlider(pt: PieceType) bool {
        return pt == .bishop or pt == .rook or pt == .queen;
    }

    const NearestPiece = struct { sq: Square, dist: u8 };

    fn findNearest(ray: *const RayEntry, occ: u64) ?NearestPiece {
        for (ray.slice(), 0..) |sq, i| {
            if (occ & sq.toBitboard() != 0) {
                return .{ .sq = sq, .dist = @intCast(i + 1) };
            }
        }
        return null;
    }

    fn emitChangeSide(
        buf: *UpdateBuffer,
        stacks: Stacks,
        board: *const Board,
        piece: ColouredPieceType,
        sq: Square,
        comptime is_add: bool,
        occ: u64,
    ) void {
        const pt = piece.toPieceType();
        const col = piece.toColour();
        const sq_idx = sq.toInt();

        if (pt != .king) {
            if (pt == .knight) {
                for (KNIGHT_TABLE[sq_idx].slice()) |ksq| {
                    if (occ & ksq.toBitboard() == 0) continue;
                    const victim = board.colouredPieceOn(ksq) orelse continue;
                    if (victim.toPieceType() == .king) continue;
                    emitTuple(buf, stacks, is_add, piece.toInt(), sq_idx, victim.toInt(), ksq.toInt());
                }
            } else {
                const out_mask = outgoingRayMask(pt, col);
                const max_dist: u8 = if (pt == .pawn) 1 else 7;
                for (0..8) |dir_idx| {
                    const dir: u3 = @intCast(dir_idx);
                    if (out_mask & (@as(u8, 1) << dir) == 0) continue;
                    if (findNearest(&RAY_TABLE[sq_idx][dir], occ)) |nearest| {
                        if (nearest.dist > max_dist) continue;
                        const victim = board.colouredPieceOn(nearest.sq) orelse continue;
                        if (victim.toPieceType() == .king) continue;
                        emitTuple(buf, stacks, is_add, piece.toInt(), sq_idx, victim.toInt(), nearest.sq.toInt());
                    }
                }
            }

            for (0..8) |dir| {
                if (findNearest(&RAY_TABLE[sq_idx][dir], occ)) |nearest| {
                    const attacker = board.colouredPieceOn(nearest.sq) orelse continue;
                    if (canAttackFocus(attacker.toPieceType(), attacker.toColour(), dir, nearest.dist)) {
                        emitTuple(buf, stacks, is_add, attacker.toInt(), nearest.sq.toInt(), piece.toInt(), sq_idx);
                    }
                }
            }

            for (KNIGHT_TABLE[sq_idx].slice()) |ksq| {
                if (occ & ksq.toBitboard() == 0) continue;
                const attacker = board.colouredPieceOn(ksq) orelse continue;
                if (attacker.toPieceType() == .knight) {
                    emitTuple(buf, stacks, is_add, attacker.toInt(), ksq.toInt(), piece.toInt(), sq_idx);
                }
            }
        }

        for (0..4) |pair_idx| {
            const dir1: u3 = @intCast(pair_idx);
            const dir2: u3 = @intCast(pair_idx + 4);

            const n1 = findNearest(&RAY_TABLE[sq_idx][dir1], occ) orelse continue;
            const n2 = findNearest(&RAY_TABLE[sq_idx][dir2], occ) orelse continue;

            const p1 = board.colouredPieceOn(n1.sq) orelse continue;
            const p2 = board.colouredPieceOn(n2.sq) orelse continue;

            if (isSlider(p1.toPieceType()) and sliderAttacksDir(p1.toPieceType(), dir2) and p2.toPieceType() != .king) {
                emitTuple(buf, stacks, !is_add, p1.toInt(), n1.sq.toInt(), p2.toInt(), n2.sq.toInt());
            }

            if (isSlider(p2.toPieceType()) and sliderAttacksDir(p2.toPieceType(), dir1) and p1.toPieceType() != .king) {
                emitTuple(buf, stacks, !is_add, p2.toInt(), n2.sq.toInt(), p1.toInt(), n1.sq.toInt());
            }
        }
    }

    pub fn doOnChange(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, piece: ColouredPieceType, sq: Square, comptime is_add: bool) void {
        emitChangeSide(buf, stacks, board, piece, sq, is_add, board.occupancy());
    }

    pub fn doOnMove(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, old_piece: ColouredPieceType, src: Square, new_piece: ColouredPieceType, dst: Square) void {
        const occ = board.occupancy();
        emitChangeSide(buf, stacks, board, old_piece, src, false, occ & ~dst.toBitboard());
        emitChangeSide(buf, stacks, board, new_piece, dst, true, occ);
    }

    pub fn doOnMutate(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, old_piece: ColouredPieceType, new_piece: ColouredPieceType, sq: Square) void {
        const occ = board.occupancy();
        const sq_idx = sq.toInt();
        const old_pt = old_piece.toPieceType();
        const old_col = old_piece.toColour();
        const new_pt = new_piece.toPieceType();
        const new_col = new_piece.toColour();

        if (old_pt == .knight) {
            for (KNIGHT_TABLE[sq_idx].slice()) |ksq| {
                if (occ & ksq.toBitboard() == 0) continue;
                const victim = board.colouredPieceOn(ksq) orelse continue;
                if (victim.toPieceType() == .king) continue;
                emitTuple(buf, stacks, false, old_piece.toInt(), sq_idx, victim.toInt(), ksq.toInt());
            }
        } else if (old_pt != .king) {
            const out_mask = outgoingRayMask(old_pt, old_col);
            const max_dist: u8 = if (old_pt == .pawn) 1 else 7;
            for (0..8) |dir_idx| {
                const dir: u3 = @intCast(dir_idx);
                if (out_mask & (@as(u8, 1) << dir) == 0) continue;
                if (findNearest(&RAY_TABLE[sq_idx][dir], occ)) |nearest| {
                    if (nearest.dist > max_dist) continue;
                    const victim = board.colouredPieceOn(nearest.sq) orelse continue;
                    if (victim.toPieceType() == .king) continue;
                    emitTuple(buf, stacks, false, old_piece.toInt(), sq_idx, victim.toInt(), nearest.sq.toInt());
                }
            }
        }

        if (new_pt == .knight) {
            for (KNIGHT_TABLE[sq_idx].slice()) |ksq| {
                if (occ & ksq.toBitboard() == 0) continue;
                const victim = board.colouredPieceOn(ksq) orelse continue;
                if (victim.toPieceType() == .king) continue;
                emitTuple(buf, stacks, true, new_piece.toInt(), sq_idx, victim.toInt(), ksq.toInt());
            }
        } else if (new_pt != .king) {
            const out_mask = outgoingRayMask(new_pt, new_col);
            const max_dist: u8 = if (new_pt == .pawn) 1 else 7;
            for (0..8) |dir_idx| {
                const dir: u3 = @intCast(dir_idx);
                if (out_mask & (@as(u8, 1) << dir) == 0) continue;
                if (findNearest(&RAY_TABLE[sq_idx][dir], occ)) |nearest| {
                    if (nearest.dist > max_dist) continue;
                    const victim = board.colouredPieceOn(nearest.sq) orelse continue;
                    if (victim.toPieceType() == .king) continue;
                    emitTuple(buf, stacks, true, new_piece.toInt(), sq_idx, victim.toInt(), nearest.sq.toInt());
                }
            }
        }

        if (old_pt != .king) {
            for (0..8) |dir_idx| {
                const dir: u3 = @intCast(dir_idx);
                if (findNearest(&RAY_TABLE[sq_idx][dir], occ)) |nearest| {
                    const attacker = board.colouredPieceOn(nearest.sq) orelse continue;
                    if (canAttackFocus(attacker.toPieceType(), attacker.toColour(), dir, nearest.dist)) {
                        emitTuple(buf, stacks, false, attacker.toInt(), nearest.sq.toInt(), old_piece.toInt(), sq_idx);
                    }
                }
            }
            for (KNIGHT_TABLE[sq_idx].slice()) |ksq| {
                if (occ & ksq.toBitboard() == 0) continue;
                const attacker = board.colouredPieceOn(ksq) orelse continue;
                if (attacker.toPieceType() == .knight) {
                    emitTuple(buf, stacks, false, attacker.toInt(), ksq.toInt(), old_piece.toInt(), sq_idx);
                }
            }
        }

        if (new_pt != .king) {
            for (0..8) |dir_idx| {
                const dir: u3 = @intCast(dir_idx);
                if (findNearest(&RAY_TABLE[sq_idx][dir], occ)) |nearest| {
                    const attacker = board.colouredPieceOn(nearest.sq) orelse continue;
                    if (canAttackFocus(attacker.toPieceType(), attacker.toColour(), dir, nearest.dist)) {
                        emitTuple(buf, stacks, true, attacker.toInt(), nearest.sq.toInt(), new_piece.toInt(), sq_idx);
                    }
                }
            }
            for (KNIGHT_TABLE[sq_idx].slice()) |ksq| {
                if (occ & ksq.toBitboard() == 0) continue;
                const attacker = board.colouredPieceOn(ksq) orelse continue;
                if (attacker.toPieceType() == .knight) {
                    emitTuple(buf, stacks, true, attacker.toInt(), ksq.toInt(), new_piece.toInt(), sq_idx);
                }
            }
        }
    }
};

const builtin = @import("builtin");
const simd = @import("simd.zig");
const arch = @import("nnue_arch.zig");
const has_vbmi = simd.TARGET == .avx512vbmi;
const has_vbmi2 = has_vbmi and builtin.cpu.has(.x86, .avx512vbmi2);

const byte_ray = struct {
    const Bitrays = u64;

    const Bit = struct {
        const WhitePawn: u8 = 0x01;
        const BlackPawn: u8 = 0x02;
        const Knight: u8 = 0x04;
        const Bishop: u8 = 0x08;
        const Rook: u8 = 0x10;
        const Queen: u8 = 0x20;
        const King: u8 = 0x40;
    };

    const NON_KNIGHT: Bitrays = 0xFEFE_FEFE_FEFE_FEFE;
    const LANE_0_MASK: Bitrays = 0x0101_0101_0101_0101;
    const INVALID_SQ: u8 = 0x80;

    const PIECE_TO_BIT: [16]u8 = .{
        Bit.WhitePawn, Bit.BlackPawn,
        Bit.Knight,    Bit.Knight,
        Bit.Bishop,    Bit.Bishop,
        Bit.Rook,      Bit.Rook,
        Bit.Queen,     Bit.Queen,
        Bit.King,      Bit.King,
        0,             0,
        0,             0,
    };

    const RAY_OFFSETS = [64]u8{
        0x1F, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70,
        0x21, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x12, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0xF2, 0xF1, 0xE2, 0xD3, 0xC4, 0xB5, 0xA6, 0x97,
        0xE1, 0xF0, 0xE0, 0xD0, 0xC0, 0xB0, 0xA0, 0x90,
        0xDF, 0xEF, 0xDE, 0xCD, 0xBC, 0xAB, 0x9A, 0x89,
        0xEE, 0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA, 0xF9,
        0x0E, 0x0F, 0x1E, 0x2D, 0x3C, 0x4B, 0x5A, 0x69,
    };

    const Permutation = struct {
        indices: Byteboard,
        valid: u64,
    };

    const PERMUTATION_TABLE: [64]Permutation = blk: {
        @setEvalBranchQuota(1 << 16);
        var table: [64]Permutation = undefined;
        for (0..64) |sq| {
            const focus_0x88: u8 = sq + (sq & 0x38);
            var indices: [64]u8 = undefined;
            var valid: u64 = 0;
            for (0..64) |i| {
                const wide = RAY_OFFSETS[i] +% focus_0x88;
                const is_valid = wide & 0x88 == 0;
                const narrow = ((wide & 0x70) >> 1) | (wide & 0x07);
                indices[i] = if (is_valid) narrow else INVALID_SQ;
                if (is_valid) valid |= @as(u64, 1) << i;
            }
            table[sq] = .{ .indices = indices, .valid = valid };
        }
        break :blk table;
    };

    const RAY_ATTACKS: [12]Bitrays = blk: {
        const LANES: Bitrays = 0xFE;
        const PAWN_LANE: Bitrays = 0x02;
        var m: [12]Bitrays = .{0} ** 12;
        m[0] = PAWN_LANE << 8 | PAWN_LANE << 56;
        m[1] = PAWN_LANE << 24 | PAWN_LANE << 40;
        m[2] = LANE_0_MASK;
        m[3] = LANE_0_MASK;
        m[4] = LANES << 8 | LANES << 24 | LANES << 40 | LANES << 56;
        m[5] = m[4];
        m[6] = LANES | LANES << 16 | LANES << 32 | LANES << 48;
        m[7] = m[6];
        m[8] = 0xFEFE_FEFE_FEFE_FEFE;
        m[9] = m[8];
        m[10] = 0;
        m[11] = 0;
        break :blk m;
    };

    const INCOMING_THREATS: [64]u8 = blk: {
        const RQ: u8 = Bit.Rook | Bit.Queen;
        const BQ: u8 = Bit.Bishop | Bit.Queen;
        const BQ_WP: u8 = BQ | Bit.WhitePawn;
        const BQ_BP: u8 = BQ | Bit.BlackPawn;
        const K: u8 = Bit.Knight;
        break :blk .{
            K, RQ,    RQ, RQ, RQ, RQ, RQ, RQ,
            K, BQ_BP, BQ, BQ, BQ, BQ, BQ, BQ,
            K, RQ,    RQ, RQ, RQ, RQ, RQ, RQ,
            K, BQ_WP, BQ, BQ, BQ, BQ, BQ, BQ,
            K, RQ,    RQ, RQ, RQ, RQ, RQ, RQ,
            K, BQ_WP, BQ, BQ, BQ, BQ, BQ, BQ,
            K, RQ,    RQ, RQ, RQ, RQ, RQ, RQ,
            K, BQ_BP, BQ, BQ, BQ, BQ, BQ, BQ,
        };
    };

    const INCOMING_SLIDERS: [64]u8 = blk: {
        const RQ: u8 = Bit.Rook | Bit.Queen;
        const BQ: u8 = Bit.Bishop | Bit.Queen;
        break :blk .{
            0, RQ, RQ, RQ, RQ, RQ, RQ, RQ,
            0, BQ, BQ, BQ, BQ, BQ, BQ, BQ,
            0, RQ, RQ, RQ, RQ, RQ, RQ, RQ,
            0, BQ, BQ, BQ, BQ, BQ, BQ, BQ,
            0, RQ, RQ, RQ, RQ, RQ, RQ, RQ,
            0, BQ, BQ, BQ, BQ, BQ, BQ, BQ,
            0, RQ, RQ, RQ, RQ, RQ, RQ, RQ,
            0, BQ, BQ, BQ, BQ, BQ, BQ, BQ,
        };
    };

    const Byteboard = @Vector(64, u8);
    const ZERO: Byteboard = @splat(0);
    const EMPTY_BIT: u8 = 0x80;
    const KING_BOARD: Byteboard = @splat(Bit.King);

    const PIECE_TO_BIT_LUT: Byteboard = blk: {
        var v: [64]u8 = undefined;
        for (0..4) |lane| for (0..16) |i| {
            v[lane * 16 + i] = if (i < PIECE_TO_BIT.len) PIECE_TO_BIT[i] else 0;
        };
        break :blk v;
    };

    const RayVector = struct {
        perm: Byteboard,
        pieces: Byteboard,
        bits: Byteboard,
    };

    inline fn permuteMailbox(board: *const Board, focus: u8, ignore: ?u8) RayVector {
        if (has_vbmi) return permuteMailboxVbmi(board, focus, ignore);
        return permuteMailboxScalar(board, focus, ignore);
    }

    inline fn permuteMailboxVbmi(board: *const Board, focus: u8, ignore: ?u8) RayVector {
        const perm = PERMUTATION_TABLE[focus];
        var mailbox_vec: Byteboard = board.mailbox;
        if (ignore) |ign| {
            const ignore_mask: @Vector(64, bool) = @bitCast(@as(u64, 1) << @intCast(ign));
            mailbox_vec = @select(u8, ignore_mask, @as(Byteboard, @splat(EMPTY_BIT)), mailbox_vec);
        }
        const pieces = simd.vpermb(perm.indices, mailbox_vec);
        const bits = simd.vpshufbMask(pieces, PIECE_TO_BIT_LUT, perm.valid);
        return .{ .perm = perm.indices, .pieces = pieces, .bits = bits };
    }

    inline fn permuteMailboxScalar(board: *const Board, focus: u8, ignore: ?u8) RayVector {
        const perm = PERMUTATION_TABLE[focus];
        const perm_arr: [64]u8 = perm.indices;
        var pieces: Byteboard = undefined;
        var bits: Byteboard = undefined;
        for (0..64) |i| {
            const sq = perm_arr[i];
            if (sq == INVALID_SQ or (ignore != null and sq == ignore.?)) {
                pieces[i] = INVALID_SQ;
                bits[i] = 0;
            } else {
                const raw = board.mailbox[sq];
                if (raw & EMPTY_BIT != 0) {
                    pieces[i] = INVALID_SQ;
                    bits[i] = 0;
                } else {
                    pieces[i] = raw;
                    bits[i] = PIECE_TO_BIT[raw];
                }
            }
        }
        return .{ .perm = perm.indices, .pieces = pieces, .bits = bits };
    }

    inline fn occupiedMask(bits: Byteboard) Bitrays {
        return @bitCast(bits != ZERO);
    }

    inline fn closestOnRays(occupied: Bitrays) Bitrays {
        const o = occupied | 0x8181_8181_8181_8181;
        return (o ^ (o -% 0x0303_0303_0303_0303)) & occupied;
    }

    inline fn testBits(a: Byteboard, b: Byteboard) Bitrays {
        return @bitCast(a & b != ZERO);
    }

    const Tupleboard = @Vector(16, u32);

    const PAIR2_SHUFFLE: @Vector(64, i8) = blk: {
        var s: [64]i8 = undefined;
        for (0..16) |idx| {
            const i: i8 = idx;
            s[idx * 4 + 0] = i;
            s[idx * 4 + 1] = -i - 1;
            s[idx * 4 + 2] = i;
            s[idx * 4 + 3] = -i - 1;
        }
        break :blk s;
    };

    const OUTGOING_SELECT: @Vector(64, bool) =
        @bitCast(@as(u64, 0xCCCC_CCCC_CCCC_CCCC));

    const INCOMING_SELECT: @Vector(64, bool) =
        @bitCast(@as(u64, 0x3333_3333_3333_3333));

    inline fn compressPairs(pieces: Byteboard, perm: Byteboard, mask: Bitrays) Byteboard {
        return @shuffle(
            u8,
            simd.vpcompressb(pieces, mask),
            simd.vpcompressb(perm, mask),
            PAIR2_SHUFFLE,
        );
    }

    noinline fn appendTuplesImpl(ptr: FeatureBuffer, tuples: Tupleboard) void {
        const dest: *[16]u32 = @ptrCast(ptr);
        dest.* = tuples;
    }

    inline fn appendTuples(buf: *UpdateBuffer, stacks: Stacks, comptime is_add: bool, n: usize, tuples: Tupleboard) void {
        const ptr = if (is_add) buf.addPtr(stacks.add) else buf.subPtr(stacks.sub);
        if (is_add) {
            std.debug.assert(buf.add_end - buf.add_start + 16 <= UpdateBuffer.MaxAdds);
            buf.add_end += @intCast(n);
        } else {
            std.debug.assert(buf.sub_end - buf.sub_start + 16 <= UpdateBuffer.MaxSubs);
            buf.sub_end += @intCast(n);
        }
        appendTuplesImpl(ptr, tuples);
    }

    inline fn brEmitOutgoing(buf: *UpdateBuffer, stacks: Stacks, rv: *const RayVector, closest: Bitrays, piece: ColouredPieceType, focus_sq: u8, comptime is_add: bool) void {
        const attacked = RAY_ATTACKS[piece.toInt()] & closest & ~testBits(rv.bits, KING_BOARD);

        if (has_vbmi2) {
            const n = @popCount(attacked);
            if (n == 0) return;

            const focus_pair_u16: @Vector(32, u16) = @splat(piece.toInt() | @as(u16, focus_sq) << 8);
            const pair1: Byteboard = @bitCast(focus_pair_u16);

            const pair2 = compressPairs(rv.pieces, rv.perm, attacked);
            const tuples: Tupleboard = @bitCast(@select(u8, OUTGOING_SELECT, pair2, pair1));
            appendTuples(buf, stacks, is_add, n, tuples);
        } else {
            const perm: [64]u8 = rv.perm;
            const pieces: [64]u8 = rv.pieces;
            var it = Bitboard.iterator(attacked);
            while (it.next()) |sq| {
                const lane = sq.toInt();
                emitTuple(buf, stacks, is_add, piece.toInt(), focus_sq, pieces[lane], perm[lane]);
            }
        }
    }

    inline fn brEmitIncoming(buf: *UpdateBuffer, stacks: Stacks, rv: *const RayVector, closest: Bitrays, piece: ColouredPieceType, focus_sq: u8, comptime is_add: bool) void {
        const attackers = closest & testBits(rv.bits, INCOMING_THREATS) & ~testBits(rv.bits, KING_BOARD);

        if (has_vbmi2) {
            const n = @popCount(attackers);
            if (n == 0) return;

            const focus_pair_u16: @Vector(32, u16) =
                @splat(@as(u16, piece.toInt()) | (@as(u16, focus_sq) << 8));
            const pair1: Byteboard = @bitCast(focus_pair_u16);

            const pair2 = compressPairs(rv.pieces, rv.perm, attackers);
            const tuples: Tupleboard = @bitCast(@select(u8, INCOMING_SELECT, pair2, pair1));
            appendTuples(buf, stacks, is_add, n, tuples);
        } else {
            const perm: [64]u8 = rv.perm;
            const pieces: [64]u8 = rv.pieces;
            var it = Bitboard.iterator(attackers);
            while (it.next()) |sq| {
                const lane = sq.toInt();
                emitTuple(buf, stacks, is_add, pieces[lane], perm[lane], piece.toInt(), focus_sq);
            }
        }
    }

    inline fn flipHalves(v: Byteboard) Byteboard {
        const FLIP: @Vector(64, i8) = comptime blk: {
            var s: [64]i8 = undefined;
            for (0..32) |i| {
                s[i] = i + 32;
                s[i + 32] = i;
            }
            break :blk s;
        };
        return @shuffle(u8, v, undefined, FLIP);
    }

    inline fn rayFill(br: Bitrays) Bitrays {
        const t = (br +% 0x7E7E_7E7E_7E7E_7E7E) & 0x8080_8080_8080_8080;
        return t -% (t >> 7);
    }

    inline fn brEmitDiscovered(buf: *UpdateBuffer, stacks: Stacks, rv: *const RayVector, closest: Bitrays, comptime is_add: bool) void {
        const non_king = closest & ~testBits(rv.bits, KING_BOARD);
        const potential_victims = non_king & NON_KNIGHT;
        const sliders = closest & testBits(rv.bits, INCOMING_SLIDERS);
        const perm_arr: [64]u8 = rv.perm;
        const pieces_arr: [64]u8 = rv.pieces;

        if (has_vbmi2) {
            const victim_flipped = (potential_victims << 32) | (potential_victims >> 32);
            const valid = rayFill(victim_flipped) & rayFill(sliders);
            const slider_mask = sliders & valid;
            const victim_mask = victim_flipped & valid;
            const n: usize = @popCount(slider_mask);

            const att = compressPairs(rv.pieces, rv.perm, slider_mask);
            const vic = compressPairs(flipHalves(rv.pieces), flipHalves(rv.perm), victim_mask);
            const tuples: Tupleboard = @bitCast(@select(u8, OUTGOING_SELECT, vic, att));
            appendTuples(buf, stacks, !is_add, n, tuples);
        } else {
            for (0..4) |pair| {
                const ray_a = pair * 8;
                const ray_b = pair * 8 + 32;

                const slider_a = sliders >> @intCast(ray_a) & 0xff;
                const victim_b = potential_victims >> @intCast(ray_b) & 0xff;
                const sl_a = ray_a + @ctz(slider_a);
                const vl_b = ray_b + @ctz(victim_b);
                if (slider_a != 0 and victim_b != 0) {
                    @branchHint(.unpredictable);
                    emitTuple(buf, stacks, !is_add, pieces_arr[sl_a], perm_arr[sl_a], pieces_arr[vl_b], perm_arr[vl_b]);
                }

                const slider_b = sliders >> @intCast(ray_b) & 0xff;
                const victim_a = potential_victims >> @intCast(ray_a) & 0xff;
                const sl_b = ray_b + @ctz(slider_b);
                const vl_a = ray_a + @ctz(victim_a);
                if (slider_b != 0 and victim_a != 0) {
                    @branchHint(.unpredictable);
                    emitTuple(buf, stacks, !is_add, pieces_arr[sl_b], perm_arr[sl_b], pieces_arr[vl_a], perm_arr[vl_a]);
                }
            }
        }
    }

    inline fn emitChangeSide(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, piece: ColouredPieceType, focus: u8, comptime is_add: bool, ignore: ?u8) void {
        const rv = permuteMailbox(board, focus, ignore);
        const occupied = occupiedMask(rv.bits);
        const closest = closestOnRays(occupied);

        if (piece.toPieceType() != .king) {
            brEmitOutgoing(buf, stacks, &rv, closest, piece, focus, is_add);
            brEmitIncoming(buf, stacks, &rv, closest, piece, focus, is_add);
        }
        brEmitDiscovered(buf, stacks, &rv, closest, is_add);
    }

    pub fn doOnChange(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, piece: ColouredPieceType, sq: Square, comptime is_add: bool) void {
        emitChangeSide(buf, stacks, board, piece, sq.toInt(), is_add, null);
    }

    pub fn doOnMove(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, old_piece: ColouredPieceType, src: Square, new_piece: ColouredPieceType, dst: Square) void {
        emitChangeSide(buf, stacks, board, old_piece, src.toInt(), false, dst.toInt());
        emitChangeSide(buf, stacks, board, new_piece, dst.toInt(), true, null);
    }

    pub fn doOnMutate(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, old_piece: ColouredPieceType, new_piece: ColouredPieceType, sq: Square) void {
        const focus = sq.toInt();
        const rv = permuteMailbox(board, focus, null);
        const occupied = occupiedMask(rv.bits);
        const closest = closestOnRays(occupied);

        if (old_piece.toPieceType() != .king) {
            brEmitOutgoing(buf, stacks, &rv, closest, old_piece, focus, false);
            brEmitIncoming(buf, stacks, &rv, closest, old_piece, focus, false);
        }
        if (new_piece.toPieceType() != .king) {
            brEmitOutgoing(buf, stacks, &rv, closest, new_piece, focus, true);
            brEmitIncoming(buf, stacks, &rv, closest, new_piece, focus, true);
        }
    }
};

const backend = if (has_vbmi) byte_ray else scalar;

pub fn onChange(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, piece: ColouredPieceType, sq: Square, comptime is_add: bool) void {
    backend.doOnChange(buf, stacks, board, piece, sq, is_add);
}

pub fn onMove(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, old_piece: ColouredPieceType, src: Square, new_piece: ColouredPieceType, dst: Square) void {
    backend.doOnMove(buf, stacks, board, old_piece, src, new_piece, dst);
}

pub fn onMutate(buf: *UpdateBuffer, stacks: Stacks, board: *const Board, old_piece: ColouredPieceType, new_piece: ColouredPieceType, sq: Square) void {
    backend.doOnMutate(buf, stacks, board, old_piece, new_piece, sq);
}

pub fn prepareKingMove(buf: *UpdateBuffer, colour: Colour) void {
    buf.refresh[colour.toInt()] = true;
}
