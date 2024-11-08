const std = @import("std");

const lib = @import("lib.zig");

pub fn main() !void {
    const board = try lib.Board.fromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    const stringified = board.toString();

    for (stringified) |row| {
        std.debug.print("{s}\n", .{row});
    }
}
