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
const tunable_constants = root.tunable_constants;

pub const TypedMove = struct {
    move: Move,
    tp: PieceType,

    pub fn init() TypedMove {
        return .{ .move = Move.init(), .tp = .pawn };
    }

    pub fn fromBoard(board: *const Board, move_: Move) TypedMove {
        if (move_.isNull()) {
            return .{
                .move = move_,
                .tp = .pawn,
            };
        }
        return .{
            .move = move_,
            .tp = (&board.mailbox)[move_.from().toInt()].toColouredPieceType().toPieceType(),
        };
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

pub const QuietHistory = struct {
    vals: [2 * 64 * 64 * 2 * 2]i16,

    fn bonus(depth: i32) i16 {
        return @intCast(@min(
            depth * tunable_constants.quiet_history_bonus_mult + tunable_constants.quiet_history_bonus_offs,
            tunable_constants.quiet_history_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * tunable_constants.quiet_history_penalty_mult + tunable_constants.quiet_history_penalty_offs,
            tunable_constants.quiet_history_penalty_max,
        ));
    }

    inline fn reset(self: *QuietHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(self: anytype, board: *const Board, move: TypedMove) root.inheritConstness(@TypeOf(self), *i16) {
        const col_offs: usize = board.stm.toInt();
        const from_offs: usize = move.move.from().toInt();
        const to_offs: usize = move.move.to().toInt();
        const threats = board.threats[board.stm.flipped().toInt()];
        const from_threatened_offs: usize = @intFromBool(threats & move.move.from().toBitboard() != 0);
        const to_threatened_offs: usize = @intFromBool(threats & move.move.to().toBitboard() != 0);

        return &(&self.vals)[col_offs * 64 * 64 * 2 * 2 + from_offs * 64 * 2 * 2 + to_offs * 2 * 2 + from_threatened_offs * 2 + to_threatened_offs];
    }

    pub inline fn updateRaw(self: *QuietHistory, board: *const Board, move: TypedMove, upd: i32) void {
        gravityUpdate(self.entry(board, move), upd);
    }

    inline fn update(self: *QuietHistory, board: *const Board, move: TypedMove, depth: i32, is_bonus: bool) void {
        self.updateRaw(board, move, if (is_bonus) bonus(depth) else -penalty(depth));
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
            depth * tunable_constants.pawn_history_bonus_mult + tunable_constants.pawn_history_bonus_offs,
            tunable_constants.pawn_history_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * tunable_constants.pawn_history_penalty_mult + tunable_constants.pawn_history_penalty_offs,
            tunable_constants.pawn_history_penalty_max,
        ));
    }

    inline fn reset(self: *PawnHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(self: anytype, board: *const Board, move: TypedMove) root.inheritConstness(@TypeOf(self), *i16) {
        const col_offs: usize = board.stm.toInt();
        const tp_offs: usize = move.tp.toInt();
        const to_offs: usize = move.move.to().toInt();
        const hash_offs: usize = @intCast(board.pawn_hash % HashSize);
        return &(&self.vals)[hash_offs * 2 * 6 * 64 + col_offs * 6 * 64 + tp_offs * 64 + to_offs];
    }

    pub inline fn updateRaw(self: *PawnHistory, board: *const Board, move: TypedMove, upd: i32) void {
        gravityUpdate(self.entry(board, move), upd);
    }

    inline fn update(self: *PawnHistory, board: *const Board, move: TypedMove, depth: i32, is_bonus: bool) void {
        self.updateRaw(board, move, if (is_bonus) bonus(depth) else -penalty(depth));
    }

    inline fn read(self: *const PawnHistory, board: *const Board, move: TypedMove) i16 {
        return self.entry(board, move).*;
    }
};

pub const NoisyHistory = struct {
    vals: [64 * 64 * 13 * 2 * 2]i16,

    fn bonus(depth: i32) i16 {
        return @intCast(@min(
            depth * tunable_constants.noisy_history_bonus_mult + tunable_constants.noisy_history_bonus_offs,
            tunable_constants.noisy_history_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * tunable_constants.noisy_history_penalty_mult + tunable_constants.noisy_history_penalty_offs,
            tunable_constants.noisy_history_penalty_max,
        ));
    }

    inline fn reset(self: *NoisyHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(self: anytype, board: *const Board, move: TypedMove) root.inheritConstness(@TypeOf(self), *i16) {
        const from_offs: usize = move.move.from().toInt();
        const to_offs: usize = move.move.to().toInt();
        const captured = (&board.mailbox)[to_offs];
        const captured_offs = if (captured.opt()) |capt| capt.toInt() else 12;
        const threats = board.threats[board.stm.flipped().toInt()];
        const from_threatened_offs: usize = @intFromBool(threats & move.move.from().toBitboard() != 0);
        const to_threatened_offs: usize = @intFromBool(threats & move.move.to().toBitboard() != 0);
        return &(&self.vals)[from_offs * 64 * 13 * 2 * 2 + to_offs * 13 * 2 * 2 + captured_offs * 2 * 2 + from_threatened_offs * 2 + to_threatened_offs];
    }

    pub inline fn updateRaw(self: *NoisyHistory, board: *const Board, move: TypedMove, upd: i32) void {
        gravityUpdate(self.entry(board, move), upd);
    }

    inline fn update(self: *NoisyHistory, board: *const Board, move: TypedMove, depth: i32, is_bonus: bool) void {
        self.updateRaw(board, move, if (is_bonus) bonus(depth) else -penalty(depth));
    }

    inline fn read(self: *const NoisyHistory, board: *const Board, move: TypedMove) i16 {
        return self.entry(board, move).*;
    }
};

pub const ContHistory = struct {
    vals: [2 * 6 * 64 * 2 * 6 * 64]i16,

    fn bonus(depth: i32) i16 {
        return @intCast(@min(
            depth * tunable_constants.cont_history_bonus_mult + tunable_constants.cont_history_bonus_offs,
            tunable_constants.cont_history_bonus_max,
        ));
    }

    fn penalty(depth: i32) i16 {
        return @intCast(@min(
            depth * tunable_constants.cont_history_penalty_mult + tunable_constants.cont_history_penalty_offs,
            tunable_constants.cont_history_penalty_max,
        ));
    }

    inline fn reset(self: *ContHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(self: anytype, col: Colour, move: TypedMove, prev_col: Colour, prev: TypedMove) root.inheritConstness(@TypeOf(self), *i16) {
        const col_offs: usize = col.toInt();
        const move_offs: usize = @as(usize, move.tp.toInt()) * 64 + move.move.to().toInt();
        const prev_col_offs: usize = prev_col.toInt();
        const prev_offs: usize = @as(usize, prev.tp.toInt()) * 64 + prev.move.to().toInt();
        return &(&self.vals)[col_offs * 6 * 64 * 2 * 6 * 64 + prev_offs * 2 * 6 * 64 + move_offs * 2 + prev_col_offs];
    }

    pub inline fn updateRaw(self: *ContHistory, col: Colour, move: TypedMove, prev_col: Colour, prev: TypedMove, upd: i32) void {
        gravityUpdate(self.entry(col, move, prev_col, prev), upd);
    }

    inline fn update(self: *ContHistory, col: Colour, move: TypedMove, prev_col: Colour, prev: TypedMove, depth: i32, is_bonus: bool) void {
        self.updateRaw(col, move, prev_col, prev, if (is_bonus) bonus(depth) else -penalty(depth));
    }

    inline fn read(self: *const ContHistory, col: Colour, move: TypedMove, prev_col: Colour, prev: TypedMove) i16 {
        return self.entry(col, move, prev_col, prev).*;
    }
};

pub const HistoryTable = struct {
    quiet: QuietHistory,
    pawn: PawnHistory,
    noisy: NoisyHistory,
    countermove: ContHistory,
    pawn_corrhist: [16384][2][2]CorrhistEntry,
    major_corrhist: [16384][2]CorrhistEntry,
    minor_corrhist: [16384][2]CorrhistEntry,
    nonpawn_corrhist: [16384][2][2]CorrhistEntry,
    countermove_corrhist: [6 * 64][2]CorrhistEntry,

    pub fn reset(self: *HistoryTable) void {
        self.quiet.reset();
        self.pawn.reset();
        self.noisy.reset();
        self.countermove.reset();
        @memset(std.mem.asBytes(&self.pawn_corrhist), 0);
        @memset(std.mem.asBytes(&self.major_corrhist), 0);
        @memset(std.mem.asBytes(&self.minor_corrhist), 0);
        @memset(std.mem.asBytes(&self.nonpawn_corrhist), 0);
        @memset(std.mem.asBytes(&self.countermove_corrhist), 0);
    }

    pub inline fn readQuietPruning(
        self: *const HistoryTable,
        board: *const Board,
        move: Move,
        moves: ConthistMoves,
    ) i32 {
        const typed = TypedMove.fromBoard(board, move);
        var res: i32 = 0;
        res += tunable_constants.quiet_pruning_weight * self.quiet.read(board, typed);
        res += tunable_constants.pawn_pruning_weight * self.pawn.read(board, typed);
        const weights = [NUM_CONTHISTS]i32{
            tunable_constants.cont1_pruning_weight,
            tunable_constants.cont2_pruning_weight,
            tunable_constants.cont4_pruning_weight,
        };
        inline for (CONTHIST_OFFSETS, 0..) |offs, i| {
            const stm = if (offs % 2 == 0) board.stm.flipped() else board.stm;
            res += weights[i] * self.countermove.read(board.stm, typed, stm, moves[i]);
        }

        return @divTrunc(res, 1024);
    }

    pub inline fn readQuietOrdering(
        self: *const HistoryTable,
        board: *const Board,
        move: Move,
        moves: ConthistMoves,
    ) i32 {
        const typed = TypedMove.fromBoard(board, move);
        var res: i32 = 0;
        res += tunable_constants.quiet_ordering_weight * self.quiet.read(board, typed);
        res += tunable_constants.pawn_ordering_weight * self.pawn.read(board, typed);
        const weights = [NUM_CONTHISTS]i32{
            tunable_constants.cont1_ordering_weight,
            tunable_constants.cont2_ordering_weight,
            tunable_constants.cont4_ordering_weight,
        };
        inline for (CONTHIST_OFFSETS, 0..) |offs, i| {
            const stm = if (offs % 2 == 0) board.stm.flipped() else board.stm;
            res += weights[i] * self.countermove.read(board.stm, typed, stm, moves[i]);
        }

        return @divTrunc(res, 1024);
    }

    pub fn updateQuiet(
        self: *HistoryTable,
        board: *const Board,
        move: Move,
        moves: ConthistMoves,
        depth: i32,
        is_bonus: bool,
    ) void {
        const typed = TypedMove.fromBoard(board, move);
        self.quiet.update(board, typed, depth, is_bonus);
        self.pawn.update(board, typed, depth, is_bonus);
        inline for (CONTHIST_OFFSETS, 0..) |offs, i| {
            const stm = if (offs % 2 == 0) board.stm.flipped() else board.stm;
            self.countermove.update(board.stm, typed, stm, moves[i], depth, is_bonus);
        }
    }

    pub fn readNoisy(self: *const HistoryTable, board: *const Board, move: Move) i32 {
        const typed = TypedMove.fromBoard(board, move);
        var res: i32 = 0;
        res += self.noisy.read(board, typed);

        return res;
    }

    pub fn updateNoisy(self: *HistoryTable, board: *const Board, move: Move, depth: i32, is_bonus: bool) void {
        const typed = TypedMove.fromBoard(board, move);
        self.noisy.update(board, typed, depth, is_bonus);
    }

    pub fn updateCorrection(self: *HistoryTable, board: *const Board, prev: TypedMove, corrected_static_eval: i32, score: i32, depth: i32) void {
        const err = score - corrected_static_eval;
        const weight = @min(depth, 15) + 1;

        const opponent_has_easy_capture = board.occupancyFor(board.stm) & board.lesser_threats[board.stm.flipped().toInt()] != 0;
        self.pawn_corrhist[board.pawn_hash % CORRHIST_SIZE][@intFromBool(opponent_has_easy_capture)][board.stm.toInt()].update(err, weight);
        self.major_corrhist[board.major_hash % CORRHIST_SIZE][board.stm.toInt()].update(err, weight);
        self.minor_corrhist[board.minor_hash % CORRHIST_SIZE][board.stm.toInt()].update(err, weight);
        self.nonpawn_corrhist[board.nonpawn_hash[0] % CORRHIST_SIZE][board.stm.toInt()][0].update(err, weight);
        self.nonpawn_corrhist[board.nonpawn_hash[1] % CORRHIST_SIZE][board.stm.toInt()][1].update(err, weight);
        self.countermove_corrhist[@as(usize, prev.tp.toInt()) * 64 + prev.move.to().toInt()][board.stm.toInt()].update(err, weight);
    }

    pub fn squaredCorrectionTerms(self: *const HistoryTable, board: *const Board, prev: TypedMove) i64 {
        const opponent_has_easy_capture = board.occupancyFor(board.stm) & board.lesser_threats[board.stm.flipped().toInt()] != 0;
        const pawn_correction: i64 = (&self.pawn_corrhist)[board.pawn_hash % CORRHIST_SIZE][@intFromBool(opponent_has_easy_capture)][board.stm.toInt()].val;

        const major_correction: i64 = (&self.major_corrhist)[board.major_hash % CORRHIST_SIZE][board.stm.toInt()].val;

        const minor_correction: i64 = (&self.minor_corrhist)[board.minor_hash % CORRHIST_SIZE][board.stm.toInt()].val;

        const white_nonpawn_correction: i64 = (&self.nonpawn_corrhist)[board.nonpawn_hash[0] % CORRHIST_SIZE][board.stm.toInt()][0].val;
        const black_nonpawn_correction: i64 = (&self.nonpawn_corrhist)[board.nonpawn_hash[1] % CORRHIST_SIZE][board.stm.toInt()][1].val;

        const countermove_correction: i64 = (&self.countermove_corrhist)[@as(usize, prev.tp.toInt()) * 64 + prev.move.to().toInt()][board.stm.toInt()].val;

        return pawn_correction * pawn_correction +
            white_nonpawn_correction * white_nonpawn_correction +
            black_nonpawn_correction * black_nonpawn_correction +
            countermove_correction * countermove_correction +
            major_correction * major_correction +
            minor_correction * minor_correction;
    }

    pub fn correct(self: *const HistoryTable, board: *const Board, prev: TypedMove, static_eval: i16) i16 {
        const opponent_has_easy_capture = board.occupancyFor(board.stm) & board.lesser_threats[board.stm.flipped().toInt()] != 0;
        const pawn_correction: i64 = (&self.pawn_corrhist)[board.pawn_hash % CORRHIST_SIZE][@intFromBool(opponent_has_easy_capture)][board.stm.toInt()].val;

        const major_correction: i64 = (&self.major_corrhist)[board.major_hash % CORRHIST_SIZE][board.stm.toInt()].val;

        const minor_correction: i64 = (&self.minor_corrhist)[board.minor_hash % CORRHIST_SIZE][board.stm.toInt()].val;

        const white_nonpawn_correction: i64 = (&self.nonpawn_corrhist)[board.nonpawn_hash[0] % CORRHIST_SIZE][board.stm.toInt()][0].val;
        const black_nonpawn_correction: i64 = (&self.nonpawn_corrhist)[board.nonpawn_hash[1] % CORRHIST_SIZE][board.stm.toInt()][1].val;
        const nonpawn_correction = white_nonpawn_correction + black_nonpawn_correction;

        const countermove_correction: i64 = (&self.countermove_corrhist)[@as(usize, prev.tp.toInt()) * 64 + prev.move.to().toInt()][board.stm.toInt()].val;

        const correction = (tunable_constants.corrhist_pawn_weight * pawn_correction +
            tunable_constants.corrhist_nonpawn_weight * nonpawn_correction +
            tunable_constants.corrhist_countermove_weight * countermove_correction +
            tunable_constants.corrhist_major_weight * major_correction +
            tunable_constants.corrhist_minor_weight * minor_correction) >> 18;

        const scaled = scaleEval(board, static_eval);

        return evaluation.clampScore(scaled + correction);
    }

    pub fn scaleEval(board: *const Board, eval: i16) i16 {
        comptime var divisor = 1;
        const fifty_move_rule_scaled = @as(i64, eval) * (200 - board.halfmove);
        divisor *= 200;
        @setEvalBranchQuota(1 << 30);
        const vals: [6]i16 = if (root.tuning.do_tuning) .{
            @intCast(tunable_constants.material_scaling_pawn),
            @intCast(tunable_constants.material_scaling_knight),
            @intCast(tunable_constants.material_scaling_bishop),
            @intCast(tunable_constants.material_scaling_rook),
            @intCast(tunable_constants.material_scaling_queen),
            0,
        } else comptime .{
            tunable_constants.material_scaling_pawn,
            tunable_constants.material_scaling_knight,
            tunable_constants.material_scaling_bishop,
            tunable_constants.material_scaling_rook,
            tunable_constants.material_scaling_queen,
            0,
        };

        const material_scaled = fifty_move_rule_scaled * (tunable_constants.material_scaling_base + board.sumPieces(vals));
        divisor *= 16384;

        return @intCast(@divTrunc(material_scaled, divisor));
    }
};

fn gravityUpdate(entry: *i16, adjustment: anytype) void {
    const clamped: i16 = @intCast(std.math.clamp(adjustment, -MAX_HISTORY, MAX_HISTORY));
    const magnitude: i32 = @abs(clamped);
    entry.* += @intCast(clamped - ((magnitude * entry.*) >> SHIFT));
}

const CorrhistEntry = struct {
    val: i16 = 0,

    fn update(self: *CorrhistEntry, err: i32, weight: i32) void {
        gravityUpdate(&self.val, std.math.clamp(err * weight << 1, -16000, 16000));
    }
};
