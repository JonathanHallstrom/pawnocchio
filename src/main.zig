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

const VERSION_STRING = "1.7.0";

pub fn main() !void {
    root.init();
    defer root.deinit();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next() orelse "pawnocchio";

    {
        const bench_depth_default: i32 = 10;
        const datagen_nodes_default: u64 = 7000;
        const datagen_threads_default: usize = std.Thread.getCpuCount() catch 1;
        const datagen_file_default: []const u8 = "outfile.vf";
        var do_bench = false;
        var bench_depth = bench_depth_default;
        var do_datagen = false;
        var datagen_nodes = datagen_nodes_default;
        var datagen_threads = datagen_threads_default;
        var datagen_file = datagen_file_default;
        while (args.next()) |arg| {
            if (std.mem.count(u8, arg, "help") != 0) {
                std.debug.print(
                    \\pawnocchio {s} - UCI Chess Engine
                    \\Usage: pawnocchio [COMMAND] [OPTIONS]
                    \\
                    \\COMMAND-LINE ARGUMENTS:
                    \\  (Processed first. If none are matched, engine enters UCI mode.)
                    \\
                    \\  bench [BENCH_DEPTH]
                    \\      Run benchmark for OB.
                    \\      Defaults: BENCH_DEPTH={d}
                    \\      Example: pawnocchio bench 12
                    \\
                    \\  datagen [threads=<COUNT>] [nodes=<NODE_COUNT>] [file=<FILEPATH>]
                    \\      Generate training data.
                    \\      Defaults: threads={d} (all CPU cores), nodes={d}, file="{s}"
                    \\      Example: pawnocchio datagen threads=4 nodes=100000
                    \\
                    \\  help
                    \\      Show this help message and exit.
                    \\
                    \\UCI MODE COMMANDS:
                    \\  (Used when engine is run without specific command-line arguments above.)
                    \\
                    \\  uci                 - Display engine info, list options. Responds with 'uciok'.
                    \\  spsa_inputs         - Display SPSA inputs.
                    \\  isready             - Check if ready. Responds with 'readyok'.
                    \\  ucinewgame          - Reset engine for a new game.
                    \\  setoption name <NAME> value <VALUE>
                    \\                      - Set option (e.g., Hash, Threads, UCI_Chess960,
                    \\                        Move Overhead, tunable parameters).
                    \\                        Example: setoption name Hash value 128
                    \\  position (fen <FEN> | startpos) [moves <MOVES...>]
                    \\                      - Set board position.
                    \\                        Example: position startpos moves e2e4 e7e5
                    \\  go [PARAMS...]      - Start search. Parameters include:
                    \\                          depth <PLY>, nodes <NODE_COUNT>, movetime <MS>,
                    \\                          wtime <MS>, btime <MS>, [winc <MS>], [binc <MS>],
                    \\                          mate <DEPTH>, perft <DEPTH> (current pos),
                    \\                          perft_file <FILEPATH> (from EPD).
                    \\  stop                - Stop current search.
                    \\  quit                - Exit engine.
                    \\  wait                - Wait for search to complete.
                    \\  d                   - Display Zobrist hash and FEN for current board.
                    \\  nneval              - Display NNUE evaluation for current position.
                    \\  bullet_evals        - Display NNUE evaluations for predefined FENs.
                    \\  hceval              - Display HCE evaluation for current position.
                    \\
                , .{ VERSION_STRING, bench_depth_default, datagen_threads_default, datagen_nodes_default, datagen_file_default });
                return;
            }
            if (std.ascii.eqlIgnoreCase(arg, "bench")) {
                do_bench = true;
            }
            if (std.fmt.parseInt(i32, arg, 10)) |depth| {
                bench_depth = depth;
            } else |_| {}
            if (std.ascii.eqlIgnoreCase(arg, "datagen")) {
                do_datagen = true;
            }
            if (std.mem.count(u8, arg, "threads=") > 0) {
                if (std.fmt.parseInt(usize, arg["threads=".len..], 10)) |thread_count| {
                    datagen_threads = thread_count;
                } else |_| {}
            }
            if (std.mem.count(u8, arg, "nodes=") > 0) {
                if (std.fmt.parseInt(u64, arg["nodes=".len..], 10)) |node_count| {
                    datagen_nodes = node_count;
                } else |_| {}
            }
            if (std.mem.count(u8, arg, "file=") > 0) {
                datagen_file = arg["file=".len..];
            }
        }
        if (do_datagen) {
            std.debug.print("datagenning with {} threads\n", .{datagen_threads});
            try root.engine.setThreadCount(datagen_threads);
            try root.engine.datagen(datagen_nodes, datagen_file);
        }
        if (do_bench) {
            var total_nodes: u64 = 0;
            var timer = std.time.Timer.start() catch std.debug.panic("Fatal: timer failed to start\n", .{});
            for ([_][]const u8{
                "1b6/1R1r4/8/1n6/7k/8/8/7K w - - 0 1",
                "1kr5/2bp3q/Q7/1K6/6q1/6B1/8/8 w - - 0 1",
                "1kr5/2bp3q/R7/1K6/6q1/6B1/8/8 w - - 96 200",
                "1n2kb1r/p1P4p/2qb4/5pP1/4n2Q/8/PP1PPP1P/RNB1KBNR w KQk - 0 1",
                "1r2r2k/1b4q1/pp5p/2pPp1p1/P3Pn2/1P1B1Q1P/2R3P1/4BR1K b - - 1 37",
                "1r4k1/4ppb1/2n1b1qp/pB4p1/1n1BP1P1/7P/2PNQPK1/3RN3 w - - 8 29",
                "1r5k/2pq2p1/3p3p/p1pP4/4QP2/PP1R3P/6PK/8 w - - 1 51",
                "1rb1rn1k/p3q1bp/2p3p1/2p1p3/2P1P2N/PP1RQNP1/1B3P2/4R1K1 b - - 4 23",
                "2q3r1/1r2pk2/pp3pp1/2pP3p/P1Pb1BbP/1P4Q1/R3NPP1/4R1K1 w - - 2 34",
                "2r2b2/5p2/5k2/p1r1pP2/P2pB3/1P3P2/K1P3R1/7R w - - 23 93",
                "2r2k2/8/4P1R1/1p6/8/P4K1N/7b/2B5 b - - 0 55",
                "2r4r/1p4k1/1Pnp4/3Qb1pq/8/4BpPp/5P2/2RR1BK1 w - - 0 42",
                "2rqr1k1/1p3p1p/p2p2p1/P1nPb3/2B1P3/5P2/1PQ2NPP/R1R4K w - - 3 25",
                "2rr2k1/1p4bp/p1q1p1p1/4Pp1n/2PB4/1PN3P1/P3Q2P/2RR2K1 w - f6 0 20",
                "3br1k1/p1pn3p/1p3n2/5pNq/2P1p3/1PN3PP/P2Q1PB1/4R1K1 w - - 0 23",
                "3q1k2/3P1rb1/p6r/1p2Rp2/1P5p/P1N2pP1/5B1P/3QRK2 w - - 1 42",
                "3qk1b1/1p4r1/1n4r1/2P1b2B/p3N2p/P2Q3P/8/1R3R1K w - - 2 39",
                "3qr2k/1p3rbp/2p3p1/p7/P2pBNn1/1P3n2/6P1/B1Q1RR1K b - - 1 30",
                "3r1rk1/1pp1pn1p/p1n1q1p1/3p4/Q3P3/2P5/PP1NBPPP/4RRK1 w - - 0 12",
                "3r3k/2r4p/1p1b3q/p4P2/P2Pp3/1B2P3/3BQ1RP/6K1 w - - 3 87",
                "3r4/ppq1ppkp/4bnp1/2pN4/2P1P3/1P4P1/PQ3PBP/R4K2 b - - 2 20",
                "4kq2/8/n7/8/8/3Q3b/8/3K4 w - - 0 1",
                "4q1bk/6b1/7p/p1p4p/PNPpP2P/KN4P1/3Q4/4R3 b - - 0 37",
                "4r1k1/1q1r3p/2bPNb2/1p1R3Q/pB3p2/n5P1/6B1/4R1K1 w - - 2 36",
                "4r1k1/4r1p1/8/p2R1P1K/5P1P/1QP3q1/1P6/3R4 b - - 0 1",
                "4r2k/1p3rbp/2p1N1p1/p3n3/P2NB1nq/1P6/4R1P1/B1Q2RK1 b - - 4 32",
                "4rrk1/2p1b1p1/p1p3q1/4p3/2P2n1p/1P1NR2P/PB3PP1/3R1QK1 b - - 2 24",
                "4rrk1/pp1n1pp1/q5p1/P1pP4/2n3P1/7P/1P3PB1/R1BQ1RK1 w - - 3 22",
                "5R2/2k3PK/8/5N2/7P/5q2/8/q7 w - - 0 69",
                "5k2/4q1p1/3P1pQb/1p1B4/pP5p/P1PR4/5PP1/1K6 b - - 0 38",
                "5rk1/1pp1pn1p/p3Brp1/8/1n6/5N2/PP3PPP/2R2RK1 w - - 2 20",
                "5rk1/1rP3pp/p4n2/3Pp3/1P2Pq2/2Q4P/P5P1/R3R1K1 b - - 0 32",
                "5rr1/4n2k/4q2P/P1P2n2/3B1p2/4pP2/2N1P3/1RR1K2Q w - - 1 49",
                "6Q1/8/1kp4P/2q1p3/2PpP3/2nP2P1/p7/5BK1 b - - 1 35",
                "6RR/4bP2/8/8/5r2/3K4/5p2/4k3 w - - 0 1",
                "6k1/1R3p2/6p1/2Bp3p/3P2q1/P7/1P2rQ1K/5R2 b - - 4 44",
                "6k1/5pp1/8/2bKP2P/2P5/p4PNb/B7/8 b - - 1 44",
                "6k1/6p1/8/6KQ/1r6/q2b4/8/8 w - - 0 32",
                "6r1/5k2/p1b1r2p/1pB1p1p1/1Pp3PP/2P1R1K1/2P2P2/3R4 w - - 1 36",
                "7r/2p3k1/1p1p1qp1/1P1Bp3/p1P2r1P/P7/4R3/Q4RK1 w - - 0 36",
                "8/1R6/1p1K1kp1/p6p/P1p2P1P/6P1/1Pn5/8 w - - 0 67",
                "8/1p2pk1p/p1p1r1p1/3n4/8/5R2/PP3PPP/4R1K1 b - - 3 27",
                "8/4pk2/1p1r2p1/p1p4p/Pn5P/3R4/1P3PP1/4RK2 w - - 1 33",
                "8/5R2/1n2RK2/8/8/7k/4r3/8 b - - 0 1",
                "8/5k2/1p4p1/p1pK3p/P2n1P1P/6P1/1P6/4R3 b - - 14 63",
                "8/5k2/1pnrp1p1/p1p4p/P6P/4R1PK/1P3P2/4R3 b - - 1 38",
                "8/6pk/2b1Rp2/3r4/1R1B2PP/P5K1/8/2r5 b - - 16 42",
                "8/8/1p1k2p1/p1prp2p/P2n3P/6P1/1P1R1PK1/4R3 b - - 5 49",
                "8/8/1p1kp1p1/p1pr1n1p/P6P/1R4P1/1P3PK1/1R6 b - - 15 45",
                "8/8/1p2k1p1/3p3p/1p1P1P1P/1P2PK2/8/8 w - - 3 54",
                "8/8/1p4p1/p1p2k1p/P2n1P1P/4K1P1/1P6/6R1 b - - 6 59",
                "8/8/1p4p1/p1p2k1p/P2npP1P/4K1P1/1P6/3R4 w - - 6 54",
                "8/8/4k3/3n1n2/5P2/8/3K4/8 b - - 0 12",
                "8/bQr5/8/8/8/7k/8/7K w - - 0 1",
                "8/bRn5/8/7b/8/7k/8/7K w - - 0 1",
                "8/bRp5/8/8/8/7k/8/7K w - - 0 1",
                "8/n3p3/8/2B5/1n6/7k/P7/7K w - - 0 1",
                "8/n3p3/8/2B5/2b5/7k/P7/7K w - - 0 1",
                "8/nQr5/8/8/8/7k/8/7K w - - 0 1",
                "8/nRp5/8/8/8/7k/8/7K w - - 0 1",
                "8/p2B4/PkP5/4p1pK/4Pb1p/5P2/8/8 w - - 29 68",
                "8/q5rk/8/8/8/8/Q5RK/7N w - - 0 1",
                "R4r2/4q1k1/2p1bb1p/2n2B1Q/1N2pP2/1r2P3/1P5P/2B2KNR w - - 3 31",
                "q5k1/5ppp/1r3bn1/1B6/P1N2P2/BQ2P1P1/5K1P/8 b - - 2 34",
                "r1b2k1r/5n2/p4q2/1ppn1Pp1/3pp1p1/NP2P3/P1PPBK2/1RQN2R1 w - - 0 22",
                "r1b2rk1/p1q1ppbp/6p1/2Q5/8/4BP2/PPP3PP/2KR1B1R b - - 2 14",
                "r1bq1rk1/pp2b1pp/n1pp1n2/3P1p2/2P1p3/2N1P2N/PP2BPPP/R1BQ1RK1 b - - 2 10",
                "r1bq2k1/p4r1p/1pp2pp1/3p4/1P1B3Q/P2B1N2/2P3PP/4R1K1 b - - 2 19",
                "r1bqk2r/pppp1ppp/5n2/4b3/4P3/P1N5/1PP2PPP/R1BQKB1R w KQkq - 0 5",
                "r1bqr1k1/pp1p1ppp/2p5/8/3N1Q2/P2BB3/1PP2PPP/R3K2n b Q - 1 12",
                "r2qr1k1/pb1nbppp/1pn1p3/2ppP3/3P4/2PB1NN1/PP3PPP/R1BQR1K1 w - - 4 12",
                "r3k2r/2pb1ppp/2pp1q2/p7/1nP1B3/1P2P3/P2N1PPP/R2QK2R w KQkq - 0 14",
                "r3k2r/2pb1ppp/2pp1q2/p7/1nP1B3/1P2P3/P2N1PPP/R2QK2R w KQkq - 0 14",
                "r3k2r/ppp1pp1p/2nqb1pn/3p4/4P3/2PP4/PP1NBPPP/R2QK1NR w KQkq - 1 5",
                "r3k2r/ppp2ppp/n7/1N1p4/Bb6/8/PPPP1PPP/RNBQ1RK1 w - - 2 1",
                "r3k2r/ppp2ppp/n7/1N1p4/Bb6/8/PPPP1PPP/RNBQ1RK1 w kq - 2 1",
                "r3kbbr/pp1n1p1P/3ppnp1/q5N1/1P1pP3/P1N1B3/2P1QP2/R3KB1R b KQkq - 0 17",
                "r3kbbr/pp1n1p1P/3ppnp1/q5N1/1P1pP3/P1N1B3/2P1QP2/R3KB1R b KQkq - 0 17",
                "r3qbrk/6p1/2b2pPp/p3pP1Q/PpPpP2P/3P1B2/2PB3K/R5R1 w - - 16 42",
                "r4qk1/6r1/1p4p1/2ppBbN1/1p5Q/P7/2P3PP/5RK1 w - - 2 25",
                "r6k/pbR5/1p2qn1p/P2pPr2/4n2Q/1P2RN1P/5PBK/8 w - - 2 31",
                "r7/6k1/1p6/2pp1p2/7Q/8/p1P2K1P/8 w - - 0 32",
                "rn2k3/4r1b1/pp1p1n2/1P1q1p1p/3P4/P3P1RP/1BQN1PR1/1K6 w - - 6 28",
                "rnb1kb1r/pppp1ppp/5n2/8/4N3/8/PPPP1PPP/RNB1R1K1 w kq - 2 5",
                "rnbqk1nr/ppp2ppp/8/4P3/1BP5/8/PP2KpPP/RN1Q1BNR b kq - 1 7",
                "rnbqk2r/ppp2ppp/3p4/8/1b2B3/3n4/PPPP1PPP/RNBQR1K1 w kq - 2 5",
                "rnbqk2r/ppp2ppp/3p4/8/1b2Bn2/8/PPPPQPPP/RNB1K2R w KQkq - 2 5",
                "rnbqk2r/pppp1ppp/5n2/8/Bb2N3/8/PPPPQPPP/RNB1K2R w KQkq - 2 1",
                "rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2",
                "rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2",
            }) |fen| {
                root.engine.reset();
                root.engine.startSearch(.{
                    .search_params = .{
                        .board = try Board.parseFen(fen, false),
                        .limits = root.Limits.initFixedDepth(bench_depth),
                        .previous_hashes = &.{},
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
            return;
        }
    }

    std.debug.print("{s}\n", .{banner});
    std.debug.print("pawnocchio {s}\n", .{VERSION_STRING});

    const line_buf = try allocator.alloc(u8, 1 << 20);
    defer allocator.free(line_buf);
    const reader = std.io.getStdIn().reader();
    var previous_hashes = std.ArrayList(u64).init(allocator);
    defer previous_hashes.deinit();

    var board = Board.startpos();
    try previous_hashes.append(board.hash);
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
            write("id name pawnocchio {s}\n", .{VERSION_STRING});
            write("id author Jonathan Hallström\n", .{});
            write("option name Hash type spin default 16 min 1 max 1048576\n", .{});
            write("option name Threads type spin default 1 min 1 max 65535\n", .{});
            write("option name Move Overhead type spin default 10 min 1 max 10000\n", .{});
            write("option name UCI_Chess960 type check default false\n", .{});
            if (root.tuning.do_tuning) {
                for (root.tuning.tunables) |tunable| {
                    write(
                        "option name {s} type spin default {} min {} max {}\n",
                        .{ tunable.name, tunable.default, tunable.getMin(), tunable.getMax() },
                    );
                }
            }
            write("uciok\n", .{});
        } else if (std.ascii.eqlIgnoreCase(command, "spsa_inputs")) {
            for (root.tuning.tunables) |tunable| {
                write(
                    "{s}, int, {d:.1}, {d:.1}, {d:.1}, {d}, 0.008\n",
                    .{
                        tunable.name,
                        @as(f64, @floatFromInt(tunable.default)),
                        @as(f64, @floatFromInt(tunable.getMin())),
                        @as(f64, @floatFromInt(tunable.getMax())),
                        tunable.getCend(),
                    },
                );
            }
        } else if (std.ascii.eqlIgnoreCase(command, "ucinewgame")) {
            root.engine.reset();
            board = Board.startpos();
        } else if (std.ascii.eqlIgnoreCase(command, "setoption")) {
            if (!std.ascii.eqlIgnoreCase("name", parts.next() orelse "")) continue;
            var option_name = parts.next() orelse "";
            var value_part = parts.next() orelse "";
            if (!std.ascii.eqlIgnoreCase("value", value_part)) {
                // yes this is cursed
                while (option_name.ptr[option_name.len..] != value_part.ptr[value_part.len..])
                    option_name.len += 1;
                value_part = parts.next() orelse "";
            }
            const value = parts.next() orelse "";

            if (std.ascii.eqlIgnoreCase("Hash", option_name)) {
                const size = std.fmt.parseInt(u16, value, 10) catch {
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

            if (std.ascii.eqlIgnoreCase("UCI_Chess960", option_name)) {
                if (std.ascii.eqlIgnoreCase("true", value)) {
                    board.frc = true;
                }
                if (std.ascii.eqlIgnoreCase("false", value)) {
                    board.frc = false;
                }
            }

            if (std.ascii.eqlIgnoreCase("Move Overhead", option_name)) {
                overhead = std.time.ns_per_ms * (std.fmt.parseInt(u64, value, 10) catch {
                    writeLog("invalid overhead: '{s}'\n", .{value});
                    continue;
                });
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
        } else if (std.ascii.eqlIgnoreCase(command, "isready")) {
            root.engine.waitUntilDoneSearching();
            write("readyok\n", .{});
        } else if (std.ascii.eqlIgnoreCase(command, "d")) {
            // for (board.toString()) |row| {
            //     write("{s}\n", .{row});
            // }
            write("zobrist: {}\n", .{board.hash});
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
            var move_time_opt: ?u64 = null;

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
            }
            const my_time = if (board.stm == .white) white_time else black_time;
            const my_increment = if (board.stm == .white) white_increment else black_increment;

            var limits = root.Limits.initStandard(
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

            if (max_nodes_opt) |max_nodes| {
                if (!std.debug.runtime_safety) {
                    write("info string Not built with runtime safety, node bound will not be exact\n", .{});
                }
                limits.soft_nodes = max_nodes;
                limits.hard_nodes = max_nodes;
            }

            root.engine.startSearch(.{
                .search_params = .{
                    .board = board,
                    .limits = limits,
                    .previous_hashes = previous_hashes.items,
                },
            });
        } else if (std.ascii.eqlIgnoreCase(command, "stop")) {
            root.engine.stopSearch();
        } else if (std.ascii.eqlIgnoreCase(command, "quit")) {
            return;
        } else if (std.ascii.eqlIgnoreCase(command, "wait")) {
            root.engine.waitUntilDoneSearching();
        } else if (std.ascii.eqlIgnoreCase(command, "nneval")) {
            write("{}\n", .{@import("nnue.zig").nnEval(&board)});
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
                write("EVAL: {}\n", .{@import("nnue.zig").nnEval(&try Board.parseFen(fen, false))});
            }
        } else if (std.ascii.eqlIgnoreCase(command, "hceval")) {
            const hce = @import("hce.zig");
            var state = hce.State.init(&board);

            switch (board.stm) {
                inline else => |stm| write("{}\n", .{hce.evaluate(stm, &board, &board, &state)}),
            }
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

                board = Board.parseFen(fen_to_parse, true) catch |e| {
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

            previous_hashes.clearRetainingCapacity();
            try previous_hashes.append(board.hash);
            var move_iter = std.mem.tokenizeAny(u8, pos_iter.rest(), &std.ascii.whitespace);
            while (move_iter.next()) |played_move| {
                if (std.ascii.eqlIgnoreCase(played_move, "moves")) continue;
                _ = board.makeMoveFromStr(played_move) catch {
                    writeLog("invalid move: '{s}'\n", .{played_move});
                    continue;
                };
                if (board.halfmove == 0) {
                    previous_hashes.clearRetainingCapacity();
                }
                try previous_hashes.append(board.hash);
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
