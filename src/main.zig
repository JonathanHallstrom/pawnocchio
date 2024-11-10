const std = @import("std");

const lib = @import("lib.zig");
test {
    _ = lib;
}

pub fn main() !void {
    const board = try lib.Board.fromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    std.debug.print("--------\n", .{});
    for (board.toString()) |row| {
        std.debug.print("{s}\n", .{row});
    }
    std.debug.print("--------\n", .{});
    for (lib.Board.fromFenUnchecked("8/8/p7/P1P5/2K2k2/5PP1/2P4P/8 w - - 0 1").toString()) |row| {
        std.debug.print("{s}\n", .{row});
    }
    std.debug.print("--------\n", .{});
    for (lib.Board.fromFenUnchecked("8/1k6/8/8/8/8/8/K7 w - - 0 1").toString()) |row| {
        std.debug.print("{s}\n", .{row});
    }
    std.debug.print("--------\n", .{});

    var move_buf: [400]lib.Move = undefined;
    const num_moves = board.getQuietPawnMoves(&move_buf);
    const moves = move_buf[0..num_moves];
    std.debug.print("{any}\n", .{moves});
}
