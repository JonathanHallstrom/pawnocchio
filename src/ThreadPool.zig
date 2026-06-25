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
const history = root.history;

const IS_LINUX_LIBC = @import("builtin").os.tag == .linux and @import("builtin").link_libc;
const mman_c = if (IS_LINUX_LIBC) @cImport({
    @cDefine("_GNU_SOURCE", "");
    @cInclude("sys/mman.h");
}) else void;
const evaluation = root.evaluation;
const numa = @import("numa.zig");
const nnue = root.nnue;

const IS_WINDOWS = @import("builtin").os.tag == .windows;
const MAX_ALIGN = if (IS_WINDOWS) std.atomic.cache_line else 2 << 20;

fn adviseHugePages(p: anytype) !void {
    const bytes = std.mem.sliceAsBytes(p);
    if (IS_LINUX_LIBC) {
        const ptr = @as([*]align(4096) u8, @alignCast(bytes.ptr));
        try std.posix.madvise(ptr, bytes.len, @as(u32, @intCast(mman_c.MADV_HUGEPAGE)));
    }
}

pub fn allocTT(allocator: std.mem.Allocator, bytes: usize) ![]align(MAX_ALIGN) TTCluster {
    const slice = try allocator.alignedAlloc(TTCluster, .fromByteUnits(MAX_ALIGN), bytes / @sizeOf(TTCluster));
    try adviseHugePages(slice);
    return slice;
}

const ThreadAction = enum {
    sleep,
    search,
    reset,
    exit,
};

fn SharedStore(comptime T: type) type {
    return struct {
        const Self = @This();

        single: ?*T = null,
        per_node: numa.PerNode(T) = .{},

        fn init(allocator: std.mem.Allocator) !Self {
            var self: Self = .{};
            if (root.numa.enabled) {
                try self.per_node.allocUndefinedToAll();
                for (self.per_node.items.items) |ptr| {
                    ptr.reset();
                }
            } else {
                const ptr = try allocator.create(T);
                ptr.reset();
                self.single = ptr;
            }

            return self;
        }

        fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            if (self.single) |ptr| {
                allocator.destroy(ptr);
            }
            self.single = null;
            self.per_node.deinit();
        }

        fn get(self: *Self, thread_idx: usize) *T {
            if (root.numa.enabled) {
                return self.per_node.get(numa.nodeForThread(thread_idx)) orelse unreachable;
            }

            return self.single orelse unreachable;
        }

        fn reset(self: *Self) void {
            if (root.numa.enabled) {
                for (self.per_node.items.items) |ptr| {
                    ptr.reset();
                }
                return;
            }

            if (self.single) |ptr| {
                ptr.reset();
            }
        }
    };
}

const Thread = struct {
    mutex: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    action: ThreadAction = .sleep,
    exited: bool = false,
    tt: []TTCluster = &.{},

    searcher: *Searcher,
    thread: std.Thread,

    search_params: Searcher.Params = undefined,
    search_main: bool = false,
    search_quiet: bool = false,

    reset_tt_slice: []TTCluster = &.{},
    idx: usize,
    correction_histories: *history.CorrectionHistoryTable = undefined,
    pawn_histories: *history.PawnHistory = undefined,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, searcher: *Searcher, idx: usize, io: std.Io) !*Thread {
        const self = try allocator.create(Thread);
        self.* = .{
            .searcher = searcher,
            .thread = undefined,
            .idx = idx,
            .io = io,
        };
        self.thread = try std.Thread.spawn(.{}, loop, .{self});
        return self;
    }

    fn loop(self: *Thread) void {
        numa.bindCurrentThread(self.idx) catch |err| {
            std.log.debug("failed to bind search thread {} to NUMA node: {}", .{ self.idx, err });
        };

        while (true) {
            self.mutex.lockUncancelable(self.io);
            while (self.action == .sleep) {
                self.cond.waitUncancelable(self.io, &self.mutex);
            }
            const action = self.action;
            self.mutex.unlock(self.io);

            if (action == .exit) break;

            switch (action) {
                .search => {
                    self.searcher.startSearch(self.search_params, self.search_main, self.search_quiet);
                },
                .reset => {
                    @memset(std.mem.asBytes(self.searcher), 0);
                    self.searcher.correction_histories = self.correction_histories;
                    self.searcher.histories.pawn = self.pawn_histories;
                    self.searcher.eval_context.initForThread(self.idx);
                    self.searcher.histories.reset();
                    self.searcher.tt = self.tt;
                    if (self.reset_tt_slice.len > 0) {
                        @memset(std.mem.sliceAsBytes(self.reset_tt_slice), 0);
                    }
                },
                else => {},
            }

            self.mutex.lockUncancelable(self.io);
            self.action = .sleep;
            self.cond.signal(self.io);
            self.mutex.unlock(self.io);
        }

        self.mutex.lockUncancelable(self.io);
        self.exited = true;
        self.cond.signal(self.io);
        self.mutex.unlock(self.io);
    }

    pub fn wake(self: *Thread, action: ThreadAction) void {
        self.mutex.lockUncancelable(self.io);
        self.action = action;
        self.mutex.unlock(self.io);
        self.cond.signal(self.io);
    }

    pub fn blockUntilSleep(self: *Thread) void {
        self.mutex.lockUncancelable(self.io);
        while (self.action != .sleep) {
            self.cond.waitUncancelable(self.io, &self.mutex);
        }
        self.mutex.unlock(self.io);
    }

    pub fn signalAndAwaitShutdown(self: *Thread) void {
        self.wake(.exit);
        self.mutex.lockUncancelable(self.io);
        while (!self.exited) {
            self.cond.waitUncancelable(self.io, &self.mutex);
        }
        self.mutex.unlock(self.io);
        self.thread.join();
    }
};

pub const ThreadPool = struct {
    threads: std.ArrayListUnmanaged(*Thread) = .empty,
    searchers: std.ArrayListUnmanaged(*Searcher) = .empty,
    tt: []align(std.atomic.cache_line) TTCluster = &.{},
    corrhists: SharedStore(history.CorrectionHistoryTable) = .{},
    pawn_histories: SharedStore(history.PawnHistory) = .{},
    allocator: std.mem.Allocator,
    io: std.Io,
    stop_searching: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !ThreadPool {
        return .{
            .corrhists = try SharedStore(history.CorrectionHistoryTable).init(allocator),
            .pawn_histories = try SharedStore(history.PawnHistory).init(allocator),
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn deinit(self: *ThreadPool) void {
        self.abort();
        self.threads.deinit(self.allocator);
        self.searchers.deinit(self.allocator);
        self.corrhists.deinit(self.allocator);
        self.pawn_histories.deinit(self.allocator);
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
        const thread = try Thread.init(self.allocator, searcher, self.threads.items.len, self.io);
        thread.tt = self.tt;
        thread.correction_histories = self.corrhists.get(self.threads.items.len);
        thread.pawn_histories = self.pawn_histories.get(self.threads.items.len);
        try self.threads.append(self.allocator, thread);
        try self.searchers.append(self.allocator, searcher);
        thread.wake(.reset);
        thread.blockUntilSleep();
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
        const age = self.searchers.items[0].ttage;
        const id = self.searchers.items[0].search_id;
        for (self.searchers.items, 0..) |s, i| {
            s.ttage = age;
            s.search_id = id;
            s.tt = self.tt;
            s.correction_histories = self.corrhists.get(i);
            s.histories.pawn = self.pawn_histories.get(i);
        }
        for (self.threads.items, 0..) |t, i| {
            t.tt = self.tt;
            t.correction_histories = self.corrhists.get(i);
            t.pawn_histories = self.pawn_histories.get(i);
        }
    }

    pub fn setTTSize(self: *ThreadPool, size_mb: usize) !void {
        if (self.tt.len > 0) {
            self.allocator.free(self.tt);
        }
        self.tt = try allocTT(self.allocator, size_mb * (1024 * 1024));

        for (self.searchers.items) |s| {
            s.tt = self.tt;
        }
        for (self.threads.items) |t| {
            t.tt = self.tt;
        }
        self.reset();
    }

    pub fn reset(self: *ThreadPool) void {
        self.corrhists.reset();
        self.pawn_histories.reset();
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

    pub fn correctionHistoriesForThread(self: *ThreadPool, thread_idx: usize) *history.CorrectionHistoryTable {
        return self.corrhists.get(thread_idx);
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
