const std = @import("std");
const lib = @import("lib.zig");
const Board = lib.Board;

fn parallelSort(
    comptime T: type,
    items: []T,
    context: anytype,
    comptime lessThanFn: fn (context: @TypeOf(context), lhs: T, rhs: T) bool,
    allocator: std.mem.Allocator,
) !void {
    const worker = struct {
        fn impl(
            worker_items: []T,
            ctx: @TypeOf(context),
        ) void {
            std.sort.pdq(T, worker_items, ctx, lessThanFn);
        }
    }.impl;
    const n = items.len;
    var num_threads = std.Thread.getCpuCount() catch 1;
    var thread_pool: std.Thread.Pool = undefined;
    try thread_pool.init(.{
        .allocator = allocator,
        .n_jobs = @intCast(num_threads),
    });
    defer thread_pool.deinit();
    while (num_threads > 1) : (num_threads >>= 1) {
        const items_per_thread = (n + num_threads - 1) / num_threads;
        var wg = std.Thread.WaitGroup{};
        var rem_items = items;
        for (0..num_threads) |_| {
            const amt = @min(items_per_thread, rem_items.len);
            if (amt == 0) break;
            const cur = rem_items[0..amt];
            rem_items = rem_items[amt..];
            thread_pool.spawnWg(&wg, worker, .{ cur, context });
        }
        thread_pool.waitAndWork(&wg);
    }
    std.sort.pdq(T, items, context, lessThanFn);
}

fn runTests(file: []const u8, allocator: std.mem.Allocator, result_writer: anytype) !void {
    const move_buf = try allocator.alloc(lib.Move, 1 << 20);
    defer allocator.free(move_buf);
    const test_file = try std.fs.cwd().openFile(file, .{});
    defer test_file.close();
    var br = std.io.bufferedReader(test_file.reader());

    var line_buf: [1024]u8 = undefined;
    var total_time: u64 = 0;
    var total_positions: u64 = 0;
    const Entry = packed struct {
        zobrist: u64,
        other_hash: u64,

        fn cmp(_: void, lhs: @This(), rhs: @This()) bool {
            if (lhs.zobrist != rhs.zobrist)
                return lhs.zobrist < rhs.zobrist;
            return lhs.other_hash < rhs.other_hash;
        }
    };
    var zobrist_list = std.ArrayList(Entry).init(std.heap.page_allocator);
    defer zobrist_list.deinit();
    var last_size: usize = 0;
    while (br.reader().readUntilDelimiter(&line_buf, '\n') catch null) |line| {
        var parts = std.mem.tokenizeSequence(u8, line, " ;D");
        const fen = parts.next().?;

        const board = try Board.parseFen(fen);
        var depth: u8 = undefined;
        while (parts.next()) |depth_info| {
            var depth_parts = std.mem.tokenizeScalar(u8, depth_info, ' ');
            depth = try std.fmt.parseInt(u8, depth_parts.next() orelse {
                std.debug.panic("invalid depth info: {s}", .{depth_info});
            }, 10);
            const expected_perft = try std.fmt.parseInt(u64, depth_parts.next() orelse {
                std.debug.panic("invalid depth info: {s}", .{depth_info});
            }, 10);
            var timer = try std.time.Timer.start();
            const actual_perft = try board.perftMultiThreaded(move_buf, depth, allocator);
            total_time += timer.lap();
            total_positions += expected_perft;
            var tmp = board;
            try tmp.perftZobrist(move_buf, depth, &zobrist_list);
            std.testing.expectEqual(expected_perft, actual_perft) catch |e| {
                std.log.err("error for: {s} at depth: {}", .{ fen, depth });
                std.log.err("expected: {}", .{expected_perft});
                std.log.err("got:      {}", .{actual_perft});
                return e;
            };
        }
        std.log.info("{s} passed, total positions: {}", .{ fen, total_positions });
        if (zobrist_list.items.len * @sizeOf(Entry) > 8 << 30 and zobrist_list.items.len > last_size * 5 / 4) { // if memory use exceeds 32GiB and has increased by more than 20%
            try parallelSort(Entry, zobrist_list.items, void{}, Entry.cmp, allocator);
            var last = zobrist_list.items[0];
            last.zobrist +%= 1;
            var unique_positions: usize = 0;
            for (0..zobrist_list.items.len) |i| {
                const cur = zobrist_list.items[i];
                zobrist_list.items[unique_positions] = cur;
                unique_positions += @intFromBool(cur.zobrist != last.zobrist or cur.other_hash != last.other_hash);
                last = cur;
            }
            zobrist_list.shrinkRetainingCapacity(unique_positions);
            last_size = zobrist_list.items.len;
        }
    }
    std.sort.pdq(Entry, zobrist_list.items, void{}, Entry.cmp);

    var last = zobrist_list.items[0];
    last.zobrist +%= 1;
    last.other_hash +%= 1;
    var zobrist_collisions: usize = 0;
    var other_hash_collisions: usize = 0;
    var unique_positions: usize = 0;
    for (0..zobrist_list.items.len) |i| {
        const cur = zobrist_list.items[i];
        zobrist_collisions += @intFromBool(cur.zobrist == last.zobrist and cur.other_hash != last.other_hash);
        other_hash_collisions += @intFromBool(cur.zobrist != last.zobrist and cur.other_hash == last.other_hash);
        zobrist_list.items[unique_positions] = cur;
        unique_positions += @intFromBool(cur.zobrist != last.zobrist or cur.other_hash != last.other_hash);
        last = cur;
    }
    zobrist_list.shrinkRetainingCapacity(unique_positions);

    std.log.info("overall nps: {}", .{std.time.ns_per_s * total_positions / total_time});
    std.log.info("zobrist collisions: {}/{} ({d:.5}%)", .{
        zobrist_collisions,
        unique_positions,
        @as(f64, @floatFromInt(zobrist_collisions * 100)) / @as(f64, @floatFromInt(unique_positions)),
    });
    result_writer.print("zobrist collisions: {}/{} ({d:.5}%)\n", .{
        zobrist_collisions,
        unique_positions,
        @as(f64, @floatFromInt(zobrist_collisions * 100)) / @as(f64, @floatFromInt(unique_positions)),
    }) catch {};

    std.log.info("other hash collisions: {}/{} ({d:.5}%)", .{
        other_hash_collisions,
        unique_positions,
        @as(f64, @floatFromInt(other_hash_collisions * 100)) / @as(f64, @floatFromInt(unique_positions)),
    });
    result_writer.print("other hash collisions: {}/{} ({d:.5}%)\n", .{
        other_hash_collisions,
        unique_positions,
        @as(f64, @floatFromInt(other_hash_collisions * 100)) / @as(f64, @floatFromInt(unique_positions)),
    }) catch {};

    var bit_counts: [65]usize = .{0} ** 65;
    for (zobrist_list.items) |item| bit_counts[@popCount(item.zobrist)] += 1;
    std.log.info("counts: {any}", .{bit_counts});
    result_writer.print("counts: {any}\n", .{bit_counts}) catch {};
}

test "perft tests" {
    try runTests("tests/reduced.epd", std.testing.allocator, std.io.null_writer);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .retain_metadata = true, .thread_safe = true, .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next();
    defer args.deinit();

    try runTests(args.next() orelse "tests/reduced.epd", allocator, std.io.getStdOut().writer());
}
