const std = @import("std");

const lib = @import("lib.zig");

const Board = lib.Board;
const Move = lib.Move;

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var move_buf: [1024]Move = undefined;

    var previous_moves = std.ArrayList(Move).init(allocator);
    var board = try lib.Board.fromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    while (true) {
        std.debug.print("Turn: {s}\n", .{@tagName(board.turn)});

        const num_moves = board.getAllMoves(&move_buf);
        const moves = move_buf[0..num_moves];

        std.debug.print("Board state:\n", .{});
        for (board.toString()) |row| {
            std.debug.print("{s}\n", .{row});
        }

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
        try board.playMove(chosen_move);
        try previous_moves.append(chosen_move);
        std.debug.print("\n", .{});
    }
}
