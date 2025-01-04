const std = @import("std");
const Move = @import("Move.zig");
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const eval = @import("eval.zig");
const move_ordering = @import("move_ordering.zig");

const testing = std.testing;
const assert = std.debug.assert;

const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const evaluate = eval.evaluate;
const checkmate_score = eval.checkmate_score;

const shouldStopSearching = engine.shouldStopSearching;

const max_search_depth = 255;

fn quiesce(comptime turn: Side, board: *Board, cur_depth: u8, alpha_inp: i16, beta: i16, move_buf: []Move) i16 {
    var alpha = alpha_inp;
    qnodes += 1;
    if (cur_depth > 0 and qnodes % 1024 == 0 and (shouldStopSearching() or timer.read() >= hard_time)) {
        shutdown = true;
        return 0;
    }
    const move_count = movegen.getCaptures(turn, board.*, move_buf);
    const static_eval = evaluate(board);
    if (move_count == 0) {
        return static_eval;
    }

    if (static_eval >= beta) return beta;
    if (static_eval > alpha) alpha = static_eval;

    move_ordering.mvvLva(board, move_buf[0..move_count]);
    var best_score = static_eval;
    for (move_buf[0..move_count]) |move| {
        if (!move.isCapture()) return -checkmate_score;
        const inv = board.playMove(turn, move);
        defer board.undoMove(turn, inv);

        const score = -quiesce(
            turn.flipped(),
            board,
            cur_depth + 1,
            -beta,
            -alpha,
            move_buf[move_count..],
        );
        if (shutdown)
            break;

        if (score > best_score) {
            best_score = score;
        }
        if (score > alpha) {
            if (score >= beta) {
                break;
            }
            alpha = score;
        }
    }
    return best_score;
}

fn search(comptime root: bool, comptime turn: Side, board: *Board, cur_depth: u8, depth_remaining: u8, alpha_inp: i16, beta: i16, move_buf: []Move, hash_history: *std.ArrayList(u64)) error{EarlyShutdown}!if (root) struct { i16, Move } else i16 {
    const result = struct {
        inline fn impl(score: i16, move: Move) if (root) struct { i16, Move } else i16 {
            return if (root) .{ score, move } else score;
        }
    }.impl;
    var alpha = alpha_inp;
    nodes += 1;
    if (cur_depth > 0 and nodes % 1024 == 0 and (shouldStopSearching() or timer.read() >= hard_time)) return error.EarlyShutdown;

    const move_count, const masks = movegen.getMovesWithInfo(turn, false, board.*, move_buf);
    const is_in_check = masks.checks != 0;
    if (move_count == 0) {
        return result(if (is_in_check) eval.mateIn(cur_depth) else 0, Move.null_move);
    }
    if (board.halfmove_clock >= 100) return result(0, move_buf[0]);

    {
        var repetitions: u8 = 0;
        const start = hash_history.items.len - @min(hash_history.items.len, board.halfmove_clock);
        for (hash_history.items[start..hash_history.items.len]) |zobrist| {
            if (board.zobrist == zobrist) {
                repetitions += 1;
            }
        }
        if (repetitions >= 3) return result(0, move_buf[0]);
    }

    if (depth_remaining == 0) {
        return result(evaluate(board), move_buf[0]);
        // const score = quiesce(turn, board, cur_depth, alpha_inp, beta, move_buf);
        // if (shutdown)
        //     return error.EarlyShutdown;
        // return result(score, move_buf[0]);
    }

    move_ordering.mvvLva(board, move_buf[0..move_count]);
    var best_score = -checkmate_score;
    var best_move = move_buf[0];
    for (move_buf[0..move_count]) |move| {
        const inv = board.playMove(turn, move);
        defer board.undoMove(turn, inv);
        hash_history.appendAssumeCapacity(board.zobrist);
        defer _ = hash_history.pop();

        const score = -(try search(
            false,
            turn.flipped(),
            board,
            cur_depth + 1,
            depth_remaining - 1,
            -beta,
            -alpha,
            move_buf[move_count..],
            hash_history,
        ));

        if (score > best_score) {
            best_score = score;
            best_move = move;

            if (score >= checkmate_score - max_search_depth) {
                break;
            }
        }
        if (score > alpha) {
            if (score >= beta) {
                break;
            }
            alpha = score;
        }
    }
    return result(best_score, best_move);
}

pub fn reset() void {
    nodes = 0;
    qnodes = 0;
    shutdown = false;
}

pub fn iterativeDeepening(board: Board, search_params: engine.SearchParameters, move_buf: []Move, hash_history: *std.ArrayList(u64), silence_output: bool) !engine.SearchResult {
    reset();
    assert(hash_history.items[hash_history.items.len - 1] == board.zobrist);
    timer = try std.time.Timer.start();
    hard_time = search_params.hardTime();
    // const soft_time =search_params.
    // while (timer.read() < searchParams.)
    var board_copy = board;
    var score: i16 = 0;
    var move = Move.null_move;
    for (0..search_params.maxDepth()) |depth| {
        score, move = switch (board.turn) {
            inline else => |turn| search(true, turn, &board_copy, 0, @intCast(depth), -checkmate_score, checkmate_score, move_buf, hash_history),
        } catch break;
        if (!silence_output) {
            write("info depth {} score cp {} nodes {} nps {} time {} pv {}\n", .{
                depth + 1,
                score,
                nodes,
                nodes * std.time.ns_per_s / timer.read(),
                (timer.read() + std.time.ns_per_ms / 2) / std.time.ns_per_ms,
                move,
            });
        }

        if (timer.read() >= search_params.softTime()) {
            break;
        }
    }
    engine.stoppedSearching();
    if (!silence_output)
        write("bestmove {}\n", .{move});
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

var nodes: u64 = 0;
var qnodes: u64 = 0;
var timer: std.time.Timer = undefined;
var shutdown = false;
var hard_time: u64 = 0;
