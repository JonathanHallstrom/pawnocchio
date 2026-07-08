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
const arg_parser = @import("arg_parser.zig");
const edit_distance = @import("edit_distance.zig");
const HyperLogLog = @import("HyperLogLog.zig");
const write = root.write;
const writeLog = std.debug.print;
const Board = root.Board;
const Colour = root.Colour;
const PieceType = root.PieceType;

const BENCH_DEPTH_DEFAULT: i32 = 11;
const DATAGEN_NODES_DEFAULT: u64 = 7000;
const CMD_SUGGEST_BASE: usize = 120;
const CMD_SUGGEST_EXTRA: usize = 20;
const SHOW_SUGGESTION_COST: bool = false;
const TOOLS_ONLY = build_options.tools_only;

const Command = enum {
    help,
    datagen,
    genfens,
    pgntovf,
    epdtovf,
    vftotxt,
    analyse,
    @"relabel-tb",
    @"relabel-chonker",
    sanitise,
    bench,
};

fn printUsageLines(usage: []const []const u8) void {
    for (usage) |part| {
        writeLog("  {s}\n", .{part});
    }
}

const CommandSuggestion = struct {
    name: []const u8,
    cost: usize,
};

fn suggestCommand(input: []const u8) ?CommandSuggestion {
    const lookup = edit_distance.matchEnum(Command, input, CMD_SUGGEST_BASE, CMD_SUGGEST_EXTRA) orelse {
        const trimmed = std.mem.trim(u8, input, "-");
        if (trimmed.len == 0) {
            return null;
        }
        const lookup = edit_distance.matchEnum(enum { help }, trimmed, CMD_SUGGEST_BASE, CMD_SUGGEST_EXTRA) orelse return null;
        return switch (lookup) {
            .closest => |closest| .{ .name = @tagName(closest.tag), .cost = closest.cost },
            .match => null,
        };
    };
    return switch (lookup) {
        .closest => |closest| .{ .name = @tagName(closest.tag), .cost = closest.cost },
        .match => null,
    };
}

fn parseOptionName(arg: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, arg, "--")) return null;
    const option = arg[2..];
    return option[0 .. std.mem.indexOfScalar(u8, option, '=') orelse option.len];
}

fn logUnknownOption(command_name: []const u8, option_name: []const u8, suggestion: ?arg_parser.Suggestion) void {
    if (suggestion) |s| {
        if (SHOW_SUGGESTION_COST) {
            writeLog("invalid {s} arguments: unknown option '--{s}' (did you mean '--{s}'? cost={d})\n", .{
                command_name,
                option_name,
                s.name,
                s.cost,
            });
        } else {
            writeLog("invalid {s} arguments: unknown option '--{s}' (did you mean '--{s}'?)\n", .{
                command_name,
                option_name,
                s.name,
            });
        }
        return;
    }
    writeLog("invalid {s} arguments: unknown option '--{s}'\n", .{ command_name, option_name });
}

fn logUnknownCommand(command_token: []const u8, suggestion: ?CommandSuggestion) void {
    if (suggestion) |s| {
        if (SHOW_SUGGESTION_COST) {
            writeLog("unknown command '{s}'. did you mean '{s}'? cost={d}. pass 'help' for usage\n", .{
                command_token,
                s.name,
                s.cost,
            });
        } else {
            writeLog("unknown command '{s}'. did you mean '{s}'? pass 'help' for usage\n", .{
                command_token,
                s.name,
            });
        }
        return;
    }
    writeLog("unknown command '{s}'. pass 'help' for usage\n", .{command_token});
}

fn parseCommandArgs(args: anytype, comptime spec_or_type: anytype, comptime options: arg_parser.Options, comptime command_name: []const u8, allocator: std.mem.Allocator) !arg_parser.ParsedType(spec_or_type, options) {
    const parse_options: arg_parser.Options = .{
        .allow_implied = options.allow_implied,
        .default_int_type = options.default_int_type,
        .default_float_type = options.default_float_type,
        .option_suggest_base = options.option_suggest_base,
        .option_suggest_extra = options.option_suggest_extra,
        .usage_descriptions = options.usage_descriptions,
    };
    const ArgTracker = struct {
        inner: @TypeOf(args),
        last: ?[]const u8 = null,

        pub fn next(self: *@This()) ?[]const u8 {
            const value = self.inner.next();
            self.last = value orelse self.last;
            return value;
        }
    };

    var tracked_args = ArgTracker{ .inner = args };
    return arg_parser.parse(&tracked_args, spec_or_type, parse_options, allocator) catch |e| {
        if (e == error.HelpRequested) {
            const usage = arg_parser.fullUsage(spec_or_type, parse_options);
            if (usage.len > 0) {
                writeLog("{s} arguments:\n", .{command_name});
                printUsageLines(usage);
            } else {
                writeLog("{s}: no command arguments\n", .{command_name});
            }
            return e;
        }
        if (e == error.MissingRequiredOption) {
            const usage = arg_parser.requiredUsage(spec_or_type, parse_options);
            if (usage.len > 0) {
                writeLog("invalid {s} arguments: missing required arguments:\n", .{command_name});
                printUsageLines(usage);
            } else {
                writeLog("invalid {s} arguments: {}\n", .{ command_name, e });
            }
            return e;
        }
        if (e == error.UnknownOption) {
            const option_name = if (tracked_args.last) |arg| parseOptionName(arg) else null;
            if (option_name) |name| {
                logUnknownOption(command_name, name, arg_parser.suggestOptionWithCost(spec_or_type, parse_options, name));
                return e;
            }
        }
        writeLog("invalid {s} arguments: {}\n", .{ command_name, e });
        return e;
    };
}

fn openInputFile(io: std.Io, path: []const u8) !std.Io.File {
    const open_result = if (std.fs.path.isAbsolute(path))
        std.Io.Dir.openFileAbsolute(io, path, .{})
    else
        std.Io.Dir.cwd().openFile(io, path, .{});
    return open_result catch |e| {
        writeLog("opening file '{s}' gave: '{}'\n", .{ path, e });
        return e;
    };
}

fn createOutputFile(io: std.Io, path: []const u8, allow_overwrite: bool) !std.Io.File {
    const flags: std.Io.Dir.CreateFileOptions = .{
        .exclusive = !allow_overwrite,
    };
    const create_result = if (std.fs.path.isAbsolute(path))
        std.Io.Dir.createFileAbsolute(io, path, flags)
    else
        std.Io.Dir.cwd().createFile(io, path, flags);
    return create_result catch |e| {
        if (e == error.PathAlreadyExists and !allow_overwrite) {
            writeLog("refusing to overwrite existing file '{s}' (pass --allow-overwrite)\n", .{path});
            return e;
        }
        writeLog("creating file '{s}' gave: '{}'\n", .{ path, e });
        return e;
    };
}

fn ensureTbPathExists(io: std.Io, tb_path: []const u8) !void {
    const access_result = if (std.fs.path.isAbsolute(tb_path))
        std.Io.Dir.accessAbsolute(io, tb_path, .{})
    else
        std.Io.Dir.cwd().access(io, tb_path, .{});
    return access_result catch |e| {
        writeLog("tb path '{s}' is not accessible: '{}'\n", .{ tb_path, e });
        return e;
    };
}

pub fn handle(init: std.process.Init, version: []const u8) !bool {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.next() orelse "pawnocchio";

    const threads: usize = std.Thread.getCpuCount() catch 1;
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            handleHelp(version, threads);
            return true;
        }

        const cmd_raw = std.mem.trim(u8, arg, "-");
        if (std.meta.stringToEnum(Command, cmd_raw)) |command| {
            switch (command) {
                .help => {
                    handleHelp(version, threads);
                    return true;
                },
                .datagen => if (TOOLS_ONLY) {
                    writeLog("datagen is unavailable in this build\n", .{});
                } else {
                    try handleDatagen(init.io, init.gpa, &args, threads);
                },
                .genfens => if (TOOLS_ONLY) {
                    writeLog("genfens is unavailable in this build\n", .{});
                } else {
                    try handleGenfens(init.io, init.gpa, &args);
                },
                .pgntovf => try handlePgntovf(init.io, init.gpa, &args),
                .epdtovf => try handleEpdtovf(init.io, init.gpa, &args),
                .vftotxt => try handleVftotxt(init.io, init.gpa, &args),
                .analyse => try handleAnalyse(init.io, init.gpa, &args),
                .@"relabel-tb" => try handleRelabelTb(init.io, init.gpa, &args),
                .@"relabel-chonker" => try handleRelabelChonker(init.io, init.gpa, &args),
                .sanitise => try handleSanitise(init.io, init.gpa, &args),
                .bench => try handleBench(init.io, init.gpa, &args),
            }
            return true;
        }

        logUnknownCommand(arg, suggestCommand(arg));
        return true;
    }

    return false;
}

pub fn writeHelp(version: []const u8) void {
    handleHelp(version, std.Thread.getCpuCount() catch 1);
}

fn handleHelp(version: []const u8, threads: usize) void {
    std.debug.print(
        \\pawnocchio {s} - UCI chess engine
        \\
        \\USAGE:
        \\  pawnocchio [COMMAND] [ARGUMENTS]
    , .{version});
    if (!TOOLS_ONLY) {
        std.debug.print("  pawnocchio (starts in UCI mode)\n", .{});
    }
    std.debug.print(
        \\
        \\TOOLS:
        \\
    , .{});
    if (!TOOLS_ONLY) {
        std.debug.print(
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
        , .{ BENCH_DEPTH_DEFAULT, threads, DATAGEN_NODES_DEFAULT });
    }
    std.debug.print(
        \\  pgntovf --input <INPUT.pgn> [<INPUT.pgn> (positional)] [--skip-broken-games] [--allow-non-pgn-extension] [--allow-overwrite] [--output <OUTPUT>] [--fill-missing-evals <i16|prev|next>]
        \\      convert PGN to viriformat. default output: <INPUT>.vf
        \\
        \\  epdtovf --input <INPUT.epd> [<INPUT.epd> (positional)] [--skip-broken-games] [--white-relative] [--allow-overwrite] [--output <OUTPUT>]
        \\      convert EPD to viriformat. default output: <INPUT>.vf
        \\
        \\  vftotxt --input <INPUT.vf> [<INPUT.vf> (positional)]
        \\      convert viriformat binary file to <FEN> | <SCORE> | <WDL>
        \\
        \\  sanitise --input <INPUT.vf> [<INPUT.vf> (positional)] [--print-errors] [--check-only] [--allow-overwrite] [--output <OUTPUT>]
        \\      sanitise a viriformat file. default output: <INPUT>_sanitised unless --check-only is used
        \\
        \\  analyse --inputs <FILE> [<FILE>...] [--approximate] [--tb-path <TB_PATH>] [--allow-overwrite]
        \\      analyze one or more dataset files
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
    , .{});
    if (!TOOLS_ONLY) {
        std.debug.print(
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
        , .{});
    }
}

fn handleBench(io: std.Io, allocator: std.mem.Allocator, args: anytype) !void {
    const bench_args = try parseCommandArgs(
        args,
        .{ .depth = BENCH_DEPTH_DEFAULT },
        .{ .allow_implied = true },
        "bench",
        allocator,
    );
    try runBench(io, bench_args.depth);
}

fn handleDatagen(io: std.Io, allocator: std.mem.Allocator, args: anytype, default_threads: usize) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            threads: ?usize = null,
            nodes: u64 = DATAGEN_NODES_DEFAULT,
            positions: u64,
        },
        .{},
        "datagen",
        allocator,
    );

    const datagen_threads = parsed.threads orelse default_threads;
    std.debug.print("datagenning with {} threads\n", .{datagen_threads});
    try root.engine.setThreadCount(datagen_threads);
    try root.engine.datagen(io, parsed.nodes, parsed.positions);
}

fn handleGenfens(io: std.Io, allocator: std.mem.Allocator, args: anytype) !void {
    var seed: u64 = 0;
    var count: usize = 0;
    var book: ?[]const u8 = null;
    count = std.fmt.parseInt(usize, args.next() orelse "", 10) catch |e| {
        writeLog("invalid fen count, error: '{}'\n", .{e});
        return e;
    };
    _ = args.next(); // discard "seed"
    seed = std.fmt.parseInt(u64, args.next() orelse "", 10) catch |e| {
        writeLog("invalid seed, error: '{}'\n", .{e});
        return e;
    };
    _ = args.next(); // discard "book"

    if (args.next()) |path| {
        if (!std.ascii.eqlIgnoreCase(path, "none")) {
            book = path;
        }
    }
    try root.engine.genfens(io, book, count, seed, root.stdout_writer, allocator);
}

fn handlePgntovf(io: std.Io, allocator: std.mem.Allocator, args: anytype) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            input: []const u8,
            output: ?[]const u8 = null,
            @"skip-broken-games": bool = false,
            @"allow-non-pgn-extension": bool = false,
            @"allow-overwrite": bool = false,
            @"fill-missing-evals": ?[]const u8 = null,
        },
        .{
            .allow_implied = true,
            .usage_descriptions = &.{
                .{ .field = "output", .default_text = "<INPUT>.vf" },
                .{ .field = "fill-missing-evals", .text = "--fill-missing-evals <VALUE|prev|next>" },
            },
        },
        "pgntovf",
        allocator,
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

    const fill: @import("pgn_to_vf.zig").MissingEvalFill = if (parsed.@"fill-missing-evals") |spec| blk: {
        if (std.ascii.eqlIgnoreCase(spec, "prev")) break :blk .prev;
        if (std.ascii.eqlIgnoreCase(spec, "next")) break :blk .next;
        const value = std.fmt.parseInt(i16, spec, 10) catch {
            writeLog("invalid --fill-missing-evals value '{s}'; expected an integer (i16), 'prev', or 'next'\n", .{spec});
            return error.InvalidValue;
        };
        break :blk .{ .value = value };
    } else .none;

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

    var input_file = try openInputFile(io, input);
    defer input_file.close(io);

    var output_file = try createOutputFile(io, output, parsed.@"allow-overwrite");
    defer output_file.close(io);

    var input_buf: [4096]u8 = undefined;
    var output_buf: [4096]u8 = undefined;

    var input_reader = input_file.readerStreaming(io, &input_buf);
    var output_writer = output_file.writerStreaming(io, &output_buf);

    try @import("pgn_to_vf.zig").convert(
        io,
        allocator,
        &input_reader.interface,
        &output_writer.interface,
        skip_broken_games,
        fill,
    );
}

fn handleEpdtovf(io: std.Io, allocator: std.mem.Allocator, args: anytype) !void {
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
                .{ .field = "output", .default_text = "<INPUT>.vf" },
            },
        },
        "epdtovf",
        allocator,
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

    var input_file = try openInputFile(io, input);
    defer input_file.close(io);

    var output_file = try createOutputFile(io, output, parsed.@"allow-overwrite");
    defer output_file.close(io);

    var input_buf: [4096]u8 = undefined;
    var output_buf: [4096]u8 = undefined;

    var input_reader = input_file.readerStreaming(io, &input_buf);
    var output_writer = output_file.writerStreaming(io, &output_buf);

    try @import("epd_to_vf.zig").convert(
        io,
        allocator,
        &input_reader.interface,
        &output_writer.interface,
        skip_broken_games,
        white_relative,
    );
}

fn handleVftotxt(io: std.Io, allocator: std.mem.Allocator, args: anytype) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            input: []const u8,
            @"sigmoid-scores": bool = false,
        },
        .{ .allow_implied = true },
        "vftotxt",
        allocator,
    );
    const input = parsed.input;

    var file = try openInputFile(io, input);
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var br = file.readerStreaming(io, &buf);

    var reader = root.viriformat.scoredPlyReader(&br.interface, allocator);
    while (try reader.next()) |game| {
        const wdl = @as(f64, @floatFromInt(@intFromEnum(game.outcome))) / 2.0;
        const sigmoid = struct {
            fn impl(score: i16) f64 {
                const f: f64 = @floatFromInt(score);

                return 1.0 / (1.0 + @exp(-f / 400.0));
            }
        }.impl;

        var it = game.iter();
        while (try it.next()) |ply| {
            const board = ply.board.*;
            const eval = ply.whiteEval().?;

            if (parsed.@"sigmoid-scores") {
                write("{s} | {d:.10} | {d:.1}\n", .{ board.toFen().slice(), sigmoid(eval), wdl });
            } else {
                write("{s} | {d} | {d}\n", .{ board.toFen().slice(), eval, wdl });
            }
        }
    }
}

const PieceCountTable = std.enums.EnumArray(PieceType, [11]u64);

const AnalysisStats = struct {
    sum_exits: i64 = 0,
    game_count: u64 = 0,
    position_count: u64 = 0,
    wins: u64 = 0,
    draws: u64 = 0,
    losses: u64 = 0,
    tb_results: std.enums.EnumArray(root.WDL, std.enums.EnumArray(root.WDL, u64)) = std.mem.zeroes(std.enums.EnumArray(root.WDL, std.enums.EnumArray(root.WDL, u64))),
    king_pos: [64]u64 = @splat(0),
    score_counts: []u64 = &.{},
    total_piece_counts: [33]u64 = @splat(0),
    phase_counts: [25]u64 = @splat(0),
    piece_counts: [2]PieceCountTable = @splat(PieceCountTable.initFill(@splat(0))),
    tracker: UniqueTracker = .{ .exact = .empty },

    fn init(approximate: bool, allocator: std.mem.Allocator) !AnalysisStats {
        var stats: AnalysisStats = .{};
        stats.tracker = try UniqueTracker.init(approximate, allocator);
        errdefer stats.tracker.deinit(allocator);
        stats.score_counts = try allocator.alloc(u64, 1 + std.math.maxInt(u16));
        @memset(stats.score_counts, 0);
        return stats;
    }

    fn deinit(self: *AnalysisStats, allocator: std.mem.Allocator) void {
        allocator.free(self.score_counts);
        self.tracker.deinit(allocator);
    }

    fn add(self: *AnalysisStats, other: *const AnalysisStats, allocator: std.mem.Allocator) !void {
        self.sum_exits += other.sum_exits;
        self.game_count += other.game_count;
        self.position_count += other.position_count;
        self.wins += other.wins;
        self.draws += other.draws;
        self.losses += other.losses;
        inline for (std.meta.fields(root.WDL)) |gf| {
            inline for (std.meta.fields(root.WDL)) |tf| {
                self.tb_results.getPtr(@field(root.WDL, gf.name)).getPtr(@field(root.WDL, tf.name)).* +=
                    other.tb_results.get(@field(root.WDL, gf.name)).get(@field(root.WDL, tf.name));
            }
        }
        for (&self.king_pos, other.king_pos) |*dst, src| dst.* += src;
        for (self.score_counts, other.score_counts) |*dst, src| dst.* += src;
        for (&self.total_piece_counts, other.total_piece_counts) |*dst, src| dst.* += src;
        for (&self.phase_counts, other.phase_counts) |*dst, src| dst.* += src;
        for (0..2) |ci| {
            for (PieceType.all) |pt| {
                for (self.piece_counts[ci].getPtr(pt), other.piece_counts[ci].get(pt)) |*dst, src| dst.* += src;
            }
        }
        try self.tracker.merge(&other.tracker, allocator);
    }
};

const UniqueTracker = union(enum) {
    exact: std.AutoArrayHashMapUnmanaged(u64, void),
    approx: HyperLogLog,

    fn init(approximate: bool, allocator: std.mem.Allocator) !UniqueTracker {
        return if (approximate)
            .{ .approx = try HyperLogLog.init(20, allocator) }
        else
            .{ .exact = .empty };
    }

    fn deinit(self: *UniqueTracker, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .exact => |*s| s.deinit(allocator),
            .approx => |a| a.deinit(allocator),
        }
    }

    fn track(self: *UniqueTracker, allocator: std.mem.Allocator, hash: u64) !void {
        switch (self.*) {
            .exact => |*s| try s.put(allocator, hash, {}),
            .approx => |*a| a.add(hash),
        }
    }

    fn count(self: *const UniqueTracker) u64 {
        return switch (self.*) {
            .exact => |s| s.count(),
            .approx => |*a| a.count(),
        };
    }

    fn merge(self: *UniqueTracker, other: *const UniqueTracker, allocator: std.mem.Allocator) !void {
        switch (self.*) {
            .exact => |*s| {
                for (other.exact.keys()) |key| try s.put(allocator, key, {});
            },
            .approx => |*a| {
                for (a.m, other.approx.m) |*dst, src| dst.* = @max(dst.*, src);
            },
        }
    }
};

fn analyseFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    file: std.Io.File,
    format: root.dataformat.FileFormat,
    use_tbs: bool,
    approximate: bool,
    bytes_done: *std.atomic.Value(u64),
) !AnalysisStats {
    var stats = try AnalysisStats.init(approximate, allocator);
    errdefer stats.deinit(allocator);

    var buf: [4096]u8 = undefined;
    var br = file.readerStreaming(io, &buf);
    var ply_reader = try root.owning_reader.OwningReader.init(format, &br.interface, allocator);
    defer ply_reader.deinit();

    var prev_pos = br.logicalPos();
    while (try (&ply_reader).next()) |game| {
        stats.game_count += 1;
        switch (@intFromEnum(game.outcome)) {
            0 => stats.losses += 1,
            1 => stats.draws += 1,
            2 => stats.wins += 1,
            else => unreachable,
        }

        if (stats.game_count % 16 == 0) {
            const new_pos = br.logicalPos();
            _ = bytes_done.fetchAdd(new_pos - prev_pos, .acq_rel);
            prev_pos = new_pos;
        }

        var had_tb_win = false;
        var had_tb_draw = false;
        var had_tb_loss = false;
        var board = game.initial_board.*;
        for (game.moves, 0..) |ply, move_idx| {
            if (move_idx == 0) {
                if (ply.stmEval(board.stm)) |ev| {
                    stats.sum_exits += ev;
                }
            }

            var king: root.Square = .fromBitboard(board.kingFor(board.stm));
            if (board.stm == .black) {
                king = king.flipRank();
            }
            stats.king_pos[king.toInt()] += 1;

            if (use_tbs) {
                if (root.pyrrhic.probeWDL(&board)) |res| {
                    switch (if (board.stm == .black) res.flipped() else res) {
                        .loss => had_tb_loss = true,
                        .draw => had_tb_draw = true,
                        .win => had_tb_win = true,
                    }
                }
            }
            stats.total_piece_counts[@popCount(board.occupancy())] += 1;
            stats.phase_counts[@min(24, board.sumPieces([_]u8{ 0, 1, 1, 2, 4, 0 }))] += 1;
            inline for (.{ Colour.white, Colour.black }) |col| {
                for (PieceType.all) |pt| {
                    const cnt = @popCount(board.pieceFor(col, pt));
                    stats.piece_counts[col.toInt()].getPtr(pt)[cnt] += 1;
                }
            }
            if (ply.whiteEval()) |ev| {
                stats.score_counts[@intCast(@as(isize, ev) - std.math.minInt(i16))] += 1;
            }
            try stats.tracker.track(allocator, board.hash);
            stats.position_count += 1;
            board.makeMoveSimple(ply.move);
        }
        if (had_tb_loss)
            stats.tb_results.getPtr(game.outcome).getPtr(.loss).* += 1;
        if (had_tb_draw)
            stats.tb_results.getPtr(game.outcome).getPtr(.draw).* += 1;
        if (had_tb_win)
            stats.tb_results.getPtr(game.outcome).getPtr(.win).* += 1;
    }

    return stats;
}

fn handleAnalyse(io: std.Io, allocator: std.mem.Allocator, args: anytype) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            inputs: []const []const u8,
            approximate: bool = false,
            verbose: bool = false,
            @"tb-path": ?[]const u8 = null,
            @"allow-overwrite": bool = false,
            format: root.dataformat.FileFormat = .viriformat,
        },
        .{ .allow_implied = false },
        "analyse",
        allocator,
    );
    defer allocator.free(parsed.inputs);
    const verbose = parsed.verbose;
    if (!parsed.@"allow-overwrite") {
        if (std.Io.Dir.cwd().access(io, "score_distribution.txt", .{})) |_| {
            writeLog("refusing to overwrite existing file 'score_distribution.txt' (pass --allow-overwrite)\n", .{});
            return error.PathAlreadyExists;
        } else |e| switch (e) {
            error.FileNotFound => {},
            else => {
                writeLog("checking output file 'score_distribution.txt' gave: '{}'\n", .{e});
                return e;
            },
        }
    }

    var use_tbs = false;
    if (parsed.@"tb-path") |tb_path| {
        try ensureTbPathExists(io, tb_path);
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

    var total_size: u64 = 0;
    for (parsed.inputs) |input_path| {
        var f = try openInputFile(io, input_path);
        defer f.close(io);
        total_size += (try f.stat(io)).size;
    }

    var combined = try AnalysisStats.init(approximate, allocator);
    defer combined.deinit(allocator);

    if (!approximate) {
        try combined.tracker.exact.ensureTotalCapacity(allocator, @intCast((total_size + 3) / 4));
    }

    var bytes_done: std.atomic.Value(u64) = .init(0);
    var merge_lock = std.Io.Mutex.init;
    var futures = std.array_list.Managed(std.Io.Future(anyerror!void)).init(allocator);
    defer futures.deinit();

    var done = std.atomic.Value(bool).init(false);
    var progress_future = try io.concurrent(struct {
        fn impl(
            io_: std.Io,
            bytes_done_: *const std.atomic.Value(u64),
            total_size_: u64,
            done_: *const std.atomic.Value(bool),
        ) !void {
            while (!done_.load(.seq_cst)) {
                try io_.sleep(.fromMilliseconds(100), .awake);
                std.debug.print("\rprogress: {d:.2}%", .{
                    @as(f64, @floatFromInt(100 * bytes_done_.load(.acquire))) /
                        @as(f64, @floatFromInt(total_size_)),
                });
            }
            std.debug.print("\n", .{});
        }
    }.impl, .{
        io,
        &bytes_done,
        total_size,
        &done,
    });
    for (parsed.inputs) |input_path| {
        try futures.append(io.async(struct {
            fn impl(
                input_path_: []const u8,
                io_: std.Io,
                allocator_: std.mem.Allocator,
                format: root.dataformat.FileFormat,
                use_tbs_: bool,
                approximate_: bool,
                bytes_done_: *std.atomic.Value(u64),
                combined_: *AnalysisStats,
                merge_lock_: *std.Io.Mutex,
            ) anyerror!void {
                var file = try openInputFile(io_, input_path_);
                defer file.close(io_);

                var file_stats = try analyseFile(io_, allocator_, file, format, use_tbs_, approximate_, bytes_done_);
                defer file_stats.deinit(allocator_);
                try merge_lock_.lock(io_);
                defer merge_lock_.unlock(io_);
                try combined_.add(&file_stats, allocator_);
            }
        }.impl, .{
            input_path,
            io,
            allocator,
            parsed.format,
            use_tbs,
            approximate,
            &bytes_done,
            &combined,
            &merge_lock,
        }));
    }
    for (futures.items) |*f| {
        try f.await(io);
    }
    done.store(true, .seq_cst);
    try progress_future.await(io);

    const unique_count = combined.tracker.count();

    var total_tb: u64 = 0;
    var tb_outer_iter = combined.tb_results.iterator();
    while (tb_outer_iter.next()) |a| {
        var tb_inner_iter = a.value.iterator();
        while (tb_inner_iter.next()) |e| {
            total_tb += e.value.*;
        }
    }
    const correct_tb =
        combined.tb_results.get(.loss).get(.loss) +
        combined.tb_results.get(.draw).get(.draw) +
        combined.tb_results.get(.win).get(.win);
    const incorrect_tb = total_tb - correct_tb;
    const positions_per_game = @as(f64, @floatFromInt(combined.position_count)) / @as(f64, @floatFromInt(@max(@as(u64, 1), combined.game_count)));
    write(
        \\
        \\games: {}
        \\positions: {}
        \\positions/game: {d:.2}
        \\average exit: {d:.2}
        \\unique positions: {}/{} ({}%)
    , .{
        combined.game_count,
        combined.position_count,
        positions_per_game,
        @as(f64, @floatFromInt(combined.sum_exits)) / @as(f64, @floatFromInt(@max(@as(u64, 1), combined.game_count))),
        unique_count,
        combined.position_count,
        @as(u64, unique_count) * 100 / @max(@as(u64, 1), combined.position_count),
    });

    if (use_tbs) {
        write("\ngames whose outcome do not match TBs: {d:.2}%", .{@as(f64, @floatFromInt(incorrect_tb)) * 100 / @as(f64, @floatFromInt(@max(@as(u64, 1), total_tb)))});
    }

    write(
        \\
        \\wins: {} ({}%)
        \\draws: {} ({}%)
        \\losses: {} ({}%)
        \\king bucket distr:
        \\{f}
        \\king bucket distr (mirrored):
        \\{f}
        \\
    , .{
        combined.wins,
        100 * combined.wins / @max(@as(u64, 1), combined.game_count),
        combined.draws,
        100 * combined.draws / @max(@as(u64, 1), combined.game_count),
        combined.losses,
        100 * combined.losses / @max(@as(u64, 1), combined.game_count),
        formatPositionCounts(false, combined.king_pos),
        formatPositionCounts(true, combined.king_pos),
    });

    if (verbose) {
        write(
            \\
            \\piece count distribution: {f}
            \\phase distribution: {f}
            \\white piece distribution: {f}
            \\black piece distribution: {f}
            \\king pos distribution: {f}
        , .{
            formatValue(combined.total_piece_counts),
            formatValue(combined.phase_counts),
            formatEnumArray(PieceType, combined.piece_counts[Colour.white.toInt()]),
            formatEnumArray(PieceType, combined.piece_counts[Colour.black.toInt()]),
            formatArrayNewline(@as([8][8]u64, @bitCast(combined.king_pos))),
        });
        if (use_tbs) {
            write("\ntb results: {f}", .{formatWdlMatrix(combined.tb_results)});
        }
        write("\n", .{});
    }

    write("writing score distribution to 'score_distribution.txt'\n", .{});
    var score_distr_file = try createOutputFile(io, "score_distribution.txt", parsed.@"allow-overwrite");
    defer score_distr_file.close(io);

    var buf: [4096]u8 = undefined;
    var writer = score_distr_file.writerStreaming(io, &buf);
    try writer.interface.print("{any}\n", .{combined.score_counts});
    try writer.interface.flush();
}

fn handleRelabelTb(io: std.Io, allocator: std.mem.Allocator, args: anytype) !void {
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
                .{ .field = "output", .default_text = "<INPUT>_relabeled" },
            },
        },
        "relabel-tb",
        allocator,
    );
    const input = parsed.input;
    try ensureTbPathExists(io, parsed.@"tb-path");
    const null_terminated = try allocator.dupeZ(u8, parsed.@"tb-path");
    defer allocator.free(null_terminated);
    try root.pyrrhic.init(null_terminated);

    var input_file = try openInputFile(io, input);
    defer input_file.close(io);
    const stat = try input_file.stat(io);

    var name_writer = std.Io.Writer.Allocating.init(allocator);
    defer name_writer.deinit();
    try name_writer.writer.print("{s}_relabeled", .{input});
    const output = parsed.output orelse name_writer.written();
    var output_file = try createOutputFile(io, output, parsed.@"allow-overwrite");
    defer output_file.close(io);

    var input_buf: [4096]u8 = undefined;
    var br = input_file.readerStreaming(io, &input_buf);
    var output_buf: [4096]u8 = undefined;
    var bw = output_file.writerStreaming(io, &output_buf);

    var game_count: u64 = 0;
    var position_count: u64 = 0;
    var incorrect_wdl_count: u64 = 0;

    var reader = root.viriformat.scoredPlyReader(&br.interface, allocator);
    while (try reader.next()) |game| {
        game_count += 1;

        if (game_count % 16384 == 0) {
            write("\rprogress: {}%", .{
                @as(u128, br.logicalPos() * 100) / stat.size,
            });
        }

        var record = root.viriformat.GameRecord.from(game.board, allocator);
        defer record.deinit();
        record.setOutCome(game.outcome);

        var skipping = false;
        var final_correct_wdl_idx: ?usize = null;
        var it = game.iter();
        var move_idx: usize = 0;
        while (try it.next()) |ply| : (move_idx += 1) {
            const eval = ply.whiteEval().?;

            if (!skipping) {
                try record.addMove(ply.move, eval);

                var board = ply.board.*;
                board.makeMoveSimple(ply.move);

                if (root.pyrrhic.probeWDL(board)) |res| {
                    const white_relative_result = if (board.stm == .black) res.flipped() else res;
                    const game_result = game.outcome;
                    if (white_relative_result != game_result) {
                        if (final_correct_wdl_idx) |final_corr_idx| {
                            while (record.moves.items.len > final_corr_idx + 1) {
                                _ = record.moves.pop();
                            }
                        } else {
                            incorrect_wdl_count += 1;
                            record.setOutCome(white_relative_result);
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
            try record.serializeInto(&bw.interface);
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

fn handleRelabelChonker(io: std.Io, allocator: std.mem.Allocator, args: anytype) !void {
    if (root.EVAL_MODE != .nnue) {
        return error.NNUENotEnabled;
    }

    const parsed = try parseCommandArgs(
        args,
        struct {
            input: []const u8,
            @"allow-overwrite": bool = false,
            output: ?[]const u8 = null,
        },
        .{
            .allow_implied = false,
            .usage_descriptions = &.{
                .{ .field = "output", .default_text = "<INPUT>_evals_relabeled" },
            },
        },
        "relabel-chonker",
        allocator,
    );
    const input = parsed.input;

    var input_file = try openInputFile(io, input);
    defer input_file.close(io);
    const stat = try input_file.stat(io);

    var name_writer = std.Io.Writer.Allocating.init(allocator);
    defer name_writer.deinit();
    try name_writer.writer.print("{s}_evals_relabeled", .{input});
    const output = parsed.output orelse name_writer.written();
    var output_file = try createOutputFile(io, output, parsed.@"allow-overwrite");
    defer output_file.close(io);

    var input_buf: [4096]u8 = undefined;
    var br = input_file.readerStreaming(io, &input_buf);
    var output_buf: [4096]u8 = undefined;
    var bw = output_file.writerStreaming(io, &output_buf);

    var game_count: u64 = 0;
    var position_count: u64 = 0;

    var reader = root.viriformat.scoredPlyReader(&br.interface, allocator);

    const ctx = root.evaluation.globalCtx.lock();
    defer root.evaluation.globalCtx.release();
    ctx.initRoot(&Board.startpos());

    const start_time = std.Io.Timestamp.now(io, .awake);
    while (try reader.next()) |game| {
        game_count += 1;

        if (position_count % 16384 == 0) {
            const now = std.Io.Timestamp.now(io, .awake);
            const elapsed = @as(u64, @intCast(start_time.durationTo(now).nanoseconds));
            write("\rprogress: {}% (evals/s: {})", .{
                @as(u128, br.logicalPos() * 100) / stat.size,
                position_count * 1000_000_000 / @max(1, elapsed),
            });
        }

        var record = root.viriformat.GameRecord.from(game.board, allocator);
        defer record.deinit();
        record.setOutCome(game.outcome);

        var it = game.iter();
        ctx.initRoot(&it.board);
        var ply: u16 = 0;
        var scored = try it.next();
        while (scored) |sp| {
            const stm_eval = ctx.handle(ply).eval(&it.board);
            const eval = if (it.board.stm == .white) stm_eval else -stm_eval;

            try record.addMove(sp.move, eval);

            position_count += 1;

            const child = ply + 1;
            ctx.prepareChild(child, &it.board);
            scored = try it.nextHandle(ctx.handle(child));
            ply = child;
            if (ply + 1 >= root.SEARCH_MAX_PLY) {
                ctx.initRoot(&it.board);
                ply = 0;
            }
        }
        try record.serializeInto(&bw.interface);
    }
    try bw.interface.flush();

    write(
        \\
        \\done
        \\
    , .{});
}

fn handleSanitise(io: std.Io, allocator: std.mem.Allocator, args: anytype) !void {
    const parsed = try parseCommandArgs(
        args,
        struct {
            input: []const u8,
            @"print-errors": bool = false,
            @"check-only": bool = false,
            @"allow-overwrite": bool = false,
            output: ?[]const u8 = null,
            @"sp-stalemate-fix": bool = false,
        },
        .{
            .allow_implied = true,
            .usage_descriptions = &.{
                .{ .field = "output", .default_text = "<INPUT>_sanitised" },
            },
        },
        "sanitise",
        allocator,
    );
    const input = parsed.input;

    var input_file = try openInputFile(io, input);
    defer input_file.close(io);

    const mapped = try @import("MappedFile.zig").init(input_file, io);
    defer mapped.deinit(io);

    const missing_null_terminator =
        mapped.data.len < 4 or
        !std.mem.eql(u8, mapped.data[mapped.data.len - 4 ..], &[4]u8{ 0, 0, 0, 0 });
    if (parsed.@"print-errors" and missing_null_terminator) {
        std.debug.print("warning: file does not end with null terminator\n", .{});
    }

    var output_file: ?std.Io.File = null;
    defer if (output_file) |*file| file.close(io);

    var name_writer: ?std.Io.Writer.Allocating = null;
    defer if (name_writer) |*writer| writer.deinit();

    var output_buf: [4096]u8 = undefined;
    var output_writer: ?std.Io.File.Writer = null;
    if (!parsed.@"check-only") {
        name_writer = std.Io.Writer.Allocating.init(allocator);
        try name_writer.?.writer.print("{s}_sanitised", .{input});
        const output = parsed.output orelse name_writer.?.written();

        output_file = try createOutputFile(io, output, parsed.@"allow-overwrite");
        output_writer = output_file.?.writerStreaming(io, &output_buf);
    }

    const skipped = try @import("viriformat_sanitiser.zig").sanitiseBufferToFile(
        mapped.data,
        if (output_writer) |*writer| &writer.interface else null,
        allocator,
        .{
            .print_errors = parsed.@"print-errors",
            .sp_stalemate_fix = parsed.@"sp-stalemate-fix",
        },
    );
    if (parsed.@"check-only" and (skipped > 0 or missing_null_terminator)) {
        std.process.exit(1);
    }
}

fn runBench(io: std.Io, bench_depth: i32) !void {
    if (root.engine == void) return error.EngineMissing;
    defer root.engine.printDebugStats();
    var total_nodes: u64 = 0;
    const start_time = std.Io.Timestamp.now(io, .awake);
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
                .limits = root.Limits.initFixedDepth(io, bench_depth),
                .previous_positions = .{},
                .previous_moves = .{},
                .contempt = 0,
                .normalize = false,
                .minimal = false,
                .show_wdl = false,
            },
            .quiet = true,
        });
        root.engine.waitUntilDoneSearching();
        const node_count = root.engine.querySearchedNodes();
        total_nodes += node_count;
    }
    const now = std.Io.Timestamp.now(io, .awake);
    const elapsed = @max(1, @as(u64, @intCast(start_time.durationTo(now).nanoseconds)));
    write("{} nodes {} nps\n", .{ total_nodes, @as(u128, total_nodes) * std.time.ns_per_s / elapsed });
    if (root.evaluation.EVAL_MODE == .nnue) {
        if (root.nnue.arch.outputs.GATHER_L1_STATS) {
            const arch = root.nnue.arch;
            var file = try createOutputFile(io, "correlations.json", true);
            defer file.close(io);
            var buf: [4096]u8 = undefined;
            var writer = file.writerStreaming(io, &buf);
            const w = &writer.interface;
            const PAIRS = arch.L1_PAIR_COUNT;
            try w.writeByte('[');
            const counts = &arch.outputs.l1_stat_counts;
            for (0..PAIRS) |i| {
                if (i != 0) try w.writeByte(',');
                try w.writeByte('[');
                for (0..PAIRS) |j| {
                    if (j != 0) try w.writeByte(',');
                    try w.print("{d}", .{counts[i][j]});
                }
                try w.writeByte(']');
            }
            try w.writeByte(']');
            try w.flush();
            const active = arch.outputs.total_activated_pairs / arch.outputs.total_sparsity_samples;
            const nnz = arch.outputs.total_nnz / arch.outputs.total_sparsity_samples;
            write("average active pairs: {}/{} nnz: {d:.2}%\n", .{ active, PAIRS, @as(f64, @floatFromInt(nnz * 100)) / @as(f64, arch.L1_SIZE / 4) });
            write("wrote correlations.json\n", .{});
        }
    }
}
fn EnumArrayFormatter(comptime Enum: type, comptime Table: type) type {
    return struct {
        table: Table,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.writeAll("{\n");
            inline for (std.meta.fields(Enum)) |field| {
                const tag: Enum = @field(Enum, field.name);
                try writer.print("\t{s}: {f},\n", .{ field.name, formatValue(self.table.get(tag)) });
            }
            try writer.writeAll("}");
        }
    };
}

fn formatEnumArray(
    comptime Enum: type,
    table: anytype,
) EnumArrayFormatter(Enum, @TypeOf(table)) {
    return .{ .table = table };
}

fn WdlMatrixFormatter() type {
    return struct {
        table: std.enums.EnumArray(root.WDL, std.enums.EnumArray(root.WDL, u64)),

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.writeAll("{\n");
            inline for (std.meta.fields(root.WDL)) |game_field| {
                const outcome: root.WDL = @field(root.WDL, game_field.name);
                const row = self.table.get(outcome);
                try writer.print("\t{s}: [", .{game_field.name});
                inline for (std.meta.fields(root.WDL), 0..) |tb_field, i| {
                    if (i != 0) try writer.writeAll(", ");
                    try writer.print("{}", .{row.get(@field(root.WDL, tb_field.name))});
                }
                try writer.writeAll("],\n");
            }
            try writer.writeAll("}");
        }
    };
}

fn formatWdlMatrix(
    table: std.enums.EnumArray(root.WDL, std.enums.EnumArray(root.WDL, u64)),
) WdlMatrixFormatter() {
    return .{ .table = table };
}

fn PositionCountsFormatter(comptime mirrored: bool) type {
    return struct {
        table: [64]u64,

        const column_len = if (mirrored) 4 else 8;

        fn percentage(self: @This(), i: usize, j: usize) f64 {
            const row = self.table[8 * i ..][0..8];

            const count = if (mirrored) row[j] + row[7 - j] else row[j];
            const countf: f64 = @floatFromInt(count);

            const total: usize = @max(1, @reduce(.Add, @as(@Vector(64, u64), self.table)));
            const totalf: f64 = @floatFromInt(total);

            return countf * 100 / totalf;
        }

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            for (0..8) |i| {
                for (0..column_len) |j| {
                    try writer.print("{d:>5.2} ", .{self.percentage(i, j)});
                }
                try writer.writeAll("\n");
            }
        }
    };
}

fn formatPositionCounts(
    comptime mirrored: bool,
    table: [64]u64,
) PositionCountsFormatter(mirrored) {
    return .{ .table = table };
}

fn ArrayFormatter(comptime Array: type) type {
    return struct {
        table: Array,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.writeAll("[");
            for (self.table, 0..) |elem, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.print("{f}", .{formatValue(elem)});
            }
            try writer.writeAll("]");
        }
    };
}

fn formatArray(
    table: anytype,
) ArrayFormatter(@TypeOf(table)) {
    return .{ .table = table };
}

fn isEnumArray(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "Key") and
            @hasDecl(T, "Value") and
            @hasDecl(T, "get") and
            @hasField(T, "values"),
        else => false,
    };
}

fn ValueFormatter(comptime T: type) type {
    return struct {
        value: T,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            if (comptime isEnumArray(T)) {
                try writer.print("{f}", .{formatEnumArray(T.Key, self.value)});
                return;
            }

            switch (@typeInfo(T)) {
                .array => try writer.print("{f}", .{formatArray(self.value)}),
                else => try writer.print("{any}", .{self.value}),
            }
        }
    };
}

fn formatValue(
    value: anytype,
) ValueFormatter(@TypeOf(value)) {
    return .{ .value = value };
}

fn ArrayNewlineFormatter(comptime Array: type) type {
    return struct {
        table: Array,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.writeAll("[\n");
            for (0..self.table.len) |i| {
                try writer.print("\t{f},\n", .{formatValue(self.table[i])});
            }
            try writer.writeAll("]");
        }
    };
}

fn formatArrayNewline(
    table: anytype,
) ArrayNewlineFormatter(@TypeOf(table)) {
    return .{ .table = table };
}
