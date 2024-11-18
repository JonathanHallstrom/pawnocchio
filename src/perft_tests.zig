const std = @import("std");
const lib = @import("lib.zig");
const Board = lib.Board;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .retain_metadata = true, .thread_safe = true, .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const move_buf = try allocator.alloc(lib.Move, 1 << 20);
    defer allocator.free(move_buf);

    const test_file = try std.fs.cwd().openFile("tests/standard.epd", .{});
    defer test_file.close();
    var br = std.io.bufferedReader(test_file.reader());

    var inp = br.reader();
    var line_buf: [1024]u8 = undefined;
    var total_time: u64 = 0;
    var total_positions: u64 = 0;
    while (inp.readUntilDelimiter(&line_buf, '\n') catch null) |line| {
        var parts = std.mem.tokenizeSequence(u8, line, " ;D");
        const fen = parts.next().?;

        const board = try Board.parseFen(fen);
        while (parts.next()) |depth_info| {
            var depth_parts = std.mem.tokenizeScalar(u8, depth_info, ' ');
            const depth = try std.fmt.parseInt(u8, depth_parts.next() orelse {
                std.debug.panic("invalid depth info: {s}\n", .{depth_info});
            }, 10);
            const expected_perft = try std.fmt.parseInt(u64, depth_parts.next() orelse {
                std.debug.panic("invalid depth info: {s}\n", .{depth_info});
            }, 10);
            var timer = try std.time.Timer.start();
            const actual_perft = try board.perftMultiThreaded(move_buf, depth, allocator);
            total_time += timer.lap();
            total_positions += expected_perft;

            if (expected_perft != actual_perft) {
                std.debug.print("error for: {s} at depth: {}\n", .{ fen, depth });
                std.debug.print("expected: {}\n", .{expected_perft});
                std.debug.print("got: {}\n", .{actual_perft});
            }
        }
        std.debug.print("{s} passed\n", .{fen});
    }
    std.debug.print("{}/{}\n", .{ Board.in_check_cnt, Board.total });
    std.debug.print("overall nps: {}", .{std.time.ns_per_s * total_positions / total_time});
}
