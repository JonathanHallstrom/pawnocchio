const std = @import("std");
const lib = @import("lib.zig");
const engine = @import("engine.zig");

const Board = lib.Board;
const Move = lib.Move;

pub var log_writer = std.io.getStdErr().writer();

const stdout = std.io.getStdOut();

pub fn write(comptime fmt: []const u8, args: anytype) void {
    log_writer.print("sent: " ++ fmt, args) catch {};
    stdout.writer().print(fmt, args) catch |e| {
        std.debug.panic("writing to stdout failed! Error: {}\n", .{e});
    };
}

pub fn main() !void {
    // disgusting ik
    const log_file_path = "/home/jonathanhallstrom/dev/zig/pawnocchio/LOGFILE.pawnocchio_log";
    const log_file = std.fs.openFileAbsolute(log_file_path, .{ .mode = .write_only }) catch null;
    defer if (log_file) |log| log.close();

    if (log_file) |lf| {
        _ = &lf;
        // log_writer = lf.writer();
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn();
    var br = std.io.bufferedReader(stdin.reader());

    const reader = br.reader();

    var board = Board.init();

    const move_buf = try allocator.alloc(Move, 1 << 20);
    defer allocator.free(move_buf);

    var line_buf: [1 << 20]u8 = undefined;
    var my_turn: ?lib.Side = null;
    while (reader.readUntilDelimiter(&line_buf, '\n') catch null) |line_raw| {
        const line = std.mem.trim(u8, line_raw, &std.ascii.whitespace);
        var parts = std.mem.tokenizeScalar(u8, line, ' ');

        const command = parts.next() orelse {
            continue; // empty command
        };

        const sub_command = parts.next() orelse "";

        try log_writer.print("got: {s}\n", .{line});

        if (std.ascii.eqlIgnoreCase(command, "uci")) {
            try stdout.writeAll("id name pawnocchio 0.0.1\n");
            try stdout.writeAll("uciok\n");
        }

        if (std.ascii.eqlIgnoreCase(command, "ucinewgame")) {
            my_turn = null;
            engine.reset();
            board = Board.init();
        }

        if (std.ascii.eqlIgnoreCase(command, "position")) {
            const rest = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);

            var pos_iter = std.mem.tokenizeSequence(u8, rest, " moves ");

            if (std.ascii.eqlIgnoreCase(sub_command, "fen")) {
                const fen_to_parse = std.mem.trim(u8, pos_iter.next() orelse {
                    try log_writer.print("no fen: '{s}'\n", .{rest});
                    continue;
                }, &std.ascii.whitespace);

                board = Board.parseFen(fen_to_parse) catch {
                    try log_writer.print("invalid fen: '{s}'\n", .{fen_to_parse});
                    continue;
                };
            } else if (std.ascii.eqlIgnoreCase(sub_command, "startpos")) {
                board = Board.init();
            }
            var move_iter = std.mem.tokenizeAny(u8, pos_iter.rest(), &std.ascii.whitespace);
            while (move_iter.next()) |played_move| {
                if (std.ascii.eqlIgnoreCase(played_move, "moves")) continue;
                _ = board.playMoveFromSquare(played_move, move_buf) catch {
                    try log_writer.print("invalid move: '{s}'\n", .{played_move});
                    continue;
                };
            }
        }

        if (std.ascii.eqlIgnoreCase(command, "isready")) {
            write("readyok\n", .{});
        }

        if (std.ascii.eqlIgnoreCase(command, "d")) {
            for (board.toString()) |row| {
                write("{s}\n", .{row});
            }
        }

        if (std.ascii.eqlIgnoreCase(command, "go")) {
            if (std.ascii.eqlIgnoreCase(sub_command, "perft")) {
                const depth_to_parse = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);
                const depth = std.fmt.parseInt(usize, depth_to_parse, 10) catch {
                    try log_writer.print("invalid depth: '{s}'\n", .{depth_to_parse});
                    continue;
                };
                write("Nodes searched: {}\n", .{try board.perftMultiThreaded(move_buf, depth, allocator)});
            }

            if (my_turn == null) my_turn = board.turn;
            if (!std.meta.eql(my_turn, board.turn)) continue;

            var max_depth: usize = 10;
            var max_nodes: u64 = std.math.maxInt(u64);

            // by default assume each player has 1000s
            // completely arbitrarily chosen value
            var white_time: u64 = 1000 * std.time.ns_per_s;
            var black_time: u64 = 1000 * std.time.ns_per_s;

            while (parts.next()) |command_part| {
                if (std.ascii.eqlIgnoreCase(command_part, "depth")) {
                    const depth_to_parse = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    max_depth = std.fmt.parseInt(usize, depth_to_parse, 10) catch {
                        try log_writer.print("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };
                }
                if (std.ascii.eqlIgnoreCase(command_part, "nodes")) {
                    const nodes_to_parse = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    max_nodes = std.fmt.parseInt(usize, nodes_to_parse, 10) catch {
                        try log_writer.print("invalid nodes: '{s}'\n", .{nodes_to_parse});
                        continue;
                    };
                }
                if (std.ascii.eqlIgnoreCase(command_part, "wtime")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    white_time = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        try log_writer.print("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
                if (std.ascii.eqlIgnoreCase(command_part, "btime")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    black_time = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        try log_writer.print("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
            }

            // const my_time = if (board.turn == .white) white_time else black_time;

            // 250ms to quit seems fine

            const hard_time = @min(white_time, black_time) / 30;

            const move_info = engine.findMove(board, move_buf, max_depth, max_nodes, hard_time, hard_time);
            const move = move_info.move;
            const depth_evaluated = move_info.depth_evaluated;
            const eval = move_info.eval;
            const nodes_evaluated = move_info.nodes_evaluated;
            write("info depth {} score cp {} nodes {} pv {s}\n", .{ depth_evaluated, eval, nodes_evaluated, move.pretty().slice() });
            write("bestmove {s}\n", .{move.pretty().slice()});
        }

        if (std.ascii.eqlIgnoreCase(command, "quit")) {
            return;
        }
    }
}
