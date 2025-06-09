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

const Move = root.Move;
const tunable_constants = root.tunable_constants;

hard_time: u64, // must always have a hard time limit
soft_time: ?u64 = null,
max_depth: ?i32 = null,
soft_nodes: u64 = std.math.maxInt(u64),
hard_nodes: u64 = std.math.maxInt(u64),
timer: std.time.Timer,
last_aspiration_print: u64 = 0,
node_counts: [64][64]u64 = std.mem.zeroes([64][64]u64),
root_depth: i32 = 0,
min_depth: i32 = 0,

const Limits = @This();

pub fn initStandard(board: *const root.Board, remaining_ns: u64, increment_ns: u64, overhead_ns: u64) Limits {
    var t = std.time.Timer.start() catch std.debug.panic("Fatal: timer failed to start", .{});
    const start_time = t.read();
    const hard_time = (remaining_ns - overhead_ns) * @as(u128, @intCast(tunable_constants.hard_limit_base + (tunable_constants.hard_limit_phase_mult * (32 - board.phase()) >> 6))) >> 10;
    const soft_time = (remaining_ns - overhead_ns) * @as(u128, @intCast(tunable_constants.soft_limit_base)) + increment_ns * @as(u128, @intCast(tunable_constants.soft_limit_incr)) >> 10;
    return Limits{
        .hard_time = @intCast(start_time + hard_time),
        .soft_time = @intCast(start_time + soft_time),
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
    if (std.debug.runtime_safety and nodes >= self.hard_nodes) {
        return true;
    }
    if (nodes % 1024 == 0) {
        if (self.root_depth < self.min_depth) {
            return false;
        }
        if (nodes >= self.hard_nodes) {
            return true;
        }
        if (self.timer.read() >= self.hard_time) {
            return true;
        }
        if (root.engine.shouldStopSearching()) {
            return true;
        }
    }
    return false;
}

fn computeNodeCountFactor(self: *const Limits, move: Move) u128 {
    var total_nodes: u64 = 0;
    for (self.node_counts) |counts| {
        for (counts) |count| {
            total_nodes += count;
        }
    }
    const best_move_count = @max(1, self.node_counts[move.from().toInt()][move.to().toInt()]);
    const node_fraction = @as(u128, best_move_count) * 1024 / total_nodes;
    return @as(u64, @intCast(tunable_constants.nodetm_mult)) * (@as(u64, @intCast(tunable_constants.nodetm_base)) - node_fraction);
}

fn computeEvalStabilityFactor(_: *const Limits, stab: i32) u64 {
    return @intCast(@max(1, tunable_constants.eval_stab_base - tunable_constants.eval_stab_offs * stab));
}

pub fn checkRoot(self: *Limits, nodes: u64, depth: i32, move: Move, eval_stability: i32) bool {
    if (self.root_depth < self.min_depth) {
        return false;
    }
    if (nodes >= @min(self.hard_nodes, self.soft_nodes)) {
        return true;
    }
    if (self.max_depth) |md| {
        if (depth >= md) {
            return true;
        }
    }
    const curr_time = self.timer.read();
    if (self.soft_time) |st| {
        var adjusted_limit = st * self.computeNodeCountFactor(move) >> 20;
        adjusted_limit = adjusted_limit * self.computeEvalStabilityFactor(eval_stability) >> 10;
        if (curr_time >= adjusted_limit) {
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

pub fn shouldPrintInfoInAspiration(self: *Limits) bool {
    const cur_time = self.timer.read();
    if (cur_time - self.last_aspiration_print > std.time.ns_per_s) {
        self.last_aspiration_print = cur_time;
        return true;
    }
    return false;
}

pub fn updateNodeCounts(self: *Limits, move: Move, nodes: u64) void {
    self.node_counts[move.from().toInt()][move.to().toInt()] += nodes;
}

pub fn resetNodeCounts(self: *Limits) void {
    @memset(std.mem.asBytes(&self.node_counts), 0);
}
