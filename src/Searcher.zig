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
const Limits = root.Limits;
const ScoredMove = root.ScoredMove;
const write = root.write;

pub const MAX_PLY = 256;
pub const MAX_HALFMOVE = 100;

pub const Params = struct {
    board: Board,
    limits: Limits,
};

nodes_searched: u64,
keys: std.BoundedArray(u64, MAX_PLY + MAX_HALFMOVE),
eval_states: std.BoundedArray(evaluation.State, MAX_PLY),
search_stack: std.BoundedArray(StackEntry, MAX_PLY),
best_root_move: Move,
limits: Limits,
ply: usize,

pub const StackEntry = struct {
    board: Board,
};

const Searcher = @This();

fn getStackEntryPtr(self: *Searcher) *StackEntry {
    return self.search_stack.slice()[self.ply];
}

fn makeMove(self: *Searcher, move: Move) void {
    _ = move; // autofix
    self.search_stack.len += 1;
}

fn negamax(self: *Searcher, depth: i32) i16 {
    if (depth <= 0 or self.ply == MAX_PLY) {
        return 0;
    }
    const is_root = self.ply == 0;
    _ = is_root; // autofix
}

pub fn startSearch(self: *Searcher, settings: Params, is_main_thread: bool) void {
    self.limits = settings.limits;
    self.ply = 0;

    var rec1: root.ScoredMoveReceiver = .{};
    var rec2: root.ScoredMoveReceiver = .{};
    switch (settings.board.stm) {
        inline else => |stm| {
            movegen.generateAllNoisies(stm, &settings.board, &rec1);
            movegen.generateAllQuiets(stm, &settings.board, &rec1);
        },
    }

    for (0..rec1.vals.len) |i| {
        rec1.vals.buffer[i].score = @intCast(i *% 13 & 127);
        if (settings.board.isNoisy(rec1.vals.buffer[i].move)) {
            rec1.vals.buffer[i].score += 128;
        }
    }
    std.sort.insertion(ScoredMove, rec1.vals.slice(), void{}, ScoredMove.desc);
    var rng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    var mp = root.MovePicker.init(&settings.board, &rec2);
    var chosen: ?Move = null;
    for (0..rec1.vals.len) |i| {
        const a = rec1.vals.slice()[i];
        switch (settings.board.stm) {
            inline else => |stm| {
                if (settings.board.isLegal(stm, a.move)) {
                    if (rng.random().boolean() or chosen == null) {
                        chosen = a.move;
                    }
                }
            },
        }
        const b = mp.next();
        if (b == null) {
            std.debug.print("ended too early\n", .{});
            break;
        } else {
            std.debug.print("{s} {s}\n", .{ a.move.toString(&settings.board).slice(), b.?.move.toString(&settings.board).slice() });
        }

        if (a.move != b.?.move) {
            std.debug.print("mismatch!\n", .{});
            chosen = @enumFromInt(0);
            break;
        }
    }

    if (is_main_thread) {
        write("info nodes 1 score 0 pv {s}\n", .{chosen.?.toString(&settings.board).slice()});
        write("bestmove {s}\n", .{chosen.?.toString(&settings.board).slice()});
    }
}
