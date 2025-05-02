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
var thread_pool: std.Thread.Pool align(std.atomic.cache_line) = undefined;
var num_finished_threads: std.atomic.Value(usize) align(std.atomic.cache_line) = std.atomic.Value(usize).init(0);
var current_num_threads: usize align(std.atomic.cache_line) = 0; // 0 for uninitialized
pub var searchers: []Searcher align(std.atomic.cache_line) = &.{};
var done_searching_mutex: std.Thread.Mutex = .{};
var done_searching_cv: std.Thread.Condition = .{};
var needs_full_reset: bool = true; // should be set to true when starting a new game, used to tell threads they need to clear their histories
var tt: []root.TTEntry = &.{};

pub const SearchSettings = struct {
    search_params: Searcher.Params,
    quiet: bool = false,
};

pub fn reset() void {
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
    @memset(std.mem.sliceAsBytes(searchers), 0);
    needs_full_reset = true;
}

pub fn setTTSize(new_size: usize) !void {
    tt = try std.heap.page_allocator.realloc(tt, (new_size * 1000000) / @sizeOf(root.TTEntry));
    @memset(tt, .{});
}

pub fn setThreadCount(thread_count: usize) !void {
    if (current_num_threads != thread_count) { // need a new threadpool
        if (current_num_threads > 0) { // deinit old threadpool
            thread_pool.deinit();
        }

        current_num_threads = thread_count;
        try thread_pool.init(.{
            .allocator = std.heap.page_allocator,
            .n_jobs = thread_count,
        });
        searchers = std.heap.page_allocator.realloc(searchers, thread_count) catch |e| std.debug.panic("Fatal: allocating search data failed with error '{}'\n", .{e});
    }
}

pub fn deinit() void {
    std.heap.page_allocator.free(tt);
    std.heap.page_allocator.free(searchers);
}

fn searchWorker(i: usize, settings: Searcher.Params, quiet: bool) void {
    searchers[i].tt = tt;
    searchers[i].startSearch(settings, i == 0, quiet);
    _ = num_finished_threads.rmw(.Add, 1, .seq_cst);
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
    random_move_count: u8,
    node_count: u64,
    writer: anytype,
    writer_mutex: *std.Thread.Mutex,
    total_position_count: *std.atomic.Value(usize),
) void {
    const viriformat = root.viriformat;
    var seed: u64 = @bitCast(std.time.microTimestamp());
    seed ^= i;
    var rng = std.Random.DefaultPrng.init(seed);
    var alloc_buffer: [1 << 20]u8 = undefined;

    datagen_loop: while (true) {
        var board = root.Board.dfrcPosition(rng.random().uintLessThanBiased(u20, 960 * 960));
        var fba = std.heap.FixedBufferAllocator.init(&alloc_buffer);
        var hashes = std.ArrayList(u64).init(fba.allocator());
        defer hashes.deinit();
        random_move_loop: for (0..random_move_count) |_| {
            switch (board.stm) {
                inline else => |stm| {
                    var rec = root.movegen.MoveListReceiver{};
                    root.movegen.generateAllQuiets(stm, &board, &rec);

                    rng.random().shuffle(root.Move, rec.vals.slice());
                    for (rec.vals.slice()) |move| {
                        if (board.isLegal(stm, move)) {
                            board.makeMove(stm, move, root.Board.NullEvalState{});
                            if (board.halfmove == 0) {
                                hashes.clearRetainingCapacity();
                            }
                            hashes.append(board.hash) catch @panic("failed to append hash");
                            continue :random_move_loop;
                        }
                    }
                    continue :datagen_loop;
                },
            }
        }
        var game: viriformat.Game = viriformat.Game.from(board, fba.allocator());
        game_loop: for (0..2000) |move_idx| {
            var limits = root.Limits.initFixedTime(std.time.ns_per_s);
            limits.soft_nodes = node_count;
            searchers[i].startSearch(
                root.Searcher.Params{
                    .board = board,
                    .limits = limits,
                    .needs_full_reset = move_idx == 0,
                    .previous_hashes = hashes.items,
                },
                false,
                true,
            );
            const search_move = searchers[i].root_move;
            const search_score = searchers[i].root_score;
            const adjusted = if (board.stm == .white) search_score else -search_score;
            if (move_idx == 0 and @abs(adjusted) > 2000) {
                continue :datagen_loop;
            }
            // const fen = board.toFen();
            // std.debug.print("{s} {}\n", .{ .slice(), adjusted });
            // std.debug.print("added move\n", .{});

            switch (board.stm) {
                inline else => |stm| {
                    // std.debug.print("{s} {s}\n", .{
                    //     board.toFen().slice(),
                    //     searchers[i].root_move.toString(&board).slice(),
                    // });
                    if (search_move.isNull()) {
                        break :game_loop;
                    }
                    board.makeMove(stm, search_move, root.Board.NullEvalState{});
                },
            }
            for (hashes.items) |prev_hash| {
                if (prev_hash == board.hash) {
                    break :game_loop;
                }
            }
            if (board.halfmove >= 100) {
                break :game_loop;
            }
            if (board.halfmove == 0) {
                hashes.clearRetainingCapacity();
            }
            game.addMove(search_move, adjusted) catch unreachable;
            hashes.append(board.hash) catch unreachable;
            if (root.evaluation.isMateScore(search_score)) {
                if (adjusted > 0) {
                    // std.debug.print("white {s}\n", .{fen.slice()});
                    game.setOutCome(2);
                } else {
                    // std.debug.print("black {s}\n", .{fen.slice()});
                    game.setOutCome(0);
                }
                break :game_loop;
            }
        }

        if (game.moves.items.len == 0) {
            continue :datagen_loop;
        }

        _ = total_position_count.fetchAdd(game.moves.items.len, .seq_cst);
        writer_mutex.lock();
        game.serializeInto(writer) catch @panic("failed to serialize position");
        writer_mutex.unlock();
    }
}

pub fn datagen(num_nodes: u64) !void {
    var timer = try std.time.Timer.start();
    var out_file = try std.fs.cwd().createFile("outfile.vf", .{});
    var buf_writer = std.io.bufferedWriter(out_file.writer());
    const writer = buf_writer.writer();
    var writer_mutex = std.Thread.Mutex{};
    var total_position_count = std.atomic.Value(usize).init(0);
    for (0..current_num_threads) |i| {
        searchers[i].tt = try std.heap.page_allocator.alloc(root.TTEntry, (16 << 20) / @sizeOf(root.TTEntry));
        // datagenWorker(0, 8, num_nodes, out_file.writer(), &writer_mutex, &total_position_count);
        try thread_pool.spawn(datagenWorker, .{ i, 8, num_nodes, &writer, &writer_mutex, &total_position_count });
    }

    var prev_positions: usize = 0;
    while (true) {
        const positions = total_position_count.load(.seq_cst);
        defer prev_positions = positions;
        if (positions == prev_positions) {
            continue;
        }
        std.debug.print("total positions:{} positions/s:{}\n", .{
            positions,
            @as(u128, positions) * std.time.ns_per_s / timer.read(),
        });
        std.Thread.sleep(std.time.ns_per_s);
    }
}

pub fn querySearchedNodes() u64 {
    var res: u64 = 0;
    for (searchers) |*searcher| {
        res += searcher.nodes;
    }
    return res;
}

pub fn stopSearch() void {
    stop_searching.store(true, .seq_cst);
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
