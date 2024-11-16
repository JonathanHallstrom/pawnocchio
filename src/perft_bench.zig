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

            const next = if (depth_remaining == 1) 1 else perft(board, depth_remaining - 1);
            // if (board.fullmove_clock == 2) {
            //     std.debug.print("{s}{s}: {}\n", .{ move.from().prettyPos(), move.to().prettyPos(), next });
            // }
            res += next;
        }
    }
    return res;
}

pub fn main() !void {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    _ = args.next();
    var parsed_board: ?Board = null;
    var fen: []const u8 = &.{};
    defer std.heap.page_allocator.free(fen);
    while (args.next()) |arg| {
        std.debug.print("arg: {s}\n", .{arg});
        fen = try std.mem.join(std.heap.page_allocator, " ", &.{ fen, arg });
        parsed_board = Board.fromFen(fen) catch null;
    }
    std.debug.print("{s}\n", .{fen});
    var board = parsed_board orelse Board.init();
    const stdout = std.io.getStdOut().writer();
    _ = &stdout;

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
