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
const builtin = @import("builtin");
const build_options = @import("build_options");

pub const enabled = build_options.use_numa and builtin.os.tag == .linux and builtin.link_libc;

const c = if (enabled) @cImport({
    @cDefine("_GNU_SOURCE", "");
    @cInclude("numa.h");
}) else struct {};

const metadata_allocator = std.heap.smp_allocator;

var cpu_masks: std.ArrayListUnmanaged(std.os.linux.cpu_set_t) = .{};
var node_ids: std.ArrayListUnmanaged(usize) = .{};
var active = false;

fn allocOnNode(comptime T: type, node: usize) !*T {
    if (!enabled) {
        unreachable;
    }

    const raw = c.numa_alloc_onnode(@sizeOf(T), @intCast(node)) orelse return error.OutOfMemory;
    return @ptrCast(@alignCast(raw));
}

fn freeOnNode(comptime T: type, ptr: *T) void {
    if (!enabled) {
        unreachable;
    }

    c.numa_free(ptr, @sizeOf(T));
}

pub fn PerNode(comptime T: type) type {
    return struct {
        items: std.ArrayListUnmanaged(*T) = .{},

        const Self = @This();

        pub fn deinit(self: *Self) void {
            for (self.items.items) |ptr| {
                freeOnNode(T, ptr);
            }
            self.items.deinit(metadata_allocator);
            self.* = .{};
        }

        pub fn get(self: *Self, node: usize) ?*T {
            if (self.items.items.len == 0) {
                return null;
            }

            return self.items.items[node % self.items.items.len];
        }

        pub fn getConst(self: *const Self, node: usize) ?*const T {
            if (self.items.items.len == 0) {
                return null;
            }

            return self.items.items[node % self.items.items.len];
        }

        pub fn allocUndefinedToAll(self: *Self) !void {
            std.debug.assert(self.items.items.len == 0);
            if (!isActive()) {
                return;
            }

            errdefer self.deinit();

            try self.items.ensureTotalCapacity(metadata_allocator, nodeCount());
            for (0..nodeCount()) |node_idx| {
                self.items.appendAssumeCapacity(try allocOnNode(T, osNodeId(node_idx)));
            }
        }

        pub fn allocCopyToAll(self: *Self, source: *const T) !void {
            std.debug.assert(self.items.items.len == 0);
            if (!isActive()) {
                return;
            }

            errdefer self.deinit();

            const source_bytes: [*]const u8 = @ptrCast(source);

            try self.items.ensureTotalCapacity(metadata_allocator, nodeCount());
            for (0..nodeCount()) |node_idx| {
                const ptr = try allocOnNode(T, osNodeId(node_idx));
                errdefer freeOnNode(T, ptr);

                const dst_bytes: [*]u8 = @ptrCast(ptr);
                @memcpy(dst_bytes[0..@sizeOf(T)], source_bytes[0..@sizeOf(T)]);
                self.items.appendAssumeCapacity(ptr);
            }
        }
    };
}

pub fn ReplicatedConstant(comptime T: type) type {
    return struct {
        fallback: *const T,
        per_node: PerNode(T) = .{},

        const Self = @This();

        pub fn init(self: *Self) !void {
            try self.per_node.allocCopyToAll(self.fallback);
        }

        pub fn deinit(self: *Self) void {
            self.per_node.deinit();
        }

        pub fn forNode(self: *const Self, node: usize) *const T {
            if (self.per_node.getConst(node)) |ptr| {
                return ptr;
            }

            return self.fallback;
        }
    };
}

pub fn init() !void {
    if (!enabled) {
        return;
    }
    if (c.numa_available() < 0) {
        return error.NumaUnavailable;
    }

    const max_node = c.numa_max_node();
    if (max_node < 0) {
        return error.NoNumaNodesReported;
    }

    errdefer deinit();

    for (0..@intCast(max_node + 1)) |node| {
        const cpu_mask = c.numa_allocate_cpumask() orelse return error.OutOfMemory;
        defer c.numa_free_cpumask(cpu_mask);

        if (c.numa_node_to_cpus(@intCast(node), cpu_mask) != 0) {
            return error.NumaCpuQueryFailed;
        }

        var set: std.os.linux.cpu_set_t = std.mem.zeroes(std.os.linux.cpu_set_t);
        var has_cpus = false;
        for (0..cpu_mask.*.size) |cpu| {
            if (c.numa_bitmask_isbitset(cpu_mask, @intCast(cpu)) == 0) {
                continue;
            }

            has_cpus = true;
            const word_bits = @bitSizeOf(usize);
            const idx = cpu / word_bits;
            const bit = cpu % word_bits;
            set[idx] |= @as(usize, 1) << @intCast(bit);
        }

        if (!has_cpus) {
            continue;
        }
        try node_ids.append(metadata_allocator, node);
        try cpu_masks.append(metadata_allocator, set);
    }

    if (cpu_masks.items.len == 0) {
        return error.NoActiveNumaNodes;
    }

    active = true;
}

pub fn deinit() void {
    if (!enabled) {
        return;
    }

    node_ids.deinit(metadata_allocator);
    node_ids = .{};
    cpu_masks.deinit(metadata_allocator);
    cpu_masks = .{};
    active = false;
}

pub fn isActive() bool {
    if (!enabled) {
        return false;
    }

    return active;
}

pub fn nodeCount() usize {
    if (!isActive()) {
        return 1;
    }

    return cpu_masks.items.len;
}

pub fn nodeForThread(thread_idx: usize) usize {
    if (!isActive()) {
        return 0;
    }

    return thread_idx % cpu_masks.items.len;
}

fn osNodeId(node_idx: usize) usize {
    if (!isActive()) {
        return 0;
    }

    return node_ids.items[node_idx % node_ids.items.len];
}

pub fn bindCurrentThread(thread_idx: usize) !void {
    if (!isActive()) return;
    try std.os.linux.sched_setaffinity(0, &cpu_masks.items[nodeForThread(thread_idx)]);
}
