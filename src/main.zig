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

const VERSION_STRING = "1.8.2";

pub fn main() !void {
    root.init();
    defer root.deinit();
    defer {
        root.engine.stopSearch();
        root.engine.waitUntilDoneSearching();
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next() orelse "pawnocchio";

    {
        const bench_depth_default: i32 = 11;
        const datagen_nodes_default: u64 = 7000;
        const datagen_threads_default: usize = std.Thread.getCpuCount() catch 1;
        var do_bench = false;
        var bench_depth = bench_depth_default;
        var do_datagen = false;
        var datagen_nodes = datagen_nodes_default;
        var datagen_threads = datagen_threads_default;
        var datagen_positions: ?u64 = null;
        var do_genfens = false;
        var genfens_seed: u64 = 0;
        var genfens_count: usize = 0;
        var genfens_book: ?[]const u8 = null;
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
                    \\  datagen [threads=<COUNT>] [nodes=<NODE_COUNT>] [positions=<POS_COUNT>]
                    \\      Generate training data.
                    \\      Defaults: threads={d} (all CPU cores), nodes={d}
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
                , .{ VERSION_STRING, bench_depth_default, datagen_threads_default, datagen_nodes_default });
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
            if (std.mem.count(u8, arg, "positions=") > 0) {
                if (std.fmt.parseInt(u64, arg["positions=".len..], 10)) |positions| {
                    datagen_positions = positions;
                } else |_| {}
            }
            if (std.mem.count(u8, arg, "nodes=") > 0) {
                if (std.fmt.parseInt(u64, arg["nodes=".len..], 10)) |node_count| {
                    datagen_nodes = node_count;
                } else |_| {}
            }
            if (std.mem.count(u8, arg, "genfens") > 0) {
                var genfens_args = std.mem.tokenizeScalar(u8, arg, ' ');
                do_genfens = true;
                _ = genfens_args.next(); // discard "genfens"
                genfens_count = std.fmt.parseInt(usize, genfens_args.next() orelse "", 10) catch |e| {
                    writeLog("invalid fen count, error: '{}'", .{e});
                    return e;
                };
                _ = genfens_args.next(); // discard "seed"
                genfens_seed = std.fmt.parseInt(u64, genfens_args.next() orelse "", 10) catch |e| {
                    writeLog("invalid seed, error: '{}'", .{e});
                    return e;
                };
                _ = genfens_args.next(); // discard "book"

                if (genfens_args.next()) |path| {
                    if (!std.ascii.eqlIgnoreCase(path, "none")) {
                        genfens_book = path;
                    }
                }
                try root.engine.genfens(genfens_book, genfens_count, genfens_seed, std.io.getStdOut().writer().any(), allocator);
                return;
            }
            if (std.mem.count(u8, arg, "pgntovf") > 0) {
                var input = args.next() orelse "";
                var skip_broken_games = false;
                if (std.ascii.eqlIgnoreCase(input, "--skip-broken-games")) {
                    skip_broken_games = true;
                    input = args.next() orelse "";
                }
                const extension_len = std.mem.indexOf(u8, input, ".pgn") orelse std.mem.lastIndexOf(u8, input, ".") orelse input.len;
                const output_base = args.next() orelse input[0..extension_len];

                const output = try std.fmt.allocPrint(allocator, "{s}.vf", .{output_base});
                defer allocator.free(output);

                var input_file = std.fs.cwd().openFile(input, .{}) catch try std.fs.openFileAbsolute(input, .{});
                defer input_file.close();

                const stat = try input_file.stat();
                const input_bytes = if (@import("builtin").target.os.tag == .windows)
                    try input_file.readToEndAlloc(allocator, std.math.maxInt(usize))
                else
                    try std.posix.mmap(null, stat.size, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, input_file.handle, 0);

                defer if (@import("builtin").target.os.tag == .windows)
                    allocator.free(input_bytes)
                else
                    std.posix.munmap(input_bytes);

                var output_file = try std.fs.cwd().createFile(output, .{});
                defer output_file.close();

                try @import("pgn_to_vf.zig").convert(input_bytes, skip_broken_games, output_file.writer(), std.heap.smp_allocator);

                return;
            }
        }
        if (do_datagen) {
            std.debug.print("datagenning with {} threads\n", .{datagen_threads});
            try root.engine.setThreadCount(datagen_threads);
            if (datagen_positions) |positions| {
                try root.engine.datagen(datagen_nodes, positions);
            } else {
                std.debug.panic("Need to specify positions with `positions=N` to specify how many positions to generage.", .{});
            }
        }
        if (do_bench) {
            var total_nodes: u64 = 0;
            var timer = std.time.Timer.start() catch std.debug.panic("Fatal: timer failed to start\n", .{});
            for ([_][]const u8{
                "1b6/1R1r4/8/1n6/7k/8/8/7K w - - 0 1",
                "1kr5/2bp3q/Q7/1K6/6q1/6B1/8/8 w - - 0 1",
                "1kr5/2bp3q/R7/1K6/6q1/6B1/8/8 w - - 96 200",
                "1n2kb1r/p1P4p/2qb4/5pP1/4n2Q/8/PP1PPP1P/RNB1KBNR w KQk - 0 1",
                "1r1q2k1/3r2p1/p4p2/5p2/2p4Q/P3B3/1bP3PP/3R1RK1 w - - 0 19",
                "1r2qrk1/2p1bpp1/3p4/1pP2b1p/1P2N1nP/4P1P1/1BQ2PB1/3R2KR w - - 3 22",
                "1r2r2k/1b4q1/pp5p/2pPp1p1/P3Pn2/1P1B1Q1P/2R3P1/4BR1K b - - 1 37",
                "1r3r1k/p1pbb1pp/1p1p1q2/4pP2/2P1P3/1P1P2P1/PB5P/R2Q1RK1 b - - 0 11",
                "1r4k1/1q3bp1/6r1/pp1pPpB1/2p1nP2/P1P1QB1P/1P4RK/R7 w - - 1 38",
                "1r4k1/4ppb1/2n1b1qp/pB4p1/1n1BP1P1/7P/2PNQPK1/3RN3 w - - 8 29",
                "1r5k/2pq2p1/3p3p/p1pP4/4QP2/PP1R3P/6PK/8 w - - 1 51",
                "1r6/p1q2kpp/2p2b2/5p2/3p1P2/BP1P2P1/P1P2Q1P/4R1K1 b - - 10 20",
                "1rb1rn1k/p3q1bp/2p3p1/2p1p3/2P1P2N/PP1RQNP1/1B3P2/4R1K1 b - - 4 23",
                "2k4r/1pp1b2p/p1n2p2/2P3p1/8/1P2BNPP/1P2PPK1/2R5 w - - 1 13",
                "2k5/2P3p1/3r1p2/7p/2RB2rP/3K2P1/5P2/8 w - - 1 48",
                "2kn3r/ppp1b2p/4qp2/2P3p1/8/1Q3NPP/PP2PPK1/R1B5 w - - 0 10",
                "2kr1b1r/pp1qpp2/1np4p/3n1Pp1/3PN2B/2N2Q2/1PP3PP/2KRR3 w - g6 0 12",
                "2q1r1k1/1p2npbp/p5p1/8/8/2P2N1P/P2B1PP1/2QR2K1 w - - 2 17",
                "2q3r1/1r2pk2/pp3pp1/2pP3p/P1Pb1BbP/1P4Q1/R3NPP1/4R1K1 w - - 2 34",
                "2r1kb1r/pp2pp1p/2nN1n2/3p2B1/3P2b1/4PN2/q3BPPP/1R1QK2R b Kk - 1 4",
                "2r2b2/5p2/5k2/p1r1pP2/P2pB3/1P3P2/K1P3R1/7R w - - 23 93",
                "2r2k2/8/4P1R1/1p6/8/P4K1N/7b/2B5 b - - 0 55",
                "2r4r/1p4k1/1Pnp4/3Qb1pq/8/4BpPp/5P2/2RR1BK1 w - - 0 42",
                "2r5/1pqn1pbk/p2p1np1/P2Pp1Bp/NPr1P3/6PP/3Q1PB1/1RR3K1 b - - 6 12",
                "2rqr1k1/1p3p1p/p2p2p1/P1nPb3/2B1P3/5P2/1PQ2NPP/R1R4K w - - 3 25",
                "2rr2k1/1p4bp/p1q1p1p1/4Pp1n/2PB4/1PN3P1/P3Q2P/2RR2K1 w - f6 0 20",
                "3br1k1/p1pn3p/1p3n2/5pNq/2P1p3/1PN3PP/P2Q1PB1/4R1K1 w - - 0 23",
                "3q1k2/3P1rb1/p6r/1p2Rp2/1P5p/P1N2pP1/5B1P/3QRK2 w - - 1 42",
                "3qk1b1/1p4r1/1n4r1/2P1b2B/p3N2p/P2Q3P/8/1R3R1K w - - 2 39",
                "3qr2k/1p3rbp/2p3p1/p7/P2pBNn1/1P3n2/6P1/B1Q1RR1K b - - 1 30",
                "3r1bk1/p4pp1/Pq4bp/1B2p3/1P2N3/1N5P/5PP1/1QB3K1 w - - 1 29",
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
                "5r1k/1p3p1p/2p2p2/1q2bP1Q/3p1P2/1PP1R1P1/6KP/2N5 w - - 0 25",
                "5rk1/1p2r1p1/p4np1/P2p4/2pNbP2/2P1PB2/6PP/3RR1K1 w - - 2 23",
                "5rk1/1pp1pn1p/p3Brp1/8/1n6/5N2/PP3PPP/2R2RK1 w - - 2 20",
                "5rk1/1rP3pp/p4n2/3Pp3/1P2Pq2/2Q4P/P5P1/R3R1K1 b - - 0 32",
                "5rr1/4n2k/4q2P/P1P2n2/3B1p2/4pP2/2N1P3/1RR1K2Q w - - 1 49",
                "6Q1/8/1kp4P/2q1p3/2PpP3/2nP2P1/p7/5BK1 b - - 1 35",
                "6RR/4bP2/8/8/5r2/3K4/5p2/4k3 w - - 0 1",
                "6k1/1R3p2/6p1/2Bp3p/3P2q1/P7/1P2rQ1K/5R2 b - - 4 44",
                "6k1/5pbp/R5p1/Pp6/8/1r2P2P/6B1/6K1 w - - 0 31",
                "6k1/5pp1/8/2bKP2P/2P5/p4PNb/B7/8 b - - 1 44",
                "6k1/6p1/8/6KQ/1r6/q2b4/8/8 w - - 0 32",
                "6k1/8/1p2R3/1Pb1p1B1/8/1r5P/6K1/8 w - - 4 45",
                "6k1/8/pB2p1p1/3p3p/7q/PB6/Q7/2R3K1 w - - 0 37",
                "6r1/5k2/p1b1r2p/1pB1p1p1/1Pp3PP/2P1R1K1/2P2P2/3R4 w - - 1 36",
                "7r/2p3k1/1p1p1qp1/1P1Bp3/p1P2r1P/P7/4R3/Q4RK1 w - - 0 36",
                "7r/p1r1p2p/2k5/1p2n1N1/1Pp5/2R1P1P1/P4P1P/3R1K2 w - - 2 31",
                "8/1R3pk1/3rpb1p/1P1p1p2/1P1P4/r4N1P/2R3PK/8 b - - 2 27",
                "8/1R6/1p1K1kp1/p6p/P1p2P1P/6P1/1Pn5/8 w - - 0 67",
                "8/1k4p1/p4p1p/n1B5/2P3P1/7P/4KP2/8 w - - 0 41",
                "8/1p2pk1p/p1p1r1p1/3n4/8/5R2/PP3PPP/4R1K1 b - - 3 27",
                "8/1p6/3p1k2/Pp1Pp1bn/1P2P2p/3K3P/4NB2/8 w - - 9 38",
                "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
                "8/2q2p1k/1p2p1p1/4P1P1/p7/P4Q2/1p3PK1/1R6 b - - 3 38",
                "8/3k4/3b3p/R1p1p2P/p1Pr4/P2P1r2/2K1R3/4B3 b - - 4 75",
                "8/4pk2/1p1r2p1/p1p4p/Pn5P/3R4/1P3PP1/4RK2 w - - 1 33",
                "8/5R2/1n2RK2/8/8/7k/4r3/8 b - - 0 1",
                "8/5k2/1p4p1/p1pK3p/P2n1P1P/6P1/1P6/4R3 b - - 14 63",
                "8/5k2/1pnrp1p1/p1p4p/P6P/4R1PK/1P3P2/4R3 b - - 1 38",
                "8/5k2/4p3/2Np4/3P4/3K1P2/7b/8 w - - 69 92",
                "8/5pk1/4pr2/8/3Q1P2/7K/8/8 b - - 76 136",
                "8/6pk/2b1Rp2/3r4/1R1B2PP/P5K1/8/2r5 b - - 16 42",
                "8/8/1k1NK3/r7/2R2P1P/3n2P1/8/8 b - - 0 59",
                "8/8/1k1r2p1/p1p2nPp/P3RN1P/8/4KP2/8 b - - 13 55",
                "8/8/1p1k2p1/p1prp2p/P2n3P/6P1/1P1R1PK1/4R3 b - - 5 49",
                "8/8/1p1kp1p1/p1pr1n1p/P6P/1R4P1/1P3PK1/1R6 b - - 15 45",
                "8/8/1p2k1p1/3p3p/1p1P1P1P/1P2PK2/8/8 w - - 3 54",
                "8/8/1p2k2P/1P6/P3B3/4B1K1/1b3P2/4n3 w - - 7 77",
                "8/8/1p4p1/p1p2k1p/P2n1P1P/4K1P1/1P6/6R1 b - - 6 59",
                "8/8/1p4p1/p1p2k1p/P2npP1P/4K1P1/1P6/3R4 w - - 6 54",
                "8/8/4k3/3n1n2/5P2/8/3K4/8 b - - 0 12",
                "8/8/5pk1/5Nn1/R3r1P1/8/6K1/8 w - - 4 65",
                "8/R3bpk1/4p3/3pPn1P/3P2K1/1rP4P/4N3/2B5 b - - 3 50",
                "8/bQr5/8/8/8/7k/8/7K w - - 0 1",
                "8/bRn5/8/7b/8/7k/8/7K w - - 0 1",
                "8/bRp5/8/8/8/7k/8/7K w - - 0 1",
                "8/n3p3/8/2B5/1n6/7k/P7/7K w - - 0 1",
                "8/n3p3/8/2B5/2b5/7k/P7/7K w - - 0 1",
                "8/nQr5/8/8/8/7k/8/7K w - - 0 1",
                "8/nRp5/8/8/8/7k/8/7K w - - 0 1",
                "8/p2B4/PkP5/4p1pK/4Pb1p/5P2/8/8 w - - 29 68",
                "8/p2r2pk/1p6/3p2pP/7N/P1R5/2p1r3/5R1K w - - 0 50",
                "8/q5rk/8/8/8/8/Q5RK/7N w - - 0 1",
                "R4r2/4q1k1/2p1bb1p/2n2B1Q/1N2pP2/1r2P3/1P5P/2B2KNR w - - 3 31",
                "q5k1/5ppp/1r3bn1/1B6/P1N2P2/BQ2P1P1/5K1P/8 b - - 2 34",
                "r1b2k1r/5n2/p4q2/1ppn1Pp1/3pp1p1/NP2P3/P1PPBK2/1RQN2R1 w - - 0 22",
                "r1b2rk1/p1q1ppbp/6p1/2Q5/8/4BP2/PPP3PP/2KR1B1R b - - 2 14",
                "r1bq1rk1/pp2b1pp/n1pp1n2/3P1p2/2P1p3/2N1P2N/PP2BPPP/R1BQ1RK1 b - - 2 10",
                "r1bq2k1/p4r1p/1pp2pp1/3p4/1P1B3Q/P2B1N2/2P3PP/4R1K1 b - - 2 19",
                "r1bqk2r/pppp1ppp/5n2/4b3/4P3/P1N5/1PP2PPP/R1BQKB1R w KQkq - 0 5",
                "r1bqr1k1/pp1p1ppp/2p5/8/3N1Q2/P2BB3/1PP2PPP/R3K2n b Q - 1 12",
                "r1r3k1/1bqnbp1N/ppn1p1p1/4P1B1/8/2N5/PPB1QPPP/R3R1K1 w - - 3 9",
                "r2q1rk1/1bpnbppp/1p2p3/8/p2PN3/2P2N2/PP1Q1PPP/1B1RR1K1 b - - 1 14",
                "r2qk2r/1bpnppbp/3p2p1/3P4/PN2P3/4BP2/1P1QN1PP/R3K2R b KQkq - 0 6",
                "r2qr1k1/pb1nbppp/1pn1p3/2ppP3/3P4/2PB1NN1/PP3PPP/R1BQR1K1 w - - 4 12",
                "r3k2r/2pb1ppp/2pp1q2/p7/1nP1B3/1P2P3/P2N1PPP/R2QK2R w KQkq - 0 14",
                "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
                "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
                "r3k2r/ppp1pp1p/2nqb1pn/3p4/4P3/2PP4/PP1NBPPP/R2QK1NR w KQkq - 1 5",
                "r3k2r/ppp2ppp/n7/1N1p4/Bb6/8/PPPP1PPP/RNBQ1RK1 w - - 2 1",
                "r3k2r/ppp2ppp/n7/1N1p4/Bb6/8/PPPP1PPP/RNBQ1RK1 w kq - 2 1",
                "r3kbbr/pp1n1p1P/3ppnp1/q5N1/1P1pP3/P1N1B3/2P1QP2/R3KB1R b KQkq - 0 17",
                "r3qbrk/6p1/2b2pPp/p3pP1Q/PpPpP2P/3P1B2/2PB3K/R5R1 w - - 16 42",
                "r4qk1/6r1/1p4p1/2ppBbN1/1p5Q/P7/2P3PP/5RK1 w - - 2 25",
                "r4rk1/1bq1ppbp/6p1/2p5/P3P3/4BP2/1P1QN1PP/R2R2K1 w - - 2 11",
                "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
                "r4rk1/1pp1qppp/pnnbp3/7b/3PP3/1PN1BNPP/P4PB1/R2Q1RK1 w - - 2 13",
                "r4rk1/2qbbppp/p1n1p3/8/2p2P2/P1N1BNQ1/1PP3PP/3R1RK1 b - - 5 11",
                "r6k/pbR5/1p2qn1p/P2pPr2/4n2Q/1P2RN1P/5PBK/8 w - - 2 31",
                "r7/1ppq1pkp/1b1p1p2/p4P2/1P2R3/P2Q1NP1/2P2P1P/6K1 w - - 0 13",
                "r7/6k1/1p6/2pp1p2/7Q/8/p1P2K1P/8 w - - 0 32",
                "rn1qr1k1/1b3n1p/p5p1/1p3p2/2p1P3/2P2N1P/PPBNQPP1/R4RK1 w - - 2 9",
                "rn2k3/4r1b1/pp1p1n2/1P1q1p1p/3P4/P3P1RP/1BQN1PR1/1K6 w - - 6 28",
                "rnb1kb1r/pppp1ppp/5n2/8/4N3/8/PPPP1PPP/RNB1R1K1 w kq - 2 5",
                "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
                "rnbqk1nr/ppp2ppp/8/4P3/1BP5/8/PP2KpPP/RN1Q1BNR b kq - 1 7",
                "rnbqk2r/ppp2ppp/3p4/8/1b2B3/3n4/PPPP1PPP/RNBQR1K1 w kq - 2 5",
                "rnbqk2r/ppp2ppp/3p4/8/1b2Bn2/8/PPPPQPPP/RNB1K2R w KQkq - 2 5",
                "rnbqk2r/pppp1ppp/5n2/8/Bb2N3/8/PPPPQPPP/RNB1K2R w KQkq - 2 1",
                "rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2",
            }) |fen| {
                root.engine.reset();
                root.engine.startSearch(.{
                    .search_params = .{
                        .board = try Board.parseFen(fen, false),
                        .limits = root.Limits.initFixedDepth(bench_depth),
                        .previous_hashes = .{},
                        .normalize = false,
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

    if (@import("builtin").os.tag == .windows) {
        const windows = @cImport(@cInclude("windows.h"));
        _ = windows.SetConsoleCP(windows.CP_UTF8);
        _ = windows.SetConsoleOutputCP(windows.CP_UTF8);
    }
    write("{s}\n", .{banner});
    write("pawnocchio {s}\n", .{VERSION_STRING});

    const line_buf = try allocator.alloc(u8, 1 << 20);
    defer allocator.free(line_buf);
    const reader = std.io.getStdIn().reader();
    var previous_hashes = std.BoundedArray(u64, 200){};

    var board = Board.startpos();
    try previous_hashes.append(board.hash);
    var overhead: u64 = std.time.ns_per_ms * 10;
    var syzygy_depth: u8 = 1;
    var min_depth: i32 = 0;
    var normalize: bool = true;
    var softnodes: bool = false;
    var weird_tcs: bool = false;
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
            write("option name MinDepth type spin default 0 min 0 max 255\n", .{});
            write("option name SyzygyPath type string default <empty>\n", .{});
            write("option name SyzygyProbeDepth type spin default 1 min 1 max 255\n", .{});
            write("option name NormalizeEval type check default true\n", .{});
            write("option name SoftNodes type check default false\n", .{});
            write("option name EnableWeirdTCs type check default false\n", .{});
            if (root.tuning.do_tuning) {
                for (root.tuning.tunables) |tunable| {
                    write(
                        "option name {s} type spin default {} min {} max {}\n",
                        .{ tunable.name, tunable.default, tunable.getMin(), tunable.getMax() },
                    );
                }
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
            previous_hashes = .{};
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

            if (std.ascii.eqlIgnoreCase("Move Overhead", option_name)) {
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
            // for (board.toString()) |row| {
            //     write("{s}\n", .{row});
            // }
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
                if (!std.debug.runtime_safety) {
                    write("info string Not built with runtime safety, node bound will not be exact\n", .{});
                }
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

            root.engine.startSearch(.{
                .search_params = .{
                    .board = board,
                    .limits = limits,
                    .previous_hashes = previous_hashes,
                    .syzygy_depth = syzygy_depth,
                    .normalize = normalize,
                },
            });
        } else if (std.ascii.eqlIgnoreCase(command, "stop")) {
            root.engine.stopSearch();
        } else if (std.ascii.eqlIgnoreCase(command, "quit")) {
            return;
        } else if (std.ascii.eqlIgnoreCase(command, "wait")) {
            root.engine.waitUntilDoneSearching();
        } else if (!root.evaluation.use_hce and std.ascii.eqlIgnoreCase(command, "get_scale")) {
            const filename = parts.next() orelse "";
            var file = try std.fs.cwd().openFile(filename, .{});
            defer file.close();

            var br = std.io.bufferedReader(file.reader());

            var buf: [128]u8 = undefined;
            var sum: i64 = 0;

            while (br.reader().readUntilDelimiter(&buf, '\n')) |data_line| {
                const end = std.mem.indexOfScalar(u8, data_line, '[') orelse data_line.len;
                const fen = data_line[0..end];

                const raw_eval = @import("nnue.zig").nnEval(&(try Board.parseFen(fen, true)));
                sum += raw_eval;
            } else |_| {}
            std.debug.print("{}\n", .{sum});
        } else if (!root.evaluation.use_hce and std.ascii.eqlIgnoreCase(command, "nneval")) {
            const raw_eval = @import("nnue.zig").nnEval(&board);
            const scaled = root.history.HistoryTable.scaleEval(&board, raw_eval);
            const normalized = root.wdl.normalize(scaled, board.classicalMaterial());
            write("raw eval: {}\n", .{raw_eval});
            write("scaled eval: {}\n", .{scaled});
            write("scaled and normalized eval: {}\n", .{normalized});
        } else if (!root.evaluation.use_hce and std.ascii.eqlIgnoreCase(command, "bullet_evals")) {
            for ([_][]const u8{
                "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
                "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
                "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/P2P2PP/q2Q1R1K w kq - 0 2",
                "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
                "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
                "rnbqkbnr/pppppppp/8/8/8/8/1PPPPPPP/RNBQKBNR w KQkq - 0 1",
                "rnbqkbnr/pppppppp/8/8/8/8/P1PPPPPP/RNBQKBNR w KQkq - 0 1",
                "rnbqkbnr/pppppppp/8/8/8/8/PP1PPPPP/RNBQKBNR w KQkq - 0 1",
                "rnbqkbnr/pppppppp/8/8/8/8/PPP1PPPP/RNBQKBNR w KQkq - 0 1",
                "rnbqkbnr/pppppppp/8/8/8/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1",
                "rnbqkbnr/pppppppp/8/8/8/8/PPPPP1PP/RNBQKBNR w KQkq - 0 1",
                "rnbqkbnr/pppppppp/8/8/8/8/PPPPPP1P/RNBQKBNR w KQkq - 0 1",
                "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPP1/RNBQKBNR w KQkq - 0 1",
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
        } else if (std.ascii.eqlIgnoreCase(command, "GenerateRandomDfrcPerft")) {
            var prng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
            var mutex = std.Thread.Mutex{};
            for (0..1024) |_| {
                const worker_fn = struct {
                    fn impl(rng: std.Random, m: *std.Thread.Mutex) void {
                        m.lock();
                        var b = Board.dfrcPosition(rng.uintLessThan(u20, 960 * 960));
                        m.unlock();
                        b.frc = true;
                        var buf: [256]u8 = undefined;
                        var fbs = std.io.fixedBufferStream(&buf);
                        fbs.writer().print("{s} ;D1 {}; D2 {}; D3 {}; D4 {}; D5 {}; D6 {}\n", .{
                            b.toFen().slice(),
                            b.perft(true, 1),
                            b.perft(true, 2),
                            b.perft(true, 3),
                            b.perft(true, 4),
                            b.perft(true, 5),
                            b.perft(true, 6),
                        }) catch unreachable;
                        m.lock();
                        write("{s}", .{fbs.getWritten()});
                        m.unlock();
                    }
                }.impl;
                try root.engine.thread_pool.spawn(worker_fn, .{ prng.random(), &mutex });
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

            previous_hashes.clear();
            try previous_hashes.append(board.hash);
            var move_iter = std.mem.tokenizeAny(u8, pos_iter.rest(), &std.ascii.whitespace);
            while (move_iter.next()) |played_move| {
                if (std.ascii.eqlIgnoreCase(played_move, "moves")) continue;
                _ = board.makeMoveFromStr(played_move) catch {
                    writeLog("invalid move: '{s}'\n", .{played_move});
                    continue;
                };
                if (board.halfmove == 0) {
                    previous_hashes.clear();
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
