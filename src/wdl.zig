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

    const p_a = ((102.232 * x / 58 + -207.792) * x / 58 + 72.524) * x / 58 + 241.773;
    const p_b = ((-27.478 * x / 58 + 91.296) * x / 58 + 3.491) * x / 58 + 61.921;

    return .{ p_a, p_b };
}

pub fn normalize(score: i16, material: anytype) i16 {
    if (root.evaluation.isMateScore(score) or root.evaluation.isTBScore(score)) {
        return score;
    }
    const a, _ = wdlParams(material);
    const scoref: f64 = @floatFromInt(score);
    return @intFromFloat(std.math.round(100 * scoref / a));
}
