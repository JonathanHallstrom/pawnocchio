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
const TTCluster = root.TTCluster;
const evaluation = root.evaluation;

const IS_WINDOWS = @import("builtin").os.tag == .windows;
const MAX_ALIGN = if (IS_WINDOWS) std.atomic.cache_line else 2 << 20;

fn adviseHugePages(p: anytype) !void {
    const bytes = std.mem.sliceAsBytes(p);
    if (@import("builtin").os.tag == .linux and @import("builtin").link_libc) {
        const ptr = @as([*]align(4096) u8, @alignCast(bytes.ptr));
        try std.posix.madvise(ptr, bytes.len, @cImport({
            @cDefine("_GNU_SOURCE", "");
            @cInclude("sys/mman.h");
        }).MADV_HUGEPAGE);
    }
}

const ThreadAction = enum {
    sleep,
    search,
    reset,
    exit,
};

const Thread = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    action: ThreadAction = .sleep,
    exited: bool = false,
    tt: []TTCluster = &.{},

    searcher: *Searcher,
    thread: std.Thread,

    search_params: Searcher.Params = undefined,
    search_main: bool = false,
    search_quiet: bool = false,

    reset_tt_slice: []TTCluster = &.{},

    pub fn init(allocator: std.mem.Allocator, searcher: *Searcher) !*Thread {
        const self = try allocator.create(Thread);
        self.* = .{
            .searcher = searcher,
            .thread = undefined,
        };
        self.thread = try std.Thread.spawn(.{}, loop, .{self});
        return self;
    }

    fn loop(self: *Thread) void {
        while (true) {
            self.mutex.lock();
            while (self.action == .sleep) {
                self.cond.wait(&self.mutex);
            }
            const action = self.action;
            self.mutex.unlock();

            if (action == .exit) break;

            switch (action) {
                .search => {
                    self.searcher.startSearch(self.search_params, self.search_main, self.search_quiet);
                },
                .reset => {
                    @memset(std.mem.asBytes(self.searcher), 0);
                    self.searcher.refresh_cache.initInPlace();
                    self.searcher.histories.reset();
                    self.searcher.tt = self.tt;
                    if (self.reset_tt_slice.len > 0) {
                        @memset(std.mem.sliceAsBytes(self.reset_tt_slice), 0);
                    }
                },
                else => {},
            }

            self.mutex.lock();
            self.action = .sleep;
            self.cond.signal();
            self.mutex.unlock();
        }

        self.mutex.lock();
        self.exited = true;
        self.cond.signal();
        self.mutex.unlock();
    }

    pub fn wake(self: *Thread, action: ThreadAction) void {
        self.mutex.lock();
        self.action = action;
        self.mutex.unlock();
        self.cond.signal();
    }

    pub fn blockUntilSleep(self: *Thread) void {
        self.mutex.lock();
        while (self.action != .sleep) {
            self.cond.wait(&self.mutex);
        }
        self.mutex.unlock();
    }

    pub fn signalAndAwaitShutdown(self: *Thread) void {
        self.wake(.exit);
        self.mutex.lock();
        while (!self.exited) {
            self.cond.wait(&self.mutex);
        }
        self.mutex.unlock();
        self.thread.join();
    }
};

pub const ThreadPool = struct {
    threads: std.ArrayListUnmanaged(*Thread) = .{},
    searchers: std.ArrayListUnmanaged(*Searcher) = .{},
    tt: []align(std.atomic.cache_line) TTCluster = &.{},
    allocator: std.mem.Allocator,
    stop_searching: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: std.mem.Allocator) ThreadPool {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ThreadPool) void {
        self.abort();
        self.threads.deinit(self.allocator);
        self.searchers.deinit(self.allocator);
        if (self.tt.len > 0) {
            self.allocator.free(self.tt);
        }
    }

    pub fn abort(self: *ThreadPool) void {
        while (self.threads.items.len > 0) {
            self.removeThread();
        }
    }

    pub fn addThread(self: *ThreadPool) !void {
        var searcher: *Searcher = undefined;
        if (IS_WINDOWS) {
            searcher = try self.allocator.create(Searcher);
        } else {
            const ptr = try self.allocator.alignedAlloc(Searcher, .fromByteUnits(MAX_ALIGN), 1);
            searcher = @ptrCast(ptr);
            try adviseHugePages(ptr);
        }
        @memset(std.mem.asBytes(searcher), 0);
        if (!evaluation.use_hce) {
            searcher.refresh_cache.initInPlace();
        }
        searcher.histories.reset();
        searcher.tt = self.tt;

        const thread = try Thread.init(self.allocator, searcher);
        thread.tt = self.tt;
        try self.threads.append(self.allocator, thread);
        try self.searchers.append(self.allocator, searcher);
    }

    pub fn removeThread(self: *ThreadPool) void {
        if (self.threads.items.len == 0) return;

        const thread = self.threads.pop().?;
        const searcher = self.searchers.pop().?;

        thread.signalAndAwaitShutdown();
        self.allocator.destroy(thread);

        if (IS_WINDOWS) {
            self.allocator.destroy(searcher);
        } else {
            const slice: []align(MAX_ALIGN) Searcher = @as([*]align(MAX_ALIGN) Searcher, @ptrCast(@alignCast(searcher)))[0..1];
            self.allocator.free(slice);
        }
    }

    pub fn setThreadCount(self: *ThreadPool, count: usize) !void {
        while (self.threads.items.len < count) {
            try self.addThread();
        }
        while (self.threads.items.len > count) {
            self.removeThread();
        }
        for (self.searchers.items) |s| {
            s.tt = self.tt;
        }
        for (self.threads.items) |t| {
            t.tt = self.tt;
        }
    }

    pub fn setTTSize(self: *ThreadPool, size_mb: usize) !void {
        if (self.tt.len > 0) {
            self.allocator.free(self.tt);
        }
        const num_clusters = size_mb * (1024 * 1024) / @sizeOf(TTCluster);

        const slice = try self.allocator.alignedAlloc(TTCluster, .fromByteUnits(MAX_ALIGN), num_clusters);
        self.tt = slice;
        try adviseHugePages(self.tt);

        for (self.searchers.items) |s| {
            s.tt = self.tt;
        }
        self.reset();
    }

    pub fn reset(self: *ThreadPool) void {
        const num_threads = self.threads.items.len;
        if (num_threads == 0) {
            if (self.tt.len > 0) {
                @memset(std.mem.sliceAsBytes(self.tt), 0);
            }
            return;
        }

        const chunk_size = self.tt.len / num_threads;
        for (self.threads.items, 0..) |t, i| {
            const start = i * chunk_size;
            const end = if (i == num_threads - 1) self.tt.len else (i + 1) * chunk_size;
            t.reset_tt_slice = self.tt[start..end];
            t.wake(.reset);
        }
        self.blockUntilReady();
    }

    pub fn startSearch(self: *ThreadPool, params: Searcher.Params, quiet: bool) void {
        self.stop_searching.store(false, .seq_cst);
        for (self.threads.items, 0..) |t, i| {
            t.search_params = params;
            t.search_quiet = quiet;
            t.search_main = (i == 0);
            t.wake(.search);
        }
    }

    pub fn stopSearch(self: *ThreadPool) void {
        self.stop_searching.store(true, .seq_cst);
        for (self.searchers.items) |s| {
            s.stop.store(true, .release);
        }
    }

    pub fn shouldStopSearching(self: *ThreadPool) bool {
        return self.stop_searching.load(.seq_cst);
    }

    pub fn blockUntilReady(self: *ThreadPool) void {
        for (self.threads.items) |t| {
            t.blockUntilSleep();
        }
    }

    pub fn waitUntilDoneSearching(self: *ThreadPool) void {
        self.blockUntilReady();
    }

    pub const SearchSettings = struct {
        search_params: Searcher.Params,
        quiet: bool = false,
    };
};
