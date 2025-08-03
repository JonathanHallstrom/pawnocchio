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

const Searcher = root.Searcher;

var is_searching: std.atomic.Value(bool) align(std.atomic.cache_line) = std.atomic.Value(bool).init(false);
var stop_searching: std.atomic.Value(bool) align(std.atomic.cache_line) = std.atomic.Value(bool).init(false);
pub var infinite: std.atomic.Value(bool) align(std.atomic.cache_line) = std.atomic.Value(bool).init(false);
pub var thread_pool: std.Thread.Pool align(std.atomic.cache_line) = undefined;
var num_finished_threads: std.atomic.Value(usize) align(std.atomic.cache_line) = std.atomic.Value(usize).init(0);
var current_num_threads: usize align(std.atomic.cache_line) = 0; // 0 for uninitialized
pub var searchers: []*Searcher align(std.atomic.cache_line) = &.{};
var done_searching_mutex: std.Thread.Mutex = .{};
var done_searching_cv: std.Thread.Condition = .{};
var needs_full_reset: bool = true; // should be set to true when starting a new game, used to tell threads they need to clear their histories
var tt: []root.TTCluster = &.{};

pub const SearchSettings = struct {
    search_params: Searcher.Params,
    quiet: bool = false,
};

fn resetTT() void {
    const reset_worker = struct {
        fn impl(start: usize, end: usize) void {
            @memset(tt[start..end], .{});
        }
    }.impl;

    if (current_num_threads <= 1) {
        @memset(tt, .{});
    } else {
        var wg = std.Thread.WaitGroup{};
        const amt_per_thread = (tt.len + current_num_threads - 1) / current_num_threads;
        var start: usize = 0;
        var end: usize = amt_per_thread;
        for (0..current_num_threads) |_| {
            thread_pool.spawnWg(&wg, reset_worker, .{ start, end });
            start = end;
            end = @min(end + amt_per_thread, tt.len);
        }
        thread_pool.waitAndWork(&wg);
    }
}

pub fn reset() void {
    resetTT();
    needs_full_reset = true;
}

pub fn setTTSize(new_size: usize) !void {
    tt = try std.heap.page_allocator.realloc(tt, @intCast(new_size * @as(u128, 1 << 20) / @sizeOf(root.TTCluster)));
    resetTT();
}

pub fn setThreadCount(thread_count: usize) !void {
    if (current_num_threads != thread_count) { // need a new threadpool
        if (current_num_threads > 0) { // deinit old threadpool
            thread_pool.deinit();
        }

        current_num_threads = thread_count;
        try thread_pool.init(.{
            .allocator = std.heap.page_allocator,
            .n_jobs = @intCast(thread_count),
        });
        for (searchers) |s| {
            std.heap.page_allocator.destroy(s);
        }
        searchers = std.heap.page_allocator.realloc(searchers, thread_count) catch |e| std.debug.panic("Fatal: allocating search data failed with error '{}'\n", .{e});
        for (searchers) |*s| {
            s.* = std.heap.page_allocator.create(Searcher) catch |e| std.debug.panic("Fatal: allocating search data failed with error '{}'\n", .{e});
        }
        needs_full_reset = true;
    }
}

pub fn deinit() void {
    std.heap.page_allocator.free(tt);
    for (searchers) |searcher| {
        std.heap.page_allocator.destroy(searcher);
    }
    std.heap.page_allocator.free(searchers);
}

fn searchWorker(i: usize, settings: Searcher.Params, quiet: bool) void {
    if (needs_full_reset) {
        @memset(std.mem.asBytes(searchers[i]), 0);
    }
    searchers[i].tt = tt;
    searchers[i].startSearch(settings, i == 0, quiet);
    // _ = num_finished_threads.rmw(.Add, 1, .seq_cst);
    _ = num_finished_threads.fetchAdd(1, .seq_cst);
    if (num_finished_threads.load(.seq_cst) == current_num_threads) {
        is_searching.store(false, .seq_cst);
        done_searching_mutex.lock();
        defer done_searching_mutex.unlock();
        done_searching_cv.signal();
    }
}

pub fn startSearch(settings: SearchSettings) void {
    if (!std.debug.runtime_safety) {
        stopSearch();
    }
    waitUntilDoneSearching();
    num_finished_threads.store(0, .seq_cst);
    is_searching.store(true, .seq_cst);
    stop_searching.store(false, .seq_cst);
    var search_params = settings.search_params;
    search_params.needs_full_reset = needs_full_reset;
    for (0..current_num_threads) |i| {
        thread_pool.spawn(searchWorker, .{ i, search_params, settings.quiet }) catch |e| std.debug.panic("Fatal: spawning thread failed with error '{}'\n", .{e});
    }
    needs_full_reset = false; // don't clear state unnecessarily
}

fn datagenWorker(
    i: usize,
    random_move_count_low: u8,
    random_move_count_high: u8,
    min_depth: i32,
    node_count: u64,
    writer: anytype,
    writer_mutex: *std.Thread.Mutex,
    total_position_count: *std.atomic.Value(usize),
    total_game_count: *std.atomic.Value(usize),
) void {
    const searcher = searchers[i];
    const viriformat = root.viriformat;
    var seed: u64 = 0;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch {
        const globals = struct {
            var fallback_datagen_seed_counter = std.atomic.Value(u64).init(0);
        };
        var seed_prng = std.Random.DefaultCsprng.init(.{0} ** 32);
        seed_prng.addEntropy(std.mem.asBytes(&globals.fallback_datagen_seed_counter.fetchAdd(1, .seq_cst)));
        seed_prng.addEntropy(std.mem.asBytes(&std.time.nanoTimestamp()));
        seed_prng.fill(std.mem.asBytes(&seed));
    };
    var rng = std.Random.DefaultPrng.init(seed);
    var alloc_buffer: [1 << 20]u8 = undefined;
    var num_positions_written: usize = 0;
    datagen_loop: while (true) {
        var board = root.Board.dfrcPosition(rng.random().uintLessThanBiased(u20, 960 * 960));
        if (rng.random().boolean()) {
            board = root.Board.startpos();
        }
        var fba = std.heap.FixedBufferAllocator.init(&alloc_buffer);
        const write_buffer = fba.allocator().alloc(u8, 1 << 16) catch @panic("failed to allocate write buffer");
        defer fba.allocator().free(write_buffer);

        var fbs = std.io.fixedBufferStream(write_buffer);
        const local_writer = fbs.writer();

        var hashes = std.BoundedArray(u64, 200){};
        const random_move_count = rng.random().intRangeAtMost(u8, random_move_count_low, random_move_count_high);
        for (0..random_move_count) |_| {
            if (!board.makeMoveDatagen(rng.random())) {
                continue :datagen_loop;
            }
            hashes.append(board.hash) catch @panic("failed to append hash");
        }
        var game: viriformat.Game = viriformat.Game.from(board, fba.allocator());
        var num_adj_win: u8 = 0;
        var num_adj_draw: u8 = 0;
        var num_adj_loss: u8 = 0;
        game_loop: for (0..2000) |move_idx| {
            var limits = root.Limits.initFixedTime(std.time.ns_per_s);
            limits.soft_nodes = node_count;
            limits.hard_nodes = 100 * node_count;
            limits.min_depth = min_depth;
            searcher.startSearch(
                root.Searcher.Params{
                    .board = board,
                    .limits = limits,
                    .needs_full_reset = move_idx == 0,
                    .previous_hashes = hashes,
                    .normalize = false,
                },
                false,
                true,
            );
            const search_move = searcher.root_move;
            const search_score = searcher.full_width_score;
            const adjusted = if (board.stm == .white) search_score else -search_score;
            const adjusted_normalized = if (board.stm == .white) searcher.full_width_score_normalized else -searcher.full_width_score_normalized;
            if (move_idx == 0 and @abs(adjusted_normalized) > 400) {
                continue :datagen_loop;
            }
            if (adjusted_normalized > 600) {
                num_adj_win += 1;
            } else {
                num_adj_win = 0;
            }
            if (adjusted_normalized < -600) {
                num_adj_loss += 1;
            } else {
                num_adj_loss = 0;
            }
            if (@abs(adjusted_normalized) < 50 and
                board.plies > 50 and
                board.phase() < 20)
            {
                num_adj_draw += 1;
            } else {
                num_adj_draw = 0;
            }
            // const fen = board.toFen();
            // var buf: [1024]u8 = undefined;
            // const dbg_log = std.fmt.bufPrint(&buf, "{s} {} {s} {}\n", .{
            //     fen.slice(),
            //     adjusted,
            //     search_move.toString(&board).slice(),
            //     board.hash,
            // }) catch unreachable;

            switch (board.stm) {
                inline else => |stm| {
                    // std.debug.print("{s} {s}\n", .{
                    //     board.toFen().slice(),
                    //     searchers[i].root_move.toString(&board).slice(),
                    // });
                    if (search_move.isNull()) {
                        // std.debug.print("{s}", .{dbg_log});
                        // std.debug.print("ended due to null move from search\n", .{});
                        break :game_loop;
                    }
                    board.makeMove(stm, search_move, root.Board.NullEvalState{});
                },
            }
            var repetitions: u8 = 0;
            for (hashes.slice()) |prev_hash| {
                repetitions += @intFromBool(prev_hash == board.hash);
            }
            if (repetitions >= 3) {
                // std.debug.print("{s}", .{dbg_log});
                // std.debug.print("ended due to repetiton\n", .{});
                // std.debug.print("hashes: {any}\n", .{hashes.items});

                // std.debug.print("hash after move: {}\n", .{board.hash});
                break :game_loop;
            }
            if (board.halfmove >= 100) {
                // std.debug.print("{s}", .{dbg_log});
                // std.debug.print("ended due to halfmove limit exceeded\n", .{});
                break :game_loop;
            }
            if (board.halfmove == 0) {
                hashes.clear();
            }
            game.addMove(search_move, adjusted) catch unreachable;
            hashes.append(board.hash) catch unreachable;
            if (root.evaluation.isMateScore(search_score) or root.evaluation.isTBScore(search_score)) {
                if (adjusted > 0) {
                    game.setOutCome(.win);
                } else {
                    game.setOutCome(.loss);
                }
                break :game_loop;
            }
            if (num_adj_win >= 5) {
                game.setOutCome(.win);
                break :game_loop;
            }
            if (num_adj_loss >= 5) {
                game.setOutCome(.loss);
                break :game_loop;
            }
            if (num_adj_draw >= 10) {
                game.setOutCome(.draw);
                break :game_loop;
            }
        }

        if (game.moves.items.len == 0) {
            continue :datagen_loop;
        }

        _ = total_position_count.fetchAdd(game.moves.items.len, .seq_cst);
        _ = total_game_count.fetchAdd(1, .seq_cst);
        num_positions_written += game.moves.items.len;

        game.serializeInto(local_writer) catch {
            writer_mutex.lock();
            writer.writeAll(fbs.getWritten()) catch @panic("failed to flush buffer");
            writer_mutex.unlock();
            fbs.reset();
            game.serializeInto(local_writer) catch {
                writer_mutex.lock();
                game.serializeInto(writer) catch @panic("failed to write game");
                writer_mutex.unlock();
            };
        };
    }
}

pub fn datagen(num_nodes: u64, filename: []const u8) !void {
    var timer = try std.time.Timer.start();
    var out_file = try std.fs.cwd().createFile(filename, .{});
    var buf_writer = std.io.bufferedWriter(out_file.writer());
    const writer = buf_writer.writer();
    var writer_mutex = std.Thread.Mutex{};
    var total_position_count = std.atomic.Value(usize).init(0);
    var total_game_count = std.atomic.Value(usize).init(0);
    for (0..current_num_threads) |i| {
        searchers[i].tt = try std.heap.page_allocator.alloc(root.TTCluster, (16 << 20) / @sizeOf(root.TTCluster));
        try thread_pool.spawn(datagenWorker, .{ i, 6, 10, 0, num_nodes, &writer, &writer_mutex, &total_position_count, &total_game_count });
    }

    var prev_positions: usize = 0;
    var prev_time = timer.read();
    var pps_ema_opt: ?u64 = null;
    while (true) {
        std.time.sleep(std.time.ns_per_s);
        if (!writer_mutex.tryLock()) {
            std.time.sleep(std.time.ns_per_ms);
            continue;
        }
        try buf_writer.flush();
        writer_mutex.unlock();
        const positions = total_position_count.load(.seq_cst);
        const time = timer.read();
        if (positions == prev_positions) {
            continue;
        }
        defer {
            prev_positions = positions;
            prev_time = time;
        }
        // u64 because if we're able to generate >2^64 positions per second then this program makes no sense
        const pps: u64 = @intCast(@as(u128, positions - prev_positions) * std.time.ns_per_s / @max(1, time - prev_time));
        const lower_bound = if (pps_ema_opt) |pps_ema| pps_ema / 2 -| 1000 else pps;
        const upper_bound = if (pps_ema_opt) |pps_ema| pps_ema * 3 / 2 + 1000 else pps;
        const clamped_pps = std.math.clamp(pps, lower_bound, upper_bound);
        pps_ema_opt = if (pps_ema_opt) |pps_ema| (pps_ema * 19 + clamped_pps) / 20 else pps;
        std.debug.print("games:{} positions:{} positions/s:{}\n", .{
            total_game_count.load(.seq_cst),
            positions,
            pps_ema_opt.?,
        });
    }
}

pub fn genfens(path: ?[]const u8, count: usize, seed: u64, writer: std.io.AnyWriter, allocator: std.mem.Allocator) !void {
    var rng = std.Random.DefaultPrng.init(seed);
    var fens = std.ArrayList([]const u8).init(allocator);
    defer fens.deinit();
    defer for (fens.items) |fen| {
        allocator.free(fen);
    };
    if (path) |p| {
        var f = try std.fs.cwd().openFile(p, .{});
        defer f.close();

        var br = std.io.bufferedReader(f.reader());
        while (br.reader().readUntilDelimiterAlloc(allocator, '\n', 128)) |fen| {
            try fens.append(fen);
            const dfrc_pos = rng.random().uintLessThan(u20, 960 * 960);
            try fens.append(try allocator.dupe(u8, root.Board.dfrcPosition(dfrc_pos).toFen().slice()));
        } else |_| {}
    }
    rng.random().shuffle([]const u8, fens.items);

    var remaining: usize = count;
    var i: usize = 0;
    fen_loop: while (remaining > 0) : (i += 1) {
        var board = if (fens.items.len > 0 and rng.random().boolean())
            try root.Board.parseFen(fens.items[i % fens.items.len], true)
        else
            root.Board.dfrcPosition(rng.random().uintLessThan(u20, 960 * 960));

        var moves = 1 + rng.random().uintLessThan(u8, 4);
        // do more random moves if we there are a lot of pieces on the first couple ranks
        moves += (@popCount(board.occupancy() & 0xff000000000000ff) + 2) / 6;
        moves += @popCount(board.occupancy() & 0x00ff00000000ff00) / 8;
        for (0..moves) |_| {
            if (!board.makeMoveDatagen(rng.random())) {
                continue :fen_loop;
            }
        }

        if (!board.hasLegalMove()) {
            continue :fen_loop;
        }

        try writer.print("info string genfens {s}\n", .{board.toFen().slice()});
        remaining -= 1;
    }
}

pub fn querySearchedNodes() u64 {
    var res: u64 = 0;
    for (searchers) |searcher| {
        res += searcher.nodes;
    }
    return res;
}

pub fn stopSearch() void {
    stop_searching.store(true, .seq_cst);
    for (searchers) |searcher| {
        searcher.stop.store(true, .release);
    }
}

pub fn shouldStopSearching() bool {
    return stop_searching.load(.seq_cst);
}

pub fn waitUntilDoneSearching() void {
    if (is_searching.load(.seq_cst)) {
        done_searching_mutex.lock();
        defer done_searching_mutex.unlock();
        while (num_finished_threads.load(.seq_cst) < current_num_threads) {
            done_searching_cv.wait(&done_searching_mutex);
        }
    }
}
