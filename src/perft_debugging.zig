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

var error_moves: [100]Move = undefined;
var num_error_moves: usize = 0;
fn findPerftErrorPos(fen: []const u8, move_buf: []Move, depth: usize, allocator: Allocator) !void {
    var board = try Board.parseFen(fen);

    const my_perft = try board.perftMultiThreaded(move_buf, depth, allocator);
    // const my_perft = board.perftSingleThreaded(move_buf, depth);
    const correct_perft = try stockfishPerft(fen, depth, allocator);
    if (my_perft == correct_perft) return;

    const num_moves = board.getAllMovesUnchecked(move_buf, board.getSelfCheckSquares());
    const moves = move_buf[0..num_moves];

    if (depth != 1) {
        for (moves) |move| {
            if (board.playMovePossibleSelfCheck(move)) |inv| {
                defer board.undoMove(inv);
                findPerftErrorPos(board.toFen().slice(), move_buf[num_moves..], depth - 1, allocator) catch |e| {
                    error_moves[num_error_moves] = move;
                    num_error_moves += 1;
                    std.debug.print("{}\n", .{move});
                    return e;
                };
            }
        }
    }
    std.debug.print("depth: {}\n", .{depth});
    std.debug.print("{s}\n", .{fen});
    std.debug.print("found: {}\n", .{my_perft});
    std.debug.print("correct: {}\n", .{correct_perft});

    for (moves) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);
            if (move.from().getType() != move.to().getType()) {
                std.debug.print("{s}{s}{c}: {}\n", .{
                    move.from().prettyPos(),
                    move.to().prettyPos(),
                    move.to().getType().toLetter(),
                    try board.perftMultiThreaded(move_buf[num_moves..], depth - 1, allocator),
                });
            } else {
                std.debug.print("{s}{s}: {}\n", .{
                    move.from().prettyPos(),
                    move.to().prettyPos(),
                    try board.perftMultiThreaded(move_buf[num_moves..], depth - 1, allocator),
                });
            }
        }
    }
    return error.FoundPos;
}

pub fn main() !void {
    defer std.debug.print("checks/total {}/{}\n", .{ Board.in_check_cnt.load(.acquire), Board.total.load(.acquire) });
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var threaded = std.heap.ThreadSafeAllocator{ .child_allocator = gpa.allocator() };
    const allocator = threaded.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    var fen: []const u8 = &.{};
    defer allocator.free(fen);
    while (args.next()) |arg| {
        fen = try std.mem.join(allocator, " ", &.{ std.mem.trim(u8, fen, " "), arg });
    }

    const TestInput = struct {
        fen_string: []const u8,
        depth: u8 = 4,
    };

    var test_inputs: []const TestInput = &.{.{ .fen_string = fen }};
    if (fen.len == 0) {
        test_inputs = &.{
            // https://www.chessprogramming.org/Perft_Results
            .{ .fen_string = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", .depth = 6 },
            .{ .fen_string = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -", .depth = 5 },
            .{ .fen_string = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -", .depth = 7 },
            .{ .fen_string = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", .depth = 6 },
            .{ .fen_string = "r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1", .depth = 6 },
            .{ .fen_string = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", .depth = 6 },
        };
    }
    const move_buf: []Move = try allocator.alloc(Move, 1 << 20);
    defer allocator.free(move_buf);

    for (test_inputs) |test_inp| {
        const fen_to_test = test_inp.fen_string;

        std.debug.print("testing: {s}\n", .{fen_to_test});
        for (1..test_inp.depth + 1) |depth| {
            try findPerftErrorPos(fen_to_test, move_buf, depth, allocator);
            std.debug.print("no errors found at a depth of {}\n", .{depth});
        }
    }
}
