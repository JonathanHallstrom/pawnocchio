const std = @import("std");
const engine = @import("engine.zig");

const Board = @import("Board.zig");
const Move = @import("Move.zig").Move;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    const log_file_path = "/home/jonathanhallstrom/dev/zig/pawnocchio/LOGFILE.pawnocchio_log";

    if (std.fs.openFileAbsolute(log_file_path, .{ .mode = .write_only })) |lf| {
        lf.writer().writeAll(fbs.getWritten()) catch {};
        lf.writer().writeAll(msg) catch {};
        lf.close();
    } else |_| {
        std.debug.print("{s}\n", .{fbs.getWritten()});
        std.debug.print("{s}\n", .{msg});
    }
    const defaultPanic = if (@hasDecl(std.builtin, "default_panic")) std.builtin.default_panic else std.debug.defaultPanic;
    defaultPanic(msg, error_return_trace, ret_addr);
}

var log_mutex = std.Thread.Mutex{};
pub fn writeLog(comptime fmt: []const u8, args: anytype) void {
    log_mutex.lock();
    defer log_mutex.unlock();
    fbs.writer().print(fmt, args) catch {};
}

var error_log_buf: [64 << 20]u8 = undefined;
var fbs = std.io.fixedBufferStream(&error_log_buf);

var stdout: std.fs.File = undefined;
var write_mutex = std.Thread.Mutex{};
pub fn write(comptime fmt: []const u8, args: anytype) void {
    write_mutex.lock();
    defer write_mutex.unlock();
    var buf: [4096]u8 = undefined;
    const to_print = std.fmt.bufPrint(&buf, fmt, args) catch "";

    writeLog("sent: {s}", .{to_print});
    stdout.writer().writeAll(to_print) catch |e| {
        std.debug.panic("writing to stdout failed! Error: {}\n", .{e});
    };
}

pub fn main() !void {
    stdout = std.io.getStdOut();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const process_name = args.next() orelse "pawnocchio";
    _ = process_name;

    var hash_history = try std.ArrayList(u64).initCapacity(allocator, 16384);
    defer hash_history.deinit();
    const move_buf = try allocator.alloc(Move, 16384);
    defer allocator.free(move_buf);

    engine.reset();
    try engine.setTTSize(256);

    if (args.next()) |arg| {
        if (std.ascii.endsWithIgnoreCase(arg, "bench")) {
            const fens = [_][]const u8{
                "r3k2r/2pb1ppp/2pp1q2/p7/1nP1B3/1P2P3/P2N1PPP/R2QK2R w KQkq - 0 14",
                "4rrk1/2p1b1p1/p1p3q1/4p3/2P2n1p/1P1NR2P/PB3PP1/3R1QK1 b - - 2 24",
                "r3qbrk/6p1/2b2pPp/p3pP1Q/PpPpP2P/3P1B2/2PB3K/R5R1 w - - 16 42",
                "6k1/1R3p2/6p1/2Bp3p/3P2q1/P7/1P2rQ1K/5R2 b - - 4 44",
                "8/8/1p2k1p1/3p3p/1p1P1P1P/1P2PK2/8/8 w - - 3 54",
                "7r/2p3k1/1p1p1qp1/1P1Bp3/p1P2r1P/P7/4R3/Q4RK1 w - - 0 36",
                "r1bq1rk1/pp2b1pp/n1pp1n2/3P1p2/2P1p3/2N1P2N/PP2BPPP/R1BQ1RK1 b - - 2 10",
                "3r3k/2r4p/1p1b3q/p4P2/P2Pp3/1B2P3/3BQ1RP/6K1 w - - 3 87",
                "2r4r/1p4k1/1Pnp4/3Qb1pq/8/4BpPp/5P2/2RR1BK1 w - - 0 42",
                "4q1bk/6b1/7p/p1p4p/PNPpP2P/KN4P1/3Q4/4R3 b - - 0 37",
                "2q3r1/1r2pk2/pp3pp1/2pP3p/P1Pb1BbP/1P4Q1/R3NPP1/4R1K1 w - - 2 34",
                "1r2r2k/1b4q1/pp5p/2pPp1p1/P3Pn2/1P1B1Q1P/2R3P1/4BR1K b - - 1 37",
                "r3kbbr/pp1n1p1P/3ppnp1/q5N1/1P1pP3/P1N1B3/2P1QP2/R3KB1R b KQkq - 0 17",
                "8/6pk/2b1Rp2/3r4/1R1B2PP/P5K1/8/2r5 b - - 16 42",
                "1r4k1/4ppb1/2n1b1qp/pB4p1/1n1BP1P1/7P/2PNQPK1/3RN3 w - - 8 29",
                "8/p2B4/PkP5/4p1pK/4Pb1p/5P2/8/8 w - - 29 68",
                "3r4/ppq1ppkp/4bnp1/2pN4/2P1P3/1P4P1/PQ3PBP/R4K2 b - - 2 20",
                "5rr1/4n2k/4q2P/P1P2n2/3B1p2/4pP2/2N1P3/1RR1K2Q w - - 1 49",
                "1r5k/2pq2p1/3p3p/p1pP4/4QP2/PP1R3P/6PK/8 w - - 1 51",
                "q5k1/5ppp/1r3bn1/1B6/P1N2P2/BQ2P1P1/5K1P/8 b - - 2 34",
                "r1b2k1r/5n2/p4q2/1ppn1Pp1/3pp1p1/NP2P3/P1PPBK2/1RQN2R1 w - - 0 22",
                "r1bqk2r/pppp1ppp/5n2/4b3/4P3/P1N5/1PP2PPP/R1BQKB1R w KQkq - 0 5",
                "r1bqr1k1/pp1p1ppp/2p5/8/3N1Q2/P2BB3/1PP2PPP/R3K2n b Q - 1 12",
                "r1bq2k1/p4r1p/1pp2pp1/3p4/1P1B3Q/P2B1N2/2P3PP/4R1K1 b - - 2 19",
                "r4qk1/6r1/1p4p1/2ppBbN1/1p5Q/P7/2P3PP/5RK1 w - - 2 25",
                "r7/6k1/1p6/2pp1p2/7Q/8/p1P2K1P/8 w - - 0 32",
                "r3k2r/ppp1pp1p/2nqb1pn/3p4/4P3/2PP4/PP1NBPPP/R2QK1NR w KQkq - 1 5",
                "3r1rk1/1pp1pn1p/p1n1q1p1/3p4/Q3P3/2P5/PP1NBPPP/4RRK1 w - - 0 12",
                "5rk1/1pp1pn1p/p3Brp1/8/1n6/5N2/PP3PPP/2R2RK1 w - - 2 20",
                "8/1p2pk1p/p1p1r1p1/3n4/8/5R2/PP3PPP/4R1K1 b - - 3 27",
                "8/4pk2/1p1r2p1/p1p4p/Pn5P/3R4/1P3PP1/4RK2 w - - 1 33",
                "8/5k2/1pnrp1p1/p1p4p/P6P/4R1PK/1P3P2/4R3 b - - 1 38",
                "8/8/1p1kp1p1/p1pr1n1p/P6P/1R4P1/1P3PK1/1R6 b - - 15 45",
                "8/8/1p1k2p1/p1prp2p/P2n3P/6P1/1P1R1PK1/4R3 b - - 5 49",
                "8/8/1p4p1/p1p2k1p/P2npP1P/4K1P1/1P6/3R4 w - - 6 54",
                "8/8/1p4p1/p1p2k1p/P2n1P1P/4K1P1/1P6/6R1 b - - 6 59",
                "8/5k2/1p4p1/p1pK3p/P2n1P1P/6P1/1P6/4R3 b - - 14 63",
                "8/1R6/1p1K1kp1/p6p/P1p2P1P/6P1/1Pn5/8 w - - 0 67",
                "1rb1rn1k/p3q1bp/2p3p1/2p1p3/2P1P2N/PP1RQNP1/1B3P2/4R1K1 b - - 4 23",
                "4rrk1/pp1n1pp1/q5p1/P1pP4/2n3P1/7P/1P3PB1/R1BQ1RK1 w - - 3 22",
                "r2qr1k1/pb1nbppp/1pn1p3/2ppP3/3P4/2PB1NN1/PP3PPP/R1BQR1K1 w - - 4 12",
                "2r2k2/8/4P1R1/1p6/8/P4K1N/7b/2B5 b - - 0 55",
                "6k1/5pp1/8/2bKP2P/2P5/p4PNb/B7/8 b - - 1 44",
                "2rqr1k1/1p3p1p/p2p2p1/P1nPb3/2B1P3/5P2/1PQ2NPP/R1R4K w - - 3 25",
                "r1b2rk1/p1q1ppbp/6p1/2Q5/8/4BP2/PPP3PP/2KR1B1R b - - 2 14",
                "6r1/5k2/p1b1r2p/1pB1p1p1/1Pp3PP/2P1R1K1/2P2P2/3R4 w - - 1 36",
                "rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2",
                "2rr2k1/1p4bp/p1q1p1p1/4Pp1n/2PB4/1PN3P1/P3Q2P/2RR2K1 w - f6 0 20",
                "3br1k1/p1pn3p/1p3n2/5pNq/2P1p3/1PN3PP/P2Q1PB1/4R1K1 w - - 0 23",
                "2r2b2/5p2/5k2/p1r1pP2/P2pB3/1P3P2/K1P3R1/7R w - - 23 93",
            };
            var num_nodes: u64 = 0;
            var time: u64 = 0;
            const depth = 7;
            for (fens) |fen| {
                const board = try Board.parseFen(fen);
                hash_history.appendAssumeCapacity(board.zobrist);
                defer _ = hash_history.pop();

                const info = engine.searchSync(board, .{ .depth = depth }, move_buf, &hash_history, true);

                num_nodes += info.stats.nodes + info.stats.qnodes;
                time += info.stats.ns_used;
            }

            write("{} nodes {} nps\n", .{ num_nodes, num_nodes * std.time.ns_per_s / time });
            return;
        }
    }

    var board = Board.init();
    var frc: bool = false;
    hash_history.appendAssumeCapacity(board.zobrist);
    const stdin = std.io.getStdIn();
    var br = std.io.bufferedReader(stdin.reader());

    const reader = br.reader();

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
        writeLog("got: {s}\n", .{line});

        if (std.ascii.eqlIgnoreCase(command, "uci")) {
            write("id name pawnocchio 0.0.6\n", .{});
            write("id author Jonathan Hallström\n", .{});
            write("option name Hash type spin default 256 min 1 max 65535\n", .{});
            write("option name Threads type spin default 1 min 1 max 1\n", .{});
            write("option name UCI_Chess960 type check default false\n", .{});
            write("uciok\n", .{});
        } else if (std.ascii.eqlIgnoreCase(command, "ucinewgame")) {
            engine.reset();
            board = Board.init();
            frc = false;
        } else if (std.ascii.eqlIgnoreCase(command, "setoption")) {
            if (!std.ascii.eqlIgnoreCase("name", parts.next() orelse "")) continue;
            const name = parts.next() orelse "";
            if (!std.ascii.eqlIgnoreCase("value", parts.next() orelse "")) continue;
            const value = parts.next() orelse "";

            if (std.ascii.eqlIgnoreCase("Hash", name)) {
                const size = std.fmt.parseInt(u16, value, 10) catch {
                    writeLog("invalid hash size: '{s}'\n", .{value});
                    continue;
                };
                try engine.setTTSize(size);
            }

            if (std.ascii.eqlIgnoreCase("UCI_Chess960", name)) {
                if (std.ascii.eqlIgnoreCase("true", value)) {
                    frc = true;
                }
                if (std.ascii.eqlIgnoreCase("false", value)) {
                    frc = false;
                }
            }
        } else if (std.ascii.eqlIgnoreCase(command, "isready")) {
            write("readyok\n", .{});
        } else if (std.ascii.eqlIgnoreCase(command, "d")) {
            for (board.toString()) |row| {
                write("{s}\n", .{row});
            }
        } else if (std.ascii.eqlIgnoreCase(command, "go")) {
            var max_depth_opt: ?u8 = null;
            var max_nodes_opt: ?u64 = null;

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
                        writeLog("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };

                    mate_finding_depth = depth;
                }

                if (std.ascii.eqlIgnoreCase(command_part, "perft")) {
                    const depth_to_parse = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);
                    const depth = std.fmt.parseInt(usize, depth_to_parse, 10) catch {
                        writeLog("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };
                    var timer = std.time.Timer.start() catch unreachable;
                    const nodes = board.perftSingleThreaded(move_buf, depth, true);
                    const elapsed_ns = timer.read();
                    write("Nodes searched: {} in {}ms ({} nps)\n", .{ nodes, elapsed_ns / std.time.ns_per_ms, @as(u128, nodes) * std.time.ns_per_s / elapsed_ns });
                    continue :main_loop;
                }
                if (std.ascii.eqlIgnoreCase(command_part, "depth")) {
                    const depth_to_parse = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    max_depth_opt = std.fmt.parseInt(u8, depth_to_parse, 10) catch {
                        writeLog("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };
                }
                if (std.ascii.eqlIgnoreCase(command_part, "nodes")) {
                    const nodes_to_parse = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    max_nodes_opt = std.fmt.parseInt(u64, nodes_to_parse, 10) catch {
                        writeLog("invalid nodes: '{s}'\n", .{nodes_to_parse});
                        continue;
                    };
                }
                if (std.ascii.eqlIgnoreCase(command_part, "wtime")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    white_time = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        writeLog("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
                if (std.ascii.eqlIgnoreCase(command_part, "btime")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    black_time = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        writeLog("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
                if (std.ascii.eqlIgnoreCase(command_part, "movetime")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    move_time = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        writeLog("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
                if (std.ascii.eqlIgnoreCase(command_part, "winc")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    white_increment = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        writeLog("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
                if (std.ascii.eqlIgnoreCase(command_part, "binc")) {
                    const time = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    black_increment = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
                        writeLog("invalid time: '{s}'\n", .{time});
                        continue;
                    });
                }
                if (std.ascii.eqlIgnoreCase(command_part, "infinite")) {
                    engine.setInfinite();
                }
            }
            if (mate_finding_depth) |depth| max_depth_opt = @min(max_depth_opt orelse 255, depth * 2 + 1);

            const my_time = if (board.turn == .white) white_time else black_time;
            const my_increment = if (board.turn == .white) white_increment else black_increment;

            // const my_time = @min(white_time, black_time);
            // const my_increment = @min(white_increment, black_increment);

            // 10ms  seems fine
            const overhead = @min(10 * std.time.ns_per_ms, my_time / 2);

            var soft_time = my_time / 20 + my_increment * 3 / 4;
            var hard_time = if (move_time) |mt| mt -| overhead else my_time / 10 -| overhead;
            // std.debug.print("{}\n", .{std.fmt.fmtDuration(hard_time)});
            hard_time = @max(std.time.ns_per_ms / 4, hard_time);
            soft_time = @min(soft_time, hard_time);

            if (hard_time <= 10) {
                _ = engine.searchSync(
                    board,
                    .{
                        .soft_time = soft_time,
                        .hard_time = hard_time,
                        .depth = max_depth_opt,
                        .frc = frc,
                    },
                    move_buf,
                    &hash_history,
                    false,
                );
            } else {
                engine.startAsyncSearch(
                    board,
                    .{
                        .soft_time = soft_time,
                        .hard_time = hard_time,
                        .depth = max_depth_opt,
                        .frc = frc,
                    },
                    move_buf,
                    &hash_history,
                );
            }
        } else if (std.ascii.eqlIgnoreCase(command, "stop")) {
            engine.stopAsyncSearch();
        } else if (std.ascii.eqlIgnoreCase(command, "quit")) {
            return;
        } else {
            const started_with_position = std.ascii.eqlIgnoreCase(command, "position");
            const sub_command = parts.next() orelse "";
            const rest = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);

            var pos_iter = std.mem.tokenizeSequence(u8, if (started_with_position) rest else line, " moves ");

            if (std.ascii.eqlIgnoreCase(sub_command, "fen") or !started_with_position) {
                const fen_to_parse = std.mem.trim(u8, pos_iter.next() orelse {
                    writeLog("no fen: '{s}'\n", .{rest});
                    continue;
                }, &std.ascii.whitespace);

                board = Board.parseFen(fen_to_parse) catch {
                    writeLog("invalid fen: '{s}'\n", .{fen_to_parse});
                    continue;
                };

                // detect FRC/shredder fen castling string
                var fen_part_iter = std.mem.tokenizeScalar(u8, fen_to_parse, ' ');
                _ = fen_part_iter.next(); // discard board part
                _ = fen_part_iter.next(); // discard side to move part
                if (fen_part_iter.next()) |castling_rights_string| {
                    for (castling_rights_string) |ch| {
                        switch (ch) {
                            'K', 'k', 'Q', 'q', '-' => continue,
                            'A'...'H' => frc = true,
                            'a'...'h' => frc = true,
                            else => {},
                        }
                    }
                }
            } else if (std.ascii.eqlIgnoreCase(sub_command, "startpos")) {
                board = Board.init();
            }
            hash_history.clearRetainingCapacity();
            hash_history.appendAssumeCapacity(board.zobrist);
            var move_iter = std.mem.tokenizeAny(u8, pos_iter.rest(), &std.ascii.whitespace);
            while (move_iter.next()) |played_move| {
                if (std.ascii.eqlIgnoreCase(played_move, "moves")) continue;
                _ = board.playMoveFromStr(played_move) catch {
                    writeLog("invalid move: '{s}'\n", .{played_move});
                    continue;
                };
                hash_history.appendAssumeCapacity(board.zobrist);
            }
        }
    }
}
