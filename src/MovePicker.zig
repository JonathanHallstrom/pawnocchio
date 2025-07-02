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

const MovePicker = @This();

movelist: *MoveReceiver,
first: usize,
last: usize,
board: *const Board,
stage: Stage,
skip_quiets: bool,
histories: *const root.history.HistoryTable,
ttmove: Move,
prev: root.history.TypedMove,
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
    board_: *const Board,
    movelist_: *MoveReceiver,
    histories_: *root.history.HistoryTable,
    ttmove_: Move,
    prev_: root.history.TypedMove,
    is_singular_search: bool,
) MovePicker {
    movelist_.vals.len = 0;
    movelist_.filter = ttmove_;
    return .{
        .movelist = movelist_,
        .board = board_,
        .first = 0,
        .last = 0,
        .stage = if (is_singular_search) .generate_noisies else .tt,
        .skip_quiets = false,
        .histories = histories_,
        .ttmove = ttmove_,
        .prev = prev_,
    };
}

pub fn initQs(
    board_: *const Board,
    movelist_: *MoveReceiver,
    histories_: *root.history.HistoryTable,
    ttmove_: Move,
    prev_: root.history.TypedMove,
) MovePicker {
    movelist_.vals.len = 0;
    movelist_.filter = ttmove_;
    return .{
        .movelist = movelist_,
        .board = board_,
        .first = 0,
        .last = 0,
        .stage = .tt,
        .skip_quiets = board_.checkers == 0,
        .histories = histories_,
        .ttmove = ttmove_,
        .prev = prev_,
    };
}

pub fn deinit(self: MovePicker) void {
    self.movelist.vals.len = 0;
}

inline fn findBest(noalias self: *MovePicker) usize {
    const scored_moves = self.movelist.vals.slice()[self.first..self.last];

    const unroll = 4;
    const loadVals = struct {
        fn impl(moves: []ScoredMove, i: usize) @Vector(unroll, u64) {
            var res: @Vector(unroll, u64) = undefined;
            inline for (0..unroll) |j| {
                res[j] = moves.ptr[i + j].toScoreU64();
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

fn noisyValue(self: MovePicker, move: Move) i32 {
    var res: i32 = 0;

    // if (self.board.isPromo(move)) {
    //     res += SEE.value(move.promoType());
    // }
    if ((&self.board.mailbox)[move.to().toInt()].opt()) |captured_type| {
        res += SEE.value(captured_type.toPieceType(), .ordering);
    } else if (self.board.isEnPassant(move)) {
        res += SEE.value(.pawn, .ordering);
    }
    res = @divFloor(res * root.tunable_constants.mvv_mult, 32);
    res += self.histories.readNoisy(self.board, move);

    return res;
}

pub fn next(self: *MovePicker) ?ScoredMove {
    while (true) {
        switch (self.stage) {
            .tt => {
                self.stage = .generate_noisies;
                if (self.skip_quiets and self.board.isQuiet(self.ttmove)) {
                    continue;
                }
                switch (self.board.stm) {
                    inline else => |stm| {
                        if (self.board.isPseudoLegal(stm, self.ttmove)) {
                            return ScoredMove{ .move = self.ttmove, .score = 0 };
                        }
                    },
                }
                continue;
            },
            .generate_noisies => {
                self.movelist.vals.len = 0;
                switch (self.board.stm) {
                    inline else => |stm| {
                        std.debug.assert(self.movelist.vals.len == 0);
                        movegen.generateAllNoisies(stm, self.board, self.movelist);
                        for (self.movelist.vals.slice()) |*scored_move| {
                            scored_move.score = self.noisyValue(scored_move.move);
                        }
                    },
                }
                self.last = self.movelist.vals.len;
                self.stage = .good_noisies;
                continue;
            },
            .good_noisies => {
                if (self.first == self.last) {
                    self.stage = .generate_quiets;
                    continue;
                }
                const res = self.movelist.vals.slice()[self.findBest()];
                const history_score = self.histories.readNoisy(self.board, res.move);
                const margin = @divTrunc(-history_score * root.tunable_constants.good_noisy_ordering_mult, 32768) +
                    root.tuning.tunable_constants.good_noisy_ordering_base;
                const threats = self.board.threats[self.board.stm.flipped().toInt()];
                const destination_unthreatened = res.move.to().toBitboard() & threats == 0;
                if (destination_unthreatened or SEE.scoreMove(self.board, res.move, margin, .ordering)) {
                    return res;
                }
                self.movelist.vals.slice()[self.last_bad_noisy] = res;
                self.last_bad_noisy += 1;
                continue;
            },
            .generate_quiets => {
                if (self.skip_quiets) {
                    self.stage = .quiets;
                    return null;
                }
                self.first = self.movelist.vals.len;
                switch (self.board.stm) {
                    inline else => |stm| {
                        movegen.generateAllQuiets(stm, self.board, self.movelist);
                        for (self.movelist.vals.slice()[self.last..]) |*scored_move| {
                            scored_move.score = self.histories.readQuiet(self.board, scored_move.move, self.prev);
                        }
                    },
                }
                self.last = self.movelist.vals.len;
                self.stage = .quiets;
                continue;
            },
            .quiets => {
                if (self.first == self.last or self.skip_quiets) {
                    self.stage = .bad_noisy_prep;
                    continue;
                }
                return self.movelist.vals.slice()[self.findBest()];
            },
            .bad_noisy_prep => {
                self.first = 0;
                self.last = self.last_bad_noisy;
                self.stage = .bad_noisies;
                continue;
            },
            .bad_noisies => {
                if (self.first == self.last) {
                    return null;
                }
                return self.movelist.vals.slice()[self.findBest()];
            },
        }
    }
}
