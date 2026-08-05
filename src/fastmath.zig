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

const M_BITS = std.math.floatMantissaBits(f32);
const M_MASK = (1 << M_BITS) - 1;

const E_BIAS = std.math.floatExponentMax(f32);

pub fn exp(x: f32) f32 {
    const xc = std.math.clamp(x, -40, 40);
    const k = @round(xc * (1.0 / std.math.ln2));
    const r = @mulAdd(f32, -k, std.math.ln2, xc);
    var p: f32 = 0;
    inline for (.{
        1.0 / 120.0,
        1.0 / 24.0,
        1.0 / 6.0,
        0.5,
        1.0,
        1.0,
    }) |c| p = @mulAdd(f32, p, r, c);
    const ki: i32 = @intFromFloat(k);
    const scale: f32 = @bitCast(ki + E_BIAS << M_BITS);
    return p * scale;
}

pub fn log(x: f32) f32 {
    const bits: i32 = @bitCast(x);
    var e: f32 = @floatFromInt((bits >> M_BITS) - E_BIAS);
    var m: f32 = @bitCast((bits & M_MASK) | (E_BIAS << M_BITS));
    if (m > std.math.sqrt2) {
        m *= 0.5;
        e += 1.0;
    }
    const s = (m - 1) / (m + 1);
    const s2 = s * s;
    var t: f32 = 0;
    inline for (.{
        1.0 / 9.0,
        1.0 / 7.0,
        1.0 / 5.0,
        1.0 / 3.0,
        1.0,
    }) |c| t = @mulAdd(f32, t, s2, c);
    return @mulAdd(f32, e, std.math.ln2, 2 * s * t);
}

pub fn pow(a: f32, b: f32) f32 {
    return exp(b * log(a));
}

pub fn sigmoid(x: f32) f32 {
    @setFloatMode(.optimized);
    return 1 / (1 + exp(-x));
}

pub fn tanh(x: f32) f32 {
    return 2 * sigmoid(2 * x) - 1;
}

pub fn sigmoidScaled(x: anytype, scale: f32) f32 {
    const xf: f32 = if (@typeInfo(@TypeOf(x)) == .int) @floatFromInt(x) else x;
    const x_scaled = xf / scale;
    return sigmoid(x_scaled);
}
