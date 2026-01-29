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

pub fn wdlParams(material: anytype, as: [4]f64, bs: [4]f64) struct { f64, f64 } {
    const x: f64 = @floatFromInt(@max(10, material));
    // p_a = ((-51.918 * x / 58 + 145.188) * x / 58 + -166.615) * x / 58 + 281.596
    // p_b = ((-24.717 * x / 58 + 82.930) * x / 58 + -33.492) * x / 58 + 52.864
    //     constexpr double as[] = {-51.91819866, 145.18809272, -166.61481017, 281.59570002};
    //     constexpr double bs[] = {-24.71724508, 82.92975519, -33.49186286, 52.86407201};
    //
    const p_a = ((as[0] * x / 58 + as[1]) * x / 58 + as[2]) * x / 58 + as[3];
    const p_b = ((bs[0] * x / 58 + bs[1]) * x / 58 + bs[2]) * x / 58 + bs[3];

    return .{ p_a, p_b };
}

pub fn unnormalizeUsingModel(score: i16, material: anytype, as: [4]f64, bs: [4]f64) i16 {
    if (root.evaluation.isMateScore(score) or root.evaluation.isTBScore(score)) {
        return score;
    }
    const a, _ = wdlParams(material, as, bs);
    const scoref: f64 = @floatFromInt(score);
    return @intFromFloat(std.math.round(a * scoref / 100));
}

pub fn normalizeUsingModel(score: i16, material: anytype, as: [4]f64, bs: [4]f64) i16 {
    if (root.evaluation.isMateScore(score) or root.evaluation.isTBScore(score)) {
        return score;
    }
    const a, _ = wdlParams(material, as, bs);
    const scoref: f64 = @floatFromInt(score);
    return @intFromFloat(std.math.round(100 * scoref / a));
}

pub fn normalize(score: i16, material: anytype) i16 {
    if (root.evaluation.isMateScore(score) or root.evaluation.isTBScore(score)) {
        return score;
    }
    const a, _ = wdlParams(
        material,
        .{ -51.91819866, 145.18809272, -166.61481017, 281.59570002 },
        .{ -24.71724508, 82.92975519, -33.49186286, 52.86407201 },
    );
    const scoref: f64 = @floatFromInt(score);
    const fudge = 0.965847119;
    return @intFromFloat(std.math.round(100 * fudge * scoref / a));
}
