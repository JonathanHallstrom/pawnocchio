const std = @import("std");
const lib = @import("lib.zig");

const Board = lib.Board;
const Move = lib.Move;

var log_writer = std.io.getStdErr().writer();

const stdout = std.io.getStdOut();

fn write(comptime fmt: []const u8, args: anytype) void {
    log_writer.print("sent: " ++ fmt, args) catch unreachable;
    stdout.writer().print(fmt, args) catch |e| {
        std.debug.panic("writing to stdout failed! Error: {}\n", .{e});
    };
}

pub fn main() !void {
    // disgusting ik
    const log_file_path = "/home/jonathanhallstrom/dev/zig/pawnocchio/LOGFILE.pawnocchio_log";
    const log_file = std.fs.openFileAbsolute(log_file_path, .{ .mode = .read_write }) catch null;
    defer if (log_file) |log| log.close();

    if (log_file) |lf| {
        log_writer = lf.writer();
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

    var line_buf: [1024]u8 = undefined;
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

        if (std.ascii.eqlIgnoreCase(command, "position") and std.mem.eql(u8, sub_command, "fen")) {
            const rest = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);
            var fen_parts = std.mem.tokenizeSequence(u8, rest, "moves");

            const fen_to_parse = std.mem.trim(u8, fen_parts.next() orelse {
                try log_writer.print("no fen: '{s}'\n", .{rest});
                continue;
            }, &std.ascii.whitespace);

            board = Board.parseFen(fen_to_parse) catch {
                try log_writer.print("invalid fen: '{s}'\n", .{fen_to_parse});
                continue;
            };

            if (fen_parts.next()) |played_moves_string| {
                var move_iter = std.mem.tokenizeScalar(u8, played_moves_string, ' ');
                while (move_iter.next()) |played_move| {
                    _ = board.playMoveFromSquare(played_move, move_buf) catch {
                        try log_writer.print("invalid move: '{s}'\n", .{played_move});
                        continue;
                    };
                }
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

            if (std.ascii.eqlIgnoreCase(sub_command, "depth") or
                std.ascii.eqlIgnoreCase(sub_command, "nodes") or
                std.ascii.eqlIgnoreCase(sub_command, "wtime") or
                std.ascii.eqlIgnoreCase(sub_command, "movetime"))
            {
                const engine = @import("negamax_engine.zig");

                const eval, const move = engine.findMove(board, 4, move_buf);
                write("info depth {} score cp {} pv {s}\n", .{ 4, eval, move.pretty().slice() });
                write("bestmove {s}\n", .{move.pretty().slice()});
            }
        }

        if (std.ascii.eqlIgnoreCase(command, "quit")) {
            return;
        }
    }
}
