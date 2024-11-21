const std = @import("std");
const lib = @import("lib.zig");
const Board = lib.Board;

fn runTests(file: []const u8, allocator: std.mem.Allocator) !void {
    const move_buf = try allocator.alloc(lib.Move, 1 << 20);
    defer allocator.free(move_buf);
    const test_file = try std.fs.cwd().openFile(file, .{});
    defer test_file.close();
    var br = std.io.bufferedReader(test_file.reader());

    var line_buf: [1024]u8 = undefined;
    var total_time: u64 = 0;
    var total_positions: u64 = 0;
    while (br.reader().readUntilDelimiter(&line_buf, '\n') catch null) |line| {
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

            std.testing.expectEqual(expected_perft, actual_perft) catch |e| {
                std.log.err("error for: {s} at depth: {}\n", .{ fen, depth });
                std.log.err("expected: {}\n", .{expected_perft});
                std.log.err("got:      {}\n", .{actual_perft});
                return e;
            };
        }
        std.log.info("{s} passed\n", .{fen});
    }
    std.log.info("overall nps: {}\n", .{std.time.ns_per_s * total_positions / total_time});
}

test "perft tests" {
    try runTests("tests/reduced.epd", std.testing.allocator);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .retain_metadata = true, .thread_safe = true, .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next();
    defer args.deinit();

    try runTests(args.next() orelse "tests/reduced.epd", allocator);
}
