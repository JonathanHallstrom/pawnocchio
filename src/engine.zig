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
var searchers: []Searcher align(std.atomic.cache_line) = &.{};
var done_searching_mutex: std.Thread.Mutex = .{};
var done_searching_cv: std.Thread.Condition = .{};
var needs_full_reset: bool = true; // should be set to true when starting a new game, used to tell threads they need to clear their histories
var tt: []root.TTEntry = &.{};

fn worker(i: usize, settings: Searcher.Params, quiet: bool) void {
    searchers[i].startSearch(settings, i == 0, quiet);
    _ = num_finished_threads.rmw(.Add, 1, .seq_cst);
    if (num_finished_threads.load(.seq_cst) == current_num_threads) {
        is_searching.store(false, .seq_cst);
        done_searching_mutex.lock();
        defer done_searching_mutex.unlock();
        done_searching_cv.signal();
    }
}

const disable_tt = true;

pub fn writeTT(hash: u64, move: root.Move, score: i16, score_type: root.ScoreType, depth: i32) void {
    _ = score;
    _ = score_type;
    _ = depth;
    if (disable_tt) return;
    tt[hash % tt.len] = root.TTEntry{
        // .score = score,
        // .score_type = score_type,
        .move = move,
        .hash = hash,
        // .depth = @intCast(depth),
    };
}

pub fn prefetchTT(hash: u64) void {
    if (disable_tt) return;
    @prefetch(&tt[hash % tt.len], .{});
}

pub fn readTT(hash: u64) root.TTEntry {
    if (disable_tt) return .{};
    return tt[hash % tt.len];
}

pub const SearchSettings = struct {
    search_params: Searcher.Params,
    num_threads: u32 = 1,
    quiet: bool = false,
};

pub fn reset() void {
    needs_full_reset = true;
}

pub fn setTTSize(new_size: usize) !void {
    tt = try std.heap.page_allocator.realloc(tt, new_size);
    @memset(tt, .{});
}

pub fn deinit() void {
    std.heap.page_allocator.free(tt);
    std.heap.page_allocator.free(searchers);
}

pub fn startSearch(settings: SearchSettings) void {
    std.debug.assert(settings.num_threads == 1);
    if (current_num_threads != settings.num_threads) { // need a new threadpool
        if (current_num_threads > 0) { // deinit old threadpool
            thread_pool.deinit();
        }

        current_num_threads = settings.num_threads;
        thread_pool.init(.{
            .allocator = std.heap.page_allocator,
            .n_jobs = settings.num_threads,
        }) catch |e| std.debug.panic("Fatal: creating thread pool failed with error '{}'\n", .{e});
        searchers = std.heap.page_allocator.realloc(searchers, settings.num_threads) catch |e| std.debug.panic("Fatal: allocating search data failed with error '{}'\n", .{e});
    }

    num_finished_threads.store(0, .seq_cst);
    is_searching.store(true, .seq_cst);
    stop_searching.store(false, .seq_cst);
    var search_params = settings.search_params;
    search_params.needs_full_reset = needs_full_reset;
    for (0..settings.num_threads) |i| {
        thread_pool.spawn(worker, .{ i, search_params, settings.quiet }) catch |e| std.debug.panic("Fatal: spawning thread failed with error '{}'\n", .{e});
    }
    needs_full_reset = false; // don't clear state unnecessarily
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
    done_searching_mutex.lock();
    defer done_searching_mutex.unlock();
    while (num_finished_threads.load(.seq_cst) < current_num_threads) {
        done_searching_cv.wait(&done_searching_mutex);
    }
}
