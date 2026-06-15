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
    const x: f64 = @floatFromInt(material);

    const p_a = ((-43.652 * x / 58 + 115.844) * x / 58 + -135.616) * x / 58 + 337.002;
    const p_b = ((43.328 * x / 58 + -55.082) * x / 58 + 29.134) * x / 58 + 54.813;

    return .{ p_a, p_b };
}

pub fn wdlModel(score: i16, material: anytype) struct { i32, i32, i32 } {
    const a, const b = wdlParams(material);

    const x: f64 = @floatFromInt(score);

    const w: i32 = @intFromFloat(@round(1000 / (1 + @exp((a - x) / b))));
    const l: i32 = @intFromFloat(@round(1000 / (1 + @exp((a + x) / b))));
    const d = 1000 - w - l;

    return .{ w, d, l };
}

pub fn normalize(score: i16, material: anytype) i16 {
    if (root.evaluation.isMateScore(score) or root.evaluation.isTBScore(score)) {
        return score;
    }
    const a, _ = wdlParams(material);
    const scoref: f64 = @floatFromInt(score);
    return @intFromFloat(std.math.round(100 * scoref / a));
}
