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
const MoveReceiver = root.FilteringScoredMoveReceiver;
const movegen = root.movegen;
const SEE = root.SEE;
const PieceType = root.PieceType;
const Colour = root.Colour;
const history = root.history;
const TypedMove = history.TypedMove;
const Historytable = history.HistoryTable;

const MovePicker = @This();

movelist: *MoveReceiver,
first: usize,
last: usize,
stage: Stage,
skip_quiets: bool,
ttmove: Move,
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
    ttmove_: Move,
    is_singular_search: bool,
) MovePicker {
    movelist_.vals.len = 0;
    movelist_.filter = ttmove_;
    return .{
        .movelist = movelist_,
        .first = 0,
        .last = 0,
        .stage = if (is_singular_search) .generate_noisies else .tt,
        .skip_quiets = false,
        .ttmove = ttmove_,
    };
}

pub fn initQs(
    movelist_: *MoveReceiver,
    ttmove_: Move,
    skip_quiets: bool,
) MovePicker {
    movelist_.vals.len = 0;
    movelist_.filter = ttmove_;
    return .{
        .movelist = movelist_,
        .first = 0,
        .last = 0,
        .stage = .tt,
        .skip_quiets = skip_quiets,
        .ttmove = ttmove_,
    };
}

pub fn deinit(self: MovePicker) void {
    self.movelist.vals.len = 0;
}

inline fn findBest(noalias self: *MovePicker) usize {
    const scored_moves = self.movelist.vals.slice()[self.first..self.last];

    const unroll = 4;
    const loadVals = struct {
        fn impl(mvs: []ScoredMove, i: usize) @Vector(unroll, u64) {
            var res: @Vector(unroll, u64) = undefined;
            inline for (0..unroll) |j| {
                res[j] = mvs.ptr[i + j].toScoreU64();
            }
            return res;
        }
    }.impl;
    const masks = comptime blk: {
        var res: [unroll]@Vector(unroll, u64) = undefined;
        res[0] = @splat(0);
        for (1..unroll) |j| {
            res[j] = res[j - 1];
            res[j][j - 1] = std.math.maxInt(u64);
        }
        break :blk res;
    };
    var best: @Vector(unroll, u64) = [_]u64{scored_moves[0].toScoreU64()} ** unroll;
    var i: u64 = 0;
    var index_vec = std.simd.iota(u64, unroll);
    while (i + unroll <= scored_moves.len) : (i += unroll) {
        best = @max(best, loadVals(scored_moves, i) | index_vec);
        index_vec += @splat(unroll);
    }
    best = @max(best, (loadVals(scored_moves, i) & masks[scored_moves.len % unroll]) | index_vec);

    const best_idx: u64 = @reduce(.Max, best) & std.math.maxInt(u32);

    if (best_idx != 0) {
        std.mem.swap(ScoredMove, &scored_moves[0], &scored_moves[best_idx]);
    }
    const res = self.first;
    self.first += 1;
    return res;
}

inline fn noisyValue(
    noalias histories: *const Historytable,
    noalias board: *const Board,
    move: Move,
) i32 {
    var res: i32 = 0;

    res += @intFromBool(move.tp() == .ep) * SEE.value(.pawn, .ordering);
    res += SEE.value(board.pieceOn(move.to()) orelse .king, .ordering);
    res = @divFloor(res * root.tunable_constants.mvv_mult, 32);
    res += histories.readNoisy(board, move);

    return res;
}

inline fn quietValue(
    noalias histories: *const Historytable,
    conthist_tables: history.ConthistTables,
    noalias board: *const Board,
    move: Move,
) i32 {
    return histories.readQuietOrdering(board, move, conthist_tables);
}

const call_modifier: std.builtin.CallModifier = if (@import("builtin").mode == .Debug or @import("builtin").cpu.arch.isPowerPC()) .auto else .always_tail;

pub inline fn next(
    noalias self: *MovePicker,
    comptime stm: Colour,
    noalias histories: *const Historytable,
    conthist_tables: history.ConthistTables,
    noalias board: *const Board,
) ?ScoredMove {
    return sw: switch (self.stage) {
        .tt => {
            @branchHint(.unpredictable);
            if (self.skip_quiets and board.isQuiet(self.ttmove)) {
                continue :sw .generate_noisies;
            }
            self.stage = .generate_noisies;
            if (board.isPseudoLegal(stm, self.ttmove)) {
                return ScoredMove{ .move = self.ttmove, .score = 0 };
            }
            continue :sw .generate_noisies;
        },
        .generate_noisies => {
            self.movelist.vals.len = 0;
            std.debug.assert(self.movelist.vals.len == 0);
            movegen.generateAllNoisies(stm, board, self.movelist);
            for (self.movelist.vals.slice()) |*scored_move| {
                scored_move.score = noisyValue(histories, board, scored_move.move);
            }
            self.last = self.movelist.vals.len;
            self.stage = .good_noisies;

            continue :sw .good_noisies;
        },
        .good_noisies => {
            if (self.first == self.last) {
                continue :sw .generate_quiets;
            }
            const res = self.movelist.vals.slice()[self.findBest()];
            const history_score = histories.readNoisy(board, res.move);
            const margin = @divTrunc(-history_score * root.tunable_constants.good_noisy_ordering_mult, 32768) +
                root.tuning.tunable_constants.good_noisy_ordering_base;
            if (SEE.scoreMove(board, res.move, margin, .ordering)) {
                return res;
            }
            self.movelist.vals.slice()[self.last_bad_noisy] = res;
            self.last_bad_noisy += 1;

            continue :sw .good_noisies;
        },
        .generate_quiets => {
            if (self.skip_quiets) {
                continue :sw .bad_noisy_prep;
            }
            self.first = self.movelist.vals.len;
            movegen.generateAllQuiets(stm, board, self.movelist);
            for (self.movelist.vals.slice()[self.last..]) |*scored_move| {
                scored_move.score = quietValue(histories, conthist_tables, board, scored_move.move);
            }
            self.last = self.movelist.vals.len;
            self.stage = .quiets;
            continue :sw .quiets;
        },
        .quiets => {
            if (self.first == self.last or self.skip_quiets) {
                continue :sw .bad_noisy_prep;
            }
            return self.movelist.vals.slice()[self.findBest()];
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
            return self.movelist.vals.slice()[self.findBest()];
        },
    };
}
