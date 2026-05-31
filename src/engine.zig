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
const ThreadPool = @import("ThreadPool.zig").ThreadPool;
const Searcher = root.Searcher;
const debug_stats_mod = @import("debug_stats.zig");
const numa = @import("numa.zig");
const nnue = root.nnue;

const IS_WINDOWS = @import("builtin").os.tag == .windows;
const MAX_ALIGN = if (IS_WINDOWS) std.atomic.cache_line else 2 << 20;

pub var thread_pool: ThreadPool = undefined;

pub var debug_stats_lock: std.Io.Mutex = .init;
pub var debug_stats: std.StringHashMap(debug_stats_mod.Scalar) = .init(std.heap.page_allocator);
pub var debug_bool_stats: std.StringHashMap(debug_stats_mod.BoolStat) = .init(std.heap.page_allocator);
pub var debug_corr_stats: std.StringHashMap(debug_stats_mod.Correlation) = .init(std.heap.page_allocator);
pub var debug_range_stats: std.StringHashMap(debug_stats_mod.Range) = .init(std.heap.page_allocator);
pub var debug_rng: std.Random.DefaultPrng = undefined;

fn castDebugValue(value: anytype) i64 {
    return switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => @as(i64, @intCast(value)),
        .bool => @intFromBool(value),
        else => @compileError(std.fmt.comptimePrint("unsupported type {s}", .{@typeName(@TypeOf(value))})),
    };
}

fn castDebugInt(comptime label: []const u8, value: anytype) i64 {
    return switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => @as(i64, @intCast(value)),
        else => @compileError(std.fmt.comptimePrint("unsupported {s} type {s}", .{ label, @typeName(@TypeOf(value)) })),
    };
}

fn castDebugFloat(value: anytype) f64 {
    return switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => @floatFromInt(value),
        .float, .comptime_float => @as(f64, value),
        .bool => @floatFromInt(@intFromBool(value)),
        else => @compileError(std.fmt.comptimePrint("unsupported correlation type {s}", .{@typeName(@TypeOf(value))})),
    };
}

fn fillDebugCorrValues(comptime expected_len: usize, values: anytype, out: *[expected_len]f64) void {
    switch (@typeInfo(@TypeOf(values))) {
        .pointer => |pointer| switch (pointer.size) {
            .one => fillDebugCorrValues(expected_len, values.*, out),
            .slice => {
                std.debug.assert(values.len == expected_len);
                for (values, 0..) |value, i| {
                    out[i] = castDebugFloat(value);
                }
            },
            else => @compileError("dbgCorr values pointer must be one-item or slice"),
        },
        .array => |array| {
            comptime {
                std.debug.assert(array.len == expected_len);
            }
            for (values, 0..) |value, i| {
                out[i] = castDebugFloat(value);
            }
        },
        .@"struct" => |struct_info| {
            if (!struct_info.is_tuple) {
                @compileError("dbgCorr values must be a tuple, array, or pointer to either");
            }
            comptime {
                std.debug.assert(struct_info.fields.len == expected_len);
            }
            inline for (struct_info.fields, 0..) |field, i| {
                out[i] = castDebugFloat(@field(values, field.name));
            }
        },
        else => @compileError("dbgCorr values must be a tuple, array, or pointer to either"),
    }
}

pub fn dbg(name: []const u8, x: anytype) @TypeOf(x) {
    switch (@typeInfo(@TypeOf(x))) {
        .int, .comptime_int => dbgImpl(name, @as(i64, @intCast(x))),
        .bool => dbgBoolImpl(name, x),
        else => @compileError(std.fmt.comptimePrint("unsupported type {s}", .{@typeName(@TypeOf(x))})),
    }
    return x;
}

pub fn dbgRange(name: []const u8, index: anytype, x: anytype, granularity: anytype) @TypeOf(x) {
    dbgRangeImpl(name, castDebugInt("index", index), castDebugValue(x), castDebugInt("granularity", granularity));
    return x;
}

pub fn dbgCorr(name: []const u8, comptime names: []const []const u8, values: anytype) void {
    var normalized_values: [names.len]f64 = undefined;
    fillDebugCorrValues(names.len, values, &normalized_values);
    dbgCorrImpl(name, names, &normalized_values);
}

fn dbgImpl(name: []const u8, value: i64) void {
    debug_stats_lock.lockUncancelable(root.io);
    defer debug_stats_lock.unlock(root.io);

    const gp = debug_stats.getOrPut(name) catch unreachable;
    if (!gp.found_existing) {
        gp.value_ptr.* = .{};
        gp.key_ptr.* = std.heap.page_allocator.dupe(u8, name) catch @panic("OOM");
    }
    gp.value_ptr.add(value, debug_rng.random());
}

fn dbgBoolImpl(name: []const u8, value: bool) void {
    debug_stats_lock.lockUncancelable(root.io);
    defer debug_stats_lock.unlock(root.io);

    const gp = debug_bool_stats.getOrPut(name) catch unreachable;
    if (!gp.found_existing) {
        gp.value_ptr.* = .{};
        gp.key_ptr.* = std.heap.page_allocator.dupe(u8, name) catch @panic("OOM");
    }
    gp.value_ptr.add(value);
}

fn dbgCorrImpl(name: []const u8, comptime names: []const []const u8, values: []const f64) void {
    debug_stats_lock.lockUncancelable(root.io);
    defer debug_stats_lock.unlock(root.io);

    const gp = debug_corr_stats.getOrPut(name) catch unreachable;
    if (!gp.found_existing) {
        gp.value_ptr.* = debug_stats_mod.Correlation.init(std.heap.page_allocator, names);
        gp.key_ptr.* = std.heap.page_allocator.dupe(u8, name) catch @panic("OOM");
    } else {
        gp.value_ptr.assertNames(names);
    }
    gp.value_ptr.add(values);
}

fn dbgRangeImpl(name: []const u8, index: i64, value: i64, granularity: i64) void {
    std.debug.assert(granularity > 0);

    debug_stats_lock.lockUncancelable(root.io);
    defer debug_stats_lock.unlock(root.io);

    const gp = debug_range_stats.getOrPut(name) catch unreachable;
    if (!gp.found_existing) {
        gp.value_ptr.* = debug_stats_mod.Range.init(std.heap.page_allocator, granularity);
        gp.key_ptr.* = std.heap.page_allocator.dupe(u8, name) catch @panic("OOM");
    } else {
        std.debug.assert(gp.value_ptr.granularity == granularity);
    }
    gp.value_ptr.add(index, value);
}

pub const TIMING_ENABLED = false;

const TimerSlot = struct {
    hash: u64 = 0,
    group: []const u8 = "",
    part: []const u8 = "",
    cycles: u64 = 0,
    hits: u64 = 0,

    pub fn nameLen(self: TimerSlot) usize {
        var res = self.group.len;
        if (self.part.len > 0) {
            res += self.part.len + 1;
        }
        return res;
    }

    pub fn cost(self: TimerSlot) f64 {
        return @as(f64, @floatFromInt(self.cycles)) / @as(f64, @floatFromInt(@max(1, self.hits)));
    }
};

const TimerInfo = struct {
    slot: TimerSlot,
    group_cycles: u64,

    pub fn order(_: void, a: TimerInfo, b: TimerInfo) bool {
        const ag = timerHash(a.slot.group);
        const bg = timerHash(b.slot.group);
        if (ag != bg) {
            if (a.group_cycles != b.group_cycles) return a.group_cycles > b.group_cycles;
            return ag < bg;
        }
        return a.slot.cycles > b.slot.cycles;
    }
};

var timer_table: []TimerSlot = &.{};
var timer_mask: u64 = 0;

inline fn timerHash(name: []const u8) u64 {
    return std.hash.Fnv1a_64.hash(name);
}

inline fn rdtscp() u64 {
    var hi: u32 = undefined;
    var lo: u32 = undefined;
    asm volatile ("rdtscp"
        : [hi] "={edx}" (hi),
          [lo] "={eax}" (lo),
        :
        : .{ .ecx = true });
    return (@as(u64, hi) << 32) | lo;
}

noinline fn registerTimer(h: u64, group: []const u8, part: []const u8) void {
    var saved: [256]TimerSlot = undefined;
    var n: usize = 0;
    for (timer_table) |e| if (e.hash != 0) {
        saved[n] = e;
        n += 1;
    };
    saved[n] = .{ .hash = h, .group = group, .part = part };
    n += 1;
    var cap: usize = 16;
    while (cap < n * 2) cap *= 2;
    while (true) {
        const fresh = std.heap.page_allocator.alloc(TimerSlot, cap) catch @panic("OOM");
        @memset(fresh, .{});
        const mask = cap - 1;
        var ok = true;
        for (saved[0..n]) |e| {
            const idx = e.hash & mask;
            if (fresh[idx].hash != 0) {
                ok = false;
                break;
            }
            fresh[idx] = e;
        }
        if (ok) {
            if (timer_table.len != 0) std.heap.page_allocator.free(timer_table);
            timer_table = fresh;
            timer_mask = mask;
            return;
        }
        std.heap.page_allocator.free(fresh);
        cap *= 2;
    }
}

pub const ScopedTimer = struct {
    start: u64,
    hash: u64,
    pub inline fn register(self: ScopedTimer) void {
        if (comptime !TIMING_ENABLED) return;
        const elapsed = rdtscp() -% self.start;
        const slot = &timer_table[self.hash & timer_mask];
        slot.cycles +%= elapsed;
        slot.hits +%= 1;
    }
};

pub inline fn timeGrouped(comptime group: []const u8, comptime part: []const u8) ScopedTimer {
    if (comptime !TIMING_ENABLED) return .{ .start = 0, .hash = 0 };
    const h = comptime timerHash(group ++ "\x00" ++ part);
    if (timer_table.len == 0 or timer_table[h & timer_mask].hash != h) registerTimer(h, group, part);
    return .{ .start = rdtscp(), .hash = h };
}

pub inline fn time(comptime name: []const u8) ScopedTimer {
    return timeGrouped(name, "");
}

fn timerPct(x: u64, total: u64) f64 {
    return if (total == 0) 0 else @as(f64, @floatFromInt(x)) * 100.0 / @as(f64, @floatFromInt(total));
}

fn printTimers(writer: *std.Io.Writer) void {
    if (comptime !TIMING_ENABLED) return;
    var infos: [256]TimerInfo = undefined;
    var n: usize = 0;
    var total_cycles: u64 = 0;
    for (timer_table) |e| {
        if (e.hash == 0 or e.hits == 0) continue;
        var group_cycles: u64 = 0;
        for (timer_table) |o| {
            if (o.hash != 0 and o.hits != 0 and std.mem.eql(u8, o.group, e.group)) group_cycles += o.cycles;
        }
        infos[n] = .{ .slot = e, .group_cycles = group_cycles };
        n += 1;
        total_cycles += e.cycles;
    }
    if (total_cycles == 0) return;

    std.mem.sort(TimerInfo, infos[0..n], {}, TimerInfo.order);

    writer.print("raw:\n", .{}) catch unreachable;
    for (infos[0..n]) |info| {
        const e = info.slot;
        var name_buf: [64]u8 = undefined;
        const sep: []const u8 = if (e.part.len > 0) " " else "";
        const label = std.fmt.bufPrint(&name_buf, "{s}{s}{s}", .{ e.group, sep, e.part }) catch "[?]";
        writer.print("  {s: <26} cyc={d: >14} hits={d: >12} cyc/hit={d: >8.2}\n", .{ label, e.cycles, e.hits, e.cost() }) catch unreachable;
    }

    writer.print("summary:\n", .{}) catch unreachable;
    var i: usize = 0;
    while (i < n) {
        const g = infos[i].slot.group;
        const gtot = infos[i].group_cycles;
        writer.print("  {s: <26}{d: >6.2}%\n", .{ g, timerPct(gtot, total_cycles) }) catch unreachable;
        while (i < n and std.mem.eql(u8, infos[i].slot.group, g)) : (i += 1) {
            const e = infos[i].slot;
            if (e.part.len == 0) continue;
            writer.print("    {s: <24}{d: >6.2}%  {d: >5.1}%\n", .{ e.part, timerPct(e.cycles, total_cycles), timerPct(e.cycles, gtot) }) catch unreachable;
        }
    }
}

fn resetTimers() void {
    for (timer_table) |*e| {
        e.cycles = 0;
        e.hits = 0;
    }
}

pub fn printDebugStats() void {
    const writer = root.stdout_writer;

    var iter = debug_stats.iterator();
    while (iter.next()) |entry| {
        writer.print("{s}\n", .{entry.key_ptr.*}) catch unreachable;
        entry.value_ptr.format(writer) catch unreachable;
    }

    var bool_iter = debug_bool_stats.iterator();
    while (bool_iter.next()) |entry| {
        writer.print("{s} (bool)\n", .{entry.key_ptr.*}) catch unreachable;
        entry.value_ptr.format(writer) catch unreachable;
    }

    var corr_iter = debug_corr_stats.iterator();
    while (corr_iter.next()) |entry| {
        writer.print("{s}\n", .{entry.key_ptr.*}) catch unreachable;
        entry.value_ptr.format(writer) catch unreachable;
    }

    var range_iter = debug_range_stats.iterator();
    while (range_iter.next()) |entry| {
        writer.print("{s}\n", .{entry.key_ptr.*}) catch unreachable;
        entry.value_ptr.format(writer) catch unreachable;
    }

    printTimers(writer);
    writer.flush() catch unreachable;
}

pub fn resetDebugStats() void {
    resetTimers();
    var iter = debug_stats.valueIterator();
    while (iter.next()) |e| {
        e.reset();
    }

    var bool_iter = debug_bool_stats.valueIterator();
    while (bool_iter.next()) |e| {
        e.reset();
    }

    var corr_iter = debug_corr_stats.valueIterator();
    while (corr_iter.next()) |e| {
        e.reset();
    }

    var range_iter = debug_range_stats.valueIterator();
    while (range_iter.next()) |e| {
        e.reset();
    }
}

pub fn init(io: std.Io) !void {
    thread_pool = try ThreadPool.init(std.heap.page_allocator, io);
    try thread_pool.setTTSize(16);
    try thread_pool.setThreadCount(1);
    debug_stats = .init(std.heap.page_allocator); // yes its inefficient no i don't care
    debug_bool_stats = .init(std.heap.page_allocator);
    debug_corr_stats = .init(std.heap.page_allocator);
    debug_range_stats = .init(std.heap.page_allocator);
    debug_rng.seed(@bitCast(@as(i64, @intCast(std.Io.Timestamp.now(io, .awake).nanoseconds))));
}

pub fn deinit() void {
    thread_pool.deinit();
    printDebugStats();

    var debug_values = debug_stats.valueIterator();
    while (debug_values.next()) |value| {
        value.deinit();
    }

    var keys = debug_stats.keyIterator();

    while (keys.next()) |key| {
        std.heap.page_allocator.free(key.*);
    }

    debug_stats.deinit();

    var bool_values = debug_bool_stats.valueIterator();
    while (bool_values.next()) |value| {
        value.deinit();
    }

    var bool_keys = debug_bool_stats.keyIterator();
    while (bool_keys.next()) |key| {
        std.heap.page_allocator.free(key.*);
    }

    debug_bool_stats.deinit();

    var corr_values = debug_corr_stats.valueIterator();
    while (corr_values.next()) |value| {
        value.deinit();
    }

    var corr_keys = debug_corr_stats.keyIterator();
    while (corr_keys.next()) |key| {
        std.heap.page_allocator.free(key.*);
    }

    debug_corr_stats.deinit();

    var range_values = debug_range_stats.valueIterator();
    while (range_values.next()) |value| {
        value.deinit();
    }

    var range_keys = debug_range_stats.keyIterator();
    while (range_keys.next()) |key| {
        std.heap.page_allocator.free(key.*);
    }

    debug_range_stats.deinit();
}

pub fn reset() void {
    thread_pool.reset();
}

pub fn setTTSize(new_size: usize) !void {
    try thread_pool.setTTSize(new_size);
}

pub fn setThreadCount(thread_count: usize) !void {
    try thread_pool.setThreadCount(thread_count);
}

pub fn startSearch(settings: ThreadPool.SearchSettings) void {
    thread_pool.startSearch(settings.search_params, settings.quiet);
}

pub fn stopSearch() void {
    thread_pool.stopSearch();
}

pub fn shouldStopSearching() bool {
    return thread_pool.shouldStopSearching();
}

pub fn waitUntilDoneSearching() void {
    thread_pool.waitUntilDoneSearching();
}

pub fn querySearchedNodes() u64 {
    var res: u64 = 0;
    for (thread_pool.searchers.items) |searcher| {
        res += searcher.nodes;
    }
    return res;
}

const DatagenStats = struct {
    positions: std.atomic.Value(usize) = .init(0),
    games: std.atomic.Value(usize) = .init(0),
    wins: std.atomic.Value(usize) = .init(0),
    draws: std.atomic.Value(usize) = .init(0),
    losses: std.atomic.Value(usize) = .init(0),
};

fn datagenWorker(
    io: std.Io,
    i: usize,
    random_move_count_low: u8,
    random_move_count_high: u8,
    min_depth: i32,
    node_count: u64,
    writer_wrapper: *std.Io.File.Writer,
    writer_mutex: *std.atomic.Mutex,
    stats: *DatagenStats,
) void {
    numa.bindCurrentThread(i) catch |err| {
        std.log.debug("failed to bind datagen thread {} to NUMA node: {}", .{ i, err });
    };

    const searcher = thread_pool.searchers.items[i];
    const old_tt = searcher.tt;
    defer searcher.tt = old_tt;
    @memset(std.mem.asBytes(searcher), 0);
    searcher.correction_histories = thread_pool.correctionHistoriesForThread(i);
    searcher.eval_context.initForThread(i);
    searcher.tt = std.heap.page_allocator.alloc(root.TTCluster, (16 << 20) / @sizeOf(root.TTCluster)) catch std.debug.panic("allocation failed\n", .{});
    const viriformat = root.viriformat;
    var seed: u64 = 0;
    _ = std.os.linux.getrandom(std.mem.asBytes(&seed).ptr, std.mem.asBytes(&seed).len, 0);
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

        var previous_positions = root.BoundedArray(root.Board, 200){};
        var previous_moves = root.BoundedArray(root.Move, 200){};
        previous_positions.append(board) catch @panic("failed to append position");
        const random_move_count = rng.random().intRangeAtMost(u8, random_move_count_low, random_move_count_high);
        for (0..random_move_count) |_| {
            const move = board.pickMoveDatagen(rng.random()) orelse {
                continue :datagen_loop;
            };
            board.makeMoveSimple(move);
            previous_moves.append(move) catch @panic("failed to append move");
            previous_positions.append(board) catch @panic("failed to append position");
        }
        var game: viriformat.GameRecord = viriformat.GameRecord.from(board, fba.allocator());
        var num_adj_win: u8 = 0;
        var num_adj_draw: u8 = 0;
        var num_adj_loss: u8 = 0;
        game_loop: for (0..2000) |move_idx| {
            var limits = root.Limits.initFixedTime(io, std.time.ns_per_s);
            limits.soft_nodes = node_count;
            limits.hard_nodes = 100 * node_count;
            limits.min_depth = min_depth;
            board.hash ^= 13345022705723281337; // hack to make tt not shared
            searcher.startSearch(
                root.Searcher.Params{
                    .board = board,
                    .limits = limits,
                    .needs_full_reset = false,
                    .previous_positions = previous_positions,
                    .previous_moves = previous_moves,
                    .contempt = 0,
                    .normalize = false,
                    .minimal = false,
                    .show_wdl = false,
                },
                false,
                true,
            );
            const search_move = searcher.root_move orelse break :game_loop;
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
            switch (board.stm) {
                inline else => |stm| {
                    board.makeMove(stm, search_move, root.evaluation.noHandle());
                },
            }
            var repetitions: u8 = 0;
            for (previous_positions.slice()) |prev_position| {
                repetitions += @intFromBool(prev_position.hash == board.hash);
            }
            if (repetitions >= 3) {
                break :game_loop;
            }
            if (board.halfmove >= 100) {
                break :game_loop;
            }
            game.addMove(search_move, adjusted) catch unreachable;
            previous_moves.append(search_move) catch unreachable;
            previous_positions.append(board) catch unreachable;
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

        _ = stats.positions.fetchAdd(game.moves.items.len, .seq_cst);
        _ = stats.games.fetchAdd(1, .seq_cst);
        num_positions_written += game.moves.items.len;

        _ = switch (game.initial_position.wdl) {
            0 => stats.losses.fetchAdd(1, .seq_cst),
            1 => stats.draws.fetchAdd(1, .seq_cst),
            2 => stats.wins.fetchAdd(1, .seq_cst),
            else => {},
        };
        while (!writer_mutex.tryLock()) {
            std.Thread.yield() catch {};
        }
        game.serializeInto(&writer_wrapper.interface) catch @panic("failed to write game");

        writer_mutex.unlock();
    }
}

fn getFileName(nodes: u64, buf: []u8) ![]const u8 {
    var fbs = std.Io.Writer.fixed(buf);

    var random_buf: [32]u8 align(32) = undefined;
    _ = std.os.linux.getrandom(std.mem.asBytes(&random_buf).ptr, std.mem.asBytes(&random_buf).len, 0);

    const build_options = @import("build_options");
    var eval_identifier = build_options.eval_identifier;
    if (std.mem.lastIndexOfAny(u8, eval_identifier, ".")) |separator| {
        eval_identifier = eval_identifier[0..separator];
    }

    try fbs.print("outfile_{s}_{}nodes_{x}.vf", .{ eval_identifier, nodes, @as(u256, @bitCast(random_buf)) });
    return fbs.buffered();
}

pub fn datagen(io: std.Io, num_nodes: u64, positions: u64) !void {
    var buf: [4096]u8 = undefined;
    const start_time = std.Io.Timestamp.now(io, .awake);
    var out_file = try std.Io.Dir.cwd().createFile(io, try getFileName(num_nodes, &buf), .{ .truncate = true });
    defer out_file.close(io);

    var writer_wrapper = out_file.writerStreaming(io, &buf);
    var writer = &writer_wrapper.interface;

    var writer_mutex = std.atomic.Mutex.unlocked;
    var stats = DatagenStats{};

    var threads = try std.ArrayList(std.Thread).initCapacity(std.heap.page_allocator, thread_pool.threads.items.len);
    defer {
        for (threads.items) |t| t.join();
        threads.deinit(std.heap.page_allocator);
    }

    for (0..thread_pool.threads.items.len) |i| {
        threads.appendAssumeCapacity(try std.Thread.spawn(.{}, datagenWorker, .{ io, i, 6, 10, 0, num_nodes, &writer_wrapper, &writer_mutex, &stats }));
    }
    defer for (0..thread_pool.threads.items.len) |i| {
        std.heap.page_allocator.free(thread_pool.searchers.items[i].tt);
    };
    var prev_positions: usize = 0;
    var prev_time: u64 = 0;
    var pps_ema_opt: ?u64 = null;
    while (true) {
        std.Io.sleep(io, std.Io.Duration.fromNanoseconds(std.time.ns_per_s), .awake) catch {};
        if (!writer_mutex.tryLock()) {
            std.Io.sleep(io, std.Io.Duration.fromNanoseconds(std.time.ns_per_ms), .awake) catch {};
            continue;
        }
        try writer.flush();
        writer_mutex.unlock();
        const cur_positions = stats.positions.load(.seq_cst);
        if (cur_positions >= positions) {
            std.process.exit(0);
        }
        const now = std.Io.Timestamp.now(io, .awake);
        const elapsed_ns = @as(u64, @intCast(start_time.durationTo(now).nanoseconds));
        if (cur_positions == prev_positions) {
            continue;
        }
        defer {
            prev_positions = cur_positions;
            prev_time = elapsed_ns;
        }
        // u64 because if we're able to generate >2^64 positions per second then this program makes no sense
        const pps: u64 = @intCast(@as(u128, cur_positions - prev_positions) * std.time.ns_per_s / @max(1, elapsed_ns - prev_time));
        const lower_bound = if (pps_ema_opt) |pps_ema| pps_ema / 2 -| 1000 else pps;
        const upper_bound = if (pps_ema_opt) |pps_ema| pps_ema * 3 / 2 + 1000 else pps;
        const clamped_pps = std.math.clamp(pps, lower_bound, upper_bound);
        pps_ema_opt = if (pps_ema_opt) |pps_ema| (pps_ema * 19 + clamped_pps) / 20 else pps;
        std.debug.print("games:{} wins:{} draws:{} losses:{} positions:{} positions/s:{}\n", .{
            stats.games.load(.seq_cst),
            stats.wins.load(.seq_cst),
            stats.draws.load(.seq_cst),
            stats.losses.load(.seq_cst),
            cur_positions,
            pps_ema_opt.?,
        });
    }
}

pub fn genfens(io: std.Io, path: ?[]const u8, count: usize, seed: u64, writer: anytype, allocator: std.mem.Allocator) !void {
    var rng = std.Random.DefaultPrng.init(seed);
    var fens = std.array_list.Managed([]const u8).init(allocator);
    defer fens.deinit();
    defer for (fens.items) |fen| {
        allocator.free(fen);
    };
    if (path) |p| {
        var f = try std.Io.Dir.cwd().openFile(io, p, .{});
        defer f.close(io);
        var reader_buf: [4096]u8 = undefined;
        var reader = f.readerStreaming(io, &reader_buf);

        var line_buf: [128]u8 = undefined;
        var line_writer = std.Io.Writer.fixed(&line_buf);

        while (reader.interface.streamDelimiter(&line_writer, '\n') catch null) |fen_size| {
            std.debug.assert(try reader.interface.discardDelimiterInclusive('\n') == 1);
            std.debug.assert(line_writer.end == fen_size);

            try fens.append(try allocator.dupe(u8, line_writer.buffer[0..line_writer.end]));
            const dfrc_pos = rng.random().uintLessThan(u20, 960 * 960);
            try fens.append(try allocator.dupe(u8, root.Board.dfrcPosition(dfrc_pos).toFen().slice()));
            _ = line_writer.consumeAll();
        }
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
            const move = board.pickMoveDatagen(rng.random()) orelse {
                continue :fen_loop;
            };
            board.makeMoveSimple(move);
        }

        if (!board.hasLegalMove()) {
            continue :fen_loop;
        }

        try writer.print("info string genfens {s}\n", .{board.toFen().slice()});
        remaining -= 1;
    }
}
