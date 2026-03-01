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
const tunables = root.tunable_constants;

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

    pub fn fromBoard(board: *const Board, move_: Move) TypedMove {
        std.debug.assert(!move_.isNull());
        return .{
            .move = move_,
            .tp = board.pieceOn(move_.from()).?,
        };
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

    pub fn fromToThreatIndex(self: *const TypedMove) usize {
        return 4 * self.move.fromTo() + (self.flags & (FROM_THREATENED | TO_THREATENED));
    }

    pub fn typeToIndex(self: *const TypedMove, side: usize) usize {
        return side * 6 * 64 + self.tp.toInt() * 64 + self.move.to().toInt();
    }
};

pub const MAX_HISTORY: i16 = 1 << 14;
const CORRHIST_SIZE = 16384;
const MAX_CORRHIST = 256 * 32;
const SHIFT = @ctz(MAX_HISTORY);
pub const CONTHIST_OFFSETS = [_]comptime_int{
    0,
    1,
    3,
};
pub const NUM_CONTHISTS = CONTHIST_OFFSETS.len;
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
    vals: [2 * 64 * 64 * 2 * 2]i16,

    fn bonus(depth: i32) i16 {
        return @intCast(@min(
            depth * tunables.quiet_bonus_mult + tunables.quiet_bonus_offs,
            tunables.quiet_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * tunables.quiet_penalty_mult + tunables.quiet_penalty_offs,
            tunables.quiet_penalty_max,
        ));
    }

    fn age(self: *QuietHistory) void {
        for (&self.vals) |*e| {
            e.* = @intCast(@divTrunc(@as(i32, e.*) * 3, 4));
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
        const col_offs: usize = board.stm.toInt();
        const from_to_offs: usize = move.move.fromTo();
        const threats = (&board.threats)[board.stm.flipped().toInt()];
        const from_threatened_offs: usize = @intFromBool(threats & move.move.from().toBitboard() != 0);
        const to_threatened_offs: usize = @intFromBool(threats & move.move.to().toBitboard() != 0);

        return &(&self.vals)[col_offs * 64 * 64 * 2 * 2 + from_to_offs * 2 * 2 + from_threatened_offs * 2 + to_threatened_offs];
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
    const HashSize = 2048;
    vals: [HashSize * 2 * 6 * 64]i16,

    fn bonus(depth: i32) i16 {
        return @intCast(@min(
            depth * tunables.pawn_bonus_mult + tunables.pawn_bonus_offs,
            tunables.pawn_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * tunables.pawn_penalty_mult + tunables.pawn_penalty_offs,
            tunables.pawn_penalty_max,
        ));
    }

    inline fn reset(self: *PawnHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(
        self: anytype,
        board: *const Board,
        move: TypedMove,
    ) root.inheritConstness(@TypeOf(self), *i16) {
        const col_offs: usize = board.stm.toInt();
        const tp_offs: usize = move.tp.toInt();
        const to_offs: usize = move.move.to().toInt();
        const hash_offs: usize = @intCast(board.pawn_hash % HashSize);
        return &(&self.vals)[hash_offs * 2 * 6 * 64 + col_offs * 6 * 64 + tp_offs * 64 + to_offs];
    }

    pub inline fn updateRaw(self: *PawnHistory, board: *const Board, move: TypedMove, upd: i32) void {
        gravityUpdate(self.entry(board, move), upd);
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
        return self.entry(board, move).*;
    }
};

pub const NoisyHistory = struct {
    vals: [64 * 64 * 13 * 2 * 2]i16,

    fn bonus(depth: i32) i16 {
        return @intCast(@min(
            depth * tunables.noisy_bonus_mult + tunables.noisy_bonus_offs,
            tunables.noisy_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * tunables.noisy_penalty_mult + tunables.noisy_penalty_offs,
            tunables.noisy_penalty_max,
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
        const from_to_offs: usize = move.move.fromTo();
        const captured = board.colouredPieceOn(move.move.to());
        const captured_offs = if (captured) |capt| capt.toInt() else 12;
        const threats = (&board.threats)[board.stm.flipped().toInt()];
        const from_threatened_offs: usize = @intFromBool(threats & move.move.from().toBitboard() != 0);
        const to_threatened_offs: usize = @intFromBool(threats & move.move.to().toBitboard() != 0);
        return &(&self.vals)[from_to_offs * 13 * 2 * 2 + captured_offs * 2 * 2 + from_threatened_offs * 2 + to_threatened_offs];
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
        vals: [2 * 6 * 64]i16,

        inline fn entry(
            self: anytype,
            col: Colour,
            move: TypedMove,
        ) root.inheritConstness(@TypeOf(self), *i16) {
            const col_offs: usize = col.toInt();
            const move_offs: usize = @as(usize, move.tp.toInt()) * 64 + move.move.to().toInt();
            return &(&self.vals)[col_offs * 6 * 64 + move_offs];
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

    vals: [2 * 6 * 64]ContHistTable,

    fn bonus(comptime idx: usize, depth: i32) i16 {
        const mult, const offs, const max = switch (idx) {
            0 => .{
                tunables.cont1_bonus_mult,
                tunables.cont1_bonus_offs,
                tunables.cont1_bonus_max,
            },
            1 => .{
                tunables.cont2_bonus_mult,
                tunables.cont2_bonus_offs,
                tunables.cont2_bonus_max,
            },
            2 => .{
                tunables.cont4_bonus_mult,
                tunables.cont4_bonus_offs,
                tunables.cont4_bonus_max,
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
                tunables.cont1_penalty_mult,
                tunables.cont1_penalty_offs,
                tunables.cont1_penalty_max,
            },
            1 => .{
                tunables.cont2_penalty_mult,
                tunables.cont2_penalty_offs,
                tunables.cont2_penalty_max,
            },
            2 => .{
                tunables.cont4_penalty_mult,
                tunables.cont4_penalty_offs,
                tunables.cont4_penalty_max,
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
        const col_offs: usize = col.toInt();
        const move_offs: usize = @as(usize, move.tp.toInt()) * 64 + move.move.to().toInt();
        return &(&self.vals)[col_offs * 6 * 64 + move_offs];
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
            return &(&self.vals)[hashIndex(board)][board.stm.toInt()];
        }

        inline fn reset(self: *Self) void {
            @memset(std.mem.asBytes(&self.vals), 0);
        }

        inline fn update(self: *Self, board: *const Board, err: i32, weight: i32) void {
            self.entry(board).update(err, weight);
        }

        inline fn read(self: *const Self, board: *const Board) i64 {
            return self.entry(board).val;
        }
    };
}

const MoveCorrhist = struct {
    vals: [64 * 64 * 2 * 2][2]CorrhistEntry = std.mem.zeroes([64 * 64 * 2 * 2][2]CorrhistEntry),

    inline fn entry(
        self: anytype,
        board: *const Board,
        move: TypedMove,
    ) root.inheritConstness(@TypeOf(self), *CorrhistEntry) {
        return &(&self.vals)[move.fromToThreatIndex()][board.stm.toInt()];
    }

    inline fn reset(self: *MoveCorrhist) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn update(self: *MoveCorrhist, board: *const Board, move: TypedMove, err: i32, weight: i32) void {
        self.entry(board, move).update(err, weight);
    }

    inline fn read(self: *const MoveCorrhist, board: *const Board, move: TypedMove) i64 {
        return self.entry(board, move).val;
    }
};

pub const HistoryTable = struct {
    quiet: QuietHistory,
    pawn: PawnHistory,
    noisy: NoisyHistory,
    countermove: ContHistory,
    pawn_corrhist: HashCorrhist("pawn_hash", CORRHIST_SIZE, .{}),
    major_corrhist: HashCorrhist("major_hash", CORRHIST_SIZE, .{}),
    minor_corrhist: HashCorrhist("minor_hash", CORRHIST_SIZE, .{}),
    white_nonpawn_corrhist: HashCorrhist("nonpawn_hash", CORRHIST_SIZE, .{ .side = .white }),
    black_nonpawn_corrhist: HashCorrhist("nonpawn_hash", CORRHIST_SIZE, .{ .side = .black }),
    prev_corrhist: MoveCorrhist,
    followup_corrhist: MoveCorrhist,

    pub fn reset(self: *HistoryTable) void {
        self.quiet.reset();
        self.pawn.reset();
        self.noisy.reset();
        self.countermove.reset();
        self.pawn_corrhist.reset();
        self.major_corrhist.reset();
        self.minor_corrhist.reset();
        self.white_nonpawn_corrhist.reset();
        self.black_nonpawn_corrhist.reset();
        self.prev_corrhist.reset();
        self.followup_corrhist.reset();
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
        move: Move,
        tables: ConthistTables,
        is_quiet: bool,
    ) MoveHistoryTerms {
        const typed = TypedMove.fromBoard(board, move);
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
        move: Move,
        tables: ConthistTables,
        depth: i32,
        is_bonus: bool,
        extra: i32,
    ) void {
        const typed = TypedMove.fromBoard(board, move);
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
        move: Move,
        depth: i32,
        is_bonus: bool,
        extra: i32,
    ) void {
        const typed = TypedMove.fromBoard(board, move);
        self.quiet.update(board, typed, depth, is_bonus, extra);
        self.pawn.update(board, typed, depth, is_bonus, extra);
    }

    pub fn readNoisy(self: *const HistoryTable, board: *const Board, move: Move) i32 {
        const typed = TypedMove.fromBoard(board, move);
        var res: i32 = 0;
        res += self.noisy.read(board, typed);

        return res;
    }

    pub fn updateNoisy(
        self: *HistoryTable,
        board: *const Board,
        move: Move,
        depth: i32,
        is_bonus: bool,
        extra: i32,
    ) void {
        const typed = TypedMove.fromBoard(board, move);
        self.noisy.update(board, typed, depth, is_bonus, extra);
    }

    pub fn updateCorrection(
        self: *HistoryTable,
        board: *const Board,
        prev: TypedMove,
        followup: TypedMove,
        corrected_static_eval: i32,
        score: i32,
        depth: i32,
    ) void {
        const err = score - corrected_static_eval;
        const weight = @min(depth, 15) + 1;

        self.pawn_corrhist.update(board, err, weight * tunables.corrhist_pawn_update_weight);
        self.major_corrhist.update(board, err, weight * tunables.corrhist_major_update_weight);
        self.minor_corrhist.update(board, err, weight * tunables.corrhist_minor_update_weight);
        self.white_nonpawn_corrhist.update(board, err, weight * tunables.corrhist_nonpawn_update_weight);
        self.black_nonpawn_corrhist.update(board, err, weight * tunables.corrhist_nonpawn_update_weight);
        self.prev_corrhist.update(board, prev, err, weight * tunables.corrhist_prev_update_weight);
        self.followup_corrhist.update(board, followup, err, weight * tunables.corrhist_followup_update_weight);
    }

    pub fn summedCorrectionTerms(
        self: *const HistoryTable,
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
        self: *const HistoryTable,
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
        self: *const HistoryTable,
        board: *const Board,
        prev: TypedMove,
        followup: TypedMove,
        static_eval: i16,
        optimism: i32,
    ) struct { i16, i16 } {
        const pawn_correction = self.pawn_corrhist.read(board);
        const major_correction = self.major_corrhist.read(board);
        const minor_correction = self.minor_corrhist.read(board);
        const white_nonpawn_correction = self.white_nonpawn_corrhist.read(board);
        const black_nonpawn_correction = self.black_nonpawn_corrhist.read(board);
        const nonpawn_correction = white_nonpawn_correction + black_nonpawn_correction;
        const prev_correction = self.prev_corrhist.read(board, prev);
        const followup_correction = self.followup_corrhist.read(board, followup);

        const correction = (tunables.corrhist_pawn_weight * pawn_correction +
            tunables.corrhist_nonpawn_weight * nonpawn_correction +
            tunables.corrhist_prev_weight * prev_correction +
            tunables.corrhist_followup_weight * followup_correction +
            tunables.corrhist_major_weight * major_correction +
            tunables.corrhist_minor_weight * minor_correction) >> 18;

        const scaled = scaleEval(board, static_eval, optimism);

        return .{ @intCast(correction), evaluation.clampScore(scaled + correction) };
    }

    pub fn scaleEval(board: *const Board, eval: i16, optimism: i64) i16 {
        comptime var divisor = 1;
        const material = board.materialScale();
        const material_scaled = @as(i64, eval) * (tunables.material_scaling_base + material);
        divisor *= 16384;
        const optimism_scaled = material_scaled * 64 + optimism * (66560 + 51 * material);
        divisor *= 64;
        const fifty_move_rule_scaled = optimism_scaled * (200 - board.halfmove);
        divisor *= 200;

        return @intCast(@divTrunc(fifty_move_rule_scaled, divisor));
    }
};

fn gravityUpdateCont(entry: *i16, total: i64, adjustment: anytype) void {
    const clamped: i16 = @intCast(std.math.clamp(adjustment, -MAX_HISTORY, MAX_HISTORY));
    const magnitude: i32 = @abs(clamped);
    const current_value: i32 = entry.*;
    entry.* = @intCast(std.math.clamp(current_value + clamped - ((magnitude * total) >> SHIFT), -MAX_HISTORY, MAX_HISTORY));
}

fn gravityUpdate(entry: *i16, adjustment: anytype) void {
    const clamped: i16 = @intCast(std.math.clamp(adjustment, -MAX_HISTORY, MAX_HISTORY));
    const magnitude: i32 = @abs(clamped);
    const current_value: i32 = entry.*;
    entry.* = @intCast(current_value + clamped - ((magnitude * current_value) >> SHIFT));
}

const CorrhistEntry = struct {
    val: i16 = 0,

    fn update(self: *CorrhistEntry, err: i32, weight: i32) void {
        gravityUpdate(&self.val, std.math.clamp(@divTrunc(err * weight, 1024), -16000, 16000));
    }
};
