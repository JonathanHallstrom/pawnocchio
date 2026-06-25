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
const Board = root.Board;

pub fn wdlParams(board: *const Board) struct { f64, f64 } {
    const material = std.math.clamp(board.classicalMaterial(), 17, 78);
    const move = std.math.clamp(board.fullmove, 1, 120);

    const x: f64 = @as(f64, @floatFromInt(material)) / 58;
    const y: f64 = @as(f64, @floatFromInt(move)) / 32;

    const p_a = 170.267570 + 219.411757 * x - 109.342795 * x * x + 52.799724 * y + 2.766119 * y * y - 53.723544 * x * y;
    const p_b = 33.280341 - 0.265123 * x + 26.285731 * x * x + 7.220614 * y + 1.585810 * y * y - 8.606530 * x * y;

    return .{ p_a, p_b };
}

pub fn wdlModel(score: i16, board: *const Board) struct { i32, i32, i32 } {
    const a, const b = wdlParams(board);

    const x: f64 = @floatFromInt(score);

    const w: i32 = @intFromFloat(@round(1000 / (1 + @exp((a - x) / b))));
    const l: i32 = @intFromFloat(@round(1000 / (1 + @exp((a + x) / b))));
    const d = 1000 - w - l;

    return .{ w, d, l };
}

pub fn normalize(score: i16, board: *const Board) i16 {
    if (root.evaluation.isMateScore(score) or root.evaluation.isTBScore(score)) {
        return score;
    }
    const a, _ = wdlParams(board);
    const scoref: f64 = @floatFromInt(score);
    return @intFromFloat(std.math.round(100 * scoref / a));
}
