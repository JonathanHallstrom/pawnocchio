const std = @import("std");
const Board = @import("Board.zig");
const Move = @import("Move.zig").Move;

var move_buf: [32768]Move = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .retain_metadata = true, .thread_safe = true, .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next();
    defer args.deinit();

    const hashes: []std.ArrayList(u64) = try allocator.alloc(std.ArrayList(u64), Board.max_material_index);
    defer allocator.free(hashes);
    for (hashes) |*h| {
        h.* = std.ArrayList(u64).init(allocator);
    }
    defer for (hashes) |h| {
        h.deinit();
    };

    for (0..10) |depth| {
        var board = Board.init();
        var timer = try std.time.Timer.start();
        try board.perftSingleThreadedNonBulkWriteHashesByMaterial(&move_buf, depth + 1, hashes);
        const perft_time = timer.lap();
        for (hashes) |h| {
            std.sort.pdq(u64, h.items, void{}, std.sort.asc(u64));
        }
        const sort_time = timer.lap();
        var unique_count: u64 = 0;
        var total_count: u64 = 0;
        for (hashes) |*h| {
            if (h.items.len == 0) continue;
            var last = h.items[0] +% 1;
            for (h.items) |hash| {
                unique_count += @intFromBool(hash != last);
                last = hash;
            }
            total_count += h.items.len;
            h.clearRetainingCapacity();
        }
        const count_time = timer.lap();
        std.debug.print("depth {} total {} unique {}\n", .{ depth + 1, total_count, unique_count });
        std.debug.print("time to generate hashes: {} time to sort hashes: {} time to count unique: {} total: {}\n", .{
            std.fmt.fmtDuration(perft_time),
            std.fmt.fmtDuration(sort_time),
            std.fmt.fmtDuration(count_time),
            std.fmt.fmtDuration(perft_time + sort_time + count_time),
        });
    }
}
