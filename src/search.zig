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

const testing = std.testing;

const use_hce = false;
const EvalState = if (use_hce) eval.EvalState else nnue.EvalState;
const evaluate: fn (*const Board, EvalState) i16 = if (use_hce) eval.evaluate else nnue.evaluate;

const assert = std.debug.assert;

const writeLog = @import("main.zig").writeLog;
const write = @import("main.zig").write;

const checkmate_score = eval.checkmate_score;

const shouldStopSearching = engine.shouldStopSearching;

const max_search_depth = 255;

const tunable_constants = @import("tuning.zig").tunable_constants;

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
    if (qnodes % 1024 == 0 and (shouldStopSearching() or timer.read() >= hard_time)) {
        shutdown = true;
        return 0;
    }
    if (board.isInsufficientMaterial() or board.isKvKNN()) {
        return 0;
    }
    const move_count, const masks = movegen.getCapturesOrEvasionsWithInfo(turn, board.*, move_buf);
    const tt_entry = tt[getTTIndex(board.zobrist)];
    var static_eval = if (masks.is_in_check) eval.mateIn(1) else evaluate(board, eval_state);
    if (!pv and tt_entry.zobrist == board.zobrist) {
        const tt_score = eval.scoreFromTt(tt_entry.score, 0);
        switch (tt_entry.tp) {
            .exact => if (!pv) return tt_score,
            .lower => {
                if (tt_score >= beta) return tt_score;
                if (tt_score >= static_eval) static_eval = tt_score;
            },
            .upper => {
                if (tt_score <= alpha) return tt_score;
                if (tt_score <= static_eval) static_eval = tt_score;
            },
        }
    }

    if (move_count == 0) {
        return static_eval;
    }

    if (static_eval >= beta) return beta;
    if (static_eval > alpha) alpha = static_eval;

    move_ordering.order(turn, board, tt_entry.move, Move.null_move, 0, move_buf[0..move_count]);
    var best_score = static_eval;
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

        const is_losing = best_score <= eval.mateIn(max_search_depth);

        if (!masks.is_in_check and
            !is_losing)
        {
            if (static_eval + 100 < alpha and
                !SEE.scoreMove(board, move, 1))
                continue;
            // if we're not in a pawn and king endgame and the capture is really bad, just skip it
            // no longer checking for pawn and king endgames, ty toanth
            if (!SEE.scoreMove(board, move, tunable_constants.quiesce_see_pruning_threshold))
                continue;
        }
        const updated_eval_state = eval_state.updateWith(turn, board, move);
        const inv = board.playMove(turn, move);
        defer board.undoMove(turn, inv);
        qnodes += 1;

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
        tt[getTTIndex(board.zobrist)] = TTEntry{
            .zobrist = board.zobrist,
            .move = best_move,
            .depth = 0,
            .tp = score_type,
            .score = eval.scoreToTt(best_score, 0),
        };
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
    depth: u8,
    move_buf: []Move,
    previous_move: Move,
    excluded: Move,
    hash_history: *std.ArrayList(u64),
) ?if (root) struct { i16, Move } else i16 {
    const result = struct {
        inline fn impl(score: i16, move: Move) if (root) struct { i16, Move } else i16 {
            return if (root) .{ score, move } else score;
        }
    }.impl;
    if (std.debug.runtime_safety and err) return result(0, Move.null_move);
    var alpha = alpha_inp;
    nodes += 1;
    if (ply > 0 and nodes % 1024 == 0 and (shouldStopSearching() or timer.read() >= hard_time)) {
        shutdown = true;
        return null;
    }
    // assert that root implies pv
    comptime assert(if (root) pv else true);
    const tt_entry = tt[getTTIndex(board.zobrist)];
    if (!pv and tt_entry.zobrist == board.zobrist and tt_entry.depth >= depth and excluded == Move.null_move) {
        const tt_score = eval.scoreFromTt(tt_entry.score, ply);
        switch (tt_entry.tp) {
            .exact => return result(tt_score, tt_entry.move),
            .lower => if (tt_score >= beta) return result(tt_score, tt_entry.move),
            .upper => if (tt_score <= alpha) return result(tt_score, tt_entry.move),
        }
    }
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

    if (depth == 0) {
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

    const static_eval = if (is_in_check) 0 else evaluate(board, eval_state);
    var tt_corrected_eval = static_eval;
    if (!is_in_check) {
        if (tt_entry.zobrist == board.zobrist) {
            tt_corrected_eval = switch (tt_entry.tp) {
                .exact => tt_entry.score,
                .lower => @max(tt_entry.score, static_eval),
                .upper => @min(tt_entry.score, static_eval),
            };
        }
    }

    // TODO: tuning
    const us = board.getSide(turn);
    const not_pawn_or_king = us.all & ~(us.getBoard(.pawn) | us.getBoard(.king));
    if (!pv and
        !is_in_check and
        beta >= eval.mateIn(max_search_depth) and
        excluded == Move.null_move)
    {

        // reverse futility pruning
        // this is basically the same as what we do in qsearch, if the position is too good we're probably not gonna get here anyway
        if (depth <= 5 and tt_corrected_eval >= beta + tunable_constants.rfp_multiplier * depth) {
            return result(tt_corrected_eval, move_buf[0]);
        }

        // razoring
        const razoring_margin: i32 = 200;
        if (depth <= 3 and tt_corrected_eval + razoring_margin * depth <= alpha) {
            const razor_score = quiesce(pv, turn, board, eval_state, alpha, beta, move_buf[move_count..]);
            if (razor_score <= alpha) {
                return razor_score;
            }
        }

        // null move pruning
        if (depth >= 4 and
            tt_corrected_eval >= beta and
            not_pawn_or_king != 0)
        {
            const reduction = 4 + depth / 5;
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
                depth - reduction,
                move_buf[move_count..],
                Move.null_move,
                Move.null_move,
                hash_history,
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
                    depth - reduction,
                    move_buf[move_count..],
                    previous_move,
                    Move.null_move,
                    hash_history,
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
        if (move == excluded) {
            continue;
        }
        const is_losing = best_score <= eval.mateIn(max_search_depth);
        if (prune_quiets and move.isQuiet() and !move.isPromotion())
            continue;
        const see_pruning_threshold = if (move.isQuiet()) @as(i16, depth) * tunable_constants.see_quiet_pruning_multiplier else @as(i32, depth) * depth * tunable_constants.see_noisy_pruning_multiplier;

        // no longer checking for pawn and king endgames, ty toanth
        if (!pv and !is_in_check and !is_losing and depth < 10 and !SEE.scoreMove(board, move, see_pruning_threshold))
            continue;

        var extension: u8 = @intFromBool(is_in_check);

        const singular_ttentry_depth_margin: u16 = 3;
        if (!root and
            depth >= 8 and
            move == tt_entry.move and
            excluded == Move.null_move and
            tt_entry.depth + singular_ttentry_depth_margin >= depth and
            tt_entry.tp != .upper)
        {
            const s_beta = @max(eval.mateIn(0) + 1, tt_entry.score - depth * 2);
            const s_depth = (depth - 1) / 2;

            const score: i16 = search(false, turn, pv, board, eval_state, s_beta - 1, s_beta, ply, s_depth, move_buf[move_count..], previous_move, move, hash_history) orelse 0;
            if (score < s_beta)
                extension += 1;
            if (score < s_beta - 20 and !pv)
                extension += 1;
        }

        const updated_eval_state = eval_state.updateWith(turn, board, move);
        const inv = board.playMove(turn, move);
        hash_history.appendAssumeCapacity(board.zobrist);
        defer _ = hash_history.pop();

        var score: i16 = 0;
        const new_depth = depth - 1 + extension;
        if (depth >= 3 and !is_in_check and num_searched > 0 and extension == 0) {
            // TODO: tuning

            // late move reduction
            const reduction = (tunable_constants.lmr_base - @intFromBool(pv) + @as(u16, std.math.log2_int(u8, depth)) * std.math.log2_int(u8, num_searched) * tunable_constants.lmr_mult) >> 5;
            const clamped_reduction = std.math.clamp(reduction, 1, depth - 1);
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
                hash_history,
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
                hash_history,
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
                hash_history,
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
                            move_ordering.updateHistory(turn, board, move_buf[j], previous_move, -move_ordering.getBonus(depth));
                        }
                    }
                }
                break;
            }
        }
        if (!is_losing and move.isQuiet() and num_searched > @as(u16, depth) * depth and !pv) {
            prune_quiets = true;
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

    if (excluded == Move.null_move) {
        tt[getTTIndex(board.zobrist)] = TTEntry{
            .zobrist = board.zobrist,
            .move = best_move,
            .depth = depth,
            .tp = score_type,
            .score = eval.scoreToTt(best_score, ply),
        };
    }

    return result(best_score, best_move);
}

fn collectPv(board: *Board, cur_depth: u8) void {
    const entry = tt[getTTIndex(board.zobrist)];
    if (entry.tp != .exact or entry.zobrist != board.zobrist) {
        return;
    }
    const globals = struct {
        var move_buf: [256]Move = undefined;
        var already_seen = std.StaticBitSet(8192).initEmpty();
    };
    if (cur_depth == 0) globals.already_seen = std.StaticBitSet(8192).initEmpty();
    if (globals.already_seen.isSet(@intCast(board.zobrist % 8192))) return;
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
            pv_moves[cur_depth] = entry.move;
            num_pv_moves = cur_depth;
            const inv = board.playMove(t, entry.move);
            collectPv(board, cur_depth + 1);
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
    var board_copy = board;
    var score: i16 = -checkmate_score;
    var move = Move.null_move;
    const eval_state = EvalState.init(&board);
    var last_score: i16 = 0;
    for (0..search_params.maxDepth()) |depth| {
        if (depth != 0) {
            var fail_lows: usize = 0;
            var fail_highs: usize = 0;
            var window: i16 = @intCast(std.math.clamp(@abs(@as(i32, score) - last_score), 15, 100));
            var alpha: i16 = score - window;
            var beta: i16 = score + window;
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
                        hash_history,
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
                    window *|= 2;
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
                    hash_history,
                ),
            } orelse break;
        }
        last_score = score;
        collectPv(&board_copy, 0);
        if (!silence_output and !shouldStopSearching()) {
            writeInfo(score, move, @intCast(depth), search_params.frc);
        }
        if (nodes + qnodes >= search_params.maxNodes()) {
            break;
        }
        if (timer.read() >= search_params.softTime()) {
            break;
        }
        if (eval.isMateScore(score)) break;
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

const ScoreType = enum {
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
};

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
    @memset(&repetition_table, 0);
}

pub fn resetHard() void {
    move_ordering.reset();
    resetSoft();
    @memset(std.mem.sliceAsBytes(tt), 0);
}

var repetition_check_fast: u64 = 0;
var repetition_table: [8192]u8 = undefined;
var pv_moves: [256]Move = undefined;
var num_pv_moves: usize = 0;
var tt: []align(16) TTEntry align(64) = &.{};
var nodes: u64 = 0;
var qnodes: u64 = 0;
var timer: std.time.Timer = undefined;
var shutdown = false;
var hard_time: u64 = 0;
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
