const std = @import("std");
const lib = @import("lib.zig");

const Board = lib.Board;
const Move = lib.Move;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn();
    var br = std.io.bufferedReader(stdin.reader());
    const stdout = std.io.getStdOut();

    const reader = br.reader();

    var board = Board.init();
    var line_buf: [1024]u8 = undefined;
    while (reader.readUntilDelimiter(&line_buf, '\n') catch null) |line| {
        var parts = std.mem.tokenizeScalar(u8, line, ' ');

        const command = parts.next() orelse {
            continue; // empty command
        };

        const sub_command = parts.next() orelse "";

        if (std.mem.eql(u8, command, "position") and std.mem.eql(u8, sub_command, "fen")) {
            const fen_to_parse = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);
            board = Board.parseFen(fen_to_parse) catch {
                std.log.warn("invalid fen: '{s}'\n", .{fen_to_parse});
                continue;
            };
        }

        if (std.mem.eql(u8, command, "d")) {
            for (board.toString()) |row| {
                _ = try stdout.write(row ++ "\n");
            }
        }

        if (std.mem.eql(u8, command, "go")) {
            if (std.mem.eql(u8, sub_command, "perft")) {
                const depth_to_parse = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);
                const depth = std.fmt.parseInt(usize, depth_to_parse, 10) catch {
                    std.log.warn("invalid depth: '{s}'\n", .{depth_to_parse});
                    continue;
                };
                const move_buf = try allocator.alloc(Move, 1 << 20);
                defer allocator.free(move_buf);
                try stdout.writer().print("Nodes searched: {}\n", .{try board.perftMultiThreaded(move_buf, depth, allocator)});
            }
        }
    }
}
