const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("lib.zig");

const Board = lib.Board;
const Move = lib.Move;

fn getMovesAlloc(board: *const Board, allocator: Allocator) ![]Move {
    var buf: [400]Move = undefined;
    const num_moves = board.getAllMovesUnchecked(&buf);
    return try allocator.dupe(Move, buf[0..num_moves]);
}

var cur_depth: usize = 0;
fn perft(board: *Board, move_buf: []Move, depth_remaining: usize) usize {
    if (depth_remaining == 0) return 0;
    cur_depth += 1;
    defer cur_depth -= 1;
    const num_moves = board.getAllMovesUnchecked(move_buf);
    const moves = move_buf[0..num_moves];
    var res: usize = 0;
    for (moves) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);

            const next = if (depth_remaining == 1) 1 else perft(board, move_buf[num_moves..], depth_remaining - 1);
            if (cur_depth == 1) {
                if (move.from().getType() != move.to().getType()) {
                    std.debug.print("{s}{s}{c}: {}\n", .{ move.from().prettyPos(), move.to().prettyPos(), move.to().getType().letter(), next });
                } else {
                    std.debug.print("{s}{s}: {}\n", .{ move.from().prettyPos(), move.to().prettyPos(), next });
                }
            }
            res += next;
        }
    }
    return res;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    var parsed_board: ?Board = null;
    var fen: []const u8 = &.{};
    while (args.next()) |arg| {
        fen = try std.mem.join(allocator, " ", &.{ fen, arg });
        parsed_board = Board.fromFen(fen) catch null;
    }
    var board = parsed_board orelse Board.init();
    const outfile = try std.fs.cwd().openFile("out.txt", .{ .mode = .write_only });
    const output = outfile.writer();

    const move_buf: []Move = try allocator.alloc(Move, 1 << 20);
    for (1..7) |max_depth| {
        var timer = try std.time.Timer.start();
        const num_moves = perft(&board, move_buf, max_depth);
        const elapsed = timer.lap();
        try output.print("{}\n", .{num_moves});
        std.debug.print("{}\n", .{num_moves});
        std.debug.print("time : {}\n", .{std.fmt.fmtDuration(elapsed)});
        std.debug.print("Moves/s: {}\n", .{num_moves * 1000_000_000 / elapsed});
        std.debug.print("Million moves/s: {}\n", .{num_moves * 1000 / elapsed});
    }
}
