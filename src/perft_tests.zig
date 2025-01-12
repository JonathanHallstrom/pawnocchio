const std = @import("std");
const Board = @import("Board.zig");
const Move = @import("Move.zig").Move;

threadlocal var move_buf: [32768]Move = undefined;
threadlocal var hash_buf: [32768]struct { u64, u64 } = .{.{ 0, 0 }} ** 32768;
fn handleLine(line: []const u8, total_time: *u64, total_positions: *u64, test_zobrist: bool) void {
    var parts = std.mem.tokenizeSequence(u8, line, " ;D");
    const fen = parts.next().?;

    var board = Board.parseFen(fen) catch |e| std.debug.panic("fen error: {}", .{e});
    var depth: u8 = undefined;
    while (parts.next()) |depth_info| {
        var depth_parts = std.mem.tokenizeScalar(u8, depth_info, ' ');
        depth = std.fmt.parseInt(u8, depth_parts.next() orelse {
            std.debug.panic("invalid depth info: {s}", .{depth_info});
        }, 10) catch |e| std.debug.panic("parse error: {}", .{e});
        const expected_perft = std.fmt.parseInt(u64, depth_parts.next() orelse {
            std.debug.panic("invalid depth info: {s}", .{depth_info});
        }, 10) catch |e| std.debug.panic("parse error: {}", .{e});
        var timer = std.time.Timer.start() catch std.debug.panic("couldn't start timer\n", .{});
        const actual_perft = board.perftSingleThreaded(&move_buf, depth, false);
        _ = @atomicRmw(u64, total_time, .Add, timer.lap(), .seq_cst);
        _ = @atomicRmw(u64, total_positions, .Add, expected_perft, .seq_cst);
        std.testing.expectEqual(expected_perft, actual_perft) catch |e| {
            std.log.err("error for: {s} at depth: {}", .{ fen, depth });
            std.log.err("expected: {}", .{expected_perft});
            std.log.err("got:      {}", .{actual_perft});
            std.debug.panic("error: {}", .{e});
        };
        if (test_zobrist and actual_perft < 1 << 20) {
            board.perftZobrist(&move_buf, &hash_buf, depth) catch {
                std.debug.panic("{s} at depth {}\n", .{ fen, depth });
            };
        }
    }
    std.log.info("{s} passed, total positions: {}", .{ fen, total_positions.* });
}

fn runTests(file: []const u8, allocator: std.mem.Allocator, result_writer: anytype, test_zobrist: bool) !void {
    const test_file = try std.fs.cwd().openFile(file, .{});
    defer test_file.close();
    var br = std.io.bufferedReader(test_file.reader());
    var timer = try std.time.Timer.start();
    var line_buf: [1024]u8 = undefined;
    var total_time: u64 = 0;
    var total_positions: u64 = 0;

    var line_number: u64 = 0;

    var tp: std.Thread.Pool = undefined;
    const cpus = std.Thread.getCpuCount() catch 1;
    // const cpus = 1;

    try tp.init(.{
        .allocator = allocator,
        .n_jobs = @intCast(cpus),
    });
    defer tp.deinit();
    var wg = std.Thread.WaitGroup{};

    var arena_wrapper = std.heap.ArenaAllocator.init(allocator);
    defer arena_wrapper.deinit();

    while (br.reader().readUntilDelimiter(&line_buf, '\n') catch null) |line| {
        const line_cp = try arena_wrapper.allocator().dupe(u8, line);
        line_number += 1;

        while (tp.run_queue.len() > 2 * cpus)
            try std.Thread.yield();
        std.log.info("starting tests for line: '{s}' (#{})\n", .{ line, line_number });
        tp.spawnWg(&wg, handleLine, .{ line_cp, &total_time, &total_positions, test_zobrist });

        const wall_time = timer.read();
        try result_writer.print("total nodes: {}, wall time: {}, cpu time {}\n", .{ total_positions, std.fmt.fmtDuration(wall_time), std.fmt.fmtDuration(total_time) });
    }
    tp.waitAndWork(&wg);

    const wall_time = timer.read();

    try result_writer.print("total nodes: {}, wall time: {}, cpu time {}\n", .{ total_positions, std.fmt.fmtDuration(wall_time), std.fmt.fmtDuration(total_time) });
    try result_writer.print("overall nps: {} (cpu time)\n", .{@as(u128, std.time.ns_per_s) * total_positions / (total_time | 1)});
    try result_writer.print("overall nps: {} (wall time)\n", .{@as(u128, std.time.ns_per_s) * total_positions / (wall_time | 1)});
}

test "perft tests" {
    try runTests("tests/reduced.epd", std.testing.allocator, std.io.null_writer, true);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .retain_metadata = true, .thread_safe = true, .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next();
    defer args.deinit();

    try runTests(args.next() orelse "tests/reduced.epd", allocator, std.io.getStdOut().writer(), false);
}
