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
var current_num_threads: u32 align(std.atomic.cache_line) = 0; // 0 for uninitialized
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

pub fn setThreadCount(thread_count: u32) !void {
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

fn datagenWorker(i: usize, random_move_count: u8, node_count: u64, writer: anytype) void {
    const viriformat = root.viriformat;
    var seed: u64 = @bitCast(std.time.microTimestamp());
    seed ^= i;
    var rng = std.Random.DefaultPrng.init(seed);
    var alloc_buffer: [4096]u8 = undefined;

    var output_buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&output_buffer);
    defer writer.writeAll(fbs.getWritten()) catch @panic("failed to write buffered data");
    datagen_loop: while (true) {
        var board = root.Board.dfrcPosition(rng.random().int(u20));

        var fba = std.heap.FixedBufferAllocator.init(&alloc_buffer);
        var hashes = std.ArrayList(u64).init(fba.allocator());
        defer hashes.deinit();
        {
            for (0..random_move_count) |_| {
                switch (board.stm) {
                    inline else => |stm| {
                        var rec = root.movegen.MoveListReceiver{};
                        root.movegen.generateAllQuiets(stm, &board, &rec);
                        const move = rec.vals.slice()[rng.random().uintLessThanBiased(usize, rec.vals.len)];
                        board = board.makeMove(stm, move, root.Board.NullEvalState);
                        hashes.append(board.hash) catch unreachable;
                    },
                }
            }
        }
        var game: viriformat.Game = viriformat.Game.from(root.Board{}, fba.allocator());
        game_loop: while (true) {
            var limits = root.Limits.initFixedTime(std.time.ns_per_s);
            limits.hard_nodes = node_count;
            searchers[i].startSearch(
                root.Searcher.Params{
                    .board = board,
                    .limits = limits,
                    .needs_full_reset = game.moves.items.len == 0,
                    .previous_hashes = hashes.items,
                },
                false,
                true,
            );
            switch (board.stm) {
                inline else => |stm| {
                    board = board.makeMove(stm, searchers[i].root_move, root.Board.NullEvalState{});
                },
            }
            hashes.append(board.hash) catch unreachable;
            for (hashes.items) |prev_hash| {
                if (prev_hash == board.hash) {
                    break :game_loop;
                }
            }
            if (root.evaluation.isMateScore(searchers[i].root_score)) {
                break :game_loop;
            }
        }

        if (game.moves.items.len == 0) {
            continue :datagen_loop;
        }

        const remaining_capacity = @sizeOf(output_buffer) - fbs.getWritten().len;
        if (game.bytesRequiredToSerialize() > remaining_capacity) {
            writer.writeAll(fbs.getWritten()) catch @panic("failed to write buffered data");
            fbs.reset();
        }
        game.serializeInto(fbs.writer());
    }
}

pub fn datagen(num_nodes: u64) void {
    _ = num_nodes;
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
