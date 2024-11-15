const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("lib.zig");

const Board = lib.Board;
const Move = lib.Move;

fn getMovesAlloc(board: *const Board, allocator: Allocator) ![]Move {
    var buf: [400]Move = undefined;
    const num_moves = board.getAllMovesUnchecked(&buf);
    return try allocator.dupe(Move, buf[0..num_moves]);
}

var move_buf: [1 << 20]Move = undefined;
var move_buf_len: usize = 0;

fn perft(board: *Board, depth_remaining: usize) usize {
    if (depth_remaining == 0) return 0;
    const num_moves = board.getAllMovesUnchecked(move_buf[move_buf_len..]);
    const moves = move_buf[move_buf_len..][0..num_moves];
    move_buf_len += num_moves;
    defer move_buf_len -= num_moves;
    var res: usize = 0;
    for (moves) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);
            if (depth_remaining == 1) {
                res += 1;
            } else {
                const next = perft(board, depth_remaining - 1);
                res += next;
            }
        }
    }
    return res;
}

pub fn main() !void {
    // var board = try lib.Board.fromFen("rnbqkbnr/1ppppppp/p7/P7/8/8/1PPPPPPP/RNBQKBNR b KQkq - 0 1");
    var board = Board.init();
    const stdout = std.io.getStdOut().writer();

    // const max_depth = 5;
    // std.debug.print("{}\n", .{perft(&board, max_depth)});
    for (1..8) |max_depth| {
        var timer = try std.time.Timer.start();
        const num_moves = perft(&board, max_depth);
        const elapsed = timer.lap();
        try stdout.print("{}\n", .{num_moves});
        std.debug.print("{}\n", .{num_moves});
        std.debug.print("time : {}\n", .{std.fmt.fmtDuration(elapsed)});
        std.debug.print("Moves/s: {}\n", .{num_moves * 1000_000_000 / elapsed});
        std.debug.print("Million moves/s: {}\n", .{num_moves * 1000 / elapsed});
    }
}
