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
const TUNABLE_CONSTANTS = root.TUNABLE_CONSTANTS;

io: std.Io,
hard_time: u64 = 0, // absolute nanoseconds
soft_time: ?u64 = null,
max_depth: ?i32 = null,
soft_nodes: u64 = std.math.maxInt(u64),
hard_nodes: u64 = std.math.maxInt(u64),
time: [2]u64 = .{std.math.maxInt(u64)} ** 2,
inc: [2]u64 = .{0} ** 2,
movestogo: ?u32 = null,
nodes: ?u64 = null,
movetime: ?u64 = null,
infinite: bool = false,
start_timestamp: std.Io.Timestamp,
last_aspiration_print: u64 = 0,
root_depth: i32 = 0,
min_depth: i32 = 0,
max_score: i16 = std.math.maxInt(i16),
min_score: i16 = std.math.minInt(i16),

const Limits = @This();

pub fn elapsed(self: *const Limits) u64 {
    const now = std.Io.Timestamp.now(self.io, .awake);
    const duration = self.start_timestamp.durationTo(now);
    return @intCast(duration.nanoseconds);
}

pub fn initStandard(io: std.Io, board: *const root.Board, remaining_ns: u64, increment_ns: u64, overhead_ns: u64) Limits {
    const start_time = std.Io.Timestamp.now(io, .awake);
    const hard_time = (remaining_ns -| overhead_ns) * @as(u128, @min(
        @as(u128, @intCast(TUNABLE_CONSTANTS.hard_limit_base + (TUNABLE_CONSTANTS.hard_limit_phase_mult * (32 -| board.phase()) >> 6))),
        1024,
    )) >> 10;
    const soft_time = (remaining_ns -| overhead_ns) * @as(u128, @intCast(TUNABLE_CONSTANTS.soft_limit_base)) + increment_ns * @as(u128, @intCast(TUNABLE_CONSTANTS.soft_limit_incr)) >> 10;
    return Limits{
        .io = io,
        .hard_time = @intCast(hard_time),
        .soft_time = @intCast(soft_time),
        .start_timestamp = start_time,
    };
}

pub fn initFixedTime(io: std.Io, ns: u64) Limits {
    const start_time = std.Io.Timestamp.now(io, .awake);
    return Limits{
        .io = io,
        .hard_time = ns,
        .start_timestamp = start_time,
    };
}

pub fn initFixedDepth(io: std.Io, max_depth_: i32) Limits {
    const start_time = std.Io.Timestamp.now(io, .awake);
    return Limits{
        .io = io,
        .hard_time = std.time.ns_per_hour,
        .start_timestamp = start_time,
        .max_depth = max_depth_,
    };
}

pub inline fn checkSearch(self: *Limits, nodes: u64) bool {
    if (nodes >= self.hard_nodes) {
        return true;
    }
    if (nodes % 1024 == 0) {
        if (root.engine.shouldStopSearching()) {
            return true;
        }
        if (self.elapsed() >= self.hard_time) {
            return true;
        }
    }
    return false;
}

fn computeNodeCountFactor(_: *const Limits, best_move_count: u64, total_nodes: u64) u128 {
    const best_count = @min(best_move_count, total_nodes);
    const node_fraction = @as(u128, best_count) * 1024 / @max(1, total_nodes);
    return @as(u64, @intCast(TUNABLE_CONSTANTS.nodetm_mult)) * (@as(u64, @intCast(TUNABLE_CONSTANTS.nodetm_base)) -| node_fraction);
}

fn computeEvalStabilityFactor(_: *const Limits, stab: i64) u64 {
    return @intCast(@max(TUNABLE_CONSTANTS.eval_stab_lim, TUNABLE_CONSTANTS.eval_stab_base -| @divTrunc(TUNABLE_CONSTANTS.eval_stab_offs * stab, 1024)));
}

fn computeMoveStabilityFactor(_: *const Limits, stab: i64) u64 {
    return @intCast(@max(TUNABLE_CONSTANTS.move_stab_lim, TUNABLE_CONSTANTS.move_stab_base -| @divTrunc(TUNABLE_CONSTANTS.move_stab_offs * stab, 1024)));
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
    const curr_time = self.elapsed();
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
    const curr_time = self.elapsed();
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
