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
const Colour = root.Colour;
const tunable_constants = root.tunable_constants;

pub const MAX_HISTORY: i16 = 1 << 14;
const SHIFT = @ctz(MAX_HISTORY);

pub fn bonus(depth: i32) i16 {
    return @intCast(@min(
        depth * tunable_constants.history_bonus_mult + tunable_constants.history_bonus_offs,
        tunable_constants.history_bonus_max,
    ));
}

pub fn penalty(depth: i32) i16 {
    return @intCast(@min(
        depth * tunable_constants.history_penalty_mult + tunable_constants.history_penalty_offs,
        tunable_constants.history_penalty_max,
    ));
}

pub const QuietHistory = struct {
    vals: [2][64][64]i16,

    pub fn reset(self: *QuietHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    fn entry(self: anytype, col: Colour, move: Move) root.inheritConstness(@TypeOf(self), *i16) {
        return &(&self.vals)[col.toInt()][move.from().toInt()][move.to().toInt()];
    }

    pub fn update(self: *QuietHistory, col: Colour, move: Move, adjustment: i16) void {
        gravityUpdate(self.entry(col, move), adjustment);
    }

    pub fn read(self: *const QuietHistory, col: Colour, move: Move) i16 {
        return self.entry(col, move).*;
    }
};

fn gravityUpdate(entry: *i16, adjustment: anytype) void {
    const clamped: i16 = @intCast(std.math.clamp(adjustment, -MAX_HISTORY, MAX_HISTORY));
    const magnitude: i32 = @abs(clamped);
    // std.debug.print("{} {} {} {}\n", .{ entry.*, clamped, magnitude, comptime @ctz(MAX_HISTORY) });
    entry.* += @intCast(clamped - (magnitude * entry.*) >> SHIFT);
}
