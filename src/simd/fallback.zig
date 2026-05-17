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
const simd = @import("../simd.zig");

pub fn maddubs(u: simd.vector(u8), i: simd.vector(i8)) simd.vector(i16) {
    const u_parts = std.simd.deinterlace(2, u);
    const i_parts = std.simd.deinterlace(2, i);
    const products_even = @as(simd.vector(i16), u_parts[0]) * @as(simd.vector(i16), i_parts[0]);
    const products_odd = @as(simd.vector(i16), u_parts[1]) * @as(simd.vector(i16), i_parts[1]);
    return products_even +| products_odd;
}

pub fn maddwd(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i32) {
    const a_parts = std.simd.deinterlace(2, a);
    const b_parts = std.simd.deinterlace(2, b);
    const products_even = @as(simd.vector(i32), a_parts[0]) * @as(simd.vector(i32), b_parts[0]);
    const products_odd = @as(simd.vector(i32), a_parts[1]) * @as(simd.vector(i32), b_parts[1]);
    return products_even + products_odd;
}

pub fn mulhi(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i16) {
    const Wide = @Vector(simd.vecSize(i16), i32);
    const products: Wide = @as(Wide, @intCast(a)) * @as(Wide, @intCast(b));
    return @as(simd.vector(i16), @intCast(products >> @as(Wide, @splat(16))));
}

pub fn packus(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(u8) {
    const zero: simd.vector(i16) = @splat(0);
    const a_packed: @Vector(simd.vecSize(i16), u8) = @intCast(@max(a, zero));
    const b_packed: @Vector(simd.vecSize(i16), u8) = @intCast(@max(b, zero));
    const halves: [2]@Vector(simd.vecSize(i16), u8) = .{ a_packed, b_packed };
    return @bitCast(halves);
}

pub fn loadN(
    comptime T: type,
    comptime N: usize,
    ptr: [*]const T,
    remaining: usize,
) @Vector(N, T) {
    comptime std.debug.assert(std.math.isPowerOfTwo(N));
    var buf: [N]T = @splat(0);
    var off: usize = 0;
    var n: usize = remaining;
    comptime var w = N;
    inline while (w >= 1) : (w /= 2) {
        if (n >= w) {
            buf[off..][0..w].* = ptr[off..][0..w].*;
            off += w;
            n -= w;
        }
    }
    return buf;
}
