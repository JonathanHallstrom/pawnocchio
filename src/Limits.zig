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

hard_time: u64, // must always have a hard time limit
soft_time: ?u64 = null,
max_depth: ?i32 = null,
timer: std.time.Timer,

const Limits = @This();

pub fn initStandard(remaining_ns: u64, increment_ns: u64, overhead_ns: u64) Limits {
    return Limits{
        .hard_time = (remaining_ns - overhead_ns) / 5,
        .soft_time = (remaining_ns - overhead_ns) / 20 + increment_ns / 2,
        .timer = std.time.Timer.start() catch @panic("Fatal: tim"),
    };
}

// pub fn
