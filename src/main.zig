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
const command_line = @import("command_line.zig");
const write = root.write;
const writeLog = std.debug.print;
const Board = root.Board;
const Move = root.Move;

const VERSION_STRING = "1.9.2";

pub fn main() !void {
    root.init();
    defer root.deinit();
    defer {
        root.engine.stopSearch();
        root.engine.waitUntilDoneSearching();
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = if (std.debug.runtime_safety) gpa.allocator() else std.heap.smp_allocator;

    if (try command_line.handle(allocator, VERSION_STRING)) {
        return;
    }

    if (@import("builtin").os.tag == .windows) {
        const windows = @cImport(@cInclude("windows.h"));
        _ = windows.SetConsoleCP(windows.CP_UTF8);
        _ = windows.SetConsoleOutputCP(windows.CP_UTF8);
    }

    const line_buf = try allocator.alloc(u8, 1 << 20);
    defer allocator.free(line_buf);
    var line_writer = std.Io.Writer.fixed(line_buf);

    var stdin_buf: [4096]u8 = undefined;
    var stdin = std.fs.File.stdin();
    var reader = stdin.readerStreaming(&stdin_buf);

    var previous_positions = std.array_list.Managed(Board).init(allocator);
    defer previous_positions.deinit();
    var previous_moves = std.array_list.Managed(Move).init(allocator);
    defer previous_moves.deinit();

    var board = Board.startpos();
    try previous_positions.append(board);
    var overhead: u64 = std.time.ns_per_ms * 10;
    var syzygy_depth: u8 = 1;
    var min_depth: i32 = 0;
    var minimal: bool = false;
    var normalize: bool = true;
    var softnodes: bool = false;
    var weird_tcs: bool = false;
    loop: while (reader.interface.streamDelimiter(&line_writer, '\n') catch |e| switch (e) {
        error.EndOfStream => null,
        else => blk: {
            std.debug.print("WARNING: encountered '{any}'\n", .{e});
            break :blk 0;
        },
    }) |line_len| {
        defer _ = line_writer.consumeAll();
        std.debug.assert(try reader.interface.discardDelimiterInclusive('\n') == 1);
        const line = std.mem.trim(u8, line_buf[0..line_len], &std.ascii.whitespace);
        for (line) |c| {
            if (!std.ascii.isPrint(c)) {
                continue :loop;
            }
        }
        var parts = std.mem.tokenizeScalar(u8, line, ' ');

        const command = parts.next() orelse {
            try std.Thread.yield();
            continue; // empty command
        };

        if (std.ascii.eqlIgnoreCase(command, "uci")) {
            write("id name pawnocchio {s}\n", .{VERSION_STRING});
            write("id author Jonathan Hallström\n", .{});
            write("option name Hash type spin default 16 min 1 max 1048576\n", .{});
            write("option name Threads type spin default 1 min 1 max 65535\n", .{});
            write("option name Move Overhead type spin default 10 min 1 max 10000\n", .{});
            write("option name UCI_Chess960 type check default false\n", .{});
            write("option name MinDepth type spin default 0 min 0 max 255\n", .{});
            write("option name SyzygyPath type string default <empty>\n", .{});
            write("option name SyzygyProbeDepth type spin default 1 min 1 max 255\n", .{});
            write("option name NormalizeEval type check default true\n", .{});
            write("option name Minimal type check default false\n", .{});
            write("option name SoftNodes type check default false\n", .{});
            write("option name EnableWeirdTCs type check default false\n", .{});
            if (root.tuning.do_tuning) {
                for (root.tuning.tunables) |tunable| {
                    write(
                        "option name {s} type spin default {} min {} max {}\n",
                        .{ tunable.name, tunable.default, tunable.getMin(), tunable.getMax() },
                    );
                }
            }
            if (root.tuning.do_factorized_tuning) {
                const factorized_lmr = root.tuning.factorized_lmr;
                const factorized_lmr_params = root.tuning.factorized_lmr_params;
                inline for (0..3, .{ factorized_lmr.one, factorized_lmr.two, factorized_lmr.three }) |i, arr| {
                    inline for (arr, 0..) |val, j| {
                        write(
                            "option name factorized_{}_{} type spin default {} min {} max {}\n",
                            .{ i, j, val, factorized_lmr_params.min, factorized_lmr_params.max },
                        );
                    }
                }
            }
            write("uciok\n", .{});
        } else if (std.ascii.eqlIgnoreCase(command, "banner")) {
            write("{s}\n", .{banner});
        } else if (std.ascii.eqlIgnoreCase(command, "spsa_inputs")) {
            for (root.tuning.tunables) |tunable| {
                write(
                    "{s}, int, {d:.1}, {d:.1}, {d:.1}, {d}, 0.002\n",
                    .{
                        tunable.name,
                        @as(f64, @floatFromInt(tunable.default)),
                        @as(f64, @floatFromInt(tunable.getMin())),
                        @as(f64, @floatFromInt(tunable.getMax())),
                        tunable.getCend(),
                    },
                );
            }
            const factorized_lmr = root.tuning.factorized_lmr;
            const factorized_lmr_params = root.tuning.factorized_lmr_params;
            inline for (0..3, .{ factorized_lmr.one, factorized_lmr.two, factorized_lmr.three }) |i, arr| {
                inline for (arr, 0..) |val, j| {
                    write(
                        "factorized_{}_{}, int, {d:.1}, {d:.1}, {d:.1}, {d}, 0.002\n",
                        .{
                            i,
                            j,
                            val,
                            factorized_lmr_params.min,
                            factorized_lmr_params.max,
                            factorized_lmr_params.c_end,
                        },
                    );
                }
            }
        } else if (std.ascii.eqlIgnoreCase(command, "ucinewgame")) {
            root.engine.reset();
            previous_positions.clearRetainingCapacity();
            previous_moves.clearRetainingCapacity();
            board = Board.startpos();
            previous_positions.append(board) catch unreachable;
        } else if (std.ascii.eqlIgnoreCase(command, "setoption") or std.ascii.eqlIgnoreCase(command, "so")) {
            var option_name = parts.next() orelse "";
            if (std.ascii.eqlIgnoreCase("name", option_name)) {
                option_name = parts.next() orelse "";
            }
            var value = parts.next() orelse "";
            if (std.ascii.eqlIgnoreCase("Overhead", value)) {
                // yes this is cursed
                while (option_name.ptr[option_name.len..] != value.ptr[value.len..])
                    option_name.len += 1;
                value = parts.next() orelse "";
            }
            if (std.ascii.eqlIgnoreCase("value", value)) {
                value = parts.next() orelse "";
            }

            if (std.ascii.eqlIgnoreCase("Hash", option_name)) {
                const size = std.fmt.parseInt(u64, value, 10) catch {
                    writeLog("invalid hash size: '{s}'\n", .{value});
                    continue;
                };
                try root.engine.setTTSize(size);
            }

            if (std.ascii.eqlIgnoreCase("Threads", option_name)) {
                const count = std.fmt.parseInt(u16, value, 10) catch {
                    writeLog("invalid thread count: '{s}'\n", .{value});
                    continue;
                };
                try root.engine.setThreadCount(count);
            }

            if (std.ascii.eqlIgnoreCase("MinDepth", option_name)) {
                min_depth = std.fmt.parseInt(u8, value, 10) catch {
                    writeLog("invalid depth: '{s}'\n", .{value});
                    continue;
                };
            }

            if (std.ascii.eqlIgnoreCase("UCI_Chess960", option_name)) {
                if (std.ascii.eqlIgnoreCase("true", value)) {
                    board.frc = true;
                }
                if (std.ascii.eqlIgnoreCase("false", value)) {
                    board.frc = false;
                }
            }

            if (std.ascii.eqlIgnoreCase("NormalizeEval", option_name)) {
                if (std.ascii.eqlIgnoreCase("true", value)) {
                    normalize = true;
                }
                if (std.ascii.eqlIgnoreCase("false", value)) {
                    normalize = false;
                }
            }

            if (std.ascii.eqlIgnoreCase("Minimal", option_name)) {
                if (std.ascii.eqlIgnoreCase("true", value)) {
                    minimal = true;
                }
                if (std.ascii.eqlIgnoreCase("false", value)) {
                    minimal = false;
                }
            }

            if (std.ascii.eqlIgnoreCase("SoftNodes", option_name)) {
                if (std.ascii.eqlIgnoreCase("true", value)) {
                    softnodes = true;
                }
                if (std.ascii.eqlIgnoreCase("false", value)) {
                    softnodes = false;
                }
            }

            if (std.ascii.eqlIgnoreCase("SetMin", option_name)) {
                root.tuning.setMin();
            }

            if (std.ascii.eqlIgnoreCase("EnableWeirdTCs", option_name)) {
                if (std.ascii.eqlIgnoreCase("true", value)) {
                    weird_tcs = true;
                }
                if (std.ascii.eqlIgnoreCase("false", value)) {
                    weird_tcs = false;
                }
            }

            if (std.ascii.eqlIgnoreCase("SetMax", option_name)) {
                root.tuning.setMax();
            }

            if (std.ascii.eqlIgnoreCase("Move Overhead", option_name) or std.ascii.eqlIgnoreCase("MoveOverhead", option_name)) {
                overhead = std.time.ns_per_ms * (std.fmt.parseInt(u64, value, 10) catch {
                    writeLog("invalid overhead: '{s}'\n", .{value});
                    continue;
                });
            }

            if (root.use_tbs) {
                if (std.ascii.eqlIgnoreCase("SyzygyPath", option_name) and !std.ascii.eqlIgnoreCase("<empty>", value) and value.len > 0) {
                    var dir = std.fs.openDirAbsolute(value, .{ .iterate = true }) catch {
                        write("info string Failed to open specified directory for Syzygy Tablebases '{s}'\n", .{value});
                        continue;
                    };

                    var num_files: usize = 0;
                    var iter = dir.iterate();
                    while (try iter.next()) |_| {
                        num_files += 1;
                    }
                    dir.close();
                    if (num_files == 0) {
                        write("info string The directory you specified contains no files, make sure the path is correct", .{});
                    }
                    const null_terminated = try allocator.dupeZ(u8, value);
                    defer allocator.free(null_terminated);
                    try root.pyrrhic.init(null_terminated);
                }
                if (std.ascii.eqlIgnoreCase("SyzygyProbeDepth", option_name)) {
                    syzygy_depth = std.fmt.parseInt(u8, value, 10) catch {
                        writeLog("invalid syzygy probing depth: '{s}'\n", .{value});
                        continue;
                    };
                }
            }

            if (root.tuning.do_tuning) {
                inline for (root.tuning.tunables) |tunable| {
                    if (std.ascii.eqlIgnoreCase(tunable.name, option_name)) {
                        @field(root.tuning.tunable_constants, tunable.name) = std.fmt.parseInt(i32, value, 10) catch {
                            writeLog("invalid constant: '{s}'\n", .{value});
                            continue :loop;
                        };
                    }
                }
            }
            if (root.tuning.do_factorized_tuning) {
                const factorized_lmr = root.tuning.factorized_lmr;
                inline for (0..3, .{ &factorized_lmr.one, &factorized_lmr.two, &factorized_lmr.three }) |i, arr| {
                    inline for (arr, 0..) |*val_ptr, j| {
                        const name = std.fmt.comptimePrint("factorized_{}_{}", .{ i, j });
                        if (std.ascii.eqlIgnoreCase(name, option_name)) {
                            val_ptr.* = std.fmt.parseInt(i16, value, 10) catch {
                                writeLog("invalid constant: '{s}'\n", .{value});
                                continue :loop;
                            };
                        }
                    }
                }
            }
        } else if (root.use_tbs and std.ascii.eqlIgnoreCase(command, "ProbeWDL")) {
            std.debug.print("{any}\n", .{root.pyrrhic.probeWDL(&board)});
        } else if (std.ascii.eqlIgnoreCase(command, "isready")) {
            root.engine.waitUntilDoneSearching();
            write("readyok\n", .{});
        } else if (std.ascii.eqlIgnoreCase(command, "d")) {
            write("zobrist: {}\n", .{board.hash});
            write("{s}\n", .{board.toFen().slice()});
        } else if (std.ascii.eqlIgnoreCase(command, "go")) {
            var max_depth_opt: ?u8 = null;
            var soft_nodes_opt: ?u64 = null;
            var hard_nodes_opt: ?u64 = null;

            var white_time: ?u64 = null;
            var black_time: ?u64 = null;
            var white_increment: u64 = 0 * std.time.ns_per_s;
            var black_increment: u64 = 0 * std.time.ns_per_s;
            var mate_score_opt: ?i16 = null;
            var move_time_opt: ?u64 = null;
            var cyclic_tc = false;

            while (parts.next()) |command_part| {
                if (std.ascii.eqlIgnoreCase(command_part, "mate")) {
                    const depth_to_parse = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    const depth = std.fmt.parseInt(i16, depth_to_parse, 10) catch {
                        writeLog("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };

                    if (depth < 0) {
                        mate_score_opt = root.evaluation.matedIn(@abs(depth) * 2);
                    } else {
                        mate_score_opt = -root.evaluation.matedIn(@abs(depth) * 2 - 1);
                    }
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
                if (std.ascii.eqlIgnoreCase(command_part, "evalbench") and root.evaluation.eval_mode == .nnue) {
                    const RC = root.refreshCache(root.nnue.HORIZONTAL_MIRRORING, root.nnue.INPUT_BUCKET_COUNT);
                    var cache: RC = undefined;
                    cache.initInPlace();
                    var acc = root.evaluation.State.init(&board);

                    var timer = std.time.Timer.start() catch unreachable;
                    const iterations = 100_000_000;
                    var res: i16 = 0;
                    switch (board.stm) {
                        inline else => |stm| {
                            const rank_from: u3 = if (stm == .white) 1 else 6;
                            const rank_to: u3 = if (stm == .white) 3 else 4;
                            for (0..iterations) |i| {
                                const file: u3 = @intCast(i % 8);
                                const is_back = (i / 8) % 2 == 1;
                                const from = root.Square.fromRankFile(rank_from, file);
                                const to = root.Square.fromRankFile(rank_to, file);

                                if (!is_back) {
                                    acc.addSub(stm, .pawn, to, stm, .pawn, from);
                                } else {
                                    acc.addSub(stm, .pawn, from, stm, .pawn, to);
                                }
                                res +%= acc.forward(stm, &board, &cache);
                                std.mem.doNotOptimizeAway(res);
                            }
                        },
                    }
                    const elapsed_ns = timer.read();
                    write("evals: {} in {D} ({} eps) res: {}\n", .{ iterations, elapsed_ns, @as(u128, iterations) * std.time.ns_per_s / elapsed_ns, res });
                    continue :loop;
                }
                if (std.ascii.eqlIgnoreCase(command_part, "refreshbench") and root.evaluation.eval_mode == .nnue) {
                    const refresh_fens = @import("refresh_fens.zig").fens;
                    const RC = root.refreshCache(root.nnue.HORIZONTAL_MIRRORING, root.nnue.INPUT_BUCKET_COUNT);
                    var cache: RC = undefined;
                    cache.initInPlace();
                    var acc = root.nnue.Accumulator.default();

                    var boards = try allocator.alloc(root.Board, refresh_fens.len);
                    defer allocator.free(boards);
                    for (refresh_fens, 0..) |fen, i| {
                        boards[i] = root.Board.parseFen(fen, true) catch unreachable;
                    }

                    var timer = std.time.Timer.start() catch unreachable;
                    const iterations = 1_000_000;
                    var res: i16 = 0;
                    for (0..iterations) |i| {
                        const b = &boards[i % boards.len];
                        cache.refresh(.white, b, acc.accFor(.white));
                        res +%= acc.accFor(.white)[0];
                        std.mem.doNotOptimizeAway(res);
                    }
                    const elapsed_ns = timer.read();
                    write("refreshes: {} in {d:.3}ms ({} eps) res: {}\n", .{ iterations, @as(f64, @floatFromInt(elapsed_ns)) / 1e6, @as(u128, iterations) * std.time.ns_per_s / elapsed_ns, res });
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
                                if (@atomicLoad(bool, stop, .seq_cst)) return;
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

                    const nodes = std.fmt.parseInt(u64, nodes_to_parse, 10) catch {
                        writeLog("invalid nodes: '{s}'\n", .{nodes_to_parse});
                        continue;
                    };
                    if (softnodes) {
                        soft_nodes_opt = nodes;
                    } else {
                        hard_nodes_opt = nodes;
                    }
                }
                if (std.ascii.eqlIgnoreCase(command_part, "softnodes")) {
                    const nodes_to_parse = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    soft_nodes_opt = std.fmt.parseInt(u64, nodes_to_parse, 10) catch {
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
                    move_time_opt = std.time.ns_per_ms * (std.fmt.parseInt(u64, time, 10) catch {
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
                if (std.ascii.eqlIgnoreCase(command_part, "movestogo")) {
                    const moves = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    _ = std.time.ns_per_ms * (std.fmt.parseInt(u64, moves, 10) catch {
                        writeLog("invalid movestogo: '{s}'\n", .{moves});
                        continue;
                    });

                    cyclic_tc = true;
                }
            }
            const my_time_opt = if (board.stm == .white) white_time else black_time;
            const my_increment = if (board.stm == .white) white_increment else black_increment;
            if ((cyclic_tc or (my_time_opt != null and my_increment == 0)) and !weird_tcs) {
                write("info string Use the EnableWeirdTCs UCI option if you REALLY want to use a {s}. it's untested and not really supported so you will get poor performance, but if you insist you can enable it using the aforementioned option.\n", .{if (cyclic_tc) "cyclic time control" else "time control without increment"});
                write("bestmove 0000\n", .{});
                continue :loop;
            }
            const my_time = my_time_opt orelse 1_000_000_000 * std.time.ns_per_s;

            var limits = root.Limits.initStandard(
                &board,
                my_time,
                my_increment,
                overhead,
            );

            if (move_time_opt) |move_time| {
                limits = root.Limits.initFixedTime(move_time);
            }

            if (max_depth_opt) |max_depth| {
                limits.max_depth = max_depth;
            }
            limits.min_depth = min_depth;
            if (hard_nodes_opt) |max_nodes| {
                limits.soft_nodes = max_nodes;
                limits.hard_nodes = max_nodes;
            }
            if (soft_nodes_opt) |max_modes| {
                limits.soft_nodes = max_modes;
                limits.hard_nodes = max_modes * 128;
            }

            if (mate_score_opt) |mate_value| {
                if (mate_value < 0) {
                    limits.min_score = mate_value;
                } else {
                    limits.max_score = mate_value;
                }
            }

            const keep_moves = @min(
                previous_moves.items.len,
                @max(
                    @as(usize, @min(board.halfmove, root.Searcher.MAX_HALFMOVE)),
                    root.history.CONTHIST_OFFSETS.len,
                ),
            );
            const recent_positions = try root.BoundedArray(Board, 200).fromSlice(
                previous_positions.items[previous_positions.items.len - keep_moves - 1 ..],
            );
            const recent_moves = try root.BoundedArray(Move, 200).fromSlice(
                previous_moves.items[previous_moves.items.len - keep_moves ..],
            );

            root.engine.startSearch(.{
                .search_params = .{
                    .board = board,
                    .limits = limits,
                    .previous_positions = recent_positions,
                    .previous_moves = recent_moves,
                    .syzygy_depth = syzygy_depth,
                    .normalize = normalize,
                    .minimal = minimal,
                },
            });
        } else if (std.ascii.eqlIgnoreCase(command, "stop")) {
            root.engine.printDebugStats();
            root.engine.resetDebugStats();
            root.engine.stopSearch();
        } else if (std.ascii.eqlIgnoreCase(command, "quit")) {
            root.engine.printDebugStats();
            return;
        } else if (std.ascii.eqlIgnoreCase(command, "wait")) {
            root.engine.waitUntilDoneSearching();
        } else if (std.ascii.eqlIgnoreCase(command, "get_scale")) {
            const filename = parts.next() orelse "";
            var file = try std.fs.cwd().openFile(filename, .{});
            defer file.close();

            var reader_buf: [4096]u8 = undefined;
            var file_reader = file.reader(&reader_buf);

            var sum: i64 = 0;
            var abs_sum: i64 = 0;
            var count: i64 = 0;

            while (file_reader.interface.takeDelimiterInclusive('\n')) |data_line| {
                const end = std.mem.indexOfScalar(u8, data_line, '[') orelse data_line.len;
                const fen = data_line[0..end];

                const raw_eval = try root.evaluation.evalFen(fen);
                sum += raw_eval;
                abs_sum += @abs(raw_eval);
                count += 1;
            } else |_| {}
            const average = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(count));
            const abs_average = @as(f64, @floatFromInt(abs_sum)) / @as(f64, @floatFromInt(count));
            std.debug.print("sum: {} sum abs: {}\n", .{ sum, abs_sum });
            std.debug.print("average: {d:.4} average abs: {d:.4}\n", .{ average, abs_average });
        } else if (root.evaluation.eval_mode == .nnue and std.ascii.eqlIgnoreCase(command, "nneval")) {
            const raw_eval = root.nnue.evalPosition(&board);
            const scaled = root.history.HistoryTable.scaleEval(&board, raw_eval);
            const normalized = root.wdl.normalize(scaled, board.classicalMaterial());
            write("raw eval: {}\n", .{raw_eval});
            write("scaled eval: {}\n", .{scaled});
            write("scaled and normalized eval: {}\n", .{normalized});
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
                write("EVAL: {}\n", .{try root.evaluation.evalFen(fen)});
            }
        } else if (std.ascii.eqlIgnoreCase(command, "hceval")) {
            const hce = @import("hce.zig");

            write("{}\n", .{hce.evalPosition(&board)});
        } else if (std.ascii.eqlIgnoreCase(command, "GenerateRandomDfrcPerft")) {
            var prng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
            var mutex = std.Thread.Mutex{};
            var tp: std.Thread.Pool = undefined;
            try tp.init(.{ .allocator = allocator });
            defer tp.deinit();

            for (0..1024) |_| {
                const worker_fn = struct {
                    fn impl(rng: std.Random, m: *std.Thread.Mutex) void {
                        m.lock();
                        var b = Board.dfrcPosition(rng.uintLessThan(u20, 960 * 960));
                        m.unlock();
                        b.frc = true;
                        var buf: [256]u8 = undefined;
                        var fbs = std.Io.Writer.fixed(&buf);
                        fbs.print("{s} ;D1 {}; D2 {}; D3 {}; D4 {}; D5 {}; D6 {}\n", .{
                            b.toFen().slice(),
                            b.perft(true, 1),
                            b.perft(true, 2),
                            b.perft(true, 3),
                            b.perft(true, 4),
                            b.perft(true, 5),
                            b.perft(true, 6),
                        }) catch unreachable;
                        m.lock();
                        write("{s}", .{fbs.buffered()});
                        m.unlock();
                    }
                }.impl;
                try tp.spawn(worker_fn, .{ prng.random(), &mutex });
            }
        } else {
            const started_with_position = std.ascii.eqlIgnoreCase(command, "position");
            const sub_command = parts.next() orelse "";
            const rest = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);

            var pos_iter = std.mem.tokenizeSequence(u8, if (started_with_position) rest else line, "moves");

            if (std.ascii.eqlIgnoreCase(sub_command, "fen") or !started_with_position) {
                const fen_to_parse = std.mem.trim(u8, pos_iter.next() orelse {
                    writeLog("no fen: '{s}'\n", .{rest});
                    continue;
                }, &std.ascii.whitespace);

                board = Board.parseFen(fen_to_parse, true) catch |e| {
                    if (!started_with_position) {
                        command_line.writeHelpText(VERSION_STRING);
                        continue;
                    }
                    writeLog("invalid fen: '{s}' error: {}\n", .{ fen_to_parse, e });
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

            var move_iter = std.mem.tokenizeAny(u8, pos_iter.rest(), &std.ascii.whitespace);
            var can_reuse = previous_positions.items.len > 0 and board.equal(&previous_positions.items[0]);
            var reused_moves: usize = 0;

            if (!can_reuse) {
                previous_positions.clearRetainingCapacity();
                previous_moves.clearRetainingCapacity();
                try previous_positions.append(board);
            }

            while (move_iter.next()) |played_move| {
                if (std.ascii.eqlIgnoreCase(played_move, "moves")) continue;

                if (can_reuse) {
                    if (reused_moves < previous_moves.items.len) {
                        const existing_move = previous_moves.items[reused_moves];
                        if (std.mem.eql(u8, existing_move.toString(&board).slice(), played_move)) {
                            reused_moves += 1;
                            board.makeMoveSimple(existing_move);
                            continue;
                        }
                    }

                    previous_positions.shrinkRetainingCapacity(reused_moves + 1);
                    previous_moves.shrinkRetainingCapacity(reused_moves);
                    can_reuse = false;
                }

                const move = board.parseMoveStr(played_move) catch {
                    writeLog("invalid move: '{s}'\n", .{played_move});
                    continue;
                };
                board.makeMoveSimple(move);
                try previous_moves.append(move);
                try previous_positions.append(board);
            }

            if (can_reuse) {
                previous_positions.shrinkRetainingCapacity(reused_moves + 1);
                previous_moves.shrinkRetainingCapacity(reused_moves);
            }
        }
    }
}

const banner =
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣾⣿⣿⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⣿⣿⣿⣿⣿⣶⣦⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⣿⣿⣿⣿⠿⠿⣿⣿⡿⠦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣿⣿⣿⣿⣿⣡⣶⣶⣾⣿⡴⢶⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⡏⠀⢸⣿⠁⠀⣿⣀⣠⣤⣤⣤⣤⣤⣴⣶⣶⣶⣶⣿⣿⣿⣿⠆⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣤⣾⣿⣷⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠿⠛⠛⠋⠉⠉⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣿⣿⣿⣿⣿⣿⣿⠟⢻⣿⣿⣿⣿⣿⠛⠛⠉⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠻⣿⣿⣿⣿⣿⣿⣿⣦⣤⣤⣴⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣹⣿⣿⣿⣿⣿⣿⣿⣿⣉⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢘⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣟⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    \\⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠛⠛⠛⠛⠻⠿⠿⠿⠿⠿⠿⠟⠛⠛⠛⠋⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
;
