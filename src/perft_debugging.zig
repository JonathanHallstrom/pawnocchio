// mega disgusting way of doing it please dont copy this its just for my own debugging....

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

// please forgive me
fn stockfishPerft(fen: []const u8, depth: usize, allocator: Allocator) !usize {
    var buf: [256]u8 = undefined;
    const python_code =
        \\import sys
        \\import subprocess
        \\
        \\args = sys.argv[1:]
        \\fen_args = args[:-1]
        \\
        \\fen = " ".join(fen_args)
        \\depth = int(args[-1])
        \\
        \\command = f"""echo "position fen {fen}
        \\go perft {depth}" | stockfish"""
        \\
        \\print(subprocess.run(command, shell=True, text=True, capture_output=True).stdout.split()[-1])
    ;
    const argv = &[_][]const u8{ "/usr/bin/python3", "-c", python_code, fen, try std.fmt.bufPrint(&buf, "{}", .{depth}) };

    const proc = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    return try std.fmt.parseInt(usize, std.mem.trim(u8, proc.stdout, "\n\t "), 10);
}

fn perft(board: *Board, move_buf: []Move, depth_remaining: usize) usize {
    if (depth_remaining == 0) return 0;
    const num_moves = board.getAllMovesUnchecked(move_buf);
    const moves = move_buf[0..num_moves];
    var res: usize = 0;
    for (moves) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);
            res += if (depth_remaining == 1) 1 else perft(board, move_buf[num_moves..], depth_remaining - 1);
        }
    }
    return res;
}

fn findPerftErrorPos(fen: []const u8, move_buf: []Move, depth: usize, allocator: Allocator) !void {
    var board = try Board.fromFen(fen);

    const my_perft = perft(&board, move_buf, depth);
    const correct_perft = try stockfishPerft(fen, depth, allocator);
    if (my_perft == correct_perft) return;

    const num_moves = board.getAllMovesUnchecked(move_buf);
    const moves = move_buf[0..num_moves];

    if (depth == 1) {
        std.debug.print("{s}\n", .{fen});
        std.debug.print("found: {}\n", .{my_perft});
        std.debug.print("correct: {}\n", .{correct_perft});

        for (moves) |move| {
            if (move.from().getType() != move.to().getType()) {
                std.debug.print("{s}{s}{c}: 1\n", .{ move.from().prettyPos(), move.to().prettyPos(), move.to().getType().letter() });
            } else {
                std.debug.print("{s}{s}: 1\n", .{ move.from().prettyPos(), move.to().prettyPos() });
            }
        }
        return error.FoundPos;
    }

    for (moves) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);
            try findPerftErrorPos(board.toFen().slice(), move_buf[num_moves..], depth - 1, allocator);
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    var fen: []const u8 = &.{};
    while (args.next()) |arg| {
        fen = try std.mem.join(allocator, " ", &.{ std.mem.trim(u8, fen, " "), arg });
    }
    const move_buf: []Move = try allocator.alloc(Move, 1 << 20);

    const max_depth = 6;
    for (1..max_depth) |depth| {
        try findPerftErrorPos(fen, move_buf, depth, allocator);
        std.debug.print("no errors found at a depth of {}\n", .{depth});
    }
}
