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
const TTEntry = root.TTEntry;
pub const MAX_PLY = 256;
pub const MAX_HALFMOVE = 100;

pub const Params = struct {
    board: Board,
    limits: Limits,
    previous_hashes: std.BoundedArray(u64, 200),
    needs_full_reset: bool = false,
    syzygy_depth: u8 = 0,
    normalize: bool,
};

const EvalPair = struct {
    white: ?i16 = null,
    black: ?i16 = null,
    prev_white: ?i16 = null,
    prev_black: ?i16 = null,

    pub fn updateWith(self: EvalPair, comptime col: Colour, val: i16) EvalPair {
        if (col == .white) {
            return .{
                .white = val,
                .black = self.black,
                .prev_white = self.white,
                .prev_black = self.prev_black,
            };
        } else {
            return .{
                .white = self.white,
                .black = val,
                .prev_white = self.prev_white,
                .prev_black = self.black,
            };
        }
    }

    inline fn curFor(self: EvalPair, col: Colour) ?i16 {
        return if (col == .white) self.white else self.black;
    }

    inline fn prevFor(self: EvalPair, col: Colour) ?i16 {
        return if (col == .white) self.prev_white else self.prev_black;
    }

    pub fn improving(self: EvalPair, col: Colour) bool {
        const prev = self.prevFor(col) orelse return false;
        const cur = self.curFor(col) orelse return false;
        return cur > prev;
    }

    pub fn worsening(self: EvalPair, col: Colour) bool {
        const prev = self.prevFor(col) orelse return false;
        const cur = self.curFor(col) orelse return false;
        return cur < prev;
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
stop: std.atomic.Value(bool),
previous_hashes: std.BoundedArray(u64, MAX_HALFMOVE * 2),
tt: []TTEntry,
pvs: [MAX_PLY]std.BoundedArray(Move, 256),
is_main_thread: bool = true,
seldepth: u8,
ttage: u5 = 0,
syzygy_depth: u8 = 1,
normalize: bool = false,
tbhits: u64 = 0,
histories: history.HistoryTable,

inline fn ttIndex(self: *const Searcher, hash: u64) usize {
    return @intCast(@as(u128, hash) * self.tt.len >> 64);
}

pub fn writeTT(
    self: *Searcher,
    tt_pv: bool,
    hash: u64,
    move: Move,
    score: i16,
    score_type: ScoreType,
    depth: i32,
    raw_static_eval: i16,
) void {
    const entry = &self.tt[self.ttIndex(hash)];

    if (!(score_type == .exact or
        !entry.hashEql(hash) or
        self.ttage != entry.flags.age or
        depth + 4 > entry.depth))
    {
        return;
    }

    entry.* = TTEntry{
        .score = score,
        .flags = .{ .score_type = score_type, .is_pv = tt_pv, .age = self.ttage },
        .move = move,
        .hash = TTEntry.compress(hash),
        .depth = @intCast(@max(0, depth)),
        .raw_static_eval = raw_static_eval,
    };
}

fn rawEval(self: *Searcher, comptime stm: Colour) i16 {
    const hash = self.stackEntry(0).board.getHashWithHalfmove();
    const eval = evaluate(stm, &self.stackEntry(0).board, &self.stackEntry(-1).board, self.evalState(0));
    self.writeTT(
        false,
        hash,
        Move.init(),
        0,
        .none,
        0,
        eval,
    );
    return eval;
}

pub fn prefetch(self: *const Searcher, move: Move) void {
    const board = &self.stackEntry(0).board;
    @prefetch(&self.tt[self.ttIndex(board.roughHashAfter(move, true))], .{});
}

pub fn readTT(self: *const Searcher, hash: u64) TTEntry {
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
    failhighs: u8,

    pub fn init(self: *StackEntry, board_: *const Board, move_: TypedMove, prev_: TypedMove, prev_evals: EvalPair) void {
        self.board = board_.*;
        self.move = move_;
        self.prev = prev_;
        self.evals = prev_evals;
        self.excluded = Move.init();
        self.static_eval = 0;
        self.failhighs = 0;
    }
};

const Searcher = @This();

fn updatePv(self: *Searcher, move: Move) void {
    const cur = &self.pvs[self.ply];
    cur.len = self.ply + 1;
    cur.slice()[self.ply] = move;
    if (self.ply + 1 < MAX_PLY) {
        const next = &self.pvs[self.ply + 1];
        const new_len = @max(cur.len, next.len);
        for (cur.len..new_len) |i| {
            cur.buffer[i] = next.buffer[i];
        }
        cur.len = new_len;
    }
}

fn stackEntry(self: anytype, offset: anytype) root.inheritConstness(@TypeOf(self), *StackEntry) {
    return &(&self.search_stack)[@intCast(STACK_PADDING + @as(i64, self.ply) + offset)];
}

fn evalState(self: anytype, offset: anytype) root.inheritConstness(@TypeOf(self), *evaluation.State) {
    return &(&self.eval_states)[@intCast(@as(i64, self.ply) + offset)];
}

fn searchStackRoot(self: anytype) root.inheritConstness(@TypeOf(self), [*]StackEntry) {
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

fn applyContempt(self: *const Searcher, raw_static_eval: i16) i16 {
    // TODO: actually make it configurable
    const contempt: i32 = 0;
    return evaluation.clampScore(if (self.ply % 2 == 0) raw_static_eval + contempt else raw_static_eval - contempt);
}

fn makeMove(self: *Searcher, comptime stm: Colour, move: Move) void {
    const old_stack_entry = self.stackEntry(-1);
    const prev_stack_entry = self.stackEntry(0);
    const prev_eval_state = self.evalState(0);
    const new_stack_entry = self.stackEntry(1);
    const new_eval_state = self.evalState(1);
    const board = &prev_stack_entry.board;

    new_eval_state.* = prev_eval_state.*;
    new_eval_state.update(board, &old_stack_entry.board);
    new_stack_entry.init(
        board,
        TypedMove.fromBoard(board, move),
        prev_stack_entry.move,
        prev_stack_entry.evals,
    );
    self.ply += 1;
    self.pvs[self.ply].len = 0;
    new_stack_entry.board.makeMove(stm, move, new_eval_state);
    self.hashes[self.ply] = new_stack_entry.board.hash;
}

fn unmakeMove(self: *Searcher, comptime stm: Colour, move: Move) void {
    _ = stm;
    _ = move;
    self.ply -= 1;
}

fn makeNullMove(self: *Searcher, comptime stm: Colour) void {
    const old_stack_entry = self.stackEntry(-1);
    const prev_stack_entry = self.stackEntry(0);
    const prev_eval_state = self.evalState(0);
    const new_stack_entry = self.stackEntry(1);
    const new_eval_state = self.evalState(1);
    const board = &prev_stack_entry.board;
    new_eval_state.* = prev_eval_state.*;
    new_eval_state.update(board, &old_stack_entry.board);
    new_stack_entry.init(
        board,
        TypedMove.init(),
        TypedMove.init(),
        prev_stack_entry.evals,
    );
    self.ply += 1;
    self.pvs[self.ply].len = 0;
    new_stack_entry.board.makeNullMove(stm);
    self.hashes[self.ply] = new_stack_entry.board.hash;
}

fn unmakeNullMove(self: *Searcher, comptime stm: Colour) void {
    _ = stm;
    self.ply -= 1;
}

fn isRepetition(self: *Searcher) bool {
    const board = &self.stackEntry(0).board;

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

fn qsearch(
    self: *Searcher,
    comptime is_root: bool,
    comptime is_pv: bool,
    comptime stm: Colour,
    alpha_original: i32,
    beta_original: i32,
) i16 {
    if (is_pv) {
        self.seldepth = @max(self.seldepth, self.ply + 1);
    }
    var alpha = alpha_original;
    var beta = beta_original;
    self.nodes += 1;
    if (self.stop.load(.acquire) or (!is_root and self.is_main_thread and self.limits.checkSearch(self.nodes))) {
        self.stop.store(true, .release);
        return 0;
    }
    const cur: *StackEntry = self.stackEntry(0);
    const board = &cur.board;
    const is_in_check = board.checkers != 0;

    const tt_hash = board.getHashWithHalfmove();
    var tt_entry = self.readTT(tt_hash);
    const tt_hit = tt_entry.hashEql(tt_hash);
    if (!tt_hit) {
        tt_entry = .{};
    }
    const tt_score = evaluation.scoreFromTt(tt_entry.score, self.ply);
    if (!is_pv and evaluation.checkTTBound(tt_score, alpha, beta, tt_entry.flags.score_type)) {
        if (tt_score >= beta and !evaluation.isMateScore(tt_score)) {
            return @intCast(tt_score + @divTrunc((beta - tt_score) * tunable_constants.qs_tt_fail_medium, 1024));
        }

        return tt_score;
    }
    const tt_pv = is_pv or tt_entry.flags.is_pv;

    var raw_static_eval: i16 = evaluation.matedIn(self.ply);
    var corrected_static_eval: i16 = raw_static_eval;
    var static_eval: i16 = corrected_static_eval;
    if (!is_in_check) {
        raw_static_eval = if (tt_hit and !evaluation.isMateScore(tt_entry.raw_static_eval)) tt_entry.raw_static_eval else self.rawEval(stm);
        corrected_static_eval = self.histories.correct(board, cur.move, self.applyContempt(raw_static_eval));
        cur.evals = cur.evals.updateWith(stm, corrected_static_eval);
        static_eval = corrected_static_eval;
        if (tt_hit and evaluation.checkTTBound(tt_score, static_eval, static_eval, tt_entry.flags.score_type)) {
            static_eval = tt_score;
        }

        if (static_eval >= beta) {
            return @intCast(static_eval + @divTrunc((beta - static_eval) * tunable_constants.standpat_fail_medium, 1024));
        }
        if (static_eval > alpha) {
            alpha = static_eval;
        }
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

    if (self.ply >= MAX_PLY - 1) {
        return static_eval;
    }

    var best_score = static_eval;
    var best_move = Move.init();
    var score_type: ScoreType = .upper;
    var mp = MovePicker.initQs(
        board,
        &cur.movelist,
        &self.histories,
        tt_entry.move,
        cur.move,
        cur.prev,
    );
    defer mp.deinit();
    var num_searched: u8 = 0;

    const futility = static_eval + tunable_constants.qs_futility_margin;

    const previous_move_destination = cur.move.move.to();

    while (mp.next()) |scored_move| {
        const move = scored_move.move;
        self.prefetch(move);
        if (!board.isLegal(stm, move)) {
            continue;
        }

        if (std.debug.runtime_safety and
            (mp.stage == .good_noisies or mp.stage == .bad_noisies))
        {
            std.debug.assert(board.isNoisy(move));
        }
        const skip_see_pruning = !std.debug.runtime_safety and mp.stage == .good_noisies;
        const is_recapture = move.to() == previous_move_destination;
        if (best_score > evaluation.matedIn(MAX_PLY)) {
            const history_score = self.histories.readNoisy(board, move);
            if (!is_in_check and
                num_searched >= 2 and
                history_score < -4000)
            {
                break;
            }
            if (!is_in_check and futility <= alpha and
                !SEE.scoreMove(board, move, 1, .pruning) and
                !is_recapture)
            {
                best_score = @intCast(@max(best_score, futility));
                continue;
            }

            if (!is_in_check and
                (!skip_see_pruning and !SEE.scoreMove(board, move, tunable_constants.qs_see_threshold, .pruning)))
            {
                continue;
            }
        }

        num_searched += 1;
        self.makeMove(stm, move);
        const score = -self.qsearch(false, is_pv, stm.flipped(), -beta, -alpha);
        self.unmakeMove(stm, move);
        if (self.stop.load(.acquire)) {
            return 0;
        }

        if (score > best_score) {
            best_score = score;
            if (score > evaluation.matedIn(MAX_PLY)) {
                mp.skip_quiets = true;
            }
        }

        if (score > alpha) {
            best_move = move;
            alpha = score;
            if (score >= beta) {
                score_type = .lower;
                break;
            }
        }
    }

    self.writeTT(
        tt_pv,
        tt_hash,
        best_move,
        evaluation.scoreToTt(best_score, self.ply),
        score_type,
        0,
        raw_static_eval,
    );
    return best_score;
}

fn float(x: anytype) f64 {
    return switch (@typeInfo(@TypeOf(x))) {
        .int, .comptime_int => @floatFromInt(x),
        .float, .comptime_float => @floatCast(x),
        else => @compileError(std.fmt.comptimePrint("unsupported type {}\n", .{@TypeOf(x)})),
    };
}

fn int(comptime T: type, x: anytype) T {
    return switch (@typeInfo(@TypeOf(x))) {
        .int, .comptime_int => @intCast(x),
        .float, .comptime_float => @intFromFloat(x),
        else => @compileError(std.fmt.comptimePrint("unsupported type {}\n", .{@TypeOf(x)})),
    };
}

fn preCalculateBaseLMR(depth: i32, legal: i32, is_quiet: bool) i32 {
    const base = if (is_quiet) tunable_constants.lmr_quiet_base else tunable_constants.lmr_noisy_base;
    const log_mult = if (is_quiet) tunable_constants.lmr_quiet_log_mult else tunable_constants.lmr_noisy_log_mult;
    const depth_mult = if (is_quiet) tunable_constants.lmr_quiet_depth_mult else tunable_constants.lmr_noisy_depth_mult;
    const legal_mult = if (is_quiet) tunable_constants.lmr_quiet_legal_mult else tunable_constants.lmr_noisy_legal_mult;
    const depth_offs = if (is_quiet) tunable_constants.lmr_quiet_depth_offs else tunable_constants.lmr_noisy_depth_offs;
    const legal_offs = if (is_quiet) tunable_constants.lmr_quiet_legal_offs else tunable_constants.lmr_noisy_legal_offs;

    var reduction: i32 = base;

    const depth_factor = int(i64, @log2(float(depth)) * float(depth_mult) + float(depth_offs));
    const legal_factor = int(i64, @log2(float(legal)) * float(legal_mult) + float(legal_offs));
    reduction += @intCast(depth_factor * log_mult * legal_factor >> 20);

    return reduction;
}

fn calculateBaseLMR(depth: i32, legal: u8, is_quiet: bool) i32 {
    if (root.tuning.do_tuning) {
        return preCalculateBaseLMR(@min(depth, 32), @min(legal, 32), is_quiet);
    } else {
        const table = comptime blk: {
            @setEvalBranchQuota(1 << 30);
            var res: [32][32][2]u16 = undefined;
            for (1..33) |d| {
                for (1..33) |l| {
                    for (0..2) |q| {
                        res[d - 1][l - 1][q] = preCalculateBaseLMR(d, l, q == 1);
                    }
                }
            }
            break :blk res;
        };
        return (&(&(&table)[@intCast(@min(depth - 1, 31))])[@min(legal - 1, 31)])[@intFromBool(is_quiet)];
    }
}

inline fn lmrConvolve(comptime N: usize, params: [N]bool) i32 {
    var res: i32 = 0;
    comptime var two = 0;
    comptime var three = 0;
    inline for (0..N) |i| {
        res += root.tuning.factorized_lmr.one[i] * @intFromBool(params[i]);
        inline for (i + 1..N) |j| {
            res += root.tuning.factorized_lmr.two[two] * @intFromBool(params[i] and params[j]);
            inline for (j + 1..N) |k| {
                res += root.tuning.factorized_lmr.three[three] * @intFromBool(params[i] and params[j] and params[k]);
                three += 1;
            }
            two += 1;
        }
    }
    return res;
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
    if (self.stop.load(.acquire) or (!is_root and self.is_main_thread and self.limits.checkSearch(self.nodes))) {
        self.stop.store(true, .release);
        return 0;
    }

    const cur: *StackEntry = self.stackEntry(0);
    const board = &cur.board;
    const is_in_check = board.checkers != 0;
    if (depth <= 0 and !is_in_check) {
        return self.qsearch(is_root, is_pv, stm, alpha, beta);
    }

    if (is_pv) {
        self.seldepth = @max(self.seldepth, self.ply + 1);
    }
    if (self.ply >= MAX_PLY - 1) {
        return self.rawEval(stm);
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
                var rec: movegen.MoveListReceiver = .{};
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
    const tt_hash = board.getHashWithHalfmove();
    var tt_entry: TTEntry = .{};
    var tt_hit = false;
    if (!is_singular_search) {
        tt_entry = self.readTT(tt_hash);

        tt_hit = tt_entry.hashEql(tt_hash);
        if (!tt_hit) {
            tt_entry = .{};
        }
    }
    const has_tt_move = tt_hit and !tt_entry.move.isNull();
    const tt_pv = is_pv or (tt_hit and tt_entry.flags.is_pv);
    const tt_score = evaluation.scoreFromTt(tt_entry.score, self.ply);
    if (tt_hit) {
        if (tt_entry.depth >= depth and !is_singular_search) {
            if (!is_pv) {
                if (evaluation.checkTTBound(tt_score, alpha, beta, tt_entry.flags.score_type)) {
                    if (tt_score >= beta and !evaluation.isMateScore(tt_score)) {
                        return @intCast(tt_score + @divTrunc((beta - tt_score) * tunable_constants.tt_fail_medium, 1024));
                    }

                    return tt_score;
                }
            }
        }
    }

    if (!is_root and cur.excluded.isNull() and depth >= self.syzygy_depth) {
        if (root.pyrrhic.probeWDL(board)) |result| {
            self.tbhits += 1;
            const tp: ScoreType, const score = switch (result) {
                .win => .{ .lower, evaluation.tbWin(self.ply) },
                .loss => .{ .upper, evaluation.tbLoss(self.ply) },
                .draw => .{ .exact, self.drawScore(stm) },
            };
            if (evaluation.checkTTBound(score, alpha, beta, tp)) {
                self.writeTT(tt_pv, tt_hash, Move.init(), score, tp, depth, evaluation.matedIn(self.ply));
                return score;
            }
        }
    }

    if (depth >= 4 and
        (is_pv or cutnode) and
        !has_tt_move)
    {
        depth -= 1;
    }
    var improving = false;
    var opponent_worsening = false;
    var raw_static_eval: i16 = evaluation.matedIn(self.ply);
    var corrected_static_eval = raw_static_eval;
    if (!is_in_check and !is_singular_search) {
        raw_static_eval = if (tt_hit and !evaluation.isMateScore(tt_entry.raw_static_eval)) tt_entry.raw_static_eval else self.rawEval(stm);
        corrected_static_eval = self.histories.correct(board, cur.move, self.applyContempt(raw_static_eval));
        cur.evals = cur.evals.updateWith(stm, corrected_static_eval);
        improving = cur.evals.improving(stm);
        opponent_worsening = cur.evals.worsening(stm.flipped());

        if (tt_hit and evaluation.checkTTBound(
            tt_score,
            corrected_static_eval,
            corrected_static_eval,
            tt_entry.flags.score_type,
        )) {
            cur.static_eval = tt_score;
        } else {
            cur.static_eval = corrected_static_eval;
        }
    }
    const eval = cur.static_eval;

    if (!is_pv and
        beta >= evaluation.matedIn(MAX_PLY) and
        !is_in_check and
        !is_singular_search)
    {
        const corrplexity = self.histories.squaredCorrectionTerms(board, cur.move);
        // cutnodes are expected to fail high
        // if we are re-searching this then its likely because its important, so otherwise we reduce more
        // basically we reduce more if this node is likely unimportant
        const no_tthit_cutnode = !tt_hit and cutnode;
        if (depth <= 6 and
            eval >= beta +
                tunable_constants.rfp_base +
                tunable_constants.rfp_mult * depth -
                tunable_constants.rfp_improving_margin * @intFromBool(improving) -
                tunable_constants.rfp_worsening_margin * @intFromBool(opponent_worsening) -
                tunable_constants.rfp_cutnode_margin * @intFromBool(no_tthit_cutnode) +
                (corrplexity * tunable_constants.rfp_corrplexity_mult >> 32))
        {
            return @intCast(eval + @divTrunc((beta - eval) * tunable_constants.rfp_fail_medium, 1024));
        }
        if (depth <= 3 and eval + tunable_constants.razoring_margin * depth <= alpha) {
            const razor_score = self.qsearch(
                is_root,
                is_pv,
                stm,
                alpha,
                alpha + 1,
            );

            return razor_score;
        }

        const non_pk = board.occupancyFor(stm) & ~(board.pawns() | board.kings());

        if (depth >= 4 and
            eval >= beta and
            non_pk != 0 and
            !cur.move.move.isNull())
        {
            self.prefetch(Move.init());
            var nmp_reduction = tunable_constants.nmp_base + depth * tunable_constants.nmp_mult;
            nmp_reduction += @min(tunable_constants.nmp_eval_reduction_max, (eval - beta) * tunable_constants.nmp_eval_reduction_scale);
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
        cur.move,
        cur.prev,
        is_singular_search,
    );
    defer mp.deinit();
    var best_move = Move.init();
    var best_score = -evaluation.inf_score;
    var searched_quiets: std.BoundedArray(Move, 64) = .{};
    var searched_noisies: std.BoundedArray(Move, 64) = .{};
    var num_searched_quiets: u8 = 0;
    var score_type: ScoreType = .upper;
    var num_searched: u8 = 0;
    self.searchStackRoot()[self.ply + 2].failhighs = 0;
    var num_legal: u8 = 0;
    while (mp.next()) |scored_move| {
        const move = scored_move.move;
        if (move == cur.excluded) {
            continue;
        }
        self.prefetch(move);
        if (!board.isLegal(stm, move)) {
            continue;
        }
        num_legal += 1;

        if (is_root and !board.isPseudoLegal(stm, move)) {
            write("info string ERROR: Illegal move in root {s} {s}\n", .{ board.toFen().slice(), move.toString(board).slice() });
            continue;
        }
        const is_quiet = board.isQuiet(move);
        if (std.debug.runtime_safety and
            (mp.stage == .good_noisies or mp.stage == .bad_noisies))
        {
            std.debug.assert(!is_quiet);
        }
        const skip_see_pruning = !std.debug.runtime_safety and mp.stage == .good_noisies;
        const history_score = if (is_quiet) self.histories.readQuietPruning(board, move, cur.move, cur.prev) else self.histories.readNoisy(board, move);

        if (!is_root and !is_pv and best_score >= evaluation.matedIn(MAX_PLY)) {
            const history_lmr_mult: i64 = if (is_quiet) tunable_constants.lmr_quiet_history_mult else tunable_constants.lmr_noisy_history_mult;
            var base_lmr = calculateBaseLMR(@max(1, depth), num_searched, is_quiet);
            base_lmr -= @intCast(history_lmr_mult * history_score >> 13);

            const lmr_depth = @max(0, depth - (base_lmr >> 10));
            if (is_quiet) {
                const lmp_linear_mult = if (improving) tunable_constants.lmp_improving_linear_mult else tunable_constants.lmp_standard_linear_mult;
                const lmp_quadratic_mult = if (improving) tunable_constants.lmp_improving_quadratic_mult else tunable_constants.lmp_standard_quadratic_mult;
                const lmp_base = if (improving) tunable_constants.lmp_improving_base else tunable_constants.lmp_standard_base;
                const granularity: i32 = 978;
                if (num_searched * granularity >=
                    lmp_base +
                        lmp_linear_mult * depth +
                        lmp_quadratic_mult * depth * depth)
                {
                    mp.skip_quiets = true;
                    continue;
                }

                if (depth <= 4 and history_score < depth * tunable_constants.history_pruning_mult + tunable_constants.history_pruning_offs) {
                    mp.skip_quiets = true;
                    continue;
                }

                if (!is_in_check and
                    lmr_depth <= 6 and
                    @abs(alpha) < 2000 and
                    eval + tunable_constants.fp_base +
                        lmr_depth * tunable_constants.fp_mult +
                        @divTrunc(history_score * tunable_constants.fp_hist_mult, 4096) <= alpha)
                {
                    mp.skip_quiets = true;
                    continue;
                }
            }

            const see_pruning_thresh = if (is_quiet)
                tunable_constants.see_quiet_pruning_mult * lmr_depth
            else
                tunable_constants.see_noisy_pruning_mult * lmr_depth * lmr_depth;

            if (!skip_see_pruning and
                !SEE.scoreMove(board, move, see_pruning_thresh, .pruning))
            {
                continue;
            }
        }

        var extension: i32 = 0;
        if (!is_root and
            depth >= 6 and
            move == tt_entry.move and
            !is_singular_search and
            tt_entry.depth + @as(i32, 3) >= depth and
            tt_entry.flags.score_type != .upper)
        {
            const s_beta = @max(evaluation.matedIn(0) + 1, tt_entry.score - (depth * tunable_constants.singular_beta_mult >> 10));
            const s_depth = depth * tunable_constants.singular_depth_mult - tunable_constants.singular_depth_offs >> 10;

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
                return @intCast(s_beta + @divTrunc((beta - s_beta) * tunable_constants.multicut_fail_medium, 1024));
            } else if (tt_entry.score >= beta) {
                extension -= 1;
            } else if (cutnode) {
                extension -= 3;
            }
        }
        num_searched += 1;

        if (std.debug.runtime_safety) {
            if (std.mem.count(Move, searched_noisies.slice(), &.{move}) != 0) {
                unreachable;
            }
            if (std.mem.count(Move, searched_quiets.slice(), &.{move}) != 0) {
                unreachable;
            }
        }

        self.makeMove(stm, move);

        const gives_check = self.stackEntry(0).board.checkers != 0;
        const score = blk: {
            const node_count_before: u64 = if (is_root) self.nodes else undefined;
            defer if (is_root) self.limits.updateNodeCounts(move, self.nodes - node_count_before);

            const corrhists_squared = self.histories.squaredCorrectionTerms(board, cur.move);

            var s: i16 = 0;
            var new_depth = depth + extension - 1;
            if (depth >= 3 and num_searched > 1) {
                const history_lmr_mult: i64 = if (is_quiet) tunable_constants.lmr_quiet_history_mult else tunable_constants.lmr_noisy_history_mult;
                var reduction = calculateBaseLMR(depth, num_searched, is_quiet);
                reduction -= @intCast(history_lmr_mult * history_score >> 13);
                reduction -= @intCast(tunable_constants.lmr_corrhist_mult * corrhists_squared >> 32);
                reduction += lmrConvolve(8, .{
                    is_pv,
                    cutnode,
                    improving,
                    has_tt_move,
                    tt_pv,
                    is_quiet,
                    gives_check,
                    self.stackEntry(-1).failhighs > 2,
                });

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
                if (self.stop.load(.acquire)) {
                    break :blk 0;
                }

                if (s > alpha and clamped_reduction > 1) {
                    const do_deeper_search = s > best_score + tunable_constants.lmr_dodeeper_margin + tunable_constants.lmr_dodeeper_mult * new_depth;
                    const do_shallower_search = s < best_score + new_depth;

                    new_depth += @intFromBool(do_deeper_search);
                    new_depth -= @intFromBool(do_shallower_search);

                    s = -self.search(
                        false,
                        false,
                        stm.flipped(),
                        -alpha - 1,
                        -alpha,
                        new_depth,
                        !cutnode,
                    );
                    if (self.stop.load(.acquire)) {
                        break :blk 0;
                    }
                }
            } else if (!is_pv or num_searched > 1) {
                s = -self.search(
                    false,
                    false,
                    stm.flipped(),
                    -alpha - 1,
                    -alpha,
                    new_depth,
                    !cutnode,
                );
                if (self.stop.load(.acquire)) {
                    break :blk 0;
                }
            }
            if (is_pv and (num_searched == 1 or s > alpha)) {
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
        if (self.stop.load(.acquire)) {
            return 0;
        }

        num_searched_quiets += @intFromBool(is_quiet);
        if (score <= alpha) {
            if (is_quiet) {
                searched_quiets.append(move) catch {};
            } else {
                searched_noisies.append(move) catch {};
            }
        }

        if (score > best_score) {
            best_score = score;
        }

        if (score > alpha) {
            best_move = move;
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
                const hist_depth = depth + @as(i32, if (score >= beta + 50) 1 else 0);
                score_type = .lower;
                cur.failhighs += 1;
                if (is_quiet) {
                    if (depth >= 3 or num_searched_quiets >= @as(u8, 2) + @intFromBool(has_tt_move and board.isQuiet(tt_entry.move))) {
                        self.histories.updateQuiet(board, move, cur.move, cur.prev, hist_depth, true);
                        for (searched_quiets.slice()) |searched_move| {
                            self.histories.updateQuiet(board, searched_move, cur.move, cur.prev, hist_depth, false);
                        }
                    }
                    self.histories.updateQuiet(board, move, cur.move, cur.prev, hist_depth, true);
                    for (searched_quiets.slice()) |searched_move| {
                        self.histories.updateQuiet(board, searched_move, cur.move, cur.prev, hist_depth, false);
                    }
                } else {
                    self.histories.updateNoisy(board, move, hist_depth, true);
                }
                for (searched_noisies.slice()) |searched_move| {
                    self.histories.updateNoisy(board, searched_move, hist_depth, false);
                }
                break;
            }
            if (2 <= depth and depth <= 12) {
                depth -= 1;
            }
        }
    }

    if (num_legal == 0) {
        const mated_score = evaluation.matedIn(self.ply);
        return if (is_in_check) mated_score else 0;
    }

    if (!is_singular_search) {
        if (score_type == .upper and tt_hit) {
            best_move = tt_entry.move;
        }
        self.writeTT(
            tt_pv,
            tt_hash,
            best_move,
            evaluation.scoreToTt(best_score, self.ply),
            score_type,
            depth,
            raw_static_eval,
        );

        if (!is_in_check and (best_score <= alpha_original or board.isQuiet(best_move))) {
            if (corrected_static_eval != best_score and
                evaluation.checkTTBound(best_score, corrected_static_eval, corrected_static_eval, score_type))
            {
                self.histories.updateCorrection(board, cur.move, corrected_static_eval, best_score, depth);
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
    var tbhits: u64 = 0;
    for (engine.searchers) |searcher| {
        nodes += searcher.nodes;
        tbhits += searcher.tbhits;
    }
    var pv_buf: [6 * 256 + 32]u8 = undefined;
    var fixed_buffer_pv_writer = std.io.fixedBufferStream(&pv_buf);
    const root_board = self.searchStackRoot()[0].board;
    {
        var board = root_board;
        for (self.pvs[0].slice()) |pv_move| {
            fixed_buffer_pv_writer.writer().print("{s} ", .{pv_move.toString(&board).slice()}) catch unreachable;
            board.stm = board.stm.flipped();
        }
    }
    var hashfull: usize = 0;
    if (self.tt.len >= 1000) {
        for (0..1000) |i| {
            hashfull += @intFromBool(self.tt[i].flags.age == self.ttage);
        }
    }

    const normalized_score = if (self.normalize) root.wdl.normalize(score, root_board.classicalMaterial()) else score;
    write("info depth {} seldepth {} score {s}{s} nodes {} nps {} hashfull {} tbhits {} time {} pv {s}\n", .{
        depth,
        self.seldepth,
        evaluation.formatScore(normalized_score).slice(),
        type_str,
        nodes,
        @as(u128, nodes) * std.time.ns_per_s / elapsed,
        hashfull,
        tbhits,
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

fn init(self: *Searcher, params: Params, is_main_thread: bool) void {
    self.limits = params.limits;
    self.syzygy_depth = params.syzygy_depth;
    self.is_main_thread = is_main_thread;
    self.ply = 0;
    self.stop.store(false, .release);
    self.nodes = 0;
    self.tbhits = 0;
    const board = params.board;
    self.previous_hashes.len = 0;
    self.normalize = params.normalize;
    var num_repeitions: u8 = 0;
    for (params.previous_hashes.slice()) |previous_hash| {
        if (params.board.hash == previous_hash) {
            num_repeitions += 1;
        }
        self.previous_hashes.append(previous_hash) catch @panic("too many hashes!");
    }
    self.fixupPreviousHashes();

    self.root_move = Move.init();
    self.root_score = 0;
    self.search_stack[0].board = Board{};
    self.pvs[0].len = 0;
    self.searchStackRoot()[0].init(&board, TypedMove.init(), TypedMove.init(), .{});
    self.evalStateRoot()[0].initInPlace(&board);
    self.ttage +%= 1;
    if (params.needs_full_reset) {
        self.histories.reset();
    }
    self.limits.resetNodeCounts();
    evaluation.initThreadLocals();
}

pub fn startSearch(self: *Searcher, params: Params, is_main_thread: bool, quiet: bool) void {
    self.init(params, is_main_thread);
    var previous_score: i32 = 0;
    var previous_move: Move = Move.init();
    var completed_depth: i32 = 0;
    var eval_stability: i32 = 0;
    var move_stability: i32 = 0;
    var last_full_width_score: i16 = 0;
    var average_score: i64 = 0;
    for (1..MAX_PLY) |d| {
        const depth: i32 = @intCast(d);
        self.limits.root_depth = depth;
        var quantized_window: i64 = tunable_constants.aspiration_initial + (average_score * tunable_constants.aspiration_score_mult >> 14);
        if (d == 1) {
            quantized_window = @as(i32, evaluation.inf_score) << 10;
        }
        var aspiration_lower: i32 = @intCast(@max(previous_score - (quantized_window >> 10), -evaluation.inf_score));
        var aspiration_upper: i32 = @intCast(@min(previous_score + (quantized_window >> 10), evaluation.inf_score));
        var failhigh_reduction: i32 = 0;
        var score = -evaluation.inf_score;
        switch (params.board.stm) {
            inline else => |stm| while (true) {
                defer quantized_window = quantized_window * tunable_constants.aspiration_multiplier >> 10;

                self.seldepth = 0;
                score = self.search(
                    true,
                    true,
                    stm,
                    aspiration_lower,
                    aspiration_upper,
                    @max(1, depth - failhigh_reduction),
                    false,
                );
                if (self.stop.load(.acquire)) {
                    break;
                }
                const should_print = is_main_thread and self.limits.shouldPrintInfoInAspiration();
                if (score >= aspiration_upper) {
                    aspiration_lower = @intCast(@max(score - (quantized_window >> 10), -evaluation.inf_score));
                    aspiration_upper = @intCast(@min(score + (quantized_window >> 10), evaluation.inf_score));
                    failhigh_reduction = @min(failhigh_reduction + 1, 4);
                    if (should_print) {
                        if (!quiet and !evaluation.isMateScore(score)) {
                            self.writeInfo(score, depth, .lower);
                        }
                    }
                } else if (score <= aspiration_lower) {
                    aspiration_lower = @intCast(@max(score - (quantized_window >> 10), -evaluation.inf_score));
                    aspiration_upper = @intCast(@min(score + (quantized_window >> 10), evaluation.inf_score));
                    failhigh_reduction >>= 1;
                    if (should_print) {
                        if (!quiet and !evaluation.isMateScore(score)) {
                            self.writeInfo(score, depth, .upper);
                        }
                    }
                } else {
                    last_full_width_score = score;
                    break;
                }
            },
        }
        if (@abs(previous_score - score) < tunable_constants.eval_stab_margin) {
            eval_stability = @min(eval_stability + 1, 8);
        } else {
            eval_stability = 0;
        }
        if (previous_move == self.root_move) {
            move_stability = @min(move_stability + 1, 8);
        } else {
            move_stability = 0;
        }
        previous_score = score;
        previous_move = self.root_move;

        average_score = if (d == 1) score else @divTrunc(average_score + @as(i64, score) * score, 2);

        completed_depth = depth;
        if (is_main_thread) {
            if (!quiet) {
                self.writeInfo(last_full_width_score, depth, .completed);
            }
        }
        if (self.stop.load(.acquire) or self.limits.checkRoot(
            self.nodes,
            depth,
            self.root_move,
            score,
            eval_stability,
            move_stability,
        )) {
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
