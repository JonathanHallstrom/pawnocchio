const std = @import("std");

const lib = @import("lib.zig");

const Board = lib.Board;
const Move = lib.Move;
const MoveInverse = lib.MoveInverse;

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.next();
    var play_against_engine = false;
    var engine_starts = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "play_against_engine")) play_against_engine = true;
        if (std.mem.eql(u8, arg, "engine_starts")) engine_starts = true;
    }

    if (play_against_engine)
        std.debug.print("playing against engine\n", .{});

    const move_buf: []Move = try allocator.alloc(Move, 1 << 20);
    defer allocator.free(move_buf);

    var previous_move_inverses = std.ArrayList(MoveInverse).init(allocator);
    defer previous_move_inverses.deinit();
    var board = try lib.Board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    while (true) {
        std.debug.print("Turn: {s}\n", .{@tagName(board.turn)});
        std.debug.print("Board state:\n", .{});
        for (board.toString()) |row| {
            std.debug.print("{s}\n", .{row});
        }
        if (board.gameOver()) |result| {
            if (result == .tie) {
                std.debug.print("Result: tie\n", .{});
            } else {
                std.debug.print("Result: {s} won!\n", .{@tagName(result)});
            }
            break;
        }

        if (play_against_engine and (engine_starts == (board.turn == .white))) {
            const engine = @import("negamax_engine.zig");
            const num_moves = board.getAllMovesUnchecked(move_buf, board.getSelfCheckSquares());
            const moves = move_buf[0..num_moves];

            var best_eval: i32 = -1000_000_000;
            var best_move: Move = undefined;
            for (moves) |move| {
                if (board.playMovePossibleSelfCheck(move)) |inv| {
                    defer board.undoMove(inv);

                    const eval = -engine.negaMax(board, 3, move_buf[num_moves..]);
                    if (eval > best_eval) {
                        best_eval = eval;
                        best_move = move;
                    }
                }
            }
            try previous_move_inverses.append(board.playMove(best_move));
        } else {
            const num_moves = board.getAllMoves(move_buf, board.getSelfCheckSquares());
            const moves = move_buf[0..num_moves];
            std.debug.print("Available moves:\n", .{});
            for (moves) |move| {
                if (move.from().getType() != move.to().getType()) {
                    std.debug.print("{s}{s}{c}\n", .{ move.from().prettyPos(), move.to().prettyPos(), move.to().getType().letter() });
                } else {
                    std.debug.print("{s}{s}\n", .{ move.from().prettyPos(), move.to().prettyPos() });
                }
            }

            var input_buf: [32]u8 = undefined;
            var choice: ?usize = null;
            while (choice == null) {
                std.debug.print("Choose a move:", .{});
                const input_str = std.mem.trim(u8, stdin.readUntilDelimiter(&input_buf, '\n') catch continue, &std.ascii.whitespace);

                for (0..num_moves, moves) |i, move| {
                    var move_str_buf: [6]u8 = undefined;
                    const move_str = try if (move.from().getType() != move.to().getType())
                        std.fmt.bufPrint(&move_str_buf, "{s}{s}{c}", .{ move.from().prettyPos(), move.to().prettyPos(), move.to().getType().letter() })
                    else
                        std.fmt.bufPrint(&move_str_buf, "{s}{s}", .{ move.from().prettyPos(), move.to().prettyPos() });

                    if (std.ascii.startsWithIgnoreCase(input_str, move_str)) {
                        choice = i;
                    }
                }
            }
            const chosen_move = moves[choice.?];
            try previous_move_inverses.append(board.playMove(chosen_move));
            std.debug.print("\n", .{});
        }
    }
}
