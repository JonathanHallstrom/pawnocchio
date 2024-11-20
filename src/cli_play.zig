const std = @import("std");

const lib = @import("lib.zig");

const Board = lib.Board;
const Move = lib.Move;
const MoveInverse = lib.MoveInverse;

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var move_buf: [1024]Move = undefined;

    var previous_move_inverses = std.ArrayList(MoveInverse).init(allocator);
    defer previous_move_inverses.deinit();
    var board = try lib.Board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    while (true) {
        std.debug.print("Turn: {s}\n", .{@tagName(board.turn)});
        std.debug.print("Board state:\n", .{});
        for (board.toString()) |row| {
            std.debug.print("{s}\n", .{row});
        }

        if (board.gameOver()) |result| {
            if (result == .tie) {
                std.debug.print("Result: tie\n", .{});
            } else {
                std.debug.print("Result: {s} won!\n", .{@tagName(result)});
            }
            break;
        }

        const num_moves = board.getAllMoves(&move_buf, board.getSelfCheckSquares());
        const moves = move_buf[0..num_moves];

        std.debug.print("Available moves:\n", .{});
        for (0..num_moves, moves) |i, move| {
            std.debug.print("{d: >3}. {}\n", .{ i + 1, move });
        }

        var input_buf: [32]u8 = undefined;
        var choice: ?usize = null;
        while (choice == null) {
            std.debug.print("Choose a move (1-{}):", .{num_moves});
            const input_str = stdin.readUntilDelimiter(&input_buf, '\n') catch continue;
            const input_num = std.fmt.parseInt(usize, input_str, 10) catch continue;
            if (1 <= input_num and input_num <= num_moves) {
                choice = input_num - 1;
            }
        }
        const chosen_move = moves[choice.?];
        try previous_move_inverses.append(board.playMove(chosen_move));
        std.debug.print("\n", .{});
    }
}
