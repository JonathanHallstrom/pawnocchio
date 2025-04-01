// Pawnocchio, UCI chess engine
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
var current_num_threads: u32 = 0; // 0 for uninitialized
var searchers: []Searcher = &.{};

fn worker(i: usize, settings: Searcher.Params) void {
    searchers[i].startSearch(settings, i == 0);
}

pub fn startSearch(settings: Searcher.Params, num_threads: u32) void {
    std.debug.assert(num_threads == 1);
    if (current_num_threads != num_threads) { // need a new threadpool
        if (current_num_threads > 0) { // deinit old threadpool
            thread_pool.deinit();
        }

        current_num_threads = num_threads;
        thread_pool.init(.{
            .allocator = std.heap.page_allocator,
            .n_jobs = num_threads,
        }) catch |e| std.debug.panic("Fatal: creating thread pool failed with error '{}'\n", .{e});
        searchers = std.heap.page_allocator.realloc(searchers, num_threads) catch |e| std.debug.panic("Fatal: allocating search data failed with error '{}'\n", .{e});
    }
    is_searching.store(true, .seq_cst);
    stop_searching.store(false, .seq_cst);
    for (0..num_threads) |i| {
        thread_pool.spawn(worker, .{ i, settings }) catch |e| std.debug.panic("Fatal: spawning thread failed with error '{}'\n", .{e});
    }
}

pub fn stopSearch() void {
    stop_searching.store(true, .seq_cst);
}
