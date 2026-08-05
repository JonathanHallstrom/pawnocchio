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

pub fn wdlParams(board: *const Board) struct { f32, f32 } {
    const material = std.math.clamp(board.classicalMaterial(), 17, 78);
    const move = std.math.clamp(board.fullmove, 1, 120);

    const materialf: f32 = @floatFromInt(material);
    const movef: f32 = @floatFromInt(move);

    const x = materialf / 58;
    const y = movef / 32;

    const p_a = 237.12953685 + 44.90698791 * y + 91.06850910 * x + -7.15217681 * y * y + -36.74902578 * x * y + -39.99297198 * x * x;
    const p_b = 94.99523877 + -50.60915179 * y + -55.02231007 * x + 11.49863200 * y * y + 4.21120174 * x * y + 43.89888051 * x * x;

    return .{ p_a, p_b };
}

fn roundWDL(x: f64) i16 {
    var res: i16 = @round(x);

    // round extreme values towards the endpoints, for visual appeal:)
    if (x < 1) res = 0;
    if (x > 999) res = 1000;

    return res;
}

fn winChance(score: i32, a: f32, b: f32) f32 {
    const x: f32 = @floatFromInt(score);
    return root.fastmath.sigmoidScaled(x - a, b);
}

pub fn wdlModel(score: i32, board: *const Board) struct { i16, i16, i16 } {
    const a, const b = wdlParams(board);

    const w = roundWDL(1000 * winChance(score, a, b));
    const l = roundWDL(1000 * winChance(-score, a, b));
    const d = 1000 - w - l;

    return .{ w, d, l };
}

pub fn normalize(score: anytype, board: *const Board) @TypeOf(score) {
    if (root.evaluation.isMateScore(score) or root.evaluation.isTBScore(score)) {
        return score;
    }
    const a, _ = wdlParams(board);
    const scoref: f32 = @floatFromInt(score);
    return @round(100 * scoref / a);
}
