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

fn search(comptime turn: Side, board: *Board, cur_depth: u8, depth_remaining: u8, alpha_inp: i16, beta: i16, move_buf: []Move, hash_history: *std.ArrayList(u64)) anyerror!struct { i16, Move } {
    var alpha = alpha_inp;
    nodes += 1;
    if (cur_depth > 0 and nodes % 1024 == 0 and (shouldStopSearching() or timer.read() >= hard_time)) return error.EarlyShutdown;
    const move_count, const masks = movegen.getMovesWithInfo(turn, false, board.*, move_buf);
    if (move_count == 0) {
        return .{ if (masks.checks == 0) 0 else eval.mateIn(cur_depth), Move.null_move };
    }

    {
        var repetitions: u8 = 0;
        for (hash_history.items[hash_history.items.len - @min(hash_history.items.len, board.halfmove_clock) .. hash_history.items.len]) |zobrist| {
            if (board.zobrist == zobrist) {
                repetitions += 1;
            }
        }
        if (repetitions >= 3) return .{ 0, Move.null_move };
    }

    if (depth_remaining == 0) return .{ evaluate(board.*), move_buf[0] };

    move_ordering.mvvLva(board, move_buf[0..move_count]);
    var best_score = -checkmate_score;
    var best_move = move_buf[0];
    for (move_buf[0..move_count]) |move| {
        const inv = board.playMove(turn, move);
        defer board.undoMove(turn, inv);
        hash_history.appendAssumeCapacity(board.zobrist);
        defer _ = hash_history.pop();

        const tmpscore, _ = try search(
            turn.flipped(),
            board,
            cur_depth + 1,
            depth_remaining - 1,
            -beta,
            -alpha,
            move_buf[move_count..],
            hash_history,
        );
        const score = -tmpscore;

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
    return .{ best_score, best_move };
}

pub fn reset() void {
    nodes = 0;
}

pub fn iterativeDeepening(board: Board, search_params: engine.SearchParameters, move_buf: []Move, hash_history: *std.ArrayList(u64), silence_output: bool) !engine.SearchResult {
    reset();
    timer = try std.time.Timer.start();
    hard_time = search_params.hardTime();
    // const soft_time =search_params.
    // while (timer.read() < searchParams.)
    var board_copy = board;
    var score: i16 = 0;
    var move = Move.null_move;
    for (0..search_params.maxDepth()) |depth| {
        score, move = switch (board.turn) {
            inline else => |turn| search(turn, &board_copy, 0, @intCast(depth), -checkmate_score, checkmate_score, move_buf, hash_history),
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
            .qnodes = 0,
            .ns_used = timer.read(),
        },
    };
}

var nodes: u64 = 0;
var timer: std.time.Timer = undefined;
var hard_time: u64 = 0;
