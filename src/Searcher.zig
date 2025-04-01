// Pawnocchio, UCI chess engine
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

const evaluation = root.evaluation;
const movegen = root.movegen;
const Move = root.Move;
const Board = root.Board;
const write = root.write;

pub const MAX_PLY = 256;
pub const MAX_HALFMOVE = 100;

pub const Params = struct {
    board: Board,
};

nodes_searched: u64,
// keys: std.BoundedArray(u64, MAX_PLY + MAX_HALFMOVE),
// eval_states: std.BoundedArray(evaluation.State, MAX_PLY),
// search_stack: std.BoundedArray(StackEntry, MAX_PLY),

// pub const StackEntry = struct {};

const Searcher = @This();
const ScoredMove = struct {
    move: Move,
    score: i16,
};

const ScoredMoveReceiver = struct {
    vals: std.BoundedArray(ScoredMove, 256) = .{},

    pub fn receive(self: *@This(), move: Move) void {
        self.vals.appendAssumeCapacity(.{ .move = move, .score = 0 });
    }
};

pub fn startSearch(self: Searcher, settings: Params, is_main_thread: bool) void {
    _ = self; // autofix
    var chosen: Move = @enumFromInt(0);
    switch (settings.board.stm) {
        inline else => |stm| {
            var rec: ScoredMoveReceiver = .{};
            movegen.generateAllNoisies(stm, &settings.board, &rec);
            movegen.generateAllQuiets(stm, &settings.board, &rec);
            var rng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
            rng.random().shuffle(ScoredMove, rec.vals.slice());
            for (rec.vals.slice()) |move| {
                if (settings.board.isLegal(stm, move.move)) {
                    chosen = move.move;
                    break;
                }
            }
        },
    }

    if (is_main_thread) {
        write("info nodes 1 score 0 pv {s}\n", .{chosen.toString(&settings.board).slice()});
        write("bestmove {s}\n", .{chosen.toString(&settings.board).slice()});
    }
}
