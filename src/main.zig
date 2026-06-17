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
const build_options = @import("build_options");
const root = @import("root.zig");
const command_line = @import("command_line.zig");
const write = root.write;
const writeLog = std.debug.print;
const Board = root.Board;
const Move = root.Move;

fn writeTuningOptions() void {
    var ctx: u8 = 0;
    root.tuning.forEachTunable(u8, &ctx, struct {
        fn call(_: *u8, param: root.tuning.TunableParam) void {
            write("option name {s} type spin default {} min {} max {}\n", .{ param.name, param.default, param.min, param.max });
        }
    }.call);
}

fn writeSpsaInputs() void {
    var ctx: u8 = 0;
    root.tuning.forEachTunable(u8, &ctx, struct {
        fn call(_: *u8, param: root.tuning.TunableParam) void {
            const desired_c = param.c_end;
            const actual_c = @max(0.5, desired_c);
            const r_end = 0.002 * (actual_c / desired_c);
            write(
                "{s}, int, {d:.1}, {d:.1}, {d:.1}, {d}, {d:.6}\n",
                .{
                    param.name,
                    @as(f64, @floatFromInt(param.default)),
                    @as(f64, @floatFromInt(param.min)),
                    @as(f64, @floatFromInt(param.max)),
                    param.c_end,
                    r_end,
                },
            );
        }
    }.call);
}

fn printTuningSchema() void {
    var ctx: u8 = 0;
    root.tuning.forEachTunable(u8, &ctx, struct {
        fn call(_: *u8, param: root.tuning.TunableParam) void {
            write("{s}, {}\n", .{ param.name, param.current });
        }
    }.call);
}

fn parseUCIBool(value: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(value, "true")) {
        return true;
    }

    if (std.ascii.eqlIgnoreCase(value, "false")) {
        return false;
    }

    if (std.fmt.parseInt(isize, value, 10)) |int| {
        return int == 1;
    } else |_| {}

    return null;
}

pub fn main(init: std.process.Init) !void {
    var threaded_io = std.Io.Threaded.init(init.gpa, .{
        .environ = init.minimal.environ,
    });
    defer threaded_io.deinit();
    const io = threaded_io.io();
    root.init(io);

    defer root.deinit();
    defer if (!build_options.tools_only) {
        root.engine.stopSearch();
        root.engine.waitUntilDoneSearching();
    };

    const allocator = init.gpa;
    const version = build_options.version_string;

    if (try command_line.handle(init, version)) {
        return;
    }

    if (build_options.tools_only) {
        command_line.writeHelp(version);
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
    var stdin = std.Io.File.stdin();
    var reader = stdin.readerStreaming(io, &stdin_buf);

    var previous_positions = std.array_list.Managed(Board).init(allocator);
    defer previous_positions.deinit();
    var previous_moves = std.array_list.Managed(Move).init(allocator);
    defer previous_moves.deinit();

    var board = Board.startpos();
    try previous_positions.append(board);
    var overhead: u64 = std.time.ns_per_ms * 10;
    var syzygy_depth: u8 = 1;
    var min_depth: i32 = 0;
    var contempt: i16 = 0;
    var minimal: bool = false;
    var normalize: bool = true;
    var softnodes: bool = false;

    const IS_POTENTIAL_ANDROID_BUILD = comptime blk: {
        const builtin = @import("builtin");

        break :blk builtin.target.os.tag == .linux and builtin.cpu.arch.isAARCH64();
    };

    var weird_tcs: bool = IS_POTENTIAL_ANDROID_BUILD;
    var show_wdl: bool = false;
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
            std.atomic.spinLoopHint();
            continue; // empty command
        };

        if (std.ascii.eqlIgnoreCase(command, "uci")) {
            write("id name pawnocchio {s}\n", .{version});
            write("id author Jonathan Hallström\n", .{});
            write("option name Hash type spin default 16 min 1 max 1048576\n", .{});
            write("option name Threads type spin default 1 min 1 max 65535\n", .{});
            write("option name Move Overhead type spin default {} min 1 max 10000\n", .{overhead});
            write("option name Contempt type spin default {} min -10000 max 10000\n", .{contempt});
            write("option name UCI_Chess960 type check default false\n", .{});
            write("option name MinDepth type spin default {} min 0 max 255\n", .{min_depth});
            write("option name SyzygyPath type string default <empty>\n", .{});
            write("option name SyzygyProbeDepth type spin default {} min 1 max 255\n", .{syzygy_depth});
            write("option name NormalizeEval type check default {}\n", .{normalize});
            write("option name Minimal type check default {}\n", .{minimal});
            write("option name SoftNodes type check default {}\n", .{softnodes});
            write("option name EnableWeirdTCs type check default {}\n", .{weird_tcs});
            write("option name UCI_ShowWDL type check default {}\n", .{show_wdl});
            if (root.tuning.DO_TUNING or root.tuning.DO_FACTORIZED_TUNING) {
                writeTuningOptions();
            }
            write("uciok\n", .{});
        } else if (std.ascii.eqlIgnoreCase(command, "banner")) {
            write("{s}\n", .{BANNER});
        } else if (std.ascii.eqlIgnoreCase(command, "spsa_inputs")) {
            writeSpsaInputs();
        } else if (std.ascii.eqlIgnoreCase(command, "print_schema")) {
            printTuningSchema();
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
                if (size == 0) {
                    writeLog("must have at least 1mb of hash\n", .{});
                    continue;
                }
                try root.engine.setTTSize(size);
            }

            if (std.ascii.eqlIgnoreCase("Threads", option_name)) {
                const count = std.fmt.parseInt(u16, value, 10) catch {
                    writeLog("invalid thread count: '{s}'\n", .{value});
                    continue;
                };
                if (count == 0) {
                    writeLog("must have at least one thread\n", .{});
                    continue;
                }
                try root.engine.setThreadCount(count);
            }

            if (std.ascii.eqlIgnoreCase("MinDepth", option_name)) {
                min_depth = std.fmt.parseInt(u8, value, 10) catch {
                    writeLog("invalid depth: '{s}'\n", .{value});
                    continue;
                };
            }

            if (std.ascii.eqlIgnoreCase("Contempt", option_name)) {
                contempt = std.fmt.parseInt(i16, value, 10) catch {
                    writeLog("invalid contempt: '{s}'\n", .{value});
                    continue;
                };
            }

            if (std.ascii.eqlIgnoreCase("UCI_Chess960", option_name)) {
                if (parseUCIBool(value)) |b| board.frc = b;
            }

            if (std.ascii.eqlIgnoreCase("NormalizeEval", option_name)) {
                if (parseUCIBool(value)) |b| normalize = b;
            }

            if (std.ascii.eqlIgnoreCase("Minimal", option_name)) {
                if (parseUCIBool(value)) |b| minimal = b;
            }

            if (std.ascii.eqlIgnoreCase("SoftNodes", option_name)) {
                if (parseUCIBool(value)) |b| softnodes = b;
            }

            if (std.ascii.eqlIgnoreCase("SetMin", option_name)) {
                root.tuning.setMin();
            }

            if (std.ascii.eqlIgnoreCase("EnableWeirdTCs", option_name)) {
                if (parseUCIBool(value)) |b| weird_tcs = b;
            }
            if (std.ascii.eqlIgnoreCase("UCI_ShowWDL", option_name) or std.ascii.eqlIgnoreCase("wdl", option_name)) {
                if (parseUCIBool(value)) |b| show_wdl = b;
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

            if (root.USE_TBS) {
                if (std.ascii.eqlIgnoreCase("SyzygyPath", option_name) and !std.ascii.eqlIgnoreCase("<empty>", value) and value.len > 0) {
                    var dir = std.Io.Dir.openDirAbsolute(io, value, .{ .iterate = true }) catch {
                        write("info string Failed to open specified directory for Syzygy Tablebases '{s}'\n", .{value});
                        continue;
                    };

                    var num_files: usize = 0;
                    var iter = dir.iterate();
                    while (try iter.next(io)) |_| {
                        num_files += 1;
                    }
                    dir.close(io);
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

            if (root.tuning.DO_TUNING or root.tuning.DO_FACTORIZED_TUNING) {
                const parsed_value = std.fmt.parseInt(i32, value, 10) catch {
                    writeLog("invalid constant: '{s}'\n", .{value});
                    continue :loop;
                };
                _ = root.tuning.trySetTunable(option_name, parsed_value);
            }
        } else if (root.USE_TBS and std.ascii.eqlIgnoreCase(command, "ProbeWDL")) {
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
                if (std.ascii.eqlIgnoreCase(command_part, "perft") or std.ascii.eqlIgnoreCase(command_part, "perft_verify")) {
                    const do_verify = std.ascii.eqlIgnoreCase(command_part, "perft_verify");
                    const depth_to_parse = std.mem.trim(u8, parts.rest(), &std.ascii.whitespace);
                    const depth = std.fmt.parseInt(i32, depth_to_parse, 10) catch {
                        writeLog("invalid depth: '{s}'\n", .{depth_to_parse});
                        continue;
                    };
                    const start_time = std.Io.Timestamp.now(io, .awake);
                    const nodes = if (do_verify) board.perftVerify(false, depth) else board.perft(false, depth);
                    const elapsed_ns = @as(u64, @intCast(start_time.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds));
                    write("Nodes searched: {} in {}ms ({} nps)\n", .{ nodes, elapsed_ns / std.time.ns_per_ms, @as(u128, nodes) * std.time.ns_per_s / elapsed_ns });
                    continue :loop;
                }
                if (std.ascii.eqlIgnoreCase(command_part, "evalbench") and root.evaluation.EVAL_MODE == .nnue) {
                    const ctx = root.evaluation.globalCtx.lock();
                    defer root.evaluation.globalCtx.release();
                    ctx.initRoot(&board);
                    const handle = ctx.handle(0);

                    const start_time = std.Io.Timestamp.now(io, .awake);
                    const iterations = 100_000_000;
                    var res: i16 = 0;
                    const stm = board.stm;
                    const rank_from: u3 = if (stm == .white) 1 else 6;
                    const rank_to: u3 = if (stm == .white) 3 else 4;
                    for (0..iterations) |i| {
                        const file: u3 = @intCast(i % 8);
                        const is_back = (i / 8) % 2 == 1;
                        const from = root.Square.fromRankFile(rank_from, file);
                        const to = root.Square.fromRankFile(rank_to, file);

                        if (!is_back) {
                            handle.addSub(.init(stm, .pawn, to), .init(stm, .pawn, from));
                        } else {
                            handle.addSub(.init(stm, .pawn, from), .init(stm, .pawn, to));
                        }
                        res +%= handle.eval(&board);
                        std.mem.doNotOptimizeAway(res);
                    }
                    const elapsed_ns = @as(u64, @intCast(start_time.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds));
                    write("evals: {} in {} ({} eps) res: {}\n", .{ iterations, elapsed_ns, @as(u128, iterations) * std.time.ns_per_s / elapsed_ns, res });
                    continue :loop;
                }
                if (std.ascii.eqlIgnoreCase(command_part, "refreshbench") and root.evaluation.EVAL_MODE == .nnue) {
                    const refresh_fens = @import("refresh_fens.zig").FENS;
                    const RC = root.refreshCache(root.nnue.arch.HORIZONTAL_MIRRORING, root.nnue.arch.INPUT_BUCKET_COUNT);
                    const weights = root.nnue.weightsForNode(0);
                    var cache: RC = undefined;
                    cache.initInPlace(weights);
                    var boards = try allocator.alloc(root.Board, refresh_fens.len);
                    defer allocator.free(boards);
                    for (refresh_fens, 0..) |fen, i| {
                        boards[i] = root.Board.parseFen(fen, true) catch unreachable;
                    }

                    const start_time = std.Io.Timestamp.now(io, .awake);
                    const iterations = 1_000_000;
                    var res: i16 = 0;
                    for (0..iterations) |i| {
                        const b = &boards[i % boards.len];
                        const acc = cache.refresh(weights, .white, b);
                        res +%= acc.ptr.data[0];
                        std.mem.doNotOptimizeAway(res);
                    }
                    const elapsed_ns = @as(u64, @intCast(start_time.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds));
                    write("refreshes: {} in {d:.3}ms ({} eps) res: {}\n", .{ iterations, @as(f64, @floatFromInt(elapsed_ns)) / 1e6, @as(u128, iterations) * std.time.ns_per_s / elapsed_ns, res });
                    continue :loop;
                }
                if (std.ascii.eqlIgnoreCase(command_part, "perft_file")) {
                    const file_name = std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace);
                    var epd_parser = root.PerftEPDParser.init(io, file_name, allocator) catch |e| {
                        writeLog("invalid file: '{s}' error: {}\n", .{ file_name, e });
                        continue;
                    };
                    defer epd_parser.deinit();
                    const start_time = std.Io.Timestamp.now(io, .awake);

                    var stop_perft = false;
                    var nodes: u64 = 0;

                    while (epd_parser.next() catch continue :loop) |position| {
                        defer position.deinit();
                        std.debug.print("{s} {any}\n", .{ position.fen, position.node_counts.slice() });
                        if (stop_perft) continue :loop;
                        const perft_board = Board.parseFen(position.fen, true) catch {
                            writeLog("invalid position: {s}\n", .{position.fen});
                            stop_perft = true;
                            continue :loop;
                        };
                        for (position.node_counts.slice()) |node_count| {
                            const expected = node_count.nodes;
                            const actual = perft_board.perft(true, node_count.depth);
                            if (stop_perft) continue :loop;
                            if (expected != actual) {
                                writeLog(
                                    \\error at depth: {}
                                    \\for position {s}
                                    \\got: {} expected: {}
                                , .{
                                    node_count.depth,
                                    position.fen,
                                    actual,
                                    expected,
                                });
                                stop_perft = true;
                                continue :loop;
                            }
                            nodes += actual;
                        }
                        write("completed {s}\n", .{position.fen});
                    }

                    const actual_nodes = @atomicLoad(u64, &nodes, .seq_cst);
                    const elapsed_ns = @as(u64, @intCast(start_time.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds));
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
                io,
                &board,
                my_time,
                my_increment,
                overhead,
            );

            if (move_time_opt) |move_time| {
                limits = root.Limits.initFixedTime(io, move_time);
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
                    @as(usize, @min(board.halfmove, root.SEARCH_MAX_HALFMOVE)),
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
                    .contempt = contempt,
                    .normalize = normalize,
                    .minimal = minimal,
                    .show_wdl = show_wdl,
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
            var file = try std.Io.Dir.cwd().openFile(io, filename, .{});
            defer file.close(io);

            var reader_buf: [4096]u8 = undefined;
            var file_reader = file.readerStreaming(io, &reader_buf);

            var sum: i64 = 0;
            var abs_sum: i64 = 0;
            var count: i64 = 0;

            const ctx = root.evaluation.globalCtx.lock();
            defer root.evaluation.globalCtx.release();
            while (file_reader.interface.takeDelimiterInclusive('\n')) |data_line| {
                const end = std.mem.indexOfScalar(u8, data_line, '[') orelse data_line.len;
                const fen = data_line[0..end];

                const b = try Board.parseFen(fen, true);
                ctx.initRoot(&b);
                const raw_eval = ctx.handle(0).eval(&b);
                sum += raw_eval;
                abs_sum += @abs(raw_eval);
                count += 1;
            } else |_| {}
            const average = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(count));
            const abs_average = @as(f64, @floatFromInt(abs_sum)) / @as(f64, @floatFromInt(count));
            std.debug.print("sum: {} sum abs: {}\n", .{ sum, abs_sum });
            std.debug.print("average: {d:.4} average abs: {d:.4}\n", .{ average, abs_average });
        } else if (std.ascii.eqlIgnoreCase(command, "get_error2")) {
            const SIGMOID_SCALE: f64 = 400.0;
            const filename = parts.next() orelse "";
            var file = try std.Io.Dir.cwd().openFile(io, filename, .{});
            defer file.close(io);

            var reader_buf: [1 << 16]u8 = undefined;
            var file_reader = file.readerStreaming(io, &reader_buf);

            var sum_sq: f64 = 0;
            var count: u64 = 0;
            const ctx = root.evaluation.globalCtx.lock();
            defer root.evaluation.globalCtx.release();

            if (std.mem.endsWith(u8, filename, ".vf")) {
                const stat = try file.stat(io);
                const start_time = std.Io.Timestamp.now(io, .awake);
                var vf = root.viriformat.scoredPlyReader(&file_reader.interface, allocator);
                defer vf.deinit();
                var seen: u64 = 0;
                while (try vf.next()) |game| {
                    const target: f64 = @as(f64, @floatFromInt(game.outcome.toInt())) / 2.0;
                    var it = game.iter();
                    ctx.initRoot(&it.board);
                    var ply: u16 = 0;
                    var scored = try it.next();
                    while (scored) |sp| {
                        const stm_eval = ctx.handle(ply).eval(&it.board);
                        const white_eval: f64 = @floatFromInt(if (it.board.stm == .white) stm_eval else -stm_eval);
                        const pred = 1.0 / (1.0 + @exp(-white_eval / SIGMOID_SCALE));
                        const err = pred - target;

                        seen += 1;
                        if (seen % 16384 == 0) {
                            const now = std.Io.Timestamp.now(io, .awake);
                            const elapsed = @as(u64, @intCast(start_time.durationTo(now).nanoseconds));
                            std.debug.print("\rprogress: {}% (evals/s: {})", .{
                                @as(u128, file_reader.logicalPos() * 100) / stat.size,
                                seen * 1_000_000_000 / @max(1, elapsed),
                            });
                        }

                        const noisy = it.board.isNoisy(sp.move);

                        const child = ply + 1;
                        ctx.prepareChild(child, &it.board);
                        scored = try it.nextHandle(ctx.handle(child));
                        const gives_check = it.board.checkers != 0;
                        if (!noisy and !gives_check) {
                            sum_sq += err * err;
                            count += 1;
                        }
                        ply = child;
                        if (ply + 1 >= root.SEARCH_MAX_PLY) {
                            ctx.initRoot(&it.board);
                            ply = 0;
                        }
                    }
                }
            } else {
                while (file_reader.interface.takeDelimiterInclusive('\n')) |data_line| {
                    const open = std.mem.indexOfScalar(u8, data_line, '[') orelse continue;
                    const close = std.mem.indexOfScalarPos(u8, data_line, open, ']') orelse continue;
                    const fen = std.mem.trim(u8, data_line[0..open], &std.ascii.whitespace);
                    const result = std.fmt.parseFloat(f64, data_line[open + 1 .. close]) catch continue;

                    const b = Board.parseFen(fen, true) catch continue;
                    ctx.initRoot(&b);
                    const stm_eval = ctx.handle(0).eval(&b);
                    const white_eval: f64 = @floatFromInt(if (b.stm == .white) stm_eval else -stm_eval);
                    const pred = 1.0 / (1.0 + @exp(-white_eval / SIGMOID_SCALE));
                    const err = pred - result;
                    sum_sq += err * err;
                    count += 1;
                } else |_| {}
            }
            std.debug.print("\ncount: {}\n", .{count});
            std.debug.print("MSE: {d:.8}\n", .{sum_sq / @as(f64, @floatFromInt(count))});
        } else if (root.evaluation.EVAL_MODE == .nnue and std.ascii.eqlIgnoreCase(command, "nneval")) {
            const raw_eval = root.nnue.evalPosition(&board);
            const scaled = root.history.HistoryTable.scaleEval(&board, raw_eval);
            const normalized = root.wdl.normalize(scaled, &board);
            write("raw eval: {}\n", .{raw_eval});
            write("scaled eval: {}\n", .{scaled});
            write("scaled and normalized eval: {}\n", .{normalized});
        } else if (std.ascii.eqlIgnoreCase(command, "eval")) {
            if (parts.peek()) |p| {
                if (std.ascii.eqlIgnoreCase(p, "position")) _ = parts.next();
            }
            if (parts.peek()) |p| {
                if (std.ascii.eqlIgnoreCase(p, "fen")) _ = parts.next();
            }
            const rest = parts.rest();
            var b = board;
            if (Board.parseFen(rest, true)) |nb| {
                b = nb;
            } else |_| {}
            const ctx = root.evaluation.globalCtx.lock();
            defer root.evaluation.globalCtx.release();
            ctx.initRoot(&b);
            const raw_eval = ctx.handle(0).eval(&b);
            write("{}\n", .{raw_eval});
        } else if (std.ascii.eqlIgnoreCase(command, "genlabels")) {
            if (parts.peek()) |p| {
                if (std.ascii.eqlIgnoreCase(p, "fen")) _ = parts.next();
            }
            const rest = parts.rest();
            var split = std.mem.tokenizeSequence(u8, rest, " moves ");

            const fen_part = split.next() orelse continue;
            const moves_part = split.next() orelse continue;

            const ctx = root.evaluation.globalCtx.lock();
            defer root.evaluation.globalCtx.release();
            var b = Board.parseFen(fen_part, true) catch continue;
            ctx.initRoot(&b);
            var ply: u16 = 0;
            var move_iter = std.mem.tokenizeScalar(u8, moves_part, ' ');
            while (move_iter.next()) |move_str| {
                write("{} ", .{ctx.handle(ply).eval(&b)});
                const move = b.parseMoveStr(move_str) catch |e| {
                    writeLog("invalid move {s} in position {s}, error: {}\n", .{ move_str, b.toFen().slice(), e });
                    break;
                };
                const child = ply + 1;
                ctx.prepareChild(child, &b);
                b.makeMove(move, ctx.handle(child));
                ply = child;
                if (ply + 1 >= root.SEARCH_MAX_PLY) {
                    ctx.initRoot(&b);
                    ply = 0;
                }
            }
            write("\n", .{});
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
                "1nbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQka - 0 1",
                "3N4/b2R2p1/3q3r/6P1/4k1nQ/7B/8/K7 w - - 0 1",
                "k2B1Q1q/8/b7/4p3/3Pr3/1N5R/2n5/1K6 w - - 0 1",
                "1B3q2/8/r5n1/8/Rp1N1PQ1/8/4bk2/2K5 w - - 0 1",
                "8/5NR1/5q1b/8/7p/3P2B1/6Q1/1k1K1n1r w - - 0 1",
                "8/8/6r1/4B3/3Q3p/N1nq4/5RP1/b3K2k b - - 0 1",
                "3qn2Q/1R6/8/1N3b1p/4B3/1kP5/r7/5K2 b - - 0 1",
                "3rBR2/2qQ1p2/N7/2P2b2/6n1/k7/8/6K1 b - - 0 1",
                "k7/8/p1rB1q2/7Q/4R3/2N2n2/7P/6bK b - - 0 1",
                "2n2Rr1/Bk5p/N7/2Q3q1/b7/8/KP6/8 w - - 0 1",
                "8/Q6r/3qR1P1/b4p2/k7/3B4/1KN2n2/8 b - - 0 1",
                "2nR4/1qB5/2p5/7r/4bQ2/1P1N4/2K1k3/8 w - - 0 1",
                "8/2Q1B3/n3qR1r/bk1p4/1P6/8/3K4/7N w - - 0 1",
                "7r/4b3/4k1N1/2q4n/1Q2B3/R5p1/1P2K3/8 b - - 0 1",
                "2r1n1k1/NbR5/6B1/2p1P3/8/8/5K2/q6Q b - - 0 1",
                "2Q2R2/P1pn4/q1N5/1b5k/1r6/B7/6K1/8 b - - 0 1",
                "1Nr2b2/R1p5/5q2/7B/2P5/3nk3/7K/1Q6 w - - 0 1",
                "4Q3/6P1/1k3p2/4N3/2r5/K6b/1n1B2Rq/8 b - - 0 1",
                "1B5Q/1n6/2p1rN2/3R4/3P4/1K3k2/3b4/6q1 w - - 0 1",
                "3n4/3q4/5Q2/4rP2/1N2p3/2K2B2/5k2/2b4R b - - 0 1",
                "6B1/2k5/2n1R3/1q2p3/2P4Q/3K4/r5b1/3N4 w - - 0 1",
                "8/8/b6N/R3pr1n/Q7/1Pk1K3/4B3/5q2 b - - 0 1",
                "3Q2r1/4P2R/1b6/8/8/1B3K2/4p2q/1k1n1N2 w - - 0 1",
                "bR5q/2r3B1/2Q1P3/8/2n5/1N1p2K1/k7/8 w - - 0 1",
                "1q1b2r1/8/8/2p5/4N3/3k1P1K/2nB1Q2/4R3 w - - 0 1",
                "5rRq/8/1Qn5/8/K7/P1B4b/1p2N3/7k w - - 0 1",
                "1n6/8/B3q3/5R2/1KPb2N1/7Q/r4p2/2k5 w - - 0 1",
                "q3N1R1/8/1B5n/2p5/2K2P2/7r/1b1k4/7Q w - - 0 1",
                "1B6/N6q/2b5/7R/P2K4/1Q1pr3/6n1/2k5 b - - 0 1",
                "1R3q2/p3Q1n1/4N3/6r1/4K1B1/2P5/7b/4k3 w - - 0 1",
                "1k6/2RQP3/1p6/b7/1B3K2/r1n5/3Nq3/8 b - - 0 1",
                "b7/k7/5P2/n2N4/5pK1/2q5/2B2R2/r4Q2 b - - 0 1",
                "1B6/P4q2/5r2/8/1k2n2K/5b2/1NR1p3/6Q1 w - - 0 1",
                "8/3Pk3/B2r4/K5N1/b7/3n1p1Q/2R5/5q2 w - - 0 1",
                "q2Q1R2/2p4N/1b1P4/1K6/1B3r2/8/8/n2k4 w - - 0 1",
                "n1k5/5pq1/R4b2/2K5/3N4/7P/4BrQ1/8 b - - 0 1",
                "8/4Q3/B7/3KN1P1/3b4/nk3p2/8/R4r1q w - - 0 1",
                "b6n/B1k5/8/4KN1r/1Q6/7R/6Pp/5q2 b - - 0 1",
                "6k1/7r/8/bB3K1N/1R1q4/4Q3/2nP1p2/8 w - - 0 1",
                "Q6R/8/2B1q3/3N1nK1/2kb4/P7/r6p/8 w - - 0 1",
                "8/p5r1/k7/6PK/3b4/2B5/n4qQ1/3N2R1 w - - 0 1",
                "4kb2/6r1/K7/p7/6n1/2N5/2BP1qR1/7Q w - - 0 1",
                "6q1/1BN5/1K3P2/3br1np/3R4/Q7/8/5k2 w - - 0 1",
                "5n2/5q2/1NK5/k1P3r1/3p4/7Q/B6b/1R6 w - - 0 1",
                "B3r3/3p4/N2K2k1/1Q6/2R5/1bP5/1q5n/8 w - - 0 1",
                "BR2Q3/4N3/1n2K3/k7/1p1b1q2/8/5P2/7r b - - 0 1",
                "1k6/7R/5K1N/1pQ5/1n6/P4b2/1r6/6qB b - - 0 1",
                "8/3k4/3NnPK1/3QR3/3r2pB/8/4b3/q7 w - - 0 1",
                "1Q6/4q3/NB5K/1R1r4/3P4/bp1k4/6n1/8 w - - 0 1",
                "3Br3/K7/2q1N3/7n/8/4PbRQ/1p1k4/8 w - - 0 1",
                "R2r4/pK1b4/1n4NB/7P/8/3Q4/6k1/4q3 b - - 0 1",
                "3N2r1/2KP4/8/1B1p4/2b5/3RQq2/2k5/7n w - - 0 1",
                "5q2/1N1KB3/5b2/p4R2/4k3/P7/Q7/4n1r1 b - - 0 1",
                "NR6/4K3/1q3r2/3Q3P/3n2k1/8/7p/B5b1 b - - 0 1",
                "q7/1N1B1K2/1Q6/5b2/5pP1/6r1/n6k/R7 w - - 0 1",
                "2R5/2n1k1K1/5r2/3P4/2Q4p/2q5/6NB/7b w - - 0 1",
                "3n1Qr1/3p3K/8/3B4/R5b1/4P3/1qN4k/8 w - - 0 1",
                "K7/3k4/3n2b1/1P2r3/8/p2Bq3/3R4/3QN3 b - - 0 1",
                "1K6/8/3rRN2/1BP3b1/3p4/8/k2n2q1/5Q2 w - - 0 1",
                "2K5/6Bn/p4r2/2P1Q3/1qb5/8/2R5/3kN3 w - - 0 1",
                "3K4/8/2bP4/1qN5/2n3B1/3R4/4Qrp1/6k1 b - - 0 1",
                "1B2K1k1/P3b3/5q2/3R4/1pQ2r1n/8/8/6N1 b - - 0 1",
                "5K2/p4P1b/5QB1/4q3/6k1/8/4r3/R1n1N3 b - - 0 1",
                "6K1/8/b6R/N2p2P1/8/q1Q5/6r1/2Bk3n b - - 0 1",
                "7K/r2R3b/1Q6/8/2q5/1nPB2k1/N3p3/8 w - - 0 1",
            }) |fen| {
                write("FEN: {s}\n", .{fen});
                write("EVAL: {}\n", .{try root.evaluation.evalFen(fen)});
            }
        } else if (std.ascii.eqlIgnoreCase(command, "hceval")) {
            const hce = @import("hce.zig");

            write("{}\n", .{hce.evalPosition(&board)});
        } else if (std.ascii.eqlIgnoreCase(command, "GenerateRandomDfrcPerft")) {
            var prng = std.Random.DefaultPrng.init(@bitCast(@as(i64, @intCast(std.Io.Timestamp.now(io, .awake).nanoseconds))));
            var indices: [960 * 960]u20 = undefined;
            for (&indices, 0..) |*e, i| e.* = @intCast(i);
            prng.random().shuffle(u20, &indices);

            var group = std.Io.Group.init;
            for (0..1024) |i| {
                const worker_fn = struct {
                    fn impl(idx: u20) void {
                        var b = Board.dfrcPosition(idx);
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
                        write("{s}", .{fbs.buffer[0..fbs.end]});
                    }
                }.impl;
                group.async(io, worker_fn, .{indices[i]});
            }
            try group.await(io);
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
                        command_line.writeHelp(version);
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

const BANNER =
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
