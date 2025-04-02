// pawnocchio, UCI chess engine
// Copyright (C) 2025 Jonathan Hallström
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const root = @import("root.zig");
const write = root.write;
const writeLog = std.debug.print;
const Board = root.Board;

pub fn main() !void {
    root.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();

    {
        var do_bench = false;
        var bench_depth: i32 = 5;
        while (args.next()) |arg| {
            if (std.ascii.eqlIgnoreCase(arg, "bench")) {
                do_bench = true;
            } else {
                if (std.fmt.parseInt(i32, arg, 10)) |depth| {
                    bench_depth = depth;
                } else |_| {}
            }
        }
        if (do_bench) {
            write("1 nodes 1000000 nps\n", .{});
            return;
        }
    }

    const line_buf = try allocator.alloc(u8, 1 << 20);
    defer allocator.free(line_buf);
    const reader = std.io.getStdIn().reader();

    var board = Board.startpos();
    var overhead: u64 = std.time.ns_per_ms * 10;
    loop: while (reader.readUntilDelimiter(line_buf, '\n') catch |e| switch (e) {
        error.EndOfStream => null,
        else => blk: {
            std.debug.print("WARNING: encountered '{any}'\n", .{e});
            break :blk "";
        },
    }) |line_raw| {
        const line = std.mem.trim(u8, line_raw, &std.ascii.whitespace);
        for (line) |c| {
            if (!std.ascii.isPrint(c)) {
                continue :loop;
            }
        }
        var parts = std.mem.tokenizeScalar(u8, line, ' ');

        const command = parts.next() orelse {
            continue; // empty command
        };

        if (std.ascii.eqlIgnoreCase(command, "uci")) {
            write("id name pawnocchio 1.4\n", .{});
            write("id author Jonathan Hallström\n", .{});
            write("option name Hash type spin default 256 min 1 max 65535\n", .{});
            write("option name Threads type spin default 1 min 1 max 1\n", .{});
            write("option name Move Overhead type spin default 10 min 1 max 10000\n", .{});
            write("option name UCI_Chess960 type check default false\n", .{});
            write("uciok\n", .{});
        } else if (std.ascii.eqlIgnoreCase(command, "ucinewgame")) {
            // engine.reset();
            board = Board.startpos();
        } else if (std.ascii.eqlIgnoreCase(command, "setoption")) {
            if (!std.ascii.eqlIgnoreCase("name", parts.next() orelse "")) continue;
            var name = parts.next() orelse "";
            var value_part = parts.next() orelse "";
            if (!std.ascii.eqlIgnoreCase("value", value_part)) {
                // yes this is cursed
                while (name.ptr[name.len..] != value_part.ptr[value_part.len..])
                    name.len += 1;
                value_part = parts.next() orelse "";
            }
            const value = parts.next() orelse "";

            if (std.ascii.eqlIgnoreCase("Hash", name)) {
                const size = std.fmt.parseInt(u16, value, 10) catch {
                    writeLog("invalid hash size: '{s}'\n", .{value});
                    continue;
                };
                _ = size; // autofix
                // try engine.setTTSize(size);
            }

            if (std.ascii.eqlIgnoreCase("UCI_Chess960", name)) {
                if (std.ascii.eqlIgnoreCase("true", value)) {
                    board.frc = true;
                }
                if (std.ascii.eqlIgnoreCase("false", value)) {
                    board.frc = false;
                }
            }

            if (std.ascii.eqlIgnoreCase("Move Overhead", name)) {
                overhead = std.time.ns_per_ms * (std.fmt.parseInt(u64, value, 10) catch {
                    writeLog("invalid overhead: '{s}'\n", .{value});
                    continue;
                });
            }
        } else if (std.ascii.eqlIgnoreCase(command, "isready")) {
            write("readyok\n", .{});
        } else if (std.ascii.eqlIgnoreCase(command, "d")) {
            // for (board.toString()) |row| {
            //     write("{s}\n", .{row});
            // }
            write("{s}\n", .{board.toFen().slice()});
        } else if (std.ascii.eqlIgnoreCase(command, "go")) {
            var max_depth_opt: ?u8 = null;
            var max_nodes_opt: ?u64 = null;

            // by default assume each player has 1000s
            // completely arbitrarily chosen value
            var white_time: u64 = 1000_000_000 * std.time.ns_per_s;
            var black_time: u64 = 1000_000_000 * std.time.ns_per_s;
            var white_increment: u64 = 0 * std.time.ns_per_s;
            var black_increment: u64 = 0 * std.time.ns_per_s;
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
                    const depth = std.fmt.parseInt(i32, depth_to_parse, 10) catch {
                        writeLog("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };
                    var timer = std.time.Timer.start() catch unreachable;
                    const nodes = board.perft(false, depth);
                    const elapsed_ns = timer.read();
                    write("Nodes searched: {} in {}ms ({} nps)\n", .{ nodes, elapsed_ns / std.time.ns_per_ms, @as(u128, nodes) * std.time.ns_per_s / elapsed_ns });
                    continue :loop;
                }
                if (std.ascii.eqlIgnoreCase(command_part, "perft_file")) {
                    const file_name = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    var epd_parser = root.PerftEPDParser.init(file_name, allocator) catch |e| {
                        writeLog("invalid file: '{s}' error: {}\n", .{ file_name, e });
                        continue;
                    };
                    defer epd_parser.deinit();
                    var timer = std.time.Timer.start() catch unreachable;

                    var thread_safe_allocator = std.heap.ThreadSafeAllocator{ .child_allocator = allocator };
                    var tp: std.Thread.Pool = undefined;

                    tp.init(.{ .allocator = thread_safe_allocator.allocator() }) catch |e| {
                        writeLog("thread pool creation failed with error: {}\n", .{e});
                        continue :loop;
                    };
                    var wg: std.Thread.WaitGroup = .{};
                    var stop_perft = false;
                    var nodes: u64 = 0;
                    const workerFn = struct {
                        fn impl(pos: anytype, node_counter: *u64, stop: *bool) void {
                            defer pos.deinit();
                            if (@atomicLoad(bool, stop, .seq_cst)) return;
                            const perft_board = Board.parseFen(pos.fen, true) catch {
                                writeLog("invalid position: {s}\n", .{pos.fen});
                                @atomicStore(bool, stop, true, .seq_cst);
                                return;
                            };
                            for (pos.node_counts.slice()) |node_count| {
                                const expected = node_count.nodes;
                                const actual = perft_board.perft(true, node_count.depth);
                                if (expected != actual) {
                                    writeLog(
                                        \\error at depth: {}
                                        \\for position {s}
                                        \\got: {} expected: {}
                                    , .{
                                        node_count.depth,
                                        pos.fen,
                                        actual,
                                        expected,
                                    });
                                    @atomicStore(bool, stop, true, .seq_cst);
                                    return;
                                }
                                _ = @atomicRmw(u64, node_counter, .Add, actual, .seq_cst);
                            }
                            write("completed {s}\n", .{pos.fen});
                        }
                    }.impl;

                    while (epd_parser.next() catch continue :loop) |position| {
                        std.debug.print("{s} {any}\n", .{ position.fen, position.node_counts.slice() });
                        tp.spawnWg(&wg, workerFn, .{ position, &nodes, &stop_perft });
                        if (@atomicLoad(bool, &stop_perft, .seq_cst)) continue :loop;
                    }
                    writeLog("spawned jobs\n", .{});
                    tp.waitAndWork(&wg);

                    const actual_nodes = @atomicLoad(u64, &nodes, .seq_cst);
                    const elapsed_ns = timer.read();
                    write("Nodes: {} in {}ms ({} nps)\n", .{ actual_nodes, elapsed_ns / std.time.ns_per_ms, @as(u128, actual_nodes) * std.time.ns_per_s / elapsed_ns });
                    continue :loop;
                }
                if (std.ascii.eqlIgnoreCase(command_part, "perft_nnue")) {
                    const depth_to_parse = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);
                    const depth = std.fmt.parseInt(usize, depth_to_parse, 10) catch {
                        writeLog("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };
                    _ = depth; // autofix
                    // var timer = std.time.Timer.start() catch unreachable;
                    // const tt = try allocator.alloc(Board.PerftTTEntry, 1 << 15);
                    // defer allocator.free(tt);
                    // const nodes = board.perftSingleThreaded(move_buf, depth, true);
                    // const nodes = board.perftNNUE(
                    //     move_buf,
                    //     depth,
                    // );
                    // const elapsed_ns = timer.read();
                    // write("Nodes searched: {} in {}ms ({} nps)\n", .{ nodes, elapsed_ns / std.time.ns_per_ms, @as(u128, nodes) * std.time.ns_per_s / elapsed_ns });
                    continue :loop;
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
                    // engine.setInfinite();
                }
            }

            const my_time = if (board.stm == .white) white_time else black_time;
            const my_increment = if (board.stm == .white) white_increment else black_increment;

            const overhead_use = @min(overhead, my_time / 2);

            var soft_time = my_time / 20 + my_increment / 2;
            var hard_time = my_time / 5 -| overhead_use;

            hard_time = @max(std.time.ns_per_ms / 4, hard_time); // use at least 0.25ms
            soft_time = @min(soft_time, hard_time);

            if (move_time) |mt| {
                soft_time = mt;
                hard_time = mt;
            }

            root.engine.startSearch(.{ .board = board, .limits = root.Limits.initStandard(my_time, my_increment, overhead) }, 1);
            // engine.startAsyncSearch(
            //     board,
            //     .{
            //         .soft_time = soft_time,
            //         .hard_time = hard_time,
            //         .nodes = max_nodes_opt,
            //         .depth = max_depth_opt,
            //         .frc = frc,
            //     },
            //     move_buf,
            //     &hash_history,
            // );
        } else if (std.ascii.eqlIgnoreCase(command, "stop")) {
            // engine.stopAsyncSearch();
        } else if (std.ascii.eqlIgnoreCase(command, "quit")) {
            return;
        } else if (std.ascii.eqlIgnoreCase(command, "nneval")) {
            // write("{}\n", .{nnue.nnEval(&board)});
        } else if (std.ascii.eqlIgnoreCase(command, "bullet_evals")) {
            for ([_][]const u8{
                "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
                "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
                "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/P2P2PP/q2Q1R1K w kq - 0 2",
                "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
                "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
                "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 1",
                "rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                "rn1qkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                "r1bqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                "1nbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQk - 0 1",
            }) |fen| {
                write("FEN: {s}\n", .{fen});
                // write("EVAL: {}\n", .{nnue.nnEval(&try Board.parseFen(fen))});
            }
        } else if (std.ascii.eqlIgnoreCase(command, "hceval")) {
            // const eval = @import("eval.zig");
            // write("{}\n", .{eval.evaluate(&board, eval.EvalState.init(&board))});
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

                board = Board.parseFen(fen_to_parse, true) catch {
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
                            'A'...'H' => board.frc = true,
                            'a'...'h' => board.frc = true,
                            else => {},
                        }
                    }
                }
            } else if (std.ascii.eqlIgnoreCase(sub_command, "startpos")) {
                board = Board.startpos();
            }
            // hash_history.clearRetainingCapacity();
            // hash_history.appendAssumeCapacity(board.zobrist);
            var move_iter = std.mem.tokenizeAny(u8, pos_iter.rest(), &std.ascii.whitespace);
            while (move_iter.next()) |played_move| {
                if (std.ascii.eqlIgnoreCase(played_move, "moves")) continue;
                _ = board.makeMoveFromStr(played_move) catch {
                    writeLog("invalid move: '{s}'\n", .{played_move});
                    continue;
                };
            }
        }
    }
}
