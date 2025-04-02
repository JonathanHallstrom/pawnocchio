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

hard_time: u64, // must always have a hard time limit
soft_time: ?u64 = null,
max_depth: ?i32 = null,
timer: std.time.Timer,

const Limits = @This();

pub fn initStandard(remaining_ns: u64, increment_ns: u64, overhead_ns: u64) Limits {
    var t = std.time.Timer.start() catch std.debug.panic("Fatal: timer failed to start", .{});
    const start_time = t.read();
    return Limits{
        .hard_time = start_time + (remaining_ns - overhead_ns) / 5,
        .soft_time = start_time + (remaining_ns - overhead_ns) / 20 + increment_ns / 2,
        .timer = t,
    };
}

pub fn initFixedTime(ns: u64) Limits {
    var t = std.time.Timer.start() catch std.debug.panic("Fatal: timer failed to start", .{});
    const start_time = t.read();
    return Limits{
        .hard_time = start_time + ns,
        .timer = t,
    };
}

pub fn initFixedDepth(max_depth_: i32) Limits {
    var t = std.time.Timer.start() catch std.debug.panic("Fatal: timer failed to start", .{});
    const start_time = t.read();
    return Limits{
        .hard_time = start_time + std.time.ns_per_hour,
        .timer = t,
        .max_depth = max_depth_,
    };
}

pub fn checkSearch(self: *Limits, nodes: u64) bool {
    if (nodes % 1024 == 0) {
        if (self.timer.read() >= self.hard_time) {
            return true;
        }
        if (root.engine.shouldStopSearching()) {
            return true;
        }
    }
    return false;
}

pub fn checkRoot(self: *Limits, nodes: u64, depth: i32) bool {
    _ = nodes;
    if (self.max_depth) |md| {
        if (depth >= md) {
            return true;
        }
    }
    const curr_time = self.timer.read();
    if (self.soft_time) |st| {
        if (curr_time >= st) {
            return true;
        }
    }
    if (curr_time >= self.hard_time) {
        return true;
    }
    if (root.engine.shouldStopSearching()) {
        return true;
    }
    return false;
}

pub fn getMaxDepth(self: Limits) i32 {
    return if (self.max_depth) |md| md else root.Searcher.MAX_PLY;
}
