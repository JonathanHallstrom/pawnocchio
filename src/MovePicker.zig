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
const Board = root.Board;
const ScoredMove = root.ScoredMove;
const MoveReceiver = root.FilteringMoveReceiver;
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
    movelist_.filter = ttmove_;
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
    movelist_.filter = ttmove_;
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
    };
}

pub fn deinit(self: MovePicker) void {
    self.movelist.vals.len = 0;
}

fn packScore(score: i32, idx: usize) u32 {
    const score_u32: u32 = @intCast(score + (1 << 20));
    return @intCast(score_u32 << 8 | idx);
}

fn packScores(comptime N: usize, scores: @Vector(N, i32), indices: @Vector(N, u32)) @Vector(N, u32) {
    const offset: @Vector(N, i32) = @splat(1 << 20);
    const scores_u32: @Vector(N, u32) = @intCast(scores + offset);
    return scores_u32 << @splat(8) | indices;
}

noinline fn findBest(noalias self: *MovePicker) usize {
    const moves = self.movelist.vals.slice()[self.first..self.last];
    const scores = self.scores[self.first..self.last];

    const UNROLL = std.simd.suggestVectorLength(u32) orelse 1;
    var best_vec: @Vector(UNROLL, u32) = @splat(0);

    var i: u32 = 0;
    var indices = std.simd.iota(u32, UNROLL);
    while (i + UNROLL <= scores.len) : ({
        i += UNROLL;
        indices += @splat(UNROLL);
    }) {
        best_vec = @max(best_vec, packScores(UNROLL, scores[i..][0..UNROLL].*, indices));
    }

    var best: u32 = @reduce(.Max, best_vec);
    while (i < scores.len) : (i += 1) {
        best = @max(best, packScore(scores[i], i));
    }

    const best_idx: usize = best & 0xff;

    if (best_idx != 0) {
        std.mem.swap(Move, &moves[0], &moves[best_idx]);
        std.mem.swap(i32, &scores[0], &scores[best_idx]);
    }
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
    res = @divFloor(res * root.tunable_constants.mvv_mult, 32);
    res += histories.readNoisy(board, typed);

    return res;
}

inline fn quietValue(
    noalias histories: *const Historytable,
    conthist_tables: history.ConthistTables,
    noalias board: *const Board,
    typed: TypedMove,
) i32 {
    const terms = histories.readMoveTerms(board, typed, conthist_tables, true);
    var res = tuning.histQ(terms, tuning.quietHistoryWeights("ord"));

    if (board.isDirectCheck(typed.move)) {
        res += 5000;
    }

    return res;
}

const call_modifier: std.builtin.CallModifier = if (@import("builtin").mode == .Debug or @import("builtin").cpu.arch.isPowerPC()) .auto else .always_tail;

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
            if (board.isPseudoLegal(stm, self.ttmove)) {
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
            const res = TypedMove.fromBoard(board, self.prev_move, self.movelist.vals.slice()[best_idx]);
            const history_score = histories.readNoisy(board, res);
            const margin = @divTrunc(-history_score * root.tunable_constants.good_noisy_ordering_mult, 32768) +
                root.tuning.tunable_constants.good_noisy_ordering_base;
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
            for (self.movelist.vals.slice()[self.first..], 0..) |move, i| {
                self.scores[self.first + i] = quietValue(histories, conthist_tables, board, TypedMove.fromBoard(board, self.prev_move, move));
            }
            self.last = self.movelist.vals.len;
            self.stage = .quiets;
            continue :sw .quiets;
        },
        .quiets => {
            if (self.first == self.last or self.skip_quiets) {
                continue :sw .bad_noisy_prep;
            }
            return TypedMove.fromBoard(board, self.prev_move, self.movelist.vals.slice()[self.findBest()]);
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
            return TypedMove.fromBoard(board, self.prev_move, self.movelist.vals.slice()[self.findBest()]);
        },
    };
}
