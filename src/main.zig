const std = @import("std");
const lib = @import("lib.zig");
const engine = @import("engine.zig");

const Board = lib.Board;
const Move = lib.Move;

pub var log_writer: std.io.AnyWriter = undefined;

var stdout: std.fs.File = undefined;

pub fn write(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const to_print = std.fmt.bufPrint(&buf, fmt, args) catch "";

    const non_printable_opt = for (to_print) |c| {
        if (!std.ascii.isPrint(c) and !std.ascii.isWhitespace(c)) {
            break c;
        }
    } else null;
    if (non_printable_opt) |non_printable| {
        log_writer.print("tried to send non printable char: '{c}' (ascii: {})\n", .{ non_printable, @as(i32, non_printable) }) catch {};
        return;
    }
    log_writer.print("sent: {s}", .{to_print}) catch {};
    stdout.writer().writeAll(to_print) catch |e| {
        std.debug.panic("writing to stdout failed! Error: {}\n", .{e});
    };
}

pub fn main() !void {
    log_writer = std.io.getStdErr().writer().any();
    if (!std.debug.runtime_safety)
        log_writer = std.io.null_writer.any();
    stdout = std.io.getStdOut();
    // disgusting ik
    const log_file_path = "/home/jonathanhallstrom/dev/zig/pawnocchio/LOGFILE.pawnocchio_log";
    const log_file = std.fs.openFileAbsolute(log_file_path, .{ .mode = .write_only }) catch null;
    defer if (log_file) |log| log.close();

    if (log_file) |lf| {
        if (std.debug.runtime_safety) {
            log_writer = lf.writer().any();
        }
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn();
    var br = std.io.bufferedReader(stdin.reader());

    const reader = br.reader();

    var board = Board.init();
    var hash_history = try std.ArrayList(u64).initCapacity(allocator, 16384);
    defer hash_history.deinit();
    const move_buf = try allocator.alloc(Move, 1 << 20);
    defer allocator.free(move_buf);

    var line_buf: [1 << 20]u8 = undefined;
    main_loop: while (reader.readUntilDelimiter(&line_buf, '\n') catch null) |line_raw| {
        const line = std.mem.trim(u8, line_raw, &std.ascii.whitespace);
        for (line) |c| {
            if (!std.ascii.isPrint(c)) {
                continue :main_loop;
            }
        }
        var parts = std.mem.tokenizeScalar(u8, line, ' ');

        const command = parts.next() orelse {
            continue; // empty command
        };

        try log_writer.print("got: {s}\n", .{line});

        if (std.ascii.eqlIgnoreCase(command, "uci")) {
            try stdout.writeAll("id name pawnocchio 0.0.4\n");
            try stdout.writeAll("uciok\n");
        }

        if (std.ascii.eqlIgnoreCase(command, "ucinewgame")) {
            engine.reset();
            board = Board.init();
        }

        if (std.ascii.eqlIgnoreCase(command, "position")) {
            const sub_command = parts.next() orelse "";
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
            hash_history.clearRetainingCapacity();
            hash_history.appendAssumeCapacity(board.zobrist);
            var move_iter = std.mem.tokenizeAny(u8, pos_iter.rest(), &std.ascii.whitespace);
            while (move_iter.next()) |played_move| {
                if (std.ascii.eqlIgnoreCase(played_move, "moves")) continue;
                _ = board.playMoveFromSquare(played_move, move_buf) catch {
                    try log_writer.print("invalid move: '{s}'\n", .{played_move});
                    continue;
                };
                hash_history.appendAssumeCapacity(board.zobrist);
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
            var max_depth: u8 = 255;
            var max_nodes: u64 = std.math.maxInt(u64);

            // by default assume each player has 1000s
            // completely arbitrarily chosen value
            var white_time: u64 = 1000 * std.time.ns_per_s;
            var black_time: u64 = 1000 * std.time.ns_per_s;
            var white_increment: u64 = 1000 * std.time.ns_per_s;
            var black_increment: u64 = 1000 * std.time.ns_per_s;
            var mate_finding_depth: ?u8 = null;
            var move_time: ?u64 = null;

            while (parts.next()) |command_part| {
                if (std.ascii.eqlIgnoreCase(command_part, "mate")) {
                    const depth_to_parse = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    const depth = std.fmt.parseInt(u8, depth_to_parse, 10) catch {
                        try log_writer.print("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };

                    mate_finding_depth = depth;
                }

                if (std.ascii.eqlIgnoreCase(command_part, "perft")) {
                    const depth_to_parse = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);
                    const depth = std.fmt.parseInt(usize, depth_to_parse, 10) catch {
                        try log_writer.print("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };
                    write("Nodes searched: {}\n", .{try board.perftMultiThreaded(move_buf, depth, allocator)});
                    continue :main_loop;
                }
                if (std.ascii.eqlIgnoreCase(command_part, "depth")) {
                    const depth_to_parse = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    max_depth = std.fmt.parseInt(u8, depth_to_parse, 10) catch {
                        try log_writer.print("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };
                }
                if (std.ascii.eqlIgnoreCase(command_part, "nodes")) {
                    const nodes_to_parse = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    max_nodes = std.fmt.parseInt(u64, nodes_to_parse, 10) catch {
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
                if (std.ascii.eqlIgnoreCase(command_part, "movetime")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    move_time = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        try log_writer.print("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
                if (std.ascii.eqlIgnoreCase(command_part, "winc")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    white_increment = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        try log_writer.print("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
                if (std.ascii.eqlIgnoreCase(command_part, "binc")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    black_increment = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        try log_writer.print("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
            }
            if (mate_finding_depth) |depth| max_depth = @min(max_depth, depth * 2);
            log_writer.print("max depth: {}\n", .{max_depth}) catch {};

            // const my_time = if (board.turn == .white) white_time else black_time;

            const my_time = @min(white_time, black_time);
            const my_increment = @min(white_increment, black_increment);

            // 50ms to quit seems fine
            const soft_time = my_time / 20 + my_increment / 2;
            var hard_time = if (move_time) |mt| mt else @min(my_time / 10, my_time / 5 + my_increment / 2);
            hard_time -|= 50 * std.time.ns_per_ms;
            log_writer.print("max time:  {}\n", .{hard_time}) catch {};

            const move_info = engine.findMove(board, move_buf, max_depth, max_nodes, soft_time, hard_time, &hash_history);
            const move = move_info.move;
            write("bestmove {s}\n", .{move.pretty().slice()});
        }

        if (std.ascii.eqlIgnoreCase(command, "quit")) {
            return;
        }
    }
}
