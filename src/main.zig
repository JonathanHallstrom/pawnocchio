const std = @import("std");

const lib = @import("lib.zig");

pub fn main() !void {
    const board = try lib.Board.fromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    for (board.toString()) |row| {
        std.debug.print("{s}\n", .{row});
    }
    std.debug.print("\n", .{});
    for (board.flip().toString()) |row| {
        std.debug.print("{s}\n", .{row});
    }
}
