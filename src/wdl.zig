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

pub fn wdlParams(material: anytype) struct { f64, f64 } {
    const x: f64 = @floatFromInt(@max(10, material));

    const p_a = ((-139.005 * x / 58 + 361.787) * x / 58 + -385.952) * x / 58 + 397.846;
    const p_b = ((-25.859 * x / 58 + 75.532) * x / 58 + -14.220) * x / 58 + 64.262;
    return .{ p_a, p_b };
}

pub fn normalize(score: i16, material: anytype) i16 {
    if (root.evaluation.isMateScore(score)) {
        return score;
    }
    const a, _ = wdlParams(material);
    const scoref: f64 = @floatFromInt(score);
    return @intFromFloat(std.math.round(100 * scoref / a));
}
