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

pub const Inputs = enum {
    eval_only,
    material,
    material_fullmove,
};

const INPUTS: Inputs = .material_fullmove;
const DEGREE = 2;

pub fn Model(comptime inputs: Inputs, comptime degree: usize) type {
    const terms = switch (inputs) {
        .eval_only => 1,
        .material => degree + 1,
        .material_fullmove => (degree + 1) * (degree + 2) / 2,
    };
    return struct {
        pub const COEFFICIENT_COUNT = terms;
        pub const Coefficients = [terms]f32;

        fn basis(material: f32, fullmove: f32) Coefficients {
            var result: Coefficients = undefined;
            switch (inputs) {
                .eval_only => result[0] = 1,
                .material => {
                    const m = std.math.clamp(material, 17, 78) / 58;
                    result[0] = 1;
                    for (1..terms) |i| result[i] = result[i - 1] * m;
                },
                .material_fullmove => {
                    const m = std.math.clamp(material, 17, 78) / 58;
                    const f = std.math.clamp(fullmove, 1, 120) / 32;
                    var m_powers: [degree + 1]f32 = undefined;
                    var f_powers: [degree + 1]f32 = undefined;
                    m_powers[0] = 1;
                    f_powers[0] = 1;
                    for (1..degree + 1) |i| {
                        m_powers[i] = m_powers[i - 1] * m;
                        f_powers[i] = f_powers[i - 1] * f;
                    }
                    var i: usize = 0;
                    for (0..degree + 1) |total_degree| {
                        for (0..total_degree + 1) |m_degree| {
                            result[i] = m_powers[m_degree] * f_powers[total_degree - m_degree];
                            i += 1;
                        }
                    }
                },
            }
            return result;
        }

        pub fn params(
            a_coefficients: *const Coefficients,
            b_coefficients: *const Coefficients,
            material: f32,
            fullmove: f32,
        ) struct { f32, f32 } {
            var a: f32 = 0;
            var b: f32 = 0;
            for (a_coefficients, b_coefficients, basis(material, fullmove)) |ca, cb, value| {
                a += ca * value;
                b += cb * value;
            }
            return .{ a, b };
        }
    };
}

const EngineModel = Model(INPUTS, DEGREE);

const A_COEFFICIENTS: EngineModel.Coefficients = .{
    237.12953685, 44.90698791, 91.06850910, -7.15217681, -36.74902578, -39.99297198,
};
const B_COEFFICIENTS: EngineModel.Coefficients = .{
    94.99523877, -50.60915179, -55.02231007, 11.49863200, 4.21120174, 43.89888051,
};

fn wdlParams(board: *const Board) struct { f32, f32 } {
    const material: f32 = @floatFromInt(board.classicalMaterial());
    const fullmove: f32 = @floatFromInt(board.fullmove);
    return EngineModel.params(&A_COEFFICIENTS, &B_COEFFICIENTS, material, fullmove);
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
