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

pub const Stage = enum {
    generate_noisies,
    noisies,
    generate_quiets,
    quiets,
};

pub fn init(
    board_: *const Board,
    movelist_: *ScoredMoveReceiver,
) MovePicker {
    return .{
        .movelist = movelist_,
        .board = board_,
        .first = 0,
        .last = 0,
        .stage = .generate_noisies,
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
        std.mem.swap(ScoredMove, &scored_moves[best_idx], &scored_moves[0]);
    }
    const res = self.first;
    self.first += 1;
    return res;
}

pub fn next(self: *MovePicker) ?ScoredMove {
    while (true) {
        switch (self.stage) {
            .generate_noisies => {
                switch (self.board.stm) {
                    inline else => |stm| {
                        movegen.generateAllNoisies(stm, self.board, self.movelist);
                    },
                }
                self.stage = .noisies;
                self.last = self.movelist.vals.len;
                for (self.first..self.last) |i| {
                    self.movelist.vals.buffer[i].score = @intCast(i *% 13 & 127);
                }
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
                switch (self.board.stm) {
                    inline else => |stm| {
                        movegen.generateAllQuiets(stm, self.board, self.movelist);
                    },
                }
                self.stage = .quiets;
                self.last = self.movelist.vals.len;
                for (self.first..self.last) |i| {
                    self.movelist.vals.buffer[i].score = @intCast(i *% 13 & 127);
                }
                self.stage = .quiets;
                continue;
            },
            .quiets => {
                if (self.first == self.last) {
                    return null;
                }
                return self.movelist.vals.slice()[self.findBest()];
            },
        }
    }
}
