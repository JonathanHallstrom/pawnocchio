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
const arg_parser = @import("arg_parser.zig");
const write = root.write;
const writeLog = std.debug.print;
const Board = root.Board;

const bench_depth_default: i32 = 11;
const datagen_nodes_default: u64 = 7000;

const Command = enum {
    help,
    datagen,
    genfens,
    pgntovf,
    epdtovf,
    vftotxt,
    analyse,
    @"relabel-tb",
    sanitise,
    bench,
};

fn parseCommandArgs(args: anytype, comptime spec_or_type: anytype, comptime options: arg_parser.Options, comptime command_name: []const u8) !arg_parser.ParsedType(spec_or_type, options) {
    const parse_options: arg_parser.Options = .{
        .allow_implied = options.allow_implied,
        .default_int_type = options.default_int_type,
        .default_float_type = options.default_float_type,
        .usage_descriptions = options.usage_descriptions,
    };
    return arg_parser.parse(args, spec_or_type, parse_options) catch |e| {
        if (e == error.HelpRequested) {
            const usage = arg_parser.fullUsage(spec_or_type, parse_options);
            if (usage.len > 0) {
                writeLog("{s} arguments:\n", .{command_name});
                var parts = std.mem.splitSequence(u8, usage, "\n");
                while (parts.next()) |part| {
                    writeLog("  {s}\n", .{part});
                }
            } else {
                writeLog("{s}: no command arguments\n", .{command_name});
            }
            return e;
        }
        if (e == error.MissingRequiredOption) {
            const usage = arg_parser.requiredUsage(spec_or_type, parse_options);
            if (usage.len > 0) {
                writeLog("invalid {s} arguments: missing required arguments:\n", .{command_name});
                var parts = std.mem.splitSequence(u8, usage, "\n");
                while (parts.next()) |part| {
                    writeLog("  {s}\n", .{part});
                }
            } else {
                writeLog("invalid {s} arguments: {}\n", .{ command_name, e });
            }
            return e;
        }
        writeLog("invalid {s} arguments: {}\n", .{ command_name, e });
        return e;
    };
}

fn openInputFile(path: []const u8) !std.fs.File {
    const open_result = if (std.fs.path.isAbsolute(path))
        std.fs.openFileAbsolute(path, .{})
    else
        std.fs.cwd().openFile(path, .{});
    return open_result catch |e| {
        writeLog("opening file '{s}' gave: '{}'\n", .{ path, e });
        return e;
    };
}

fn createOutputFile(path: []const u8, allow_overwrite: bool) !std.fs.File {
    const flags: std.fs.File.CreateFlags = .{
        .exclusive = !allow_overwrite,
    };
    const create_result = if (std.fs.path.isAbsolute(path))
        std.fs.createFileAbsolute(path, flags)
    else
        std.fs.cwd().createFile(path, flags);
    return create_result catch |e| {
        if (e == error.PathAlreadyExists and !allow_overwrite) {
            writeLog("refusing to overwrite existing file '{s}' (pass --allow-overwrite)\n", .{path});
            return e;
        }
        writeLog("creating file '{s}' gave: '{}'\n", .{ path, e });
        return e;
    };
}

fn ensureTbPathExists(tb_path: []const u8) !void {
    const access_result = if (std.fs.path.isAbsolute(tb_path))
        std.fs.accessAbsolute(tb_path, .{})
    else
        std.fs.cwd().access(tb_path, .{});
    return access_result catch |e| {
        writeLog("tb path '{s}' is not accessible: '{}'\n", .{ tb_path, e });
        return e;
    };
}

pub fn handle(allocator: std.mem.Allocator, version_string: []const u8) !bool {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next() orelse "pawnocchio";

    const datagen_threads_default: usize = std.Thread.getCpuCount() catch 1;
    while (args.next()) |arg| {
        var tokens = std.mem.tokenizeScalar(u8, arg, ' ');
        const command_token = tokens.next() orelse "";
        if (std.meta.stringToEnum(Command, command_token)) |command| {
            (switch (command) {
                .help => {
                    handleHelp(version_string, datagen_threads_default);
                    return true;
                },
                .datagen => handleDatagen(&args, datagen_threads_default),
                .genfens => handleGenfens(arg, allocator),
                .pgntovf => handlePgnToVf(&args, allocator),
                .epdtovf => handleEpdToVf(&args, allocator),
                .vftotxt => handleVfToTxt(&args),
                .analyse => handleAnalyse(&args, allocator),
                .@"relabel-tb" => handleRelabelTb(&args, allocator),
                .sanitise => handleSanitise(&args, allocator),
                .bench => handleBench(&args),
            }) catch |e| {
                if (e != error.HelpRequested) {
                    return e;
                }
            };
            return true;
        }

        handleHelp(version_string, datagen_threads_default);
        return true;
    }

    return false;
}

fn handleHelp(version_string: []const u8, datagen_threads_default: usize) void {
    std.debug.print(
        \\pawnocchio {s} - UCI chess engine
        \\
        \\USAGE:
        \\  pawnocchio [COMMAND] [ARGUMENTS]
        \\  pawnocchio (starts in UCI mode)
        \\
        \\TOOLS:
        \\
        \\  bench [--depth <DEPTH>] [<DEPTH> (positional)]
        \\      run benchmark. default depth: {d}
        \\
        \\  datagen --threads N --nodes N --positions N
        \\      generate training data. arguments must be passed as --key value or --key=value
        \\      defaults: threads={d}, nodes={d}
        \\
        \\  genfens "<COUNT> seed <SEED> book <BOOK|none>"
        \\      generate FENs. note: must be enclosed in quotes due to argument parsing
        \\      example: pawnocchio "genfens 100 seed 12345 book book.bin"
        \\
        \\  pgntovf --input <INPUT.pgn> [<INPUT.pgn> (positional)] [--skip-broken-games] [--allow-non-pgn-extension] [--allow-overwrite] [--output <OUTPUT>]
        \\      convert PGN to viriformat. default output: <INPUT>.vf
        \\
        \\  epdtovf --input <INPUT.epd> [<INPUT.epd> (positional)] [--skip-broken-games] [--white-relative] [--allow-overwrite] [--output <OUTPUT>]
        \\      convert EPD to viriformat. default output: <INPUT>.vf
        \\
        \\  vftotxt --input <INPUT.vf> [<INPUT.vf> (positional)]
        \\      convert viriformat binary file to <FEN> | <SCORE> | <WDL>
        \\
        \\  sanitise --input <INPUT.vf> [<INPUT.vf> (positional)] [--print-errors] [--allow-overwrite] [--output <OUTPUT>]
        \\      sanitise a viriformat file. default output: <INPUT>_sanitised
        \\
        \\  analyse --input <INPUT.vf> [<INPUT.vf> (positional)] [--approximate] [--tb-path <TB_PATH>] [--allow-overwrite]
        \\      analyze a dataset file
        \\      --approximate: use HyperLogLog for faster unique count
        \\      --tb-path: required for TB statistics
        \\      score distribution output: score_distribution.txt
        \\
        \\  relabel-tb --input <INPUT.vf> --tb-path <TB_PATH> [--allow-overwrite] [--output <OUTPUT>]
        \\      relabel dataset outcomes based on Syzygy tablebases. default output: <INPUT>_relabeled
        \\
        \\  help
        \\      show this help message and exit
        \\
        \\UCI COMMANDS:
        \\  uci                     - handshake
        \\  isready                 - synchronization
        \\  setoption               - set Hash, Threads, SyzygyPath, EnableWeirdTCs, etc
        \\  ucinewgame              - clear hash and reset
        \\  position                - set board (fen <FEN> | startpos) [moves ...]
        \\  go                      - search. params: depth, nodes, softnodes, movetime,
        \\                            wtime, btime, winc, binc, mate, perft, perft_file
        \\  stop                    - stop current search
        \\  wait                    - wait for search to complete
        \\  d                       - print position
        \\  banner                  - print engine logo
        \\  nneval                  - show raw/scaled NNUE evaluation
        \\  hceval                  - show hand crafted evaluation
        \\  get_scale               - read evaluation scale from file
        \\  bullet_evals            - run eval on a set of known test positions
        \\  ProbeWDL                - query Syzygy tablebase
        \\  quit                    - exit
        \\
    , .{ version_string, bench_depth_default, datagen_threads_default, datagen_nodes_default });
}

fn handleBench(args: anytype) !void {
    const bench_args = try parseCommandArgs(
        args,
        .{ .depth = bench_depth_default },
        .{ .allow_implied = true },
        "bench",
    );
    try runBench(bench_args.depth);
}

fn handleDatagen(args: anytype, datagen_threads_default: usize) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            threads: ?usize = null,
            nodes: u64 = datagen_nodes_default,
            positions: u64,
        },
        .{},
        "datagen",
    );

    const datagen_threads = parsed.threads orelse datagen_threads_default;
    std.debug.print("datagenning with {} threads\n", .{datagen_threads});
    try root.engine.setThreadCount(datagen_threads);
    try root.engine.datagen(parsed.nodes, parsed.positions);
}

fn handleGenfens(arg: []const u8, allocator: std.mem.Allocator) !void {
    var genfens_seed: u64 = 0;
    var genfens_count: usize = 0;
    var genfens_book: ?[]const u8 = null;
    var genfens_args = std.mem.tokenizeScalar(u8, arg, ' ');
    _ = genfens_args.next(); // discard "genfens"
    genfens_count = std.fmt.parseInt(usize, genfens_args.next() orelse "", 10) catch |e| {
        writeLog("invalid fen count, error: '{}'\n", .{e});
        return e;
    };
    _ = genfens_args.next(); // discard "seed"
    genfens_seed = std.fmt.parseInt(u64, genfens_args.next() orelse "", 10) catch |e| {
        writeLog("invalid seed, error: '{}'\n", .{e});
        return e;
    };
    _ = genfens_args.next(); // discard "book"

    if (genfens_args.next()) |path| {
        if (!std.ascii.eqlIgnoreCase(path, "none")) {
            genfens_book = path;
        }
    }
    try root.engine.genfens(genfens_book, genfens_count, genfens_seed, &root.stdout_writer, allocator);
}

fn handlePgnToVf(args: anytype, allocator: std.mem.Allocator) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            input: []const u8,
            output: ?[]const u8 = null,
            @"skip-broken-games": bool = false,
            @"allow-non-pgn-extension": bool = false,
            @"allow-overwrite": bool = false,
        },
        .{
            .allow_implied = true,
            .usage_descriptions = &.{
                .{ .field = "output", .text = "--output <OUTPUT> (optional, default: <INPUT>.vf)" },
            },
        },
        "pgntovf",
    );
    const input = parsed.input;
    const skip_broken_games = parsed.@"skip-broken-games";
    const allow_non_pgn_extension = parsed.@"allow-non-pgn-extension";
    if (skip_broken_games) {
        std.debug.print("skipping broken games\n", .{});
    }
    if (allow_non_pgn_extension) {
        std.debug.print("allowing non pgn extension\n", .{});
    }

    if (!allow_non_pgn_extension and !std.mem.endsWith(u8, input, ".pgn")) {
        const len = std.mem.lastIndexOf(u8, input, ".") orelse input.len;
        writeLog("extension '{s}' is not allowed without '--allow-non-pgn-extension'\n", .{input[len..]});
        return error.InvalidExtension;
    }
    const output = if (parsed.output) |explicit_output|
        explicit_output
    else
        try std.fmt.allocPrint(allocator, "{s}.vf", .{input});
    defer if (parsed.output == null) allocator.free(output);

    var input_file = try openInputFile(input);
    defer input_file.close();

    var output_file = try createOutputFile(output, parsed.@"allow-overwrite");
    defer output_file.close();

    var input_buf: [4096]u8 = undefined;
    var output_buf: [4096]u8 = undefined;

    var input_reader = input_file.reader(&input_buf);
    var output_writer = output_file.writer(&output_buf);

    try @import("pgn_to_vf.zig").convert(
        &input_reader.interface,
        &output_writer.interface,
        skip_broken_games,
        std.heap.smp_allocator,
    );
}

fn handleEpdToVf(args: anytype, allocator: std.mem.Allocator) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            input: []const u8,
            output: ?[]const u8 = null,
            @"skip-broken-games": bool = false,
            @"white-relative": bool = false,
            @"allow-overwrite": bool = false,
        },
        .{
            .allow_implied = true,
            .usage_descriptions = &.{
                .{ .field = "output", .text = "--output <OUTPUT> (optional, default: <INPUT>.vf)" },
            },
        },
        "epdtovf",
    );
    const input = parsed.input;
    const skip_broken_games = parsed.@"skip-broken-games";
    const white_relative = parsed.@"white-relative";
    if (skip_broken_games) {
        std.debug.print("skipping broken games\n", .{});
    }
    if (white_relative) {
        std.debug.print("treating scores as white relative\n", .{});
    }

    const output = if (parsed.output) |explicit_output|
        explicit_output
    else
        try std.fmt.allocPrint(allocator, "{s}.vf", .{input});
    defer if (parsed.output == null) allocator.free(output);

    var input_file = try openInputFile(input);
    defer input_file.close();

    var output_file = try createOutputFile(output, parsed.@"allow-overwrite");
    defer output_file.close();

    var input_buf: [4096]u8 = undefined;
    var output_buf: [4096]u8 = undefined;

    var input_reader = input_file.reader(&input_buf);
    var output_writer = output_file.writer(&output_buf);

    try @import("epd_to_vf.zig").convert(
        &input_reader.interface,
        &output_writer.interface,
        skip_broken_games,
        white_relative,
        std.heap.smp_allocator,
    );
}

fn handleVfToTxt(args: anytype) !void {
    const parsed = try parseCommandArgs(
        args,
        struct { input: []const u8 },
        .{ .allow_implied = true },
        "vftotxt",
    );
    const input = parsed.input;

    var file = try openInputFile(input);
    defer file.close();

    var buf: [4096]u8 = undefined;
    var br = file.reader(&buf);

    const viriformat = root.viriformat;
    while (!br.atEnd()) {
        var marlin_board: viriformat.MarlinPackedBoard = undefined;
        br.interface.readSliceAll(std.mem.asBytes(&marlin_board)) catch |e| {
            if (e == error.EndOfStream) {
                break;
            } else {
                return e;
            }
        };

        var board = try marlin_board.toBoard();
        const wdl = @as(f64, @floatFromInt(marlin_board.wdl)) / 2.0;
        const sigmoid = struct {
            fn impl(score: i16) f64 {
                const f: f64 = @floatFromInt(score);

                return 1.0 / (1.0 + @exp(-f / 400.0));
            }
        }.impl;

        // var chosen_board: Board = undefined;
        // var chosen_eval: i16 = undefined;

        for (0..std.math.maxInt(usize)) |_| {
            var move_eval_pair: viriformat.MoveEvalPair = undefined;
            br.interface.readSliceAll(std.mem.asBytes(&move_eval_pair)) catch |e| {
                if (e == error.EndOfStream) {
                    break;
                } else {
                    return e;
                }
            };
            const viri_move = move_eval_pair.move;

            if (viri_move.data == 0) {
                break;
            }

            const move = viri_move.toMove(&board);

            switch (board.stm) {
                inline else => |stm| {
                    board.makeMove(stm, move, Board.NullEvalState{});
                },
            }

            write("{s} | {d:.10} | {d:.1}\n", .{ board.toFen().slice(), sigmoid(move_eval_pair.eval.toNative()), wdl });
            // if (rng.random().int(u32) % (i + 1) == 0) {
            //     chosen_board = board;
            //     chosen_eval = move_eval_pair.eval.toNative();
            // }
        }
        // write("{s} | {d:.10} | {d:.1}\n", .{ chosen_board.toFen().slice(), sigmoid(chosen_eval), wdl });
    }
}

fn handleAnalyse(args: anytype, allocator: std.mem.Allocator) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            input: []const u8,
            approximate: bool = false,
            @"tb-path": ?[]const u8 = null,
            @"allow-overwrite": bool = false,
        },
        .{ .allow_implied = true },
        "analyse",
    );
    const input = parsed.input;

    var use_tbs = false;
    if (parsed.@"tb-path") |tb_path| {
        try ensureTbPathExists(tb_path);
        const null_terminated = try allocator.dupeZ(u8, tb_path);
        defer allocator.free(null_terminated);
        try root.pyrrhic.init(null_terminated);
        use_tbs = true;
    }

    const approximate = parsed.approximate;
    if (!use_tbs) {
        std.debug.print("not using TBs, if you want TB stats please pass --tb-path\n", .{});
    }
    if (approximate) {
        std.debug.print("unique count is using HyperLogLog, and so may be slightly wrong\n", .{});
    } else {
        std.debug.print("unique count is using a hashset, for better performance try --approximate\n", .{});
    }

    var file = try openInputFile(input);
    defer file.close();
    const stat = try file.stat();

    var buf: [4096]u8 = undefined;
    var br = file.reader(&buf);

    var sum_exits: i64 = 0;
    var game_count: u64 = 0;
    var position_count: u64 = 0;
    var wins: u64 = 0;
    var draws: u64 = 0;
    var losses: u64 = 0;
    var tb_results = std.mem.zeroes([3][3]u64);
    var king_pos: [64]u64 = .{0} ** 64;
    var zobrist_set: std.AutoArrayHashMap(u64, void) = .init(allocator);
    defer zobrist_set.deinit();
    var score_counts: []u64 = try allocator.alloc(u64, 1 + std.math.maxInt(u16));
    defer allocator.free(score_counts);
    var piece_counts: [33]u64 = .{0} ** 33;
    var phase_counts: [25]u64 = .{0} ** 25;

    if (!approximate) {
        try zobrist_set.ensureTotalCapacity(@intCast((stat.size + 3) / 4));
    }

    var approximator = if (approximate) try @import("HyperLogLog.zig").init(20, allocator) else undefined;
    defer if (approximate) approximator.deinit(allocator);

    const viriformat = root.viriformat;
    while (!br.atEnd()) {
        var marlin_board: viriformat.MarlinPackedBoard = undefined;
        br.interface.readSliceAll(std.mem.asBytes(&marlin_board)) catch |e| {
            if (e == error.EndOfStream) {
                break;
            } else {
                return e;
            }
        };

        game_count += 1;
        switch (marlin_board.wdl) {
            0 => losses += 1,
            1 => draws += 1,
            2 => wins += 1,
            else => unreachable,
        }

        if (game_count % 16384 == 0) {
            const unique_count = if (approximate) approximator.count() else zobrist_set.count();
            write("\rprogress: {}% average exit so far: {d:.2} unique positions: {}/{} ({}%)", .{
                @as(u128, br.logicalPos() * 100) / @max(@as(u64, 1), stat.size),
                @as(f64, @floatFromInt(sum_exits)) / @as(f64, @floatFromInt(@max(@as(u64, 1), game_count))),
                unique_count,
                position_count,
                @as(u64, unique_count) * 100 / @max(@as(u64, 1), position_count),
            });
        }
        var board = try marlin_board.toBoard();
        var had_tb_win = false;
        var had_tb_draw = false;
        var had_tb_loss = false;
        for (0..std.math.maxInt(usize)) |move_idx| {
            var move_eval_pair: viriformat.MoveEvalPair = undefined;
            br.interface.readSliceAll(std.mem.asBytes(&move_eval_pair)) catch |e| {
                if (e == error.EndOfStream) {
                    break;
                } else {
                    return e;
                }
            };
            const viri_move = move_eval_pair.move;

            if (move_idx == 0) {
                const exit = if (board.stm == .white) move_eval_pair.eval.toNative() else -@as(i32, move_eval_pair.eval.toNative());

                sum_exits += exit;
            }

            if (viri_move.data == 0) {
                break;
            }

            const move = viri_move.toMove(&board);

            switch (board.stm) {
                inline else => |stm| {
                    @setEvalBranchQuota(1 << 30);
                    board.makeMove(stm, move, Board.NullEvalState{});
                },
            }
            var king: root.Square = .fromBitboard(board.kingFor(board.stm));
            if (board.stm == .black) {
                king = king.flipRank();
            }
            king_pos[king.toInt()] += 1;

            if (use_tbs) {
                if (root.pyrrhic.probeWDL(&board)) |res| {
                    switch (if (board.stm == .black) res.flipped() else res) {
                        .loss => had_tb_loss = true,
                        .draw => had_tb_draw = true,
                        .win => had_tb_win = true,
                    }
                }
            }
            piece_counts[@popCount(board.occupancy())] += 1;
            phase_counts[@min(24, board.sumPieces([_]u8{ 0, 1, 1, 2, 4, 0 }))] += 1;
            score_counts[@intCast(@as(isize, move_eval_pair.eval.toNative()) - std.math.minInt(i16))] += 1;
            if (approximate) {
                approximator.add(board.hash);
            } else {
                try zobrist_set.put(board.hash, void{});
            }
            position_count += 1;
        }
        if (had_tb_loss)
            tb_results[marlin_board.wdl][0] += 1;
        if (had_tb_draw)
            tb_results[marlin_board.wdl][1] += 1;
        if (had_tb_win)
            tb_results[marlin_board.wdl][2] += 1;
    }

    const unique_count = if (approximate) approximator.count() else zobrist_set.count();

    var total_tb: u64 = 0;
    for (tb_results) |tb_arr| for (tb_arr) |tb_count| {
        total_tb += tb_count;
    };
    const incorrect_tb = total_tb - (tb_results[0][0] + tb_results[1][1] + tb_results[2][2]);
    write(
        \\
        \\average exit: {d:.2}
        \\unique positions: {}/{} ({}%)
        \\piece count distribution: {any}
        \\phase distribution: {any}
        \\king position distribution: {any}
        \\tb results: {any}
        \\games whose outcome do not match TBs: {d:.2}%
        \\wins: {} ({}%)
        \\draws: {} ({}%)
        \\losses: {} ({}%)
        \\
    , .{
        @as(f64, @floatFromInt(sum_exits)) / @as(f64, @floatFromInt(@max(@as(u64, 1), game_count))),
        unique_count,
        position_count,
        @as(u64, unique_count) * 100 / @max(@as(u64, 1), position_count),
        piece_counts,
        phase_counts,
        king_pos,
        tb_results,
        @as(f64, @floatFromInt(incorrect_tb)) * 100 / @as(f64, @floatFromInt(@max(@as(u64, 1), total_tb))),
        wins,
        100 * wins / @max(@as(u64, 1), game_count),
        draws,
        100 * draws / @max(@as(u64, 1), game_count),
        losses,
        100 * losses / @max(@as(u64, 1), game_count),
    });
    write("king bucket distr:\n", .{});
    for (0..8) |i| {
        for (0..8) |j| {
            const count = king_pos[i * 8 + j];
            write("{d:>5.2} ", .{@as(f64, @floatFromInt(count * 100)) / @as(f64, @floatFromInt(@max(@as(u64, 1), position_count)))});
        }
        write("\n", .{});
    }
    write("king bucket distr (with mirroring):\n", .{});
    for (0..8) |i| {
        for (0..4) |j| {
            const count = king_pos[i * 8 + j] + king_pos[i * 8 + 7 - j];
            write("{d:>5.2} ", .{@as(f64, @floatFromInt(count * 100)) / @as(f64, @floatFromInt(@max(@as(u64, 1), position_count)))});
        }
        write("\n", .{});
    }

    write("writing score distribution to 'score_distribution.txt'\n", .{});
    var score_distr_file = try createOutputFile("score_distribution.txt", parsed.@"allow-overwrite");
    defer score_distr_file.close();

    // its fine to reuse the buffer since we finished reading the file
    var writer = score_distr_file.writer(&buf);
    try writer.interface.print("{any}\n", .{score_counts});
    try writer.interface.flush();
}

fn handleRelabelTb(args: anytype, allocator: std.mem.Allocator) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            input: []const u8,
            @"tb-path": []const u8,
            @"allow-overwrite": bool = false,
            output: ?[]const u8 = null,
        },
        .{
            .allow_implied = false,
            .usage_descriptions = &.{
                .{ .field = "input", .text = "--input <INPUT>" },
                .{ .field = "output", .text = "--output <OUTPUT> (optional, default: <INPUT>_relabeled)" },
            },
        },
        "relabel-tb",
    );
    const input = parsed.input;
    try ensureTbPathExists(parsed.@"tb-path");
    const null_terminated = try allocator.dupeZ(u8, parsed.@"tb-path");
    defer allocator.free(null_terminated);
    try root.pyrrhic.init(null_terminated);

    var input_file = try openInputFile(input);
    defer input_file.close();
    const stat = try input_file.stat();

    var name_writer = std.Io.Writer.Allocating.init(allocator);
    defer name_writer.deinit();
    try name_writer.writer.print("{s}_relabeled", .{input});
    const output = parsed.output orelse name_writer.written();
    var output_file = try createOutputFile(output, parsed.@"allow-overwrite");
    defer output_file.close();

    var input_buf: [4096]u8 = undefined;
    var br = input_file.reader(&input_buf);
    var output_buf: [4096]u8 = undefined;
    var bw = output_file.writer(&output_buf);

    var game_count: u64 = 0;
    var position_count: u64 = 0;
    var incorrect_wdl_count: u64 = 0;

    const viriformat = root.viriformat;
    while (!br.atEnd()) {
        var marlin_board: viriformat.MarlinPackedBoard = undefined;
        br.interface.readSliceAll(std.mem.asBytes(&marlin_board)) catch |e| {
            if (e == error.EndOfStream) {
                break;
            } else {
                return e;
            }
        };

        game_count += 1;

        if (game_count % 16384 == 0) {
            write("\rprogress: {}%", .{
                @as(u128, br.logicalPos() * 100) / stat.size,
            });
        }
        var board = try marlin_board.toBoard();
        var game = viriformat.Game.from(board, allocator);
        game.initial_position = marlin_board;
        defer game.moves.deinit();
        var skipping = false;
        var final_correct_wdl_idx: ?usize = null;
        for (0..std.math.maxInt(usize)) |move_idx| {
            var move_eval_pair: viriformat.MoveEvalPair = undefined;
            br.interface.readSliceAll(std.mem.asBytes(&move_eval_pair)) catch |e| {
                if (e == error.EndOfStream) {
                    break;
                } else {
                    return e;
                }
            };
            const viri_move = move_eval_pair.move;

            if (viri_move.data == 0) {
                break;
            }

            const move = viri_move.toMove(&board);
            if (!skipping) {
                try game.addMove(move, move_eval_pair.eval.toNative());
            }

            switch (board.stm) {
                inline else => |stm| {
                    @setEvalBranchQuota(1 << 30);
                    board.makeMove(stm, move, Board.NullEvalState{});
                },
            }

            if (!skipping) {
                if (root.pyrrhic.probeWDL(&board)) |res| {
                    const white_relative_result = if (board.stm == .black) res.flipped() else res;
                    const game_result: root.WDL = @enumFromInt(marlin_board.wdl);
                    if (white_relative_result != game_result) {
                        if (final_correct_wdl_idx) |final_corr_idx| {
                            while (game.moves.items.len > final_corr_idx + 1) {
                                _ = game.moves.pop();
                            }
                        } else {
                            incorrect_wdl_count += 1;
                            game.setOutCome(white_relative_result);
                        }
                        skipping = true;
                    } else {
                        final_correct_wdl_idx = move_idx;
                    }
                }
            }
            position_count += 1;
        }
        if (!skipping) {
            try game.serializeInto(&bw.interface);
        }
    }
    try bw.interface.flush();

    write(
        \\
        \\relabeled {}/{} games
        \\
    , .{
        incorrect_wdl_count,
        game_count,
    });
}

fn handleSanitise(args: anytype, allocator: std.mem.Allocator) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            input: []const u8,
            @"print-errors": bool = false,
            @"allow-overwrite": bool = false,
            output: ?[]const u8 = null,
        },
        .{
            .allow_implied = true,
            .usage_descriptions = &.{
                .{ .field = "output", .text = "--output <OUTPUT> (optional, default: <INPUT>_sanitised)" },
            },
        },
        "sanitise",
    );
    const input = parsed.input;

    var input_file = try openInputFile(input);
    defer input_file.close();

    var name_writer = std.Io.Writer.Allocating.init(allocator);
    defer name_writer.deinit();

    try name_writer.writer.print("{s}_sanitised", .{input});
    const output = parsed.output orelse name_writer.written();

    var output_file = try createOutputFile(output, parsed.@"allow-overwrite");
    defer output_file.close();

    const mapped = try @import("MappedFile.zig").init(input_file);
    defer mapped.deinit();

    var output_buf: [4096]u8 = undefined;
    var bw = output_file.writer(&output_buf);

    try @import("viriformat_sanitiser.zig").sanitiseBufferToFile(
        mapped.data,
        &bw.interface,
        allocator,
        parsed.@"print-errors",
    );

    try bw.interface.flush();
}

fn runBench(bench_depth: i32) !void {
    defer root.engine.printDebugStats();
    var total_nodes: u64 = 0;
    var timer = std.time.Timer.start() catch std.debug.panic("Fatal: timer failed to start\n", .{});
    root.engine.reset();
    for ([_][]const u8{
        "1B6/4R1p1/1p4kp/p7/r7/8/5P2/5K2 w - - 2 42",
        "1N6/1kp5/1p1p4/n3p3/5n2/P7/KP6/3R4 w - - 4 39",
        "1R6/2k5/8/1n6/1p1N1rP1/5P2/2K5/8 w - - 12 51",
        "1k1r4/1p1pq1p1/1bp1bpn1/6r1/4P3/1P1N2R1/1BPRQP1P/1NK5 w - - 1 19",
        "1k1r4/2p1p3/1pq2p2/p2bp1p1/P3BnPp/R2P1P1P/1PP5/1K2Q2R w - - 2 28",
        "1nkrr3/ppp2p1p/2n3p1/1N6/1P6/P3P3/2PBKP1P/6RR w - - 1 19",
        "1q2rnr1/1bpp1k1p/p3p1p1/1p3p1P/5PP1/1PP5/P2PP2Q/NBK1R1B1 b - - 0 16",
        "1qkr1bb1/1pp3pp/r2n2n1/p2p4/P3p1P1/2P1P2P/1P1PN2B/RQ1KNR1B w KQk - 1 11",
        "1r1kb1nr/p1pp4/2q1pp2/1pP1P1pp/8/P6P/1PPB1PP1/1Q1R1BKR b KQkq - 0 12",
        "1r1nkbr1/4pp2/1np4p/3P4/1p1P4/3N2B1/PP5P/R1KN1R2 b KQq - 0 19",
        "1r1q1rk1/p2p3p/5ppP/2bPp3/RP1nP1P1/3Q4/5P2/2BB1RK1 b - - 0 25",
        "1r3rk1/2p1p2p/6p1/QnP1q3/1N3p2/6P1/4PP1P/3R1R1K b - - 2 20",
        "1r6/2kp2p1/2q2p1b/2p1pP2/p1P1P2P/3N2PK/P3Q3/3R4 b - - 11 33",
        "1r6/p1p2p2/5k2/4R3/b1p2P2/2P5/PP2P1B1/4K3 b - - 0 33",
        "1rbq1b1r/p1p1nkp1/4pp2/1p6/7p/1N1PPBP1/PPP2P1P/R1BQK2R b KQ - 3 11",
        "2N5/8/2k2b2/6p1/6B1/P7/K7/8 w - - 5 69",
        "2R5/p3p3/1q2kp2/5n2/6R1/5P2/3BK1P1/8 b - - 5 52",
        "2k2r2/2b3p1/3rq1Pp/pR1np3/P3Q1P1/2PN1R2/3P1P2/4BK2 b - - 0 22",
        "2kq4/ppp2pp1/4p1n1/5nP1/2PPNB2/1P1Q1N2/PK6/R6r b - - 0 24",
        "2kr1b1r/pbpp2pp/2n5/4p2P/6R1/2NPP3/PPP2P2/R1B1K1N1 b Q - 0 14",
        "2kr4/p1pb2p1/8/qp2pP2/8/1P1PN1NB/3KQ3/8 w - - 4 31",
        "2n3k1/5r2/6pb/3R1p2/2PB4/3PP1Pp/4KP1P/8 b - - 1 45",
        "2r1k2r/1b1nbp2/p3p2p/1p1p4/1B1NnPPP/PP3B2/2P1N3/3RK2R b k - 2 23",
        "2r1k3/1Q6/p3q2r/1P1N1n2/3P2p1/P3P3/5P1b/1RBK3R b - - 0 25",
        "2rnk3/pq2pr1b/n1p2b1P/2Pp4/1p1P1pB1/2B2R2/PPN1Q2P/2KR4 w - - 0 23",
        "2rq1rk1/4bppp/p1n1pn2/1p1p4/1P6/PQ5P/1BNPPPBP/1R3R1K b - - 2 15",
        "3q1bk1/p1p2pp1/3n3r/7p/5Q1P/2P2BP1/1NK5/4R1B1 b - - 3 21",
        "3q1rk1/2p3n1/4p2p/2Pp2p1/1P1P1bP1/5P2/5N1P/B2Q1K1R w - - 1 24",
        "3r1nk1/p2br1p1/1p1q1p1p/2pPpB2/4P1PP/P2P1Q2/PB4R1/5RK1 w - - 2 31",
        "3r1r2/1b1p1pkp/1Nn3p1/p1p5/4P3/R2P2P1/P5BP/5RK1 w - - 6 25",
        "3r4/2k2p1p/2n3p1/Pp1b2P1/8/1Nb2N2/2P2PBP/3R2K1 b - - 4 26",
        "3r4/5pk1/8/5p2/Q2p1q1P/P1r2B2/2P1P1KP/3R4 w - - 3 30",
        "4R3/7B/1kp5/1p6/1p4Pn/2b5/1r3P2/3R2K1 b - - 0 30",
        "4k3/1pp5/3P2N1/p2P1R2/1rb5/2K4P/8/8 b - - 0 50",
        "4k3/4bp2/1pr3p1/p2p3p/3PN3/1RP1P2P/4K2P/R7 b - - 0 29",
        "4r3/7k/2p3p1/p1Nn2Rp/2pPp2P/1r2P3/1n3PB1/R5K1 b - - 1 33",
        "4r3/pp6/4k3/3bpR2/3pB1P1/5P2/PPP5/1K6 w - - 3 34",
        "5k2/6p1/5p2/p4P1p/1b2PBb1/1B2K1P1/8/8 w - - 0 44",
        "5n2/8/2k1b3/p7/P2RK3/4B3/8/8 b - - 0 52",
        "5q2/1p2nr1k/2ppn1pp/1p1b4/1P3PP1/P2PQ3/1B2N2K/3B1R2 b - - 0 53",
        "5r2/3kb3/4r3/1p2p3/p2pP1Q1/P2P1p1P/1PP2B2/1K6 w - - 0 40",
        "5r2/p3n3/1k6/1r1p4/7R/3BN3/1P2P3/2K5 b - - 1 32",
        "5rk1/6pn/4qp1B/2b1r3/2Pp1Q1P/6P1/3PP1K1/R1N2R2 b - - 0 28",
        "6k1/1b2B3/8/3P4/8/5K2/6P1/8 w - - 4 91",
        "6k1/3n1pp1/n6p/8/2rp3P/3N1NP1/1R2PPK1/8 w - - 5 33",
        "6k1/4R2p/Pn1r2p1/1p6/2bp4/4P2P/5PP1/5BK1 w - - 0 40",
        "6k1/5pp1/4p2p/8/3P4/2r1P3/1R3PPP/6K1 w - - 0 38",
        "7Q/pkn4p/1p2q1p1/P2n4/2p1N2P/5PP1/6K1/1B6 w - - 4 36",
        "8/1n2pp2/5kp1/3P4/1P6/r1N4P/5PKP/1R6 w - - 5 42",
        "8/1p1k4/5p1p/1PP4P/2K2N2/4n3/8/8 w - - 3 54",
        "8/1p6/3kb3/p2p4/3K4/P1P3p1/1P6/7B w - - 0 37",
        "8/1p6/k7/r7/1KN5/2P5/8/8 b - - 32 77",
        "8/2R3p1/1P3pkp/B7/5n2/1r6/3K4/8 w - - 1 52",
        "8/2k5/3n4/1bppNp2/p3pPn1/2P1P3/2KPN1P1/5B2 w - - 2 38",
        "8/2k5/8/1R6/1p1r2P1/5P2/2K5/8 w - - 0 52",
        "8/2p5/8/8/8/2P1R3/2KP2k1/5q2 w - - 32 72",
        "8/4k3/3Rp3/p4p1p/r6P/5PP1/5K2/8 w - - 2 44",
        "8/5p1k/2p1bPpq/p7/P3P3/3P1RQP/8/1r3BK1 w - - 5 42",
        "8/5p2/5N2/2p5/b3P3/1k2K1P1/5P2/8 w - - 7 45",
        "8/5pbk/1p6/p7/2Rq3p/5P2/4Q3/1K6 b - - 3 44",
        "8/5ppk/p6p/5Nn1/8/1P4P1/P2r1P2/R3K3 b - - 9 41",
        "8/6kp/4R3/3P4/8/4K1P1/7r/8 b - - 0 43",
        "8/8/1pk2N2/4P3/1P1np3/8/3K1P2/8 b - - 1 57",
        "8/8/2R5/3P1k1p/8/4P2K/5r1P/2B1b3 b - - 2 42",
        "8/8/R5b1/2P3k1/3Kr3/1B2P3/8/8 w - - 5 57",
        "8/8/r2k4/Pp6/8/P7/1KNB4/8 w - - 3 60",
        "8/Npk4r/p3p3/2PpP1p1/P2B4/1K3p2/2P2P2/3R3r w - - 2 41",
        "8/k7/8/P7/1B6/P7/8/3K4 b - - 4 77",
        "8/p1N5/3p1k2/P1p2n1p/2P5/3P4/3K4/8 w - - 0 44",
        "8/p1r5/5pkb/2NR2pp/1P3P2/3p4/P2Bb2P/6K1 w - - 4 43",
        "8/p2p3p/1Pp4k/5r2/1P2n2P/5N2/P2P4/2RK4 b - - 0 33",
        "8/p7/kp6/8/1Qp5/P1P5/8/2K1q3 w - - 10 52",
        "b1r1r1kb/Q1pp1p1p/4q1p1/8/8/1NP2pP1/Pn1PP2P/1BR1BRK1 w - - 0 15",
        "b3kb2/5pp1/8/2Pn2P1/1p1P4/3N4/1B6/4KB2 w - - 1 30",
        "bb1rk1r1/n3qn2/p5pP/1ppppp2/8/NBPP1P2/PP2PN1P/Q1B1RK1R w kq - 0 13",
        "n2rbrk1/pq2pp1p/3p2p1/1pp5/1P2PPP1/1P1B2Q1/2PP3P/R2NK2R w K - 0 11",
        "n7/k5pp/1pp5/5p2/2N5/7P/r4PK1/4R3 w - - 0 28",
        "nbkr2rq/p3p2p/1pb1n1p1/P2p1p2/1P3P2/R5P1/B2PP2P/2KNNRBQ b K - 2 10",
        "nqbrkrnb/2pp1p1p/4p1p1/8/R4P2/6P1/1P1PP2P/1NBBQNKR w Kkq - 0 7",
        "qrkn1brn/ppp1p2p/3p1p2/6Pb/8/3P2P1/PPPKPP2/BRN1RBQN b kq - 0 5",
        "r1b1rn1b/k2p1ppp/1q1P4/NQ1p2P1/Pp2p3/4P3/1PP2P1P/1RK1B1NB w Q - 1 16",
        "r1bk1b1r/p4ppp/4p3/1p6/4n3/2N5/PPP1NP1P/R1B1R1K1 b - - 1 13",
        "r1bqk1nr/p3ppbp/n1p3p1/3P4/Np6/1P6/P1PP1PPP/R1BQKBNR w KQkq - 2 8",
        "r1bqkb1r/1p2pppp/n4n2/p1p5/3pP3/NP1P1P2/P1P2NPP/R1BQKB1R b KQkq e3 0 7",
        "r2kqbrn/p1pb3p/n2p2p1/1pP2p2/1P2p3/2N1PPB1/P2P2PP/NRK2BRQ w KQkq - 2 9",
        "r2q1rk1/pp3pb1/2p1b1p1/2P5/3p2Pp/2N1Q2N/PP5P/2KR1BR1 w - - 0 18",
        "r3k3/7r/1p3ppp/4p3/2Pn3P/PnN3P1/1P3P2/1RBR2K1 b q - 3 25",
        "r3r1k1/1pp2ppp/2nq2bn/p6B/2P5/1P2PQ1P/PB1P1RP1/R3N1K1 w - - 3 21",
        "r3rbk1/p1qn1p1p/b4np1/Ppp1p3/1P2P3/B4NP1/2P1QPBP/RR1N2K1 b - - 1 17",
        "r4kr1/pQ6/1p3p2/8/3pP1P1/2b5/P1P1KP2/8 b - - 2 21",
        "r7/1kp2p2/8/1P1p4/2p1p3/2P1R3/3rN1K1/6R1 w - - 0 50",
        "r7/5k1p/p3qpp1/1pNp4/3Q1n2/PPB2P2/6nP/6K1 w - - 0 32",
        "rb1kbrnn/pp1ppppp/2pq4/8/P5P1/2N4P/1PPPPP2/R1KBBNQR b KQkq - 0 4",
        "rk2bn2/1pp2q2/p2p1n2/5p1p/5N1b/1PBN1B2/1KPP4/5RQ1 w q - 4 23",
        "rknqr3/2p2R1B/1pb1n2B/p2pP2p/P6P/2P3pR/QP2P1P1/3N2K1 b q - 0 15",
        "rn2kb1r/ppq2p2/2p1p1pn/3pP2p/P2P4/5b1P/1PP1BPP1/RNBQ1RK1 w kq - 0 10",
        "rnbqkbnr/1pp2ppp/4p3/p2p4/8/N1P5/PP1PPPPP/R1BQKBNR b KQkq - 1 4",
        "rnbqkbnr/2p1p1pp/5p2/1B1p4/3P4/4P1P1/PP3P1P/RNBQK1NR b KQkq - 0 7",
        "rnkbnrbq/1pp3p1/3pp2p/p6P/P4pP1/2PP1P2/1P2P3/RKRBBNQN b KQkq - 0 7",
        "rqnk2r1/2p1b2p/6b1/p2p4/1p1P2PB/PP6/2P4Q/NNKR3R b kq - 0 15",
    }) |fen| {
        root.engine.startSearch(.{
            .search_params = .{
                .board = try Board.parseFen(fen, false),
                .limits = root.Limits.initFixedDepth(bench_depth),
                .previous_hashes = .{},
                .normalize = false,
                .minimal = false,
            },
            .quiet = true,
        });
        root.engine.waitUntilDoneSearching();
        total_nodes += root.engine.querySearchedNodes();
    }
    // in the event that bench *somehow* takes 0ns lets still not divide by 0
    // more realistically this would indicate that the timer is broken
    const elapsed = @max(1, timer.read());
    write("{} nodes {} nps\n", .{ total_nodes, @as(u256, total_nodes) * std.time.ns_per_s / elapsed });
}
