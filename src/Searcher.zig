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

const evaluation = root.evaluation;
const movegen = root.movegen;
const Move = root.Move;
const Board = root.Board;
const Limits = root.Limits;
const ScoredMove = root.ScoredMove;
const ScoredMoveReceiver = root.ScoredMoveReceiver;
const Colour = root.Colour;
const MovePicker = root.MovePicker;
const write = root.write;
const evaluate = evaluation.evaluate;

pub const MAX_PLY = 256;
pub const MAX_HALFMOVE = 100;

pub const Params = struct {
    board: Board,
    limits: Limits,
    previous_hashes: []u64,
};

nodes: u64,
keys: [MAX_PLY + MAX_HALFMOVE]u64,
eval_states: [MAX_PLY]evaluation.State,
search_stack: [MAX_PLY]StackEntry,
root_move: Move,
root_score: i16,
limits: Limits,
ply: usize,
stop: bool,

pub const StackEntry = struct {
    board: Board,
    movelist: ScoredMoveReceiver,

    pub fn init(self: *StackEntry, board_: anytype) void {
        self.board = if (@TypeOf(board_) == std.builtin.Type.Pointer) board_.* else board_;
    }
};

const Searcher = @This();

fn curStackEntry(self: *Searcher) *StackEntry {
    return &(&self.search_stack)[self.ply];
}

fn curEvalState(self: *Searcher) *evaluation.State {
    return &(&self.eval_states)[self.ply];
}

fn drawScore(self: *const Searcher, comptime stm: Colour) i16 {
    _ = stm;
    _ = self;
    return 0;
}

fn makeMove(noalias self: *Searcher, comptime stm: Colour, move: Move) void {
    const prev_stack_entry = self.curStackEntry();
    const prev_eval_state = self.curEvalState();
    self.ply += 1;
    const new_stack_entry = self.curStackEntry();
    const new_eval_state = self.curEvalState();

    new_stack_entry.init(prev_stack_entry.board);
    new_eval_state.* = prev_eval_state.*;
    new_stack_entry.board.makeMove(stm, move, new_eval_state);
    self.keys[MAX_HALFMOVE + self.ply] = new_stack_entry.board.hash;
}

fn unmakeMove(self: *Searcher, comptime stm: Colour, move: Move) void {
    _ = stm;
    _ = move;
    self.ply -= 1;
}

fn isRepetition(self: *Searcher) bool {
    {
        return false;
    }
    const board = &self.curStackEntry().board;

    const key = board.hash;
    for (0..self.ply) |i| {
        if (self.keys[MAX_HALFMOVE + i] == key) {
            return true; // found repetition in the search tree
        }
    }
    var has_rep = false;
    const amt_before: usize = @max(@min(board.halfmove - self.ply, MAX_HALFMOVE), 0);
    for (0..amt_before) |i| {
        const matches = key == self.keys[MAX_HALFMOVE - i];
        if (matches and has_rep) {
            return true; // found 2 repetitions before the search
        }
        has_rep = has_rep or matches;
    }
    return false;
}

fn negamax(self: *Searcher, comptime is_root: bool, comptime stm: Colour, alpha_: i32, beta: i32, depth: i32) i16 {
    self.nodes += 1;
    var alpha = alpha_;
    if (self.stop or self.limits.checkSearch(self.nodes)) {
        self.stop = true;
        return 0;
    }
    if (depth <= 0) {
        return evaluate(&self.curStackEntry().board, self.eval_states[self.ply]);
    }

    if (self.ply >= MAX_PLY - 1) {
        return 0;
    }

    const cur = self.curStackEntry();
    const board = &cur.board;
    const is_in_check = board.checkers != 0;

    if (!is_root and (board.halfmove >= 100 or self.isRepetition())) {
        return 0;
    }

    var mp = MovePicker.init(board, &cur.movelist);
    var best_move = Move.init();
    var best_score = -evaluation.inf_score;
    while (mp.next()) |scored_move| {
        const move = scored_move.move;
        const ordering_score = scored_move.score;
        _ = ordering_score; // autofix
        if (!board.isLegal(stm, move)) {
            continue;
        }

        self.makeMove(stm, move);
        const score = -self.negamax(false, stm.flipped(), -beta, -alpha, depth - 1);
        self.unmakeMove(stm, move);
        if (self.stop) {
            return 0;
        }

        if (score > best_score) {
            best_score = score;
            best_move = move;
        }
        if (score > alpha) {
            alpha = score;
            if (score >= beta) {
                break;
            }
        }
    }

    if (best_move.isNull()) {
        const mated_score = evaluation.matedIn(@intCast(self.ply));
        return if (is_in_check) mated_score else 0;
    }

    if (is_root) {
        self.root_move = best_move;
        self.root_score = best_score;
    }

    return best_score;
}

fn writeInfo(self: *Searcher, score: i16, depth: i32) void {
    const elapsed = @max(1, self.limits.timer.read());
    write("info depth {} score {s} nodes {} nps {} time {} pv {s}\n", .{
        depth,
        evaluation.formatScore(score).slice(),
        self.nodes,
        @as(u128, self.nodes) * std.time.ns_per_s / elapsed,
        (elapsed + std.time.ns_per_ms / 2) / std.time.ns_per_ms,
        self.root_move.toString(&self.search_stack[0].board).slice(),
    });
}

pub fn startSearch(self: *Searcher, settings: Params, is_main_thread: bool, quiet: bool) void {
    self.limits = settings.limits;
    self.ply = 0;
    self.stop = false;
    self.nodes = 0;
    const board = settings.board;
    const num_keys_to_copy = @min(board.halfmove, settings.previous_hashes.len);
    @memcpy(self.keys[MAX_HALFMOVE - num_keys_to_copy .. MAX_HALFMOVE], settings.previous_hashes[settings.previous_hashes.len - num_keys_to_copy ..]);
    self.root_move = Move.init();
    self.root_score = 0;
    self.search_stack[0].init(board);
    self.eval_states[0].initInPlace(&board);
    for (1..MAX_PLY) |d| {
        const depth: i32 = @intCast(d);
        _ = switch (board.stm) {
            inline else => |stm| self.negamax(true, stm, -evaluation.inf_score, evaluation.inf_score, depth),
        };
        if (self.stop)
            break;
        if (self.limits.checkRoot(self.nodes, depth))
            break;
        if (!quiet)
            self.writeInfo(self.root_score, depth);
    }

    if (is_main_thread) {
        if (!quiet)
            write("bestmove {s}\n", .{self.root_move.toString(&board).slice()});
    }
}
