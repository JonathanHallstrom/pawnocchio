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
root_depth: i32 = 0,
min_depth: i32 = 0,
max_score: i16 = std.math.maxInt(i16),
min_score: i16 = std.math.minInt(i16),

const Limits = @This();

pub fn initStandard(board: *const root.Board, remaining_ns: u64, increment_ns: u64, overhead_ns: u64) Limits {
    var t = std.time.Timer.start() catch std.debug.panic("Fatal: timer failed to start", .{});
    const start_time = t.read();
    const hard_time = (remaining_ns -| overhead_ns) * @as(u128, @min(
        @as(u128, @intCast(tunable_constants.hard_limit_base + (tunable_constants.hard_limit_phase_mult * (32 -| board.phase()) >> 6))),
        1024,
    )) >> 10;
    const soft_time = (remaining_ns -| overhead_ns) * @as(u128, @intCast(tunable_constants.soft_limit_base)) + increment_ns * @as(u128, @intCast(tunable_constants.soft_limit_incr)) >> 10;
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
        if (nodes >= self.hard_nodes) {
            return true;
        }
        if (root.engine.shouldStopSearching()) {
            return true;
        }
        if (self.timer.read() >= self.hard_time) {
            return true;
        }
    }
    return false;
}

fn computeNodeCountFactor(_: *const Limits, best_move_count: u64, total_nodes: u64) u128 {
    const node_fraction = @as(u128, best_move_count) * 1024 / @max(1, total_nodes);
    return @as(u64, @intCast(tunable_constants.nodetm_mult)) * (@as(u64, @intCast(tunable_constants.nodetm_base)) - node_fraction);
}

fn computeEvalStabilityFactor(_: *const Limits, stab: i64) u64 {
    return @intCast(@max(tunable_constants.eval_stab_lim, tunable_constants.eval_stab_base - @divTrunc(tunable_constants.eval_stab_offs * stab, 1024)));
}

fn computeMoveStabilityFactor(_: *const Limits, stab: i64) u64 {
    return @intCast(@max(tunable_constants.move_stab_lim, tunable_constants.move_stab_base - @divTrunc(tunable_constants.move_stab_offs * stab, 1024)));
}

pub fn checkRoot(
    self: *Limits,
    nodes: u64,
    depth: i32,
    score: i16,
) bool {
    if (nodes >= @min(self.hard_nodes, self.soft_nodes)) {
        return true;
    }
    if (score >= self.max_score or
        score <= self.min_score)
    {
        return true;
    }
    if (self.max_depth) |md| {
        if (depth >= md) {
            return true;
        }
    }
    const curr_time = self.timer.read();
    if (curr_time >= self.hard_time) {
        return true;
    }
    if (root.engine.shouldStopSearching()) {
        return true;
    }
    return false;
}

pub fn checkRootTime(
    self: *Limits,
    eval_stability: u32,
    move_stability: u32,
    best_move_count: u64,
    total_nodes: u64,
) bool {
    const curr_time = self.timer.read();
    if (curr_time >= self.hard_time) {
        return true;
    }
    if (self.soft_time) |st| {
        var adjusted_limit = st * self.computeNodeCountFactor(best_move_count, total_nodes) >> 20;
        adjusted_limit = adjusted_limit * self.computeEvalStabilityFactor(eval_stability) >> 10;
        adjusted_limit = adjusted_limit * self.computeMoveStabilityFactor(move_stability) >> 10;
        if (curr_time >= adjusted_limit) {
            return true;
        }
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
