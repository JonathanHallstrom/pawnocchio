const std = @import("std");
const Move = @import("Move.zig");
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const testing = std.testing;
const assert = std.debug.assert;

const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const eval = @import("eval.zig").eval;

const shouldStopSearching = engine.shouldStopSearching;

const checkmate_score: i16 = 16000;

var nodes: u64 = 0;

fn search(comptime turn: Side, board: *Board, cur_depth: u8, depth_remaining: u8, move_buf: []Move, hash_history: *std.ArrayList(u64)) anyerror!struct { i16, Move } {
    nodes += 1;
    if (cur_depth > 0 and shouldStopSearching()) return error.EarlyShutdown;
    const move_count, const masks = movegen.getMovesWithInfo(turn, false, board.*, move_buf);
    if (move_count == 0) {
        return .{ if (masks.checks == 0) 0 else -checkmate_score + cur_depth, Move.null_move };
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

    if (depth_remaining == 0) return .{ eval(board.*), move_buf[0] };

    var best_score = -checkmate_score;
    var best_move = Move.null_move;
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
            move_buf[move_count..],
            hash_history,
        );
        const score = -tmpscore;

        if (score > best_score) {
            best_score = score;
            best_move = move;
        }
    }

    return .{ best_score, best_move };
}

fn reset() void {
    nodes = 0;
}

pub fn iterativeDeepening(board: Board, search_params: engine.SearchParameters, move_buf: []Move, hash_history: *std.ArrayList(u64), silence_output: bool) !engine.SearchResult {
    reset();
    var timer = try std.time.Timer.start();
    _ = &timer; // autofix
    // const soft_time =search_params.
    // while (timer.read() < searchParams.)
    var board_copy = board;
    var score: i16 = 0;
    var move = Move.null_move;
    for (0..search_params.maxDepth()) |depth| {
        if (timer.read() >= search_params.hardTime()) break;

        score, move = switch (board.turn) {
            inline else => |turn| search(turn, &board_copy, 0, @intCast(depth), move_buf, hash_history),
        } catch break;
        if (!silence_output) {
            write("info depth {} score cp {} nodes {} nps {} pv {}\n", .{
                depth + 1,
                score,
                nodes,
                nodes * std.time.ns_per_s / timer.read(),
                move,
            });
        }

        if (timer.read() >= search_params.softTime()) {
            break;
        }
    }
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
