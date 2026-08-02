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

fn everyOther(comptime T: type, comptime offset: comptime_int, v: simd.Vector(T)) @Vector(simd.vecSize(T) / 2, T) {
    const N = simd.vecSize(T) / 2;
    return switch (@import("builtin").cpu.arch.endian()) {
        .little => @shuffle(T, v, undefined, std.simd.iota(i32, N) *
            @as(@Vector(N, i32), @splat(2)) + @as(@Vector(N, i32), @splat(offset))),
        .big => blk: {
            const lanes: [simd.vecSize(T)]T = v;
            var out: [N]T = undefined;
            for (0..N) |k| out[k] = lanes[2 * k + offset];
            break :blk out;
        },
    };
}

pub fn maddubs(u: simd.Vector(u8), i: simd.Vector(i8)) simd.Vector(i16) {
    const products_even = @as(simd.Vector(i16), everyOther(u8, 0, u)) * @as(simd.Vector(i16), everyOther(i8, 0, i));
    const products_odd = @as(simd.Vector(i16), everyOther(u8, 1, u)) * @as(simd.Vector(i16), everyOther(i8, 1, i));
    return products_even +| products_odd;
}

pub fn maddwd(a: simd.Vector(i16), b: simd.Vector(i16)) simd.Vector(i32) {
    const products_even = @as(simd.Vector(i32), everyOther(i16, 0, a)) * @as(simd.Vector(i32), everyOther(i16, 0, b));
    const products_odd = @as(simd.Vector(i32), everyOther(i16, 1, a)) * @as(simd.Vector(i32), everyOther(i16, 1, b));
    return products_even + products_odd;
}

pub fn mulhi(a: simd.Vector(i16), b: simd.Vector(i16)) simd.Vector(i16) {
    const Wide = @Vector(simd.vecSize(i16), i32);
    const products: Wide = @as(Wide, @intCast(a)) * @as(Wide, @intCast(b));
    return @as(simd.Vector(i16), @intCast(products >> @as(Wide, @splat(16))));
}

pub fn packus(a: simd.Vector(i16), b: simd.Vector(i16)) simd.Vector(u8) {
    const zero: simd.Vector(i16) = @splat(0);
    const a_packed: @Vector(simd.vecSize(i16), u8) = @intCast(@max(a, zero));
    const b_packed: @Vector(simd.vecSize(i16), u8) = @intCast(@max(b, zero));
    const halves: [2]@Vector(simd.vecSize(i16), u8) = .{ a_packed, b_packed };
    return @bitCast(halves);
}
