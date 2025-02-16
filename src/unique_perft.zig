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

    for (0..10) |depth| {
        var hashes = std.ArrayList(u64).init(allocator);
        defer hashes.deinit();
        var board = Board.init();
        try board.perftSingleThreadedNonBulkWriteHashes(&move_buf, depth + 1, &hashes);
        std.mem.sort(u64, hashes.items, void{}, std.sort.asc(u64));
        var last = hashes.items[0] +% 1;
        var unique_count: usize = 0;
        for (hashes.items) |hash| {
            unique_count += @intFromBool(hash != last);
            last = hash;
        }
        std.debug.print("depth {} total {} unique {}\n", .{ depth + 1, hashes.items.len, unique_count });
    }
}
