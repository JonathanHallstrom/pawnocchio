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

const Move = root.Move;
const Colour = root.Colour;
const ColouredPieceType = root.ColouredPieceType;
const PieceType = root.PieceType;
const Board = root.Board;
const evaluation = root.evaluation;
const TUNABLES = root.TUNABLE_CONSTANTS;

pub const TypedMove = struct {
    move: Move,
    tp: PieceType,
    flags: u8 = 0,

    pub fn init() TypedMove {
        return .{
            .move = Move.init(),
            .tp = .pawn,
        };
    }

    pub inline fn fromBoard(
        board: *const Board,
        prev_move: Move,
        move_: Move,
    ) TypedMove {
        std.debug.assert(!move_.isNull());
        var res: TypedMove = .{
            .move = move_,
            .tp = board.pieceOn(move_.from()).?,
        };
        const opponent_threats = board.threatsFor(board.stm.flipped());
        res.setFromThreatened(move_.from().toBitboard() & opponent_threats != 0);
        res.setToThreatened(move_.to().toBitboard() & opponent_threats != 0);
        _ = prev_move;
        // res.setRecapture(move_.to() == prev_move.to() and !prev_move.isNull());
        return res;
    }

    const FROM_THREATENED = 1;
    const TO_THREATENED = 2;
    const RECAPTURE = 4;

    pub fn setFromThreatened(self: *TypedMove, val: bool) void {
        self.flags |= if (val) FROM_THREATENED else 0;
    }

    pub fn setToThreatened(self: *TypedMove, val: bool) void {
        self.flags |= if (val) TO_THREATENED else 0;
    }

    pub fn setRecapture(self: *TypedMove, val: bool) void {
        self.flags |= if (val) RECAPTURE else 0;
    }

    pub fn fromThreatened(self: *const TypedMove) bool {
        return self.flags & FROM_THREATENED != 0;
    }

    pub fn toThreatened(self: *const TypedMove) bool {
        return self.flags & TO_THREATENED != 0;
    }

    pub fn recapture(self: *const TypedMove) bool {
        return self.flags & RECAPTURE != 0;
    }
};

pub const MAX_HISTORY: i16 = 1 << 14;
const CORRHIST_SIZE = 32768;
const MAX_CORRHIST = 256 * 32;
const SHIFT = @ctz(MAX_HISTORY);
pub const CONTHIST_OFFSETS = [_]comptime_int{
    0,
    1,
    3,
};
pub const NUM_CONTHISTS = CONTHIST_OFFSETS.len;
pub const HIGHEST_CONTHIST_OFFSET = CONTHIST_OFFSETS[NUM_CONTHISTS - 1];
pub const ConthistMoves = [NUM_CONTHISTS]TypedMove;
pub const ConthistTables = [NUM_CONTHISTS]*ContHistory.ContHistTable;

pub const MoveHistoryTerms = struct {
    quiet: i32 = 0,
    pawn: i32 = 0,
    cont1: i32 = 0,
    cont2: i32 = 0,
    cont4: i32 = 0,
    noisy: i32 = 0,
};

pub const QuietHistory = struct {
    vals: [2][64 * 64][4]i16,

    fn bonus(depth: i32) i16 {
        return @intCast(@min(
            depth * TUNABLES.quiet_bonus_mult + TUNABLES.quiet_bonus_offs,
            TUNABLES.quiet_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * TUNABLES.quiet_penalty_mult + TUNABLES.quiet_penalty_offs,
            TUNABLES.quiet_penalty_max,
        ));
    }

    fn age(self: *QuietHistory) void {
        for (&self.vals) |*stm_arr| {
            for (stm_arr) |*from_to_arr| {
                for (from_to_arr) |*e| {
                    e.* = @intCast(@divTrunc(@as(i32, e.*) * 3, 4));
                }
            }
        }
    }

    inline fn reset(self: *QuietHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(
        self: anytype,
        board: *const Board,
        move: TypedMove,
    ) root.inheritConstness(@TypeOf(self), *i16) {
        return &self.vals[board.stm.toInt()][move.move.fromTo()][move.flags & 3];
    }

    pub inline fn updateRaw(self: *QuietHistory, board: *const Board, move: TypedMove, upd: i32) void {
        gravityUpdate(self.entry(board, move), upd);
    }

    inline fn update(
        self: *QuietHistory,
        board: *const Board,
        move: TypedMove,
        depth: i32,
        is_bonus: bool,
        extra: i32,
    ) void {
        self.updateRaw(board, move, extra + if (is_bonus) bonus(depth) else -penalty(depth));
    }

    inline fn read(self: *const QuietHistory, board: *const Board, move: TypedMove) i16 {
        return self.entry(board, move).*;
    }
};

pub const PawnHistory = struct {
    const HashSize = 8192;
    vals: [HashSize][2][6][64]std.atomic.Value(i16),

    fn bonus(depth: i32) i16 {
        return @intCast(@min(
            depth * TUNABLES.pawn_bonus_mult + TUNABLES.pawn_bonus_offs,
            TUNABLES.pawn_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * TUNABLES.pawn_penalty_mult + TUNABLES.pawn_penalty_offs,
            TUNABLES.pawn_penalty_max,
        ));
    }

    pub inline fn reset(self: *PawnHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(
        self: anytype,
        board: *const Board,
        move: TypedMove,
    ) root.inheritConstness(@TypeOf(self), *std.atomic.Value(i16)) {
        const hash_offs: usize = @intCast(board.pawn_hash % HashSize);
        return &self.vals[hash_offs][board.stm.toInt()][move.tp.toInt()][move.move.to().toInt()];
    }

    pub inline fn updateRaw(self: *PawnHistory, board: *const Board, move: TypedMove, upd: i32) void {
        const e = self.entry(board, move);
        const cur: i32 = e.load(.monotonic);
        e.store(gravityImpl(cur, cur, upd), .monotonic);
    }

    inline fn update(
        self: *PawnHistory,
        board: *const Board,
        move: TypedMove,
        depth: i32,
        is_bonus: bool,
        extra: i32,
    ) void {
        self.updateRaw(board, move, extra + if (is_bonus) bonus(depth) else -penalty(depth));
    }

    inline fn read(self: *const PawnHistory, board: *const Board, move: TypedMove) i16 {
        return self.entry(board, move).load(.monotonic);
    }
};

pub const NoisyHistory = struct {
    vals: [64 * 64][13][4]i16,

    fn bonus(depth: i32) i16 {
        return @intCast(@min(
            depth * TUNABLES.noisy_bonus_mult + TUNABLES.noisy_bonus_offs,
            TUNABLES.noisy_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * TUNABLES.noisy_penalty_mult + TUNABLES.noisy_penalty_offs,
            TUNABLES.noisy_penalty_max,
        ));
    }

    inline fn reset(self: *NoisyHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(
        self: anytype,
        board: *const Board,
        move: TypedMove,
    ) root.inheritConstness(@TypeOf(self), *i16) {
        const captured = board.colouredPieceOn(move.move.to());
        const captured_offs = if (captured) |capt| capt.toInt() else 12;
        return &self.vals[move.move.fromTo()][captured_offs][move.flags & 3];
    }

    pub inline fn updateRaw(self: *NoisyHistory, board: *const Board, move: TypedMove, upd: i32) void {
        gravityUpdate(self.entry(board, move), upd);
    }

    inline fn update(
        self: *NoisyHistory,
        board: *const Board,
        move: TypedMove,
        depth: i32,
        is_bonus: bool,
        extra: i32,
    ) void {
        self.updateRaw(board, move, extra + if (is_bonus) bonus(depth) else -penalty(depth));
    }

    inline fn read(self: *const NoisyHistory, board: *const Board, move: TypedMove) i16 {
        return self.entry(board, move).*;
    }
};

pub const ContHistory = struct {
    pub const ContHistTable = struct {
        vals: [2][6][64]i16,

        inline fn entry(
            self: anytype,
            col: Colour,
            move: TypedMove,
        ) root.inheritConstness(@TypeOf(self), *i16) {
            return &self.vals[col.toInt()][move.tp.toInt()][move.move.to().toInt()];
        }

        pub inline fn updateRaw(
            self: *ContHistTable,
            total_cont: i64,
            col: Colour,
            move: TypedMove,
            upd: i32,
        ) void {
            gravityUpdateCont(self.entry(col, move), total_cont, upd);
        }

        pub inline fn read(
            self: *const ContHistTable,
            col: Colour,
            move: TypedMove,
        ) i16 {
            return self.entry(col, move).*;
        }
    };

    vals: [2][6][64]ContHistTable,

    fn bonus(comptime idx: usize, depth: i32) i16 {
        const mult, const offs, const max = switch (idx) {
            0 => .{
                TUNABLES.cont1_bonus_mult,
                TUNABLES.cont1_bonus_offs,
                TUNABLES.cont1_bonus_max,
            },
            1 => .{
                TUNABLES.cont2_bonus_mult,
                TUNABLES.cont2_bonus_offs,
                TUNABLES.cont2_bonus_max,
            },
            2 => .{
                TUNABLES.cont4_bonus_mult,
                TUNABLES.cont4_bonus_offs,
                TUNABLES.cont4_bonus_max,
            },
            else => unreachable,
        };
        return @intCast(@min(
            depth * mult + offs,
            max,
        ));
    }

    fn penalty(comptime idx: usize, depth: i32) i16 {
        const mult, const offs, const max = switch (idx) {
            0 => .{
                TUNABLES.cont1_penalty_mult,
                TUNABLES.cont1_penalty_offs,
                TUNABLES.cont1_penalty_max,
            },
            1 => .{
                TUNABLES.cont2_penalty_mult,
                TUNABLES.cont2_penalty_offs,
                TUNABLES.cont2_penalty_max,
            },
            2 => .{
                TUNABLES.cont4_penalty_mult,
                TUNABLES.cont4_penalty_offs,
                TUNABLES.cont4_penalty_max,
            },
            else => unreachable,
        };
        return @intCast(@min(
            depth * mult + offs,
            max,
        ));
    }

    inline fn reset(self: *ContHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    pub inline fn table(
        self: anytype,
        col: Colour,
        move: TypedMove,
    ) root.inheritConstness(@TypeOf(self), *ContHistTable) {
        return &self.vals[col.toInt()][move.tp.toInt()][move.move.to().toInt()];
    }
};

fn HashCorrhist(
    comptime field_name: []const u8,
    comptime size: comptime_int,
    comptime options: struct { side: ?Colour = null },
) type {
    return struct {
        const Self = @This();
        vals: [size][2]CorrhistEntry = std.mem.zeroes([size][2]CorrhistEntry),

        inline fn hashIndex(board: *const Board) usize {
            return if (comptime options.side) |side|
                @intCast(@field(board.*, field_name)[side.toInt()] % size)
            else
                @intCast(@field(board.*, field_name) % size);
        }

        inline fn entry(
            self: anytype,
            board: *const Board,
        ) root.inheritConstness(@TypeOf(self), *CorrhistEntry) {
            return &self.vals[hashIndex(board)][board.stm.toInt()];
        }

        inline fn reset(self: *Self) void {
            @memset(std.mem.asBytes(&self.vals), 0);
        }

        inline fn update(self: *Self, board: *const Board, err: i32, weight: i32) void {
            self.entry(board).update(err, weight);
        }

        inline fn read(self: *const Self, board: *const Board) i64 {
            return self.entry(board).read();
        }
    };
}

const MoveCorrhist = struct {
    vals: [64 * 64][4][2]CorrhistEntry = std.mem.zeroes([64 * 64][4][2]CorrhistEntry),

    inline fn entry(
        self: anytype,
        board: *const Board,
        move: TypedMove,
    ) root.inheritConstness(@TypeOf(self), *CorrhistEntry) {
        return &self.vals[move.move.fromTo()][move.flags & 3][board.stm.toInt()];
    }

    inline fn reset(self: *MoveCorrhist) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn update(self: *MoveCorrhist, board: *const Board, move: TypedMove, err: i32, weight: i32) void {
        self.entry(board, move).update(err, weight);
    }

    inline fn read(self: *const MoveCorrhist, board: *const Board, move: TypedMove) i64 {
        return self.entry(board, move).read();
    }
};

pub const CorrectionHistoryTable = struct {
    pawn_corrhist: HashCorrhist("pawn_hash", CORRHIST_SIZE, .{}),
    major_corrhist: HashCorrhist("major_hash", CORRHIST_SIZE, .{}),
    minor_corrhist: HashCorrhist("minor_hash", CORRHIST_SIZE, .{}),
    white_nonpawn_corrhist: HashCorrhist("nonpawn_hash", CORRHIST_SIZE, .{ .side = .white }),
    black_nonpawn_corrhist: HashCorrhist("nonpawn_hash", CORRHIST_SIZE, .{ .side = .black }),
    prev_corrhist: MoveCorrhist,
    followup_corrhist: MoveCorrhist,

    pub fn reset(self: *CorrectionHistoryTable) void {
        self.pawn_corrhist.reset();
        self.major_corrhist.reset();
        self.minor_corrhist.reset();
        self.white_nonpawn_corrhist.reset();
        self.black_nonpawn_corrhist.reset();
        self.prev_corrhist.reset();
        self.followup_corrhist.reset();
    }

    pub fn updateCorrection(
        self: *CorrectionHistoryTable,
        board: *const Board,
        prev: TypedMove,
        followup: TypedMove,
        corrected_static_eval: i32,
        score: i32,
        depth: i32,
    ) void {
        const err = score - corrected_static_eval;
        const weight = @min(depth, 15) + 1;

        self.pawn_corrhist.update(board, err, weight * TUNABLES.corrhist_pawn_update_weight);
        self.major_corrhist.update(board, err, weight * TUNABLES.corrhist_major_update_weight);
        self.minor_corrhist.update(board, err, weight * TUNABLES.corrhist_minor_update_weight);
        self.white_nonpawn_corrhist.update(board, err, weight * TUNABLES.corrhist_nonpawn_update_weight);
        self.black_nonpawn_corrhist.update(board, err, weight * TUNABLES.corrhist_nonpawn_update_weight);
        self.prev_corrhist.update(board, prev, err, weight * TUNABLES.corrhist_prev_update_weight);
        self.followup_corrhist.update(board, followup, err, weight * TUNABLES.corrhist_followup_update_weight);
    }

    pub fn summedCorrectionTerms(
        self: *const CorrectionHistoryTable,
        board: *const Board,
        prev: TypedMove,
        followup: TypedMove,
    ) i64 {
        const pawn_correction = self.pawn_corrhist.read(board);
        const major_correction = self.major_corrhist.read(board);
        const minor_correction = self.minor_corrhist.read(board);
        const white_nonpawn_correction = self.white_nonpawn_corrhist.read(board);
        const black_nonpawn_correction = self.black_nonpawn_corrhist.read(board);
        const prev_correction = self.prev_corrhist.read(board, prev);
        const followup_correction = self.followup_corrhist.read(board, followup);

        return @intCast(@abs(pawn_correction) +
            @abs(white_nonpawn_correction) +
            @abs(black_nonpawn_correction) +
            @abs(prev_correction) +
            @abs(followup_correction) +
            @abs(major_correction) +
            @abs(minor_correction));
    }

    pub fn squaredCorrectionTerms(
        self: *const CorrectionHistoryTable,
        board: *const Board,
        prev: TypedMove,
        followup: TypedMove,
    ) i64 {
        const pawn_correction = self.pawn_corrhist.read(board);
        const major_correction = self.major_corrhist.read(board);
        const minor_correction = self.minor_corrhist.read(board);
        const white_nonpawn_correction = self.white_nonpawn_corrhist.read(board);
        const black_nonpawn_correction = self.black_nonpawn_corrhist.read(board);
        const prev_correction = self.prev_corrhist.read(board, prev);
        const followup_correction = self.followup_corrhist.read(board, followup);

        return pawn_correction * pawn_correction +
            white_nonpawn_correction * white_nonpawn_correction +
            black_nonpawn_correction * black_nonpawn_correction +
            prev_correction * prev_correction +
            followup_correction * followup_correction +
            major_correction * major_correction +
            minor_correction * minor_correction;
    }

    pub fn correct(
        self: *const CorrectionHistoryTable,
        board: *const Board,
        prev: TypedMove,
        followup: TypedMove,
        scaled: i16,
    ) struct { i16, i16 } {
        const pawn_correction = self.pawn_corrhist.read(board);
        const major_correction = self.major_corrhist.read(board);
        const minor_correction = self.minor_corrhist.read(board);
        const white_nonpawn_correction = self.white_nonpawn_corrhist.read(board);
        const black_nonpawn_correction = self.black_nonpawn_corrhist.read(board);
        const nonpawn_correction = white_nonpawn_correction + black_nonpawn_correction;
        const prev_correction = self.prev_corrhist.read(board, prev);
        const followup_correction = self.followup_corrhist.read(board, followup);

        const correction = (TUNABLES.corrhist_pawn_weight * pawn_correction +
            TUNABLES.corrhist_nonpawn_weight * nonpawn_correction +
            TUNABLES.corrhist_prev_weight * prev_correction +
            TUNABLES.corrhist_followup_weight * followup_correction +
            TUNABLES.corrhist_major_weight * major_correction +
            TUNABLES.corrhist_minor_weight * minor_correction) >> 18;

        return .{ @intCast(correction), evaluation.clampScore(scaled + correction) };
    }
};

pub const HistoryTable = struct {
    quiet: QuietHistory,
    pawn: *PawnHistory,
    noisy: NoisyHistory,
    countermove: ContHistory,

    pub fn reset(self: *HistoryTable) void {
        self.quiet.reset();
        self.noisy.reset();
        self.countermove.reset();
    }

    pub fn age(self: *HistoryTable) void {
        self.quiet.age();
    }

    pub fn getConthistTables(
        self: *HistoryTable,
        col: Colour,
        moves: ConthistMoves,
    ) ConthistTables {
        var res: ConthistTables = undefined;

        for (0..NUM_CONTHISTS) |i| {
            res[i] = self.countermove.table(col, moves[i]);
        }

        return res;
    }

    pub inline fn readMoveTerms(
        self: *const HistoryTable,
        board: *const Board,
        typed: TypedMove,
        tables: ConthistTables,
        is_quiet: bool,
    ) MoveHistoryTerms {
        var terms: MoveHistoryTerms = .{};
        if (!is_quiet) {
            terms.noisy = self.noisy.read(board, typed);
            return terms;
        }

        terms.quiet = self.quiet.read(board, typed);
        terms.pawn = self.pawn.read(board, typed);

        const cont_values = [NUM_CONTHISTS]*i32{
            &terms.cont1,
            &terms.cont2,
            &terms.cont4,
        };
        inline for (CONTHIST_OFFSETS, 0.., tables) |offs, i, table| {
            const stm = if (offs % 2 == 0) board.stm.flipped() else board.stm;
            cont_values[i].* = table.read(stm, typed);
        }

        return terms;
    }

    pub fn updateCont(
        _: *HistoryTable,
        board: *const Board,
        typed: TypedMove,
        tables: ConthistTables,
        depth: i32,
        is_bonus: bool,
        extra: i32,
    ) void {
        var cont: i64 = 0;
        const stm = board.stm;
        inline for (CONTHIST_OFFSETS, tables) |offs, table| {
            const cstm = if (offs % 2 == 0) stm.flipped() else stm;
            cont += table.read(cstm, typed);
        }
        inline for (CONTHIST_OFFSETS, 0.., tables) |offs, i, table| {
            const cstm = if (offs % 2 == 0) stm.flipped() else stm;
            const upd = extra + if (is_bonus) ContHistory.bonus(i, depth) else -ContHistory.penalty(i, depth);
            table.updateRaw(cont, cstm, typed, upd);
        }
    }

    pub fn updateQuiet(
        self: *HistoryTable,
        board: *const Board,
        typed: TypedMove,
        depth: i32,
        is_bonus: bool,
        extra: i32,
    ) void {
        self.quiet.update(board, typed, depth, is_bonus, extra);
        self.pawn.update(board, typed, depth, is_bonus, extra);
    }

    pub fn readNoisy(self: *const HistoryTable, board: *const Board, typed: TypedMove) i32 {
        var res: i32 = 0;
        res += self.noisy.read(board, typed);

        return res;
    }

    pub fn updateNoisy(
        self: *HistoryTable,
        board: *const Board,
        typed: TypedMove,
        depth: i32,
        is_bonus: bool,
        extra: i32,
    ) void {
        self.noisy.update(board, typed, depth, is_bonus, extra);
    }

    pub fn scaleEval(
        board: *const Board,
        eval: i16,
    ) i16 {
        comptime var divisor = 1;
        const material = board.materialScale();
        const material_scaled = @as(i64, eval) * (TUNABLES.material_scaling_base + material);
        divisor *= 16384;
        const fifty_move_rule_scaled = material_scaled * (200 - board.halfmove);
        divisor *= 200;

        return @intCast(@divTrunc(fifty_move_rule_scaled, divisor));
    }
};

inline fn gravityImpl(current_value: i32, total: i64, adjustment: anytype) i16 {
    const clamped: i16 = @intCast(std.math.clamp(adjustment, -MAX_HISTORY, MAX_HISTORY));
    const magnitude: i32 = @abs(clamped);
    return @intCast(std.math.clamp(
        current_value + clamped - ((magnitude * total) >> SHIFT),
        -MAX_HISTORY,
        MAX_HISTORY,
    ));
}

fn gravityUpdateCont(entry: *i16, total: i64, adjustment: anytype) void {
    entry.* = gravityImpl(entry.*, total, adjustment);
}

fn gravityUpdate(entry: *i16, adjustment: anytype) void {
    entry.* = gravityImpl(entry.*, entry.*, adjustment);
}

const CorrhistEntry = struct {
    val: std.atomic.Value(i16) = .init(0),

    fn update(self: *CorrhistEntry, err: i32, weight: i32) void {
        const adjustment = std.math.clamp(@divTrunc(err * weight, 1024), -16000, 16000);
        const current_value: i32 = self.val.load(.monotonic);
        self.val.store(gravityImpl(current_value, current_value, adjustment), .monotonic);
    }

    fn read(self: *const CorrhistEntry) i64 {
        return self.val.load(.monotonic);
    }
};
