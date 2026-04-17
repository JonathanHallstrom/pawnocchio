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

    // p_a = ((-5.273 * x / 58 + -3.581) * x / 58 + 2.813) * x / 58 + 284.631
    // p_b = ((49.231 * x / 58 + -69.854) * x / 58 + 48.236) * x / 58 + 41.310
    //     constexpr double as[] = {-5.27254245, -3.58054810, 2.81336795, 284.63146557};
    //     constexpr double bs[] = {49.23056003, -69.85434163, 48.23555930, 41.30969488};

    const p_a = ((-5.273 * x / 58 + -3.581) * x / 58 + 2.813) * x / 58 + 284.631;
    const p_b = ((49.231 * x / 58 + -69.854) * x / 58 + 48.236) * x / 58 + 41.310;

    return .{ p_a, p_b };
}

// std::pair<i32, i32> wdlModel(Score povScore, i32 material) {
//     const auto [a, b] = wdlParams(material);
//
//     const auto x = static_cast<f64>(povScore);
//
//     return {
//         static_cast<i32>(std::round(1000.0 / (1.0 + std::exp((a - x) / b)))),
//         static_cast<i32>(std::round(1000.0 / (1.0 + std::exp((a + x) / b))))
//     };
// }

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
