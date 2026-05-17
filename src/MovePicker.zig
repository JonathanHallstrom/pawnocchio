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
const simd = root.simd;

const Move = root.Move;
const Board = root.Board;
const ScoredMove = root.ScoredMove;
const MoveReceiver = movegen.MoveListReceiver;
const movegen = root.movegen;
const SEE = root.SEE;
const PieceType = root.PieceType;
const Colour = root.Colour;
const history = root.history;
const TypedMove = history.TypedMove;
const Historytable = history.HistoryTable;

const MovePicker = @This();
const tuning = root.tuning;

movelist: *MoveReceiver,
scores: [*]i32,
first: usize,
last: usize,
stage: Stage,
skip_quiets: bool,
ttmove: Move,
prev_move: Move,
last_bad_noisy: usize = 0,
probcut_threshold: ?i32,

pub const Stage = enum {
    tt,
    generate_noisies,
    good_noisies,
    generate_quiets,
    quiets,
    bad_noisy_prep,
    bad_noisies,
};

pub fn init(
    movelist_: *MoveReceiver,
    scores_: [*]i32,
    ttmove_: Move,
    prev_move_: Move,
    is_singular_search: bool,
) MovePicker {
    movelist_.vals.len = 0;
    var stage: Stage = undefined;
    if (is_singular_search or ttmove_.isNull()) {
        @branchHint(.unpredictable);
        stage = .generate_noisies;
    } else {
        stage = .tt;
    }
    return .{
        .movelist = movelist_,
        .scores = scores_,
        .first = 0,
        .last = 0,
        .stage = stage,
        .skip_quiets = false,
        .ttmove = ttmove_,
        .prev_move = prev_move_,
        .probcut_threshold = null,
    };
}

pub fn initQs(
    movelist_: *MoveReceiver,
    scores_: [*]i32,
    ttmove_: Move,
    prev_move_: Move,
    skip_quiets: bool,
) MovePicker {
    movelist_.vals.len = 0;
    var stage: Stage = undefined;
    if (ttmove_.isNull()) {
        @branchHint(.unpredictable);
        stage = .generate_noisies;
    } else {
        stage = .tt;
    }
    return .{
        .movelist = movelist_,
        .scores = scores_,
        .first = 0,
        .last = 0,
        .stage = stage,
        .skip_quiets = skip_quiets,
        .ttmove = ttmove_,
        .prev_move = prev_move_,
        .probcut_threshold = null,
    };
}

pub fn initProbcut(
    movelist_: *MoveReceiver,
    scores_: [*]i32,
    ttmove_: Move,
    prev_move_: Move,
    threshold: i32,
) MovePicker {
    movelist_.vals.len = 0;
    const stage: Stage = if (ttmove_.isNull()) .generate_noisies else .tt;
    return .{
        .movelist = movelist_,
        .scores = scores_,
        .first = 0,
        .last = 0,
        .stage = stage,
        .skip_quiets = true,
        .ttmove = ttmove_,
        .prev_move = prev_move_,
        .probcut_threshold = threshold,
    };
}

pub fn deinit(self: MovePicker) void {
    self.movelist.vals.len = 0;
}

fn packScore(score: i32, idx: u32) i32 {
    return score << 8 | @as(i32, @intCast(idx));
}

fn packScores(comptime N: usize, scores: @Vector(N, i32), indices: @Vector(N, i32)) @Vector(N, i32) {
    return scores << @splat(8) | indices;
}

noinline fn findBest(noalias self: *MovePicker) usize {
    const moves = self.movelist.vals.slice()[self.first..self.last];
    const len = self.last - self.first;
    const scores = self.scores[self.first..];

    var best: i32 = std.math.minInt(i32);

    if (std.simd.suggestVectorLength(i32)) |UNROLL| {
        var best_vec: @Vector(UNROLL, i32) = @splat(std.math.minInt(i32));
        var iter = simd.indexedChunkIter(i32, UNROLL, scores[0..len]);
        while (iter.fullChunk()) |c| {
            best_vec = @max(best_vec, packScores(UNROLL, c.data, c.indices));
        }
        {
            var c = iter.tail();
            c.data = packScores(UNROLL, c.data, c.indices);
            best_vec = @max(best_vec, c.select(best_vec));
        }
        best = @reduce(.Max, best_vec) & 0xff;
    } else {
        var i: usize = 0;
        while (i < len) : (i += 1) {
            best = @max(best, packScore(scores[i], i));
        }
    }

    const best_idx: usize = @intCast(best);

    std.mem.swap(Move, &moves[0], &moves[best_idx]);
    std.mem.swap(i32, &scores[0], &scores[best_idx]);

    const res = self.first;
    self.first += 1;
    return res;
}

inline fn noisyValue(
    noalias histories: *const Historytable,
    noalias board: *const Board,
    typed: TypedMove,
) i32 {
    var res: i32 = 0;

    res += @intFromBool(typed.move.tp() == .ep) * SEE.value(.pawn, .ordering);
    res += SEE.value(board.pieceOn(typed.move.to()) orelse .king, .ordering);
    res = @divFloor(res * root.TUNABLE_CONSTANTS.mvv_mult, 32);
    res += histories.readNoisy(board, typed);

    return res;
}

inline fn quietValue(
    noalias histories: *const Historytable,
    conthist_tables: history.ConthistTables,
    noalias board: *const Board,
    typed: TypedMove,
    danger_squares: *const [6]u64,
) i32 {
    const from_danger_bonus = [6]i32{
        root.TUNABLE_CONSTANTS.ord_from_danger_pawn_bonus,
        root.TUNABLE_CONSTANTS.ord_from_danger_knight_bonus,
        root.TUNABLE_CONSTANTS.ord_from_danger_bishop_bonus,
        root.TUNABLE_CONSTANTS.ord_from_danger_rook_bonus,
        root.TUNABLE_CONSTANTS.ord_from_danger_queen_bonus,
        root.TUNABLE_CONSTANTS.ord_from_danger_king_bonus,
    };
    const to_danger_penalty = [6]i32{
        root.TUNABLE_CONSTANTS.ord_to_danger_pawn_penalty,
        root.TUNABLE_CONSTANTS.ord_to_danger_knight_penalty,
        root.TUNABLE_CONSTANTS.ord_to_danger_bishop_penalty,
        root.TUNABLE_CONSTANTS.ord_to_danger_rook_penalty,
        root.TUNABLE_CONSTANTS.ord_to_danger_queen_penalty,
        0,
    };

    const terms = histories.readMoveTerms(board, typed, conthist_tables, true);
    var res = tuning.histQ(terms, tuning.quietHistoryWeights("ord"));
    const piece_idx = typed.tp.toInt();

    if (board.givesDirectCheck(typed.move)) {
        @branchHint(.unpredictable);
        res += root.TUNABLE_CONSTANTS.ord_direct_check_bonus;
    }

    const danger = danger_squares[piece_idx];
    const danger_bonus = from_danger_bonus[piece_idx];
    const danger_penalty = to_danger_penalty[piece_idx];
    if (root.Bitboard.contains(danger, typed.move.from())) {
        @branchHint(.unpredictable);
        res += danger_bonus;
    }

    if (root.Bitboard.contains(danger, typed.move.to())) {
        @branchHint(.unpredictable);
        res -= danger_penalty;
    }

    return res;
}

pub fn next(
    noalias self: *MovePicker,
    comptime stm: Colour,
    noalias histories: *const Historytable,
    conthist_tables: history.ConthistTables,
    noalias board: *const Board,
) ?TypedMove {
    return sw: switch (self.stage) {
        .tt => {
            @branchHint(.unpredictable);
            if (self.skip_quiets and board.isQuiet(self.ttmove)) {
                continue :sw .generate_noisies;
            }
            self.stage = .generate_noisies;
            if (board.isLegal(stm, self.ttmove)) {
                return TypedMove.fromBoard(board, self.prev_move, self.ttmove);
            }
            continue :sw .generate_noisies;
        },
        .generate_noisies => {
            self.movelist.vals.len = 0;
            std.debug.assert(self.movelist.vals.len == 0);
            movegen.generateAllNoisies(stm, board, self.movelist);
            for (self.movelist.vals.slice(), 0..) |move, i| {
                self.scores[i] = noisyValue(histories, board, TypedMove.fromBoard(board, self.prev_move, move));
            }
            self.last = self.movelist.vals.len;
            self.stage = .good_noisies;

            continue :sw .good_noisies;
        },
        .good_noisies => {
            if (self.first == self.last) {
                continue :sw .generate_quiets;
            }
            const best_idx = self.findBest();
            const move = self.movelist.vals.slice()[best_idx];
            if (move == self.ttmove) {
                continue :sw .good_noisies;
            }
            const res = TypedMove.fromBoard(board, self.prev_move, move);
            if (self.probcut_threshold) |threshold| {
                if (SEE.scoreMove(board, res.move, threshold, .pruning)) {
                    return res;
                }
                continue :sw .good_noisies;
            }

            const history_score = histories.readNoisy(board, res);
            const margin = @divTrunc(-history_score * root.TUNABLE_CONSTANTS.good_noisy_ordering_mult, 32768) +
                root.tuning.TUNABLE_CONSTANTS.good_noisy_ordering_base;
            if (SEE.scoreMove(board, res.move, margin, .ordering)) {
                return res;
            }
            const score = self.scores[best_idx];
            self.movelist.vals.slice()[self.last_bad_noisy] = res.move;
            self.scores[self.last_bad_noisy] = score;
            self.last_bad_noisy += 1;

            continue :sw .good_noisies;
        },
        .generate_quiets => {
            if (self.skip_quiets) {
                return null;
            }
            self.first = self.movelist.vals.len;
            movegen.generateAllQuiets(stm, board, self.movelist);

            const all_threats = board.threatsFor(stm.flipped());
            const defended = board.threatsFor(stm);
            const undefended_threats = all_threats & ~defended;
            const pawn = board.threatsBy(stm.flipped(), .pawn);
            const knight = board.threatsBy(stm.flipped(), .knight);
            const bishop = board.threatsBy(stm.flipped(), .bishop);
            const rook = board.threatsBy(stm.flipped(), .rook);

            const minor = pawn | knight | bishop;
            const major = minor | rook;
            const danger_squares: [6]u64 = .{
                undefended_threats,
                pawn,
                pawn,
                minor,
                major,
                all_threats,
            };
            for (self.movelist.vals.slice()[self.first..], 0..) |move, i| {
                self.scores[self.first + i] = quietValue(
                    histories,
                    conthist_tables,
                    board,
                    TypedMove.fromBoard(board, self.prev_move, move),
                    &danger_squares,
                );
            }
            self.last = self.movelist.vals.len;
            self.stage = .quiets;
            continue :sw .quiets;
        },
        .quiets => {
            if (self.first == self.last or self.skip_quiets) {
                continue :sw .bad_noisy_prep;
            }
            const move = self.movelist.vals.slice()[self.findBest()];
            if (move == self.ttmove) {
                continue :sw .quiets;
            }
            return TypedMove.fromBoard(board, self.prev_move, move);
        },
        .bad_noisy_prep => {
            self.first = 0;
            self.last = self.last_bad_noisy;
            self.stage = .bad_noisies;
            continue :sw .bad_noisies;
        },
        .bad_noisies => {
            if (self.first == self.last) {
                return null;
            }
            const move = self.movelist.vals.slice()[self.findBest()];
            if (move == self.ttmove) {
                continue :sw .bad_noisies;
            }
            return TypedMove.fromBoard(board, self.prev_move, move);
        },
    };
}
