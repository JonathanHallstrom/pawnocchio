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
const ScoredMoveReceiver = root.ScoredMoveReceiver;
const movegen = root.movegen;

const MovePicker = @This();

movelist: *ScoredMoveReceiver,
first: usize,
last: usize,
board: *const Board,
stage: Stage,
skip_quiets: bool,
quiet_history: *const root.history.QuietHistory,

pub const Stage = enum {
    generate_noisies,
    noisies,
    generate_quiets,
    quiets,
};

pub fn init(
    board_: *const Board,
    movelist_: *ScoredMoveReceiver,
    quiet_history_: *root.history.QuietHistory,
) MovePicker {
    movelist_.vals.len = 0;
    return .{
        .movelist = movelist_,
        .board = board_,
        .first = 0,
        .last = 0,
        .stage = .generate_noisies,
        .skip_quiets = false,
        .quiet_history = quiet_history_,
    };
}

pub fn initQs(
    board_: *const Board,
    movelist_: *ScoredMoveReceiver,
    quiet_history_: *root.history.QuietHistory,
) MovePicker {
    movelist_.vals.len = 0;
    return .{
        .movelist = movelist_,
        .board = board_,
        .first = 0,
        .last = 0,
        .stage = .generate_noisies,
        .skip_quiets = board_.checkers == 0,
        .quiet_history = quiet_history_,
    };
}

fn findBest(self: *MovePicker) usize {
    const scored_moves = self.movelist.vals.slice()[self.first..self.last];
    var best_idx: usize = 0;
    var best_score: i16 = scored_moves[0].score;
    for (0..scored_moves.len) |i| {
        if (scored_moves[i].score > best_score) {
            best_idx = i;
            best_score = scored_moves[i].score;
        }
    }
    if (best_idx != 0) {
        std.mem.swap(ScoredMove, &scored_moves[0], &scored_moves[best_idx]);
    }
    const res = self.first;
    self.first += 1;
    return res;
}

fn noisyValue(self: MovePicker, move: Move) i16 {
    var res: i16 = 0;

    if (self.board.isPromo(move)) {
        res += (move.promoType().toInt() + 1) * 10;
    }

    if ((&self.board.mailbox)[move.to().toInt()]) |captured_type| {
        res += (captured_type.toInt() + 1) * 10;
    } else if (self.board.isEnPassant(move)) {
        res += 10;
    }
    const from_type = (&self.board.mailbox)[move.from().toInt()].?.toPieceType();
    res -= from_type.toInt();

    return res;
}

pub fn next(self: *MovePicker) ?ScoredMove {
    while (true) {
        switch (self.stage) {
            .generate_noisies => {
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
                self.stage = .noisies;
                continue;
            },
            .noisies => {
                if (self.first == self.last) {
                    self.stage = .generate_quiets;
                    continue;
                }
                return self.movelist.vals.slice()[self.findBest()];
            },
            .generate_quiets => {
                if (self.skip_quiets) {
                    self.stage = .quiets;
                    return null;
                }
                switch (self.board.stm) {
                    inline else => |stm| {
                        movegen.generateAllQuiets(stm, self.board, self.movelist);
                        for (self.movelist.vals.slice()[self.last..]) |*scored_move| {
                            scored_move.score = self.quiet_history.read(stm, scored_move.move);
                        }
                    },
                }
                self.last = self.movelist.vals.len;
                self.stage = .quiets;
                continue;
            },
            .quiets => {
                if (self.first == self.last or self.skip_quiets) {
                    return null;
                }
                return self.movelist.vals.slice()[self.findBest()];
            },
        }
    }
}
