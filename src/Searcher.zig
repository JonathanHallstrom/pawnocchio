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
const FilteringScoredMoveReceiver = root.FilteringScoredMoveReceiver;
const Colour = root.Colour;
const MovePicker = root.MovePicker;
const history = root.history;
const ScoreType = root.ScoreType;
const engine = root.engine;
const write = root.write;
const evaluate = evaluation.evaluate;
pub const MAX_PLY = 256;
pub const MAX_HALFMOVE = 100;

pub const Params = struct {
    board: Board,
    limits: Limits,
    previous_hashes: []u64,
    needs_full_reset: bool = false,
};

nodes: u64,
hashes: [MAX_PLY]u64,
eval_states: [MAX_PLY]evaluation.State,
search_stack: [MAX_PLY]StackEntry,
root_move: Move,
root_score: i16,
limits: Limits,
ply: u8,
stop: bool,
previous_hashes: std.BoundedArray(u64, MAX_HALFMOVE),
quiet_history: history.QuietHistory,

pub const StackEntry = struct {
    board: Board,
    movelist: FilteringScoredMoveReceiver,

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
    self.hashes[self.ply] = new_stack_entry.board.hash;
}

fn unmakeMove(self: *Searcher, comptime stm: Colour, move: Move) void {
    _ = stm;
    _ = move;
    self.ply -= 1;
}

fn isRepetition(self: *Searcher) bool {
    const board = &self.curStackEntry().board;

    const hash = board.hash;
    const amt = @min(self.ply, board.halfmove);
    for (self.hashes[self.ply - amt .. self.ply]) |previous_hash| {
        if (previous_hash == hash) {
            return true; // found repetition in the search tree
        }
    }
    for (self.previous_hashes.slice()) |previous_hash| {
        if (previous_hash == hash) {
            return true;
        }
    }
    return false;
}

fn qsearch(self: *Searcher, comptime is_root: bool, comptime stm: Colour, alpha_: i32, beta: i32) i16 {
    var alpha = alpha_;

    self.nodes += 1;
    if (self.stop or self.limits.checkSearch(self.nodes)) {
        self.stop = true;
        return 0;
    }
    const cur = self.curStackEntry();
    const board = &cur.board;
    const is_in_check = board.checkers != 0;

    var static_eval: i16 = evaluation.matedIn(self.ply);
    if (!is_in_check) {
        static_eval = evaluate(&self.curStackEntry().board, (&self.eval_states)[self.ply]);

        if (static_eval >= beta)
            return static_eval;
        if (static_eval > alpha)
            alpha = static_eval;
    }
    var best_score = static_eval;
    var best_move = Move.init();
    var mp = MovePicker.initQs(
        board,
        &cur.movelist,
        &self.quiet_history,
        Move.init(),
    );

    while (mp.next()) |scored_move| {
        const move = scored_move.move;
        if (!board.isLegal(stm, move)) {
            continue;
        }

        self.makeMove(stm, move);
        const score = -self.qsearch(false, stm.flipped(), -beta, -alpha);
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

    if (is_root) {
        self.root_move = best_move;
        self.root_score = best_score;
    }

    return best_score;
}

fn negamax(
    self: *Searcher,
    comptime is_root: bool,
    comptime is_pv: bool,
    comptime stm: Colour,
    alpha_: i32,
    beta: i32,
    depth: i32,
) i16 {
    var alpha = alpha_;

    self.nodes += 1;
    if (self.stop or (!is_root and self.limits.checkSearch(self.nodes))) {
        self.stop = true;
        return 0;
    }
    if (depth <= 0) {
        return self.qsearch(is_root, stm, alpha, beta);
    }

    if (self.ply >= MAX_PLY - 1) {
        return evaluate(&self.curStackEntry().board, (&self.eval_states)[self.ply]);
    }

    const cur = self.curStackEntry();
    const board = &cur.board;
    const is_in_check = board.checkers != 0;

    if (!is_root and (board.halfmove >= 100 or self.isRepetition())) {
        return 0;
    }

    const tt_hash = board.hash;
    var tt_entry = engine.readTT(tt_hash);
    if (tt_entry.hash != tt_hash) {
        tt_entry = .{};
    }

    var mp = MovePicker.init(
        board,
        &cur.movelist,
        &self.quiet_history,
        tt_entry.move,
    );
    var best_move = Move.init();
    var best_score = -evaluation.inf_score;
    var searched_quiets: std.BoundedArray(Move, 64) = .{};
    var searched_noisies: std.BoundedArray(Move, 64) = .{};
    var score_type: ScoreType = .upper;
    var num_legal: u8 = 0;
    while (mp.next()) |scored_move| {
        const move = scored_move.move;
        engine.prefetchTT(board.roughHashAfter(move));
        if (!board.isLegal(stm, move)) {
            continue;
        }
        num_legal += 1;
        std.debug.assert(std.mem.count(Move, searched_noisies.slice(), &.{move}) == 0);
        std.debug.assert(std.mem.count(Move, searched_quiets.slice(), &.{move}) == 0);

        const is_quiet = board.isQuiet(move);
        self.makeMove(stm, move);
        const score = blk: {
            var s: i16 = 0;
            if (!is_pv or num_legal > 1) {
                s = -self.negamax(
                    false,
                    false,
                    stm.flipped(),
                    -alpha - 1,
                    -alpha,
                    depth - 1,
                );
            }
            if (is_pv and (num_legal == 1 or s > alpha)) {
                s = -self.negamax(
                    false,
                    true,
                    stm.flipped(),
                    -beta,
                    -alpha,
                    depth - 1,
                );
            }

            break :blk s;
        };
        self.unmakeMove(stm, move);
        if (self.stop) {
            return 0;
        }

        if (is_quiet) {
            searched_quiets.append(move) catch {};
        } else {
            searched_noisies.append(move) catch {};
        }

        if (score > best_score) {
            best_score = score;
            best_move = move;
        }
        if (score > alpha) {
            alpha = score;
            score_type = .exact;
            if (score >= beta) {
                score_type = .lower;
                if (is_quiet) {
                    self.quiet_history.update(stm, move, root.history.bonus(depth));
                    for (searched_quiets.slice()) |searched_move| {
                        if (searched_move == move) break;
                        self.quiet_history.update(stm, searched_move, -root.history.penalty(depth));
                    }
                }
                break;
            }
        }
    }

    if (best_move.isNull()) {
        const mated_score = evaluation.matedIn(self.ply);
        return if (is_in_check) mated_score else 0;
    }

    engine.writeTT(
        tt_hash,
        best_move,
        evaluation.scoreToTt(best_score, self.ply),
        score_type,
        depth,
    );

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

fn retainOnlyDuplicates(slice: []u64) usize {
    std.sort.pdq(u64, slice, void{}, std.sort.asc(u64));
    var write_idx: usize = 0;
    var last: u64 = 0;
    var count: usize = 0;
    for (slice) |hash| {
        if (hash == last) {
            count += 1;
            if (count == 2) {
                slice[write_idx] = last;
                write_idx += 1;
            }
        } else {
            count = 1;
        }
        last = hash;
    }
    return write_idx;
}

test retainOnlyDuplicates {
    var vals = [_]u64{ 0, 1, 1, 2, 2, 2, 8, 2, 2, 2, 3, 8, 4, 4 };
    const count = retainOnlyDuplicates(&vals);
    try std.testing.expectEqualSlices(u64, &.{ 1, 2, 4, 8 }, vals[0..count]);
}
/// we make the previous hashes only contain hashes that occur twice, so that we can just search for the current hash in isRepetition()
fn fixupPreviousHashes(self: *Searcher) void {
    self.previous_hashes.len = @intCast(retainOnlyDuplicates(self.previous_hashes.slice()));
    self.previous_hashes.appendAssumeCapacity(std.math.maxInt(u64));
}

fn init(self: *Searcher, params: Params) void {
    self.limits = params.limits;
    self.ply = 0;
    self.stop = false;
    self.nodes = 0;
    const board = params.board;
    self.previous_hashes.len = 0;
    for (params.previous_hashes) |previous_hash| {
        self.previous_hashes.appendAssumeCapacity(previous_hash);
    }
    self.fixupPreviousHashes();

    self.root_move = Move.init();
    self.root_score = 0;
    self.search_stack[0].init(board);
    self.eval_states[0].initInPlace(&board);
    if (params.needs_full_reset) {
        self.quiet_history.reset();
    }
}

pub fn startSearch(self: *Searcher, params: Params, is_main_thread: bool, quiet: bool) void {
    self.init(params);
    for (1..MAX_PLY) |d| {
        const depth: i32 = @intCast(d);
        _ = switch (params.board.stm) {
            inline else => |stm| self.negamax(
                true,
                true,
                stm,
                -evaluation.inf_score,
                evaluation.inf_score,
                depth,
            ),
        };
        if (self.stop)
            break;
        if (self.limits.checkRoot(self.nodes, depth))
            break;
        if (!quiet)
            self.writeInfo(self.root_score, depth);
    }

    if (is_main_thread) {
        if (!quiet) {
            write("bestmove {s}\n", .{self.root_move.toString(&params.board).slice()});
        }
    }
}
