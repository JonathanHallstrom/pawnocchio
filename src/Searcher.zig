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
const FilteringScoredMoveReceiver = root.FilteringScoredMoveReceiver;
const Colour = root.Colour;
const MovePicker = root.MovePicker;
const history = root.history;
const ScoreType = root.ScoreType;
const engine = root.engine;
const TypedMove = history.TypedMove;
const SEE = root.SEE;
const tunable_constants = root.tunable_constants;
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

const EvalPair = struct {
    white: ?i16 = null,
    black: ?i16 = null,

    pub fn updateWith(self: EvalPair, comptime col: Colour, val: i16) EvalPair {
        if (col == .white) {
            return .{
                .white = val,
                .black = self.black,
            };
        } else {
            return .{
                .white = self.white,
                .black = val,
            };
        }
    }

    pub fn isImprovement(self: EvalPair, comptime col: Colour, val: i16) bool {
        const prev_opt = if (col == .white) self.white else self.black;
        return if (prev_opt) |prev| val > prev else false;
    }
};

const STACK_PADDING = 1;

nodes: u64,
hashes: [MAX_PLY]u64,
eval_states: [MAX_PLY]evaluation.State,
search_stack: [MAX_PLY + STACK_PADDING]StackEntry,
root_move: Move,
root_score: i16,
limits: Limits,
ply: u8,
stop: bool,
histories: history.HistoryTable,
previous_hashes: std.BoundedArray(u64, MAX_HALFMOVE),
tt: []root.TTEntry,

inline fn ttIndex(self: *const Searcher, hash: u64) usize {
    return @intCast(@as(u128, hash) * self.tt.len >> 64);
}

pub fn writeTT(self: *Searcher, hash: u64, move: root.Move, score: i16, score_type: root.ScoreType, depth: i32) void {
    self.tt[self.ttIndex(hash)] = root.TTEntry{
        .score = score,
        .score_type = score_type,
        .move = move,
        .hash = hash,
        .depth = @intCast(depth),
    };
}

pub fn prefetchTT(self: *const Searcher, hash: u64) void {
    @prefetch(&self.tt[self.ttIndex(hash)], .{});
}

pub fn readTT(self: *const Searcher, hash: u64) root.TTEntry {
    return self.tt[self.ttIndex(hash)];
}

pub const StackEntry = struct {
    board: Board,
    movelist: FilteringScoredMoveReceiver,
    move: TypedMove,
    prev: TypedMove,
    evals: EvalPair,
    excluded: Move = Move.init(),
    static_eval: i16,
    pv: std.BoundedArray(Move, 256),

    pub fn init(self: *StackEntry, board_: *const Board, move_: TypedMove, prev_: TypedMove, prev_evals: EvalPair) void {
        self.board = board_.*;
        self.move = move_;
        self.prev = prev_;
        self.evals = prev_evals;
        self.excluded = Move.init();
        self.static_eval = 0;
        self.pv.len = 0;
    }
};

const Searcher = @This();

fn updatePv(self: *Searcher, move: Move) void {
    const cur = self.curStackEntry();
    cur.pv.len = self.ply + 1;
    cur.pv.slice()[self.ply] = move;
    if (self.ply + 1 < MAX_PLY) {
        const next = &self.nextStackEntry().pv;
        const new_len = @max(cur.pv.len, next.len);
        for (cur.pv.len..new_len) |i| {
            cur.pv.buffer[i] = next.buffer[i];
        }
        cur.pv.len = new_len;
    }
}

fn curStackEntry(self: *Searcher) *StackEntry {
    return &self.searchStackRoot()[self.ply];
}

fn nextStackEntry(self: *Searcher) *StackEntry {
    return &self.searchStackRoot()[self.ply + 1];
}

fn prevStackEntry(self: *Searcher) *StackEntry {
    return &(&self.search_stack)[STACK_PADDING + self.ply - 1];
}

fn curEvalState(self: *Searcher) *evaluation.State {
    return &self.evalStateRoot()[self.ply];
}

fn searchStackRoot(self: *Searcher) [*]StackEntry {
    return (&self.search_stack)[STACK_PADDING..];
}

fn evalStateRoot(self: *Searcher) [*]evaluation.State {
    return (&self.eval_states)[0..];
}

fn drawScore(self: *const Searcher, comptime stm: Colour) i16 {
    _ = stm;
    _ = self;
    return 0;
}

fn makeMove(self: *Searcher, comptime stm: Colour, move: Move) void {
    const old_stack_entry = self.prevStackEntry();
    const prev_stack_entry = self.curStackEntry();
    const prev_eval_state = self.curEvalState();
    self.ply += 1;
    const new_stack_entry = self.curStackEntry();
    const new_eval_state = self.curEvalState();
    const board = &prev_stack_entry.board;

    new_eval_state.* = prev_eval_state.*;
    if (self.ply == 0) {
        new_eval_state.initInPlace(board);
    } else {
        new_eval_state.update(board, &old_stack_entry.board);
    }
    new_stack_entry.init(
        board,
        TypedMove.fromBoard(board, move),
        prev_stack_entry.move,
        prev_stack_entry.evals,
    );
    new_stack_entry.board.makeMove(stm, move, new_eval_state);
    self.hashes[self.ply] = new_stack_entry.board.hash;
}

fn unmakeMove(self: *Searcher, comptime stm: Colour, move: Move) void {
    _ = stm;
    _ = move;
    self.ply -= 1;
}

fn makeNullMove(self: *Searcher, comptime stm: Colour) void {
    const old_stack_entry = self.prevStackEntry();
    const prev_stack_entry = self.curStackEntry();
    const prev_eval_state = self.curEvalState();
    self.ply += 1;
    const new_stack_entry = self.curStackEntry();
    const new_eval_state = self.curEvalState();
    const board = &prev_stack_entry.board;

    new_eval_state.* = prev_eval_state.*;
    new_eval_state.update(board, &old_stack_entry.board);
    new_stack_entry.init(
        board,
        TypedMove.init(),
        TypedMove.init(),
        prev_stack_entry.evals,
    );
    new_stack_entry.board.makeNullMove(stm);
    self.hashes[self.ply] = new_stack_entry.board.hash;
}

fn unmakeNullMove(self: *Searcher, comptime stm: Colour) void {
    _ = stm;
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

fn qsearch(self: *Searcher, comptime is_root: bool, comptime is_pv: bool, comptime stm: Colour, alpha_: i32, beta: i32) i16 {
    var alpha = alpha_;

    self.nodes += 1;
    if (self.stop or self.limits.checkSearch(self.nodes)) {
        self.stop = true;
        return 0;
    }
    const par = self.prevStackEntry();
    const cur = self.curStackEntry();
    const board = &cur.board;
    const is_in_check = board.checkers != 0;

    const tt_hash = board.hash;
    var tt_entry = self.readTT(tt_hash);
    const tt_hit = tt_entry.hash == tt_hash;
    if (!tt_hit) {
        tt_entry = .{};
    }
    const tt_score = evaluation.scoreFromTt(tt_entry.score, self.ply);
    if (!is_pv and evaluation.checkTTBound(tt_score, alpha, beta, tt_entry.score_type)) {
        return tt_score;
    }

    var raw_static_eval: i16 = evaluation.matedIn(self.ply);
    var corrected_static_eval: i16 = raw_static_eval;
    var static_eval: i16 = corrected_static_eval;
    if (!is_in_check) {
        raw_static_eval = evaluate(stm, board, &par.board, self.curEvalState());
        corrected_static_eval = self.histories.correct(board, cur.prev, raw_static_eval);
        cur.evals = cur.evals.updateWith(stm, corrected_static_eval);
        static_eval = corrected_static_eval;
        if (tt_hit and evaluation.checkTTBound(tt_score, static_eval, static_eval, tt_entry.score_type)) {
            static_eval = tt_score;
        }

        if (static_eval >= beta)
            return static_eval;
        if (static_eval > alpha)
            alpha = static_eval;
    }

    if (self.ply >= MAX_PLY - 1) {
        return static_eval;
    }

    var best_score = static_eval;
    var best_move = Move.init();
    var mp = MovePicker.initQs(
        board,
        &cur.movelist,
        &self.histories,
        tt_entry.move,
        cur.prev,
    );
    defer mp.deinit();

    const futility = static_eval + tunable_constants.qs_futility_margin;

    while (mp.next()) |scored_move| {
        const move = scored_move.move;
        if (!board.isLegal(stm, move)) {
            continue;
        }

        if (std.debug.runtime_safety and
            (mp.stage == .good_noisies or mp.stage == .bad_noisies))
        {
            std.debug.assert(board.isNoisy(move));
        }
        if (std.debug.runtime_safety and
            mp.stage == .good_noisies)
        {
            std.debug.assert(SEE.scoreMove(board, move, 0));
        }
        if (std.debug.runtime_safety and
            mp.stage == .bad_noisies)
        {
            std.debug.assert(!SEE.scoreMove(board, move, 0));
        }
        const skip_see_pruning = !std.debug.runtime_safety and mp.stage == .good_noisies;
        if (best_score > evaluation.matedIn(MAX_PLY)) {
            if (!is_in_check and futility <= alpha and !SEE.scoreMove(board, move, 1)) {
                best_score = @intCast(@max(best_score, futility));
                continue;
            }

            if (!is_in_check and
                (!skip_see_pruning and !SEE.scoreMove(board, move, tunable_constants.qs_see_threshold)))
            {
                std.debug.assert(mp.stage != .good_noisies);
                continue;
            }
        }

        self.makeMove(stm, move);
        const score = -self.qsearch(false, is_pv, stm.flipped(), -beta, -alpha);
        self.unmakeMove(stm, move);
        if (self.stop) {
            return 0;
        }

        if (score > best_score) {
            best_score = score;
            best_move = move;
            if (score > evaluation.matedIn(MAX_PLY)) {
                mp.skip_quiets = true;
            }
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

fn search(
    self: *Searcher,
    comptime is_root: bool,
    comptime is_pv: bool,
    comptime stm: Colour,
    alpha_original: i32,
    beta_original: i32,
    depth_: i32,
    cutnode: bool,
) i16 {
    var depth = depth_;
    var alpha = alpha_original;
    var beta = beta_original;

    self.nodes += 1;
    if (self.stop or (!is_root and self.limits.checkSearch(self.nodes))) {
        self.stop = true;
        return 0;
    }
    if (depth <= 0) {
        return self.qsearch(is_root, is_pv, stm, alpha, beta);
    }

    const par = self.prevStackEntry();
    const cur = self.curStackEntry();
    const board = &cur.board;
    const is_in_check = board.checkers != 0;

    if (self.ply >= MAX_PLY - 1) {
        return evaluate(stm, board, &par.board, self.curEvalState());
    }

    if (!is_root) {
        const worst_possible = evaluation.matedIn(self.ply);
        const best_possible = -evaluation.matedIn(self.ply + 1);

        alpha = @max(alpha, worst_possible);
        beta = @min(beta, best_possible);
        if (alpha >= beta) {
            return @intCast(alpha);
        }
    }

    if (!is_root and (board.halfmove >= 100 or self.isRepetition())) {
        if (board.halfmove >= 100) {
            if (is_in_check) {
                var rec: root.movegen.MoveListReceiver = .{};
                movegen.generateAllQuiets(stm, board, &rec);
                movegen.generateAllNoisies(stm, board, &rec);
                var has_legal = false;
                for (rec.vals.slice()) |move| {
                    if (board.isLegal(stm, move)) {
                        has_legal = true;
                        break;
                    }
                }
                if (has_legal) {
                    return 0;
                } else {
                    return evaluation.matedIn(self.ply);
                }
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    }

    const is_singular_search = !cur.excluded.isNull();
    const tt_hash = board.hash;
    var tt_entry: root.TTEntry = .{};
    var tt_hit = false;
    if (!is_singular_search) {
        tt_entry = self.readTT(tt_hash);

        tt_hit = tt_entry.hash == tt_hash;
        if (!tt_hit) {
            tt_entry = .{};
        }
    }

    const tt_score = evaluation.scoreFromTt(tt_entry.score, self.ply);
    if (tt_hit) {
        if (tt_entry.depth >= depth and !is_singular_search) {
            if (!is_pv) {
                if (evaluation.checkTTBound(tt_score, alpha, beta, tt_entry.score_type)) {
                    return tt_score;
                }
            }
        }
    }

    if (depth >= 4 and
        (is_pv or cutnode) and
        (tt_entry.move.isNull() or !tt_hit))
    {
        depth -= 1;
    }

    var improving = false;
    var raw_static_eval: i16 = evaluation.matedIn(self.ply);
    var corrected_static_eval = raw_static_eval;
    if (!is_in_check and !is_singular_search) {
        raw_static_eval = evaluate(stm, board, &par.board, self.curEvalState());
        corrected_static_eval = self.histories.correct(board, cur.prev, raw_static_eval);
        improving = cur.evals.isImprovement(stm, corrected_static_eval);
        cur.evals = cur.evals.updateWith(stm, corrected_static_eval);

        if (tt_hit and evaluation.checkTTBound(tt_score, corrected_static_eval, corrected_static_eval, tt_entry.score_type)) {
            cur.static_eval = tt_score;
        } else {
            cur.static_eval = corrected_static_eval;
        }
    }
    const static_eval = cur.static_eval;

    if (!is_pv and
        beta >= evaluation.matedIn(MAX_PLY) and
        !is_in_check and
        !is_singular_search)
    {
        // cutnodes are expected to fail high
        // if we are re-searching this then its likely because its important, so otherwise we reduce more
        // basically we reduce more if this node is likely unimportant
        const no_tthit_cutnode = !tt_hit and cutnode;
        if (depth <= 5 and
            static_eval >= beta +
                tunable_constants.rfp_margin * (depth + @intFromBool(!improving)) -
                tunable_constants.rfp_cutnode_margin * @intFromBool(no_tthit_cutnode))
        {
            return static_eval;
        }
        if (depth <= 3 and static_eval + tunable_constants.razoring_margin * depth <= alpha) {
            const razor_score = self.qsearch(
                is_root,
                is_pv,
                stm,
                alpha,
                alpha + 1,
            );

            if (razor_score <= alpha) {
                return razor_score;
            }
        }

        const non_pk = board.occupancyFor(stm) & ~(board.pawns() | board.kings());

        if (depth >= 4 and
            static_eval >= beta and
            non_pk != 0 and
            !cur.prev.move.isNull())
        {
            self.prefetchTT(board.hash ^ root.zobrist.turn());
            var nmp_reduction = tunable_constants.nmp_base + depth * tunable_constants.nmp_mult;
            nmp_reduction += @min(tunable_constants.nmp_eval_reduction_max, (static_eval - beta) * tunable_constants.nmp_eval_reduction_scale);
            nmp_reduction >>= 13;

            self.makeNullMove(stm);
            const nmp_score = -self.search(
                false,
                false,
                stm.flipped(),
                -beta,
                -beta + 1,
                depth - nmp_reduction,
                !cutnode,
            );
            self.unmakeNullMove(stm);

            if (nmp_score >= beta) {
                return if (evaluation.isMateScore(nmp_score)) @intCast(beta) else nmp_score;
            }
        }
    }

    var mp = MovePicker.init(
        board,
        &cur.movelist,
        &self.histories,
        if (is_singular_search) cur.excluded else tt_entry.move,
        cur.prev,
        is_singular_search,
    );
    defer mp.deinit();
    var best_move = Move.init();
    var best_score = -evaluation.inf_score;
    var searched_quiets: std.BoundedArray(Move, 64) = .{};
    var searched_noisies: std.BoundedArray(Move, 64) = .{};
    var score_type: ScoreType = .upper;
    var num_legal: u8 = 0;
    while (mp.next()) |scored_move| {
        const move = scored_move.move;
        if (move == cur.excluded) {
            continue;
        }
        self.prefetchTT(board.roughHashAfter(move));
        if (!board.isLegal(stm, move)) {
            continue;
        }

        const is_quiet = board.isQuiet(move);
        if (std.debug.runtime_safety and
            (mp.stage == .good_noisies or mp.stage == .bad_noisies))
        {
            std.debug.assert(!is_quiet);
        }
        if (std.debug.runtime_safety and
            mp.stage == .good_noisies)
        {
            std.debug.assert(SEE.scoreMove(board, move, 0));
        }
        if (std.debug.runtime_safety and
            mp.stage == .bad_noisies)
        {
            std.debug.assert(!SEE.scoreMove(board, move, 0));
        }
        const skip_see_pruning = !std.debug.runtime_safety and mp.stage == .good_noisies;
        const history_score = if (is_quiet) self.histories.readQuiet(board, move, cur.prev) else self.histories.readNoisy(board, move);
        if (!is_root and !is_pv and best_score >= evaluation.matedIn(MAX_PLY)) {
            if (is_quiet) {
                const lmp_mult = if (improving) tunable_constants.lmp_improving_mult else tunable_constants.lmp_standard_mult;
                if (num_legal * tunable_constants.lmp_legal_mult + tunable_constants.lmp_legal_base >= depth * depth * lmp_mult) {
                    mp.skip_quiets = true;
                    continue;
                }

                if (depth <= 3 and history_score < depth * tunable_constants.history_pruning_mult) {
                    mp.skip_quiets = true;
                    continue;
                }

                if (!is_in_check and
                    depth <= 6 and
                    @abs(alpha) < 2000 and
                    static_eval + tunable_constants.fp_base + depth * tunable_constants.fp_mult <= alpha)
                {
                    mp.skip_quiets = true;
                    continue;
                }
            }

            const see_pruning_thresh = if (is_quiet)
                tunable_constants.see_quiet_pruning_mult * depth
            else
                tunable_constants.see_noisy_pruning_mult * depth * depth;

            if (!skip_see_pruning and
                !SEE.scoreMove(board, move, see_pruning_thresh))
            {
                std.debug.assert(mp.stage != .good_noisies);
                continue;
            }
        }

        var extension: i32 = 0;
        if (!is_root and
            depth >= tunable_constants.singular_depth_limit and
            move == tt_entry.move and
            !is_singular_search and
            tt_entry.depth + tunable_constants.singular_tt_depth_margin >= depth and
            tt_entry.score_type != .upper)
        {
            const s_beta = @max(evaluation.matedIn(0) + 1, tt_entry.score - (depth * tunable_constants.singular_beta_mult >> 5));
            const s_depth = (depth - 1) * tunable_constants.singular_depth_mult >> 5;

            cur.excluded = move;
            const s_score = self.search(
                false,
                is_pv,
                stm,
                s_beta - 1,
                s_beta,
                s_depth,
                cutnode,
            );
            cur.excluded = Move.init();

            if (s_score < s_beta) {
                extension += 1;

                if (!is_pv and s_score < s_beta - tunable_constants.singular_dext_margin) {
                    extension += 1;
                }
            } else if (s_beta >= beta) {
                return @intCast(s_beta);
            } else if (tt_entry.score >= beta) {
                extension -= 1;
            } else if (cutnode) {
                extension -= 2;
            }
        }
        num_legal += 1;

        if (std.debug.runtime_safety) {
            if (std.mem.count(Move, searched_noisies.slice(), &.{move}) != 0) {
                unreachable;
            }
            if (std.mem.count(Move, searched_quiets.slice(), &.{move}) != 0) {
                unreachable;
            }
        }

        self.makeMove(stm, move);

        const gives_check = self.curStackEntry().board.checkers != 0;
        if (gives_check) {
            extension += 1;
        }
        const score = blk: {
            const node_count_before: u64 = if (is_root) self.nodes else undefined;
            defer if (is_root) self.limits.updateNodeCounts(move, self.nodes - node_count_before);

            const corrhists_squared = self.histories.squaredCorrectionTerms(board, cur.prev);

            var s: i16 = 0;
            const new_depth = depth + extension - 1;
            if (depth >= 3 and num_legal > 1) {
                const history_lmr_mult: i64 = if (is_quiet) tunable_constants.lmr_quiet_history_mult else tunable_constants.lmr_noisy_history_mult;
                var reduction: i32 = tunable_constants.lmr_base;
                reduction += std.math.log2_int(u32, @intCast(depth)) * tunable_constants.lmr_log_mult * @as(i32, std.math.log2_int(u32, num_legal)) >> 2;
                reduction -= tunable_constants.lmr_pv_mult * @intFromBool(is_pv);
                reduction += tunable_constants.lmr_cutnode_mult * @intFromBool(cutnode);
                reduction -= tunable_constants.lmr_improving_mult * @intFromBool(improving);
                reduction -= @intCast(history_lmr_mult * history_score >> 13);
                reduction -= @intCast(tunable_constants.lmr_corrhist_mult * corrhists_squared >> 32);
                reduction >>= 10;

                const clamped_reduction = std.math.clamp(reduction, 1, depth - 1);

                const reduced_depth = depth + extension - clamped_reduction;

                s = -self.search(
                    false,
                    false,
                    stm.flipped(),
                    -alpha - 1,
                    -alpha,
                    reduced_depth,
                    true,
                );
                if (self.stop) {
                    break :blk 0;
                }

                if (s > alpha and clamped_reduction > 1) {
                    s = -self.search(
                        false,
                        false,
                        stm.flipped(),
                        -alpha - 1,
                        -alpha,
                        new_depth,
                        !cutnode,
                    );
                    if (self.stop) {
                        break :blk 0;
                    }
                }
            } else if (!is_pv or num_legal > 1) {
                s = -self.search(
                    false,
                    false,
                    stm.flipped(),
                    -alpha - 1,
                    -alpha,
                    new_depth,
                    !cutnode,
                );
                if (self.stop) {
                    break :blk 0;
                }
            }
            if (is_pv and (num_legal == 1 or s > alpha)) {
                s = -self.search(
                    false,
                    true,
                    stm.flipped(),
                    -beta,
                    -alpha,
                    new_depth,
                    false,
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
            if (is_root) {
                self.root_move = move;
                self.root_score = best_score;
            }
            if (is_pv) {
                self.updatePv(move);
            }
            alpha = score;
            score_type = .exact;
            if (score >= beta) {
                score_type = .lower;
                const bonus = root.history.bonus(depth);
                const penalty = -root.history.penalty(depth);
                if (is_quiet) {
                    self.histories.updateQuiet(board, move, cur.prev, bonus);
                    for (searched_quiets.slice()) |searched_move| {
                        if (searched_move == move) break;
                        self.histories.updateQuiet(board, searched_move, cur.prev, penalty);
                    }
                } else {
                    self.histories.updateNoisy(board, move, bonus);
                }
                for (searched_noisies.slice()) |searched_move| {
                    if (searched_move == move) break;
                    self.histories.updateNoisy(board, searched_move, penalty);
                }
                break;
            }
        }
    }

    if (best_move.isNull()) {
        const mated_score = evaluation.matedIn(self.ply);
        return if (is_in_check) mated_score else 0;
    }

    if (!is_singular_search) {
        if (score_type == .upper and tt_hit) {
            best_move = tt_entry.move;
        }
        self.writeTT(
            tt_hash,
            best_move,
            evaluation.scoreToTt(best_score, self.ply),
            score_type,
            depth,
        );

        if (!is_in_check and (best_score <= alpha_original or board.isQuiet(best_move))) {
            if (corrected_static_eval != best_score and
                evaluation.checkTTBound(best_score, corrected_static_eval, corrected_static_eval, score_type))
            {
                self.histories.updateCorrection(board, cur.prev, corrected_static_eval, best_score, depth);
            }
        }
    }

    return best_score;
}

const InfoType = enum {
    completed,
    lower,
    upper,
};

fn writeInfo(self: *Searcher, score: i16, depth: i32, tp: InfoType) void {
    const elapsed = @max(1, self.limits.timer.read());
    const type_str = switch (tp) {
        .completed => "",
        .lower => " lowerbound",
        .upper => " upperbound",
    };
    var nodes: u64 = 0;
    for (engine.searchers) |searcher| {
        nodes += searcher.nodes;
    }
    var pv_buf: [6 * 256 + 32]u8 = undefined;
    var fixed_buffer_pv_writer = std.io.fixedBufferStream(&pv_buf);
    {
        var board = self.searchStackRoot()[0].board;
        for (self.searchStackRoot()[0].pv.slice()) |pv_move| {
            fixed_buffer_pv_writer.writer().print("{s} ", .{pv_move.toString(&board).slice()}) catch unreachable;
            board.stm = board.stm.flipped();
        }
    }
    write("info depth {} score {s}{s} nodes {} nps {} time {} pv {s}\n", .{
        depth,
        evaluation.formatScore(score).slice(),
        type_str,
        nodes,
        @as(u128, nodes) * std.time.ns_per_s / elapsed,
        (elapsed + std.time.ns_per_ms / 2) / std.time.ns_per_ms,
        std.mem.trim(u8, fixed_buffer_pv_writer.getWritten(), &std.ascii.whitespace),
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
    self.search_stack[0].board = Board{};
    self.searchStackRoot()[0].init(&board, TypedMove.init(), TypedMove.init(), .{});
    self.evalStateRoot()[0].initInPlace(&board);
    if (params.needs_full_reset) {
        self.histories.reset();
    }
    self.limits.resetNodeCounts();
    evaluation.initThreadLocals();
}

pub fn startSearch(self: *Searcher, params: Params, is_main_thread: bool, quiet: bool) void {
    self.init(params);
    var previous_score: i32 = 0;
    var completed_depth: i32 = 0;
    for (1..MAX_PLY) |d| {
        const depth: i32 = @intCast(d);

        var window = tunable_constants.aspiration_initial;
        if (d == 1) {
            window = evaluation.inf_score;
        }
        var aspiration_lower = @max(previous_score - window, -evaluation.inf_score);
        var aspiration_upper = @min(previous_score + window, evaluation.inf_score);
        var failhigh_reduction: i32 = 0;
        var score = -evaluation.inf_score;
        switch (params.board.stm) {
            inline else => |stm| while (true) : (window = (window * tunable_constants.aspiration_multiplier) >> 10) {
                score = self.search(
                    true,
                    true,
                    stm,
                    aspiration_lower,
                    aspiration_upper,
                    @max(1, depth - failhigh_reduction),
                    false,
                );
                if (self.stop or evaluation.isMateScore(score)) {
                    break;
                }
                const should_print = is_main_thread and self.limits.shouldPrintInfoInAspiration();
                if (score >= aspiration_upper) {
                    aspiration_lower = @max(score - window, -evaluation.inf_score);
                    aspiration_upper = @min(score + window, evaluation.inf_score);
                    failhigh_reduction = @min(failhigh_reduction + 1, 4);
                    if (should_print) {
                        if (!quiet) {
                            self.writeInfo(score, depth, .lower);
                        }
                    }
                } else if (score <= aspiration_lower) {
                    aspiration_lower = @max(score - window, -evaluation.inf_score);
                    aspiration_upper = @min(score + window, evaluation.inf_score);
                    failhigh_reduction >>= 1;
                    if (should_print) {
                        if (!quiet) {
                            self.writeInfo(score, depth, .upper);
                        }
                    }
                } else {
                    break;
                }
            },
        }
        previous_score = score;

        completed_depth = depth;
        if (is_main_thread) {
            if (!quiet) {
                self.writeInfo(self.root_score, depth, .completed);
            }
        }
        if (self.stop or self.limits.checkRoot(self.nodes, depth, self.root_move)) {
            break;
        }
    }

    if (is_main_thread) {
        if (!quiet) {
            write("bestmove {s}\n", .{self.root_move.toString(&params.board).slice()});
        }
        engine.stopSearch();
    }
}
