const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const eval = @import("eval.zig");
const move_ordering = @import("move_ordering.zig");
const Square = @import("square.zig").Square;
const SEE = @import("see.zig");
const nnue = @import("nnue.zig");
const correction = @import("correction.zig");

const testing = std.testing;

const use_hce = false;
const EvalState = if (use_hce) eval.EvalState else nnue.EvalState;
const evaluate: fn (*const Board, EvalState) i16 = if (use_hce) eval.evaluate else nnue.evaluate;

const assert = std.debug.assert;

const writeLog = @import("main.zig").writeLog;
const write = @import("main.zig").write;

const checkmate_score = eval.checkmate_score;

const shouldStopSearching = engine.shouldStopSearching;

const tunable_constants = @import("tuning.zig").tunable_constants;

const EvalPair = struct {
    white: ?i16 = null,
    black: ?i16 = null,

    pub fn updateWith(self: EvalPair, comptime turn: Side, val: i16) EvalPair {
        if (turn == .white) {
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

    pub fn isImprovement(self: EvalPair, comptime turn: Side, val: i16) bool {
        const prev_opt = if (turn == .white) self.white else self.black;
        return if (prev_opt) |prev| val > prev else false;
    }
};

fn quiesce(
    comptime pv: bool,
    comptime turn: Side,
    board: *Board,
    eval_state: EvalState,
    alpha_inp: i16,
    beta: i16,
    move_buf: []Move,
) i16 {
    var alpha = alpha_inp;
    qnodes += 1;
    if (qnodes % 1024 == 0 and (shouldStopSearching() or timer.read() >= hard_time or nodes + qnodes >= hard_nodes)) {
        shutdown = true;
        return 0;
    }
    if (board.isInsufficientMaterial() or board.isKvKNN()) {
        return 0;
    }
    const move_count, const masks = movegen.getCapturesOrEvasionsWithInfo(turn, board.*, move_buf);
    const tt_entry = tt[getTTIndex(board.zobrist)];
    const raw_static_eval = if (masks.is_in_check) eval.mateIn(1) else if (!pv and tt_entry.sameZobrist(board.zobrist)) tt_entry.raw_static_eval else evaluate(board, eval_state);
    const corrected_static_eval = if (masks.is_in_check) raw_static_eval else correction.correct(board, raw_static_eval);
    var tt_corrected_eval = corrected_static_eval;
    if (tt_entry.zobrist == board.zobrist) {
        const tt_score = eval.scoreFromTt(tt_entry.score, 0);
        switch (tt_entry.tp) {
            .exact => if (!pv) return tt_score,
            .lower => {
                if (!pv and tt_score >= beta) return tt_score;
                if (tt_score >= corrected_static_eval) tt_corrected_eval = tt_score;
            },
            .upper => {
                if (!pv and tt_score <= alpha) return tt_score;
                if (tt_score <= corrected_static_eval) tt_corrected_eval = tt_score;
            },
        }
    }

    if (move_count == 0) {
        return tt_corrected_eval;
    }

    if (tt_corrected_eval >= beta) return beta;
    if (tt_corrected_eval > alpha) alpha = tt_corrected_eval;

    move_ordering.order(turn, board, tt_entry.move, Move.null_move, 0, move_buf[0..move_count]);
    var best_score = tt_corrected_eval;
    var best_move = Move.null_move;
    for (move_buf[0..move_count]) |move| {
        if (std.debug.runtime_safety) {
            if (board.mailbox[move.getTo().toInt()]) |cap| {
                if (cap == .king) {
                    writeLog("{} captures king\nboard:{}\n", .{ move, board.* });
                    err = true;
                    shutdown = true;
                    return 0;
                }
            }
        }

        const is_losing = best_score <= eval.mateIn(MAX_SEARCH_DEPTH);

        if (!masks.is_in_check and
            !is_losing)
        {
            if (tt_corrected_eval + tunable_constants.quiesce_futility_margin < alpha and
                !SEE.scoreMove(board, move, 1))
                continue;
            // if we're not in a pawn and king endgame and the capture is really bad, just skip it
            // no longer checking for pawn and king endgames, ty toanth
            if (!SEE.scoreMove(board, move, tunable_constants.quiesce_see_pruning_threshold))
                continue;
        }
        const updated_eval_state = eval_state.updateWith(turn, board, move);
        const inv = board.playMove(turn, move);
        @prefetch(&tt[getTTIndex(board.zobrist)], .{});
        defer board.undoMove(turn, inv);

        const score = -quiesce(
            pv,
            turn.flipped(),
            board,
            updated_eval_state,
            -beta,
            -alpha,
            move_buf[move_count..],
        );
        if (errored()) {
            writeLog("{}\n", .{move});
            break;
        }

        if (shutdown)
            break;
        if (score > best_score) {
            best_score = score;
            best_move = move;
        }
        if (score > alpha) {
            if (score >= beta) {
                break;
            }
            alpha = score;
        }
    }
    var score_type: ScoreType = .exact;
    if (best_score <= alpha_inp) score_type = .upper;
    if (best_score >= beta) score_type = .lower;

    if (tt_entry.depth == 0) {
        tt[getTTIndex(board.zobrist)] = TTEntry.init(
            board.zobrist,
            best_move,
            0,
            score_type,
            eval.scoreToTt(best_score, 0),
            raw_static_eval,
        );
    }

    return best_score;
}

fn search(
    comptime root: bool,
    comptime turn: Side,
    comptime pv: bool,
    board: *Board,
    eval_state: EvalState,
    alpha_inp: i16,
    beta: i16,
    ply: u8,
    depth_inp: u8,
    move_buf: []Move,
    previous_move: Move,
    excluded: Move,
    previous_evals: EvalPair,
    hash_history: *std.ArrayList(u64),
    cutnode: bool,
) ?if (root) struct { i16, Move } else i16 {
    const result = struct {
        inline fn impl(score: i16, move: Move) if (root) struct { i16, Move } else i16 {
            return if (root) .{ score, move } else score;
        }
    }.impl;
    if (std.debug.runtime_safety and err) return result(0, Move.null_move);
    var alpha = alpha_inp;
    var depth = depth_inp;
    nodes += 1;
    if (ply > 0 and nodes % 1024 == 0 and (shouldStopSearching() or timer.read() >= hard_time or nodes + qnodes >= hard_nodes)) {
        shutdown = true;
        return null;
    }
    // assert that root implies pv
    comptime assert(if (root) pv else true);
    const tt_entry = tt[getTTIndex(board.zobrist)];
    const tt_hit = tt_entry.sameZobrist(board.zobrist);
    if (!pv and tt_hit and tt_entry.depth >= depth and excluded.isNull()) {
        const tt_score = eval.scoreFromTt(tt_entry.score, ply);
        switch (tt_entry.tp) {
            .exact => return result(tt_score, tt_entry.move),
            .lower => if (tt_score >= beta) return result(tt_score, tt_entry.move),
            .upper => if (tt_score <= alpha) return result(tt_score, tt_entry.move),
        }
    }
    if (depth >= 4 and
        excluded.isNull() and
        (pv or cutnode) and
        (tt_entry.move.isNull() or !tt_hit))
        depth -= 1;

    const worst_possible = eval.mateIn(ply);
    const best_possible = -worst_possible;
    if (!root and best_possible < beta) {
        if (alpha >= best_possible) {
            return result(best_possible, Move.null_move);
        }
    }
    if (!root and worst_possible > alpha) {
        if (beta <= worst_possible) {
            return result(worst_possible, Move.null_move);
        }
    }

    const move_count, const masks = movegen.getMovesWithInfo(turn, false, board.*, move_buf);
    const is_in_check = masks.is_in_check;
    if (root and move_count == 0) {
        return result(0, Move.null_move);
    }
    if (!root and move_count == 0) {
        return if (is_in_check) eval.mateIn(ply) else 0;
    }
    if (board.halfmove_clock >= 100) {
        return result(0, Move.null_move);
    }

    const repetition_idx: usize = @intCast(board.zobrist % repetition_table.len);
    repetition_table[repetition_idx] += 1;
    defer repetition_table[repetition_idx] -= 1;
    if (repetition_table[repetition_idx] >= 3) {
        var repetitions: u8 = 0;
        const start = hash_history.items.len - @min(hash_history.items.len, board.halfmove_clock);
        for (hash_history.items[start..hash_history.items.len]) |zobrist| {
            if (board.zobrist == zobrist) {
                repetitions += 1;
            }
        }
        if (repetitions >= 3) {
            return result(0, Move.null_move);
        }
    }

    if (depth == 0 or depth == max_depth) {
        var score = quiesce(
            pv,
            turn,
            board,
            eval_state,
            alpha,
            beta,
            move_buf,
        );
        if (shutdown or errored()) {
            return null;
        }

        // don't return unproven mate scores
        if (eval.isMateScore(score)) score = std.math.clamp(score, alpha, beta);
        return result(score, move_buf[0]);
    }

    // if its king vs king and two knights its either a draw or M1, depth 4 just to be safe
    if (board.isInsufficientMaterial() or (board.isKvKNN() and depth >= 4)) {
        return result(0, move_buf[0]);
    }

    const raw_static_eval = if (tt_hit and !pv) tt_entry.raw_static_eval else (if (is_in_check) 0 else evaluate(board, eval_state));
    const corrected_static_eval = correction.correct(board, raw_static_eval);
    var tt_corrected_eval = corrected_static_eval;
    const improving = if (is_in_check) false else previous_evals.isImprovement(turn, corrected_static_eval);
    const updated_evals = if (is_in_check) previous_evals else previous_evals.updateWith(turn, corrected_static_eval);
    if (!is_in_check) {
        if (tt_entry.zobrist == board.zobrist) {
            tt_corrected_eval = switch (tt_entry.tp) {
                .exact => tt_entry.score,
                .lower => @max(tt_entry.score, corrected_static_eval),
                .upper => @min(tt_entry.score, corrected_static_eval),
            };
        }
    }

    // TODO: tuning
    const us = board.getSide(turn);
    const not_pawn_or_king = us.all & ~(us.getBoard(.pawn) | us.getBoard(.king));
    if (!pv and
        !is_in_check and
        beta >= eval.mateIn(MAX_SEARCH_DEPTH) and
        excluded.isNull())
    {

        // reverse futility pruning
        // this is basically the same as what we do in qsearch, if the position is too good we're probably not gonna get here anyway
        if (depth <= 5 and tt_corrected_eval >= beta + tunable_constants.rfp_mult * (depth -| @intFromBool(improving))) {
            return result(tt_corrected_eval, move_buf[0]);
        }

        // razoring
        if (depth <= 3 and tt_corrected_eval + tunable_constants.razoring_margin * depth <= alpha) {
            const razor_score = quiesce(
                pv,
                turn,
                board,
                eval_state,
                alpha,
                beta,
                move_buf[move_count..],
            );
            if (razor_score <= alpha) {
                return razor_score;
            }
        }

        // null move pruning
        if (depth >= 4 and
            tt_corrected_eval >= beta and
            not_pawn_or_king != 0)
        {
            const improving_factor: u8 = 3;
            const reduction: i32 = 4 + (depth + improving_factor * @intFromBool(improving)) / 5;

            const reduced_depth: u8 = @intCast(std.math.clamp(depth - reduction, 0, MAX_SEARCH_DEPTH));
            const updated_eval_state = eval_state.negate();
            const inv = board.playNullMove();
            hash_history.appendAssumeCapacity(board.zobrist);
            const score = -(search(
                false,
                turn.flipped(),
                false,
                board,
                updated_eval_state,
                -beta,
                -beta + 1,
                ply + 1,
                reduced_depth,
                move_buf[move_count..],
                Move.null_move,
                Move.null_move,
                previous_evals,
                hash_history,
                !cutnode,
            ) orelse 0);
            _ = hash_history.pop();
            board.undoNullMove(inv);

            if (score >= beta) {
                const anti_zugzwang_score = search(
                    false,
                    turn,
                    false,
                    board,
                    eval_state,
                    beta - 1,
                    beta,
                    ply + 1,
                    reduced_depth,
                    move_buf[move_count..],
                    previous_move,
                    Move.null_move,
                    previous_evals,
                    hash_history,
                    true,
                ) orelse 0;

                if (anti_zugzwang_score >= beta) {
                    return anti_zugzwang_score;
                }
            }
        }
    }

    move_ordering.clearIrrelevantKillers(ply);
    move_ordering.order(turn, board, tt_entry.move, previous_move, ply, move_buf[0..move_count]);
    var best_score = -checkmate_score;
    var best_move = move_buf[0];
    var num_searched: u8 = 0;
    var prune_quiets = false;
    for (move_buf[0..move_count], 0..) |move, i| {
        const node_count_before_search: u64 = if (root) nodes + qnodes else 0;
        if (move == excluded) {
            continue;
        }
        const is_losing = best_score <= eval.mateIn(MAX_SEARCH_DEPTH);
        if (prune_quiets and move.isQuiet() and !move.isPromotion())
            continue;
        const see_pruning_threshold = if (move.isQuiet()) @as(i32, depth) * tunable_constants.see_quiet_pruning_mult else @as(i32, depth) * depth * tunable_constants.see_noisy_pruning_mult;

        // no longer checking for pawn and king endgames, ty toanth
        if (!pv and !is_in_check and !is_losing and depth < 10 and !SEE.scoreMove(board, move, see_pruning_threshold))
            continue;

        var extension: i32 = @intFromBool(is_in_check);

        const singular_ttentry_depth_margin: u16 = 3;
        if (!root and
            depth >= 8 and
            move == tt_entry.move and
            excluded.isNull() and
            tt_entry.depth + singular_ttentry_depth_margin >= depth and
            tt_entry.tp != .upper)
        {
            const s_beta: i16 = @intCast(@max(eval.mateIn(0) + 1, tt_entry.score -| (depth * tunable_constants.singular_beta_depth_mult >> 4)));
            const s_depth = (depth - 1) / 2;

            const score: i16 = search(
                false,
                turn,
                pv,
                board,
                eval_state,
                s_beta - 1,
                s_beta,
                ply,
                s_depth,
                move_buf[move_count..],
                previous_move,
                move,
                previous_evals,
                hash_history,
                cutnode,
            ) orelse 0;
            if (score < s_beta) {
                extension += 1;
                if (score < s_beta - tunable_constants.double_extension_margin and !pv)
                    extension += 1;
            } else if (tt_entry.score >= beta) {
                extension -= 1;
            }
        }

        const updated_eval_state = eval_state.updateWith(turn, board, move);
        const inv = board.playMove(turn, move);
        @prefetch(&tt[getTTIndex(board.zobrist)], .{});
        hash_history.appendAssumeCapacity(board.zobrist);
        defer _ = hash_history.pop();

        var score: i16 = 0;
        const new_depth: u8 = @intCast(std.math.clamp(depth - 1 + extension, 0, 255));
        if (depth >= 3 and !is_in_check and num_searched > 0 and extension <= 0) {
            // TODO: tuning

            // late move reduction
            var reduction: i32 = tunable_constants.lmr_base +
                std.math.log2_int(u8, depth) * tunable_constants.lmr_depth_mult * std.math.log2_int(u8, num_searched);
            reduction -= @intFromBool(improving) * tunable_constants.lmr_improving_mult;
            reduction -= @intFromBool(pv) * tunable_constants.lmr_pv_mult;
            reduction += @intFromBool(cutnode) * tunable_constants.lmr_cutnode_mult;
            reduction >>= 10;

            const clamped_reduction: i32 = std.math.clamp(reduction - extension, 1, depth - 1);
            const reduced_depth: u8 = @intCast(depth - clamped_reduction);

            score = -(search(
                false,
                turn.flipped(),
                false,
                board,
                updated_eval_state,
                -(alpha + 1),
                -alpha,
                ply + 1,
                reduced_depth,
                move_buf[move_count..],
                move,
                Move.null_move,
                updated_evals,
                hash_history,
                true,
            ) orelse 0);
        } else if (!pv or num_searched > 0) {
            score = -(search(
                false,
                turn.flipped(),
                false,
                board,
                updated_eval_state,
                -(alpha + 1),
                -alpha,
                ply + 1,
                new_depth,
                move_buf[move_count..],
                move,
                Move.null_move,
                updated_evals,
                hash_history,
                !cutnode,
            ) orelse 0);
        }
        if (pv and (num_searched == 0 or score > alpha)) {
            score = -(search(
                false,
                turn.flipped(),
                true,
                board,
                updated_eval_state,
                -beta,
                -alpha,
                ply + 1,
                new_depth,
                move_buf[move_count..],
                move,
                Move.null_move,
                updated_evals,
                hash_history,
                false,
            ) orelse 0);
        }
        if (errored()) {
            writeLog("{}\n", .{move});
            break;
        }
        board.undoMove(turn, inv);
        if (shutdown) break;
        num_searched += 1;

        if (score > best_score) {
            best_score = score;
            best_move = move;
        }
        if (score > alpha) {
            alpha = score;
            if (score >= beta) {
                if (move.isQuiet()) {
                    move_ordering.recordKiller(move, ply);
                    move_ordering.updateHistory(turn, board, move, previous_move, move_ordering.getBonus(depth));
                    for (0..i) |j| {
                        if (move_buf[j].isQuiet()) {
                            move_ordering.updateHistory(turn, board, move_buf[j], previous_move, move_ordering.getMalus(depth));
                        }
                    }
                }
                break;
            }
        }

        // lmp
        if (!is_losing and move.isQuiet() and num_searched > (@as(u16, depth) * depth >> @intFromBool(!improving)) and !pv) {
            prune_quiets = true;
        }
        const node_count_after_search: u64 = if (root) nodes + qnodes else 0;
        if (root) {
            root_node_counts[move.getFrom().toInt()][move.getTo().toInt()] += node_count_after_search - node_count_before_search;
        }
    }

    if (shutdown) {
        if (num_searched >= 1) {
            return result(best_score, best_move);
        } else {
            return null;
        }
    }
    var score_type: ScoreType = .exact;
    if (best_score <= alpha_inp) score_type = .upper;
    if (best_score >= beta) score_type = .lower;

    if (excluded.isNull()) {
        if (!is_in_check and
            best_move.isQuiet() and
            (score_type == .exact or
                (score_type == .lower and best_score > raw_static_eval) or
                (score_type == .upper and best_score < raw_static_eval)))
        {
            correction.update(board, corrected_static_eval, best_score, depth);
        }
    }

    if (excluded.isNull()) {
        tt[getTTIndex(board.zobrist)] = TTEntry.init(
            board.zobrist,
            best_move,
            depth,
            score_type,
            eval.scoreToTt(best_score, ply),
            raw_static_eval,
        );
    }

    return result(best_score, best_move);
}

fn collectPv(board: *Board, ply: u8, hash_history: *std.ArrayList(u64)) void {
    const entry = tt[getTTIndex(board.zobrist)];
    if (entry.tp != .exact or entry.zobrist != board.zobrist) {
        return;
    }
    const globals = struct {
        var move_buf: [256]Move = undefined;
        var already_seen = std.StaticBitSet(8192).initEmpty();
    };
    if (ply == 0) globals.already_seen = std.StaticBitSet(8192).initEmpty();
    if (globals.already_seen.isSet(@intCast(board.zobrist % 8192))) return;
    if (ply == 0) {
        for (hash_history.items) |item| {
            globals.already_seen.set(@intCast(item % 8192));
        }
    }
    globals.already_seen.set(@intCast(board.zobrist % 8192));

    var buf: []Move = &globals.move_buf;

    switch (board.turn) {
        inline else => |t| {
            const num_moves = movegen.getMoves(t, board.*, buf);
            var tt_move_valid = false;
            for (buf[0..num_moves]) |move| {
                tt_move_valid = tt_move_valid or move == entry.move;
            }
            if (!tt_move_valid) return;
            if (board.halfmove_clock >= 100) return;
            pv_moves[ply] = entry.move;
            num_pv_moves = ply;
            const inv = board.playMove(t, entry.move);
            collectPv(board, ply + 1, hash_history);
            board.undoMove(t, inv);
        },
    }
}

fn writeInfo(score: i16, move: Move, depth: u8, frc: bool) void {
    const node_count = @max(1, nodes + qnodes);

    var pv_buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&pv_buf);
    if (num_pv_moves == 0 or pv_moves[0] != move) {
        pv_moves[0] = move;
        num_pv_moves = 1;
    }
    for (0..num_pv_moves) |i| {
        if (i != 0) {
            fbs.writer().writeByte(' ') catch unreachable;
        }
        fbs.writer().writeAll(pv_moves[i].toString(frc).slice()) catch unreachable;
    }

    if (eval.isMateScore(score)) {
        const plies_to_mate = if (score > 0) eval.checkmate_score - score else eval.checkmate_score + score;
        write("info depth {} score mate {s}{} nodes {} nps {} time {} pv {s}\n", .{
            depth + 1,
            if (score > 0) "" else "-",
            @divTrunc(plies_to_mate + 1, 2),
            node_count,
            node_count * std.time.ns_per_s / timer.read(),
            (timer.read() + std.time.ns_per_ms / 2) / std.time.ns_per_ms,
            fbs.getWritten(),
        });
    } else {
        write("info depth {} score cp {} nodes {} nps {} time {} pv {s}\n", .{
            depth + 1,
            score,
            node_count,
            node_count * std.time.ns_per_s / timer.read(),
            (timer.read() + std.time.ns_per_ms / 2) / std.time.ns_per_ms,
            fbs.getWritten(),
        });
    }
}

pub fn iterativeDeepening(board: Board, search_params: engine.SearchParameters, move_buf: []Move, hash_history: *std.ArrayList(u64), silence_output: bool) engine.SearchResult {
    resetSoft();
    assert(hash_history.items[hash_history.items.len - 1] == board.zobrist);
    for (hash_history.items) |zobrist| repetition_table[@intCast(zobrist % repetition_table.len)] += 1;
    timer = std.time.Timer.start() catch unreachable;
    hard_time = search_params.hardTime();
    hard_nodes = search_params.maxNodes() *| 4;
    var board_copy = board;
    var score: i16 = -checkmate_score;
    var move = Move.null_move;
    const eval_state = EvalState.init(&board);
    var last_score: i16 = 0;
    for (0..search_params.maxDepth()) |depth| {
        max_depth = @intCast(@min(MAX_SEARCH_DEPTH, 2 * depth));
        if (depth != 0) {
            var fail_lows: usize = 0;
            var fail_highs: usize = 0;
            var window: i16 = @intCast(std.math.clamp(
                @as(i32, @intCast(@abs(@as(i32, score) - last_score))) * tunable_constants.aspiration_window_diff_mult,
                tunable_constants.aspiration_window_lower_bound,
                tunable_constants.aspiration_window_upper_bound,
            ) >> 10);
            var alpha: i16 = score -| window;
            var beta: i16 = score +| window;
            var aspiration_score, var aspiration_move = .{ score, move };
            while (true) {
                aspiration_score, aspiration_move = switch (board.turn) {
                    inline else => |turn| search(
                        true,
                        turn,
                        true,
                        &board_copy,
                        eval_state,
                        alpha,
                        beta,
                        0,
                        @intCast(depth),
                        move_buf,
                        Move.null_move,
                        Move.null_move,
                        .{},
                        hash_history,
                        false,
                    ),
                } orelse break;
                if (aspiration_score >= beta) {
                    beta = @min(checkmate_score, beta +| window);
                    fail_highs += 1;
                } else if (aspiration_score <= alpha) {
                    alpha = @max(-checkmate_score, alpha -| window);
                    fail_lows += 1;
                } else {
                    break;
                }
                if (eval.isMateScore(aspiration_score)) {
                    alpha = -checkmate_score;
                    beta = checkmate_score;
                } else {
                    window = @intCast(std.math.clamp(window * tunable_constants.aspiration_window_mult >> 10, -eval.win_score + 1, eval.win_score - 1));
                }
            }
            if (!silence_output and std.debug.runtime_safety) {
                write("info string fail_lows {} fail_highs {}\n", .{ fail_lows, fail_highs });
            }
            score = aspiration_score;
            move = aspiration_move;
        } else {
            score, move = switch (board.turn) {
                inline else => |turn| search(
                    true,
                    turn,
                    true,
                    &board_copy,
                    eval_state,
                    -checkmate_score,
                    checkmate_score,
                    0,
                    @intCast(depth),
                    move_buf,
                    Move.null_move,
                    Move.null_move,
                    .{},
                    hash_history,
                    false,
                ),
            } orelse break;
        }
        last_score = score;
        collectPv(&board_copy, 0, hash_history);
        if (!silence_output and !shouldStopSearching()) {
            writeInfo(score, move, @intCast(depth), search_params.frc);
        }
        if (nodes + qnodes >= search_params.maxNodes()) {
            break;
        }
        var total_nodes: u64 = 0;
        for (root_node_counts) |counts| {
            for (counts) |count| {
                total_nodes += count;
            }
        }
        total_nodes = @max(1, total_nodes);
        const best_move_count = @max(1, root_node_counts[move.getFrom().toInt()][move.getTo().toInt()]);
        const node_fraction = @as(u128, best_move_count) * 1024 / total_nodes;
        const node_count_factor = @as(u64, @intCast(tunable_constants.nodetm_mult)) * (@as(u64, @intCast(tunable_constants.nodetm_base)) - node_fraction);
        const adjusted_limit: u128 = search_params.softTime() * node_count_factor >> 20;
        // const adjusted_time: u64 = @intFromFloat(@as(f64, @floatFromInt(timer.read())) * node_count_factor);
        if (timer.read() >= @min(search_params.hardTime(), adjusted_limit)) {
            break;
        }
        if (shouldStopSearching()) {
            break;
        }
        // if (eval.isMateScore(score)) break;
    }
    if (errored()) {
        std.debug.panic("error encountered, writing logs!\n", .{});
    }
    if (!silence_output) {
        engine.waitUntilWritingBestMoveAllowed();
        write("bestmove {s}\n", .{move.toString(search_params.frc).slice()});
    }
    engine.stoppedSearching();
    return engine.SearchResult{
        .move = move,
        .score = score,
        .stats = engine.SearchStatistics{
            .nodes = nodes,
            .qnodes = qnodes,
            .ns_used = timer.read(),
        },
    };
}

const ScoreType = enum(u2) {
    lower,
    upper,
    exact,
};

pub const TTEntry = struct {
    zobrist: u64,
    move: Move,
    depth: u8,
    tp: ScoreType,
    score: i16,
    raw_static_eval: i16,

    pub fn init(zobrist_: u64, move_: Move, depth_: anytype, tp_: ScoreType, score_: i16, static_eval_: i16) TTEntry {
        return .{
            .zobrist = @intCast(zobrist_),
            .move = move_,
            .depth = depth_,
            .tp = tp_,
            .score = score_,
            .raw_static_eval = static_eval_,
        };
    }

    pub fn sameZobrist(self: TTEntry, other: u64) bool {
        return self.zobrist == other;
    }
};

comptime {
    assert(@sizeOf(TTEntry) == 16);
}
pub fn setTTSize(mb: usize) !void {
    if (@as(u128, mb) << 20 > std.math.maxInt(usize)) return error.TableTooBig;
    tt = try std.heap.page_allocator.realloc(tt, (mb << 20) / @sizeOf(TTEntry));
    assert(tt.len % (std.simd.suggestVectorLength(u8) orelse 64) == 0);
    @memset(std.mem.sliceAsBytes(tt), 0);
}

fn getTTIndex(hash: u64) usize {
    assert(tt.len > 0);
    return @intCast((((hash & std.math.maxInt(u32)) ^ (hash >> 32)) * tt.len) >> 32);
}

pub fn resetSoft() void {
    nodes = 0;
    qnodes = 0;
    shutdown = false;
    tt_hits = 0;
    tt_collisions = 0;
    max_depth = MAX_SEARCH_DEPTH;
    hard_nodes = std.math.maxInt(u64);
    @memset(std.mem.asBytes(&root_node_counts), 0);
    @memset(&repetition_table, 0);
}

pub fn resetHard() void {
    correction.reset();
    move_ordering.reset();
    resetSoft();
    @memset(std.mem.sliceAsBytes(tt), 0);
}

const MAX_SEARCH_DEPTH = 255;
var root_node_counts: [64][64]u64 = undefined;
var repetition_table: [8192]u8 = undefined;
var pv_moves: [256]Move = undefined;
var num_pv_moves: usize = 0;
var tt: []align(16) TTEntry align(64) = &.{};
var nodes: u64 = 0;
var qnodes: u64 = 0;
var timer: std.time.Timer = undefined;
var shutdown = false;
var hard_time: u64 = 0;
var hard_nodes: u64 = std.math.maxInt(u64);
var max_depth: u8 = MAX_SEARCH_DEPTH;
var tt_hits: usize = 0;
var tt_collisions: usize = 0;
fn errored() bool {
    if (std.debug.runtime_safety) {
        return err;
    } else {
        return false;
    }
}
var err = if (std.debug.runtime_safety) false else @compileError("you shouldn't be reading this variable!");
