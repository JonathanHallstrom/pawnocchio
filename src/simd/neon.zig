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

const simd = @import("../simd.zig");

pub fn usdot(sum: simd.Vector(i32), u: simd.Vector(u8), i: simd.Vector(i8)) simd.Vector(i32) {
    return @extern(*const fn (simd.Vector(i32), simd.Vector(u8), simd.Vector(i8)) callconv(.c) simd.Vector(i32), .{
        .name = "llvm.aarch64.neon.usdot.v4i32.v16i8",
    }).*(sum, u, i);
}

fn sqdmulh(a: simd.Vector(i16), b: simd.Vector(i16)) simd.Vector(i16) {
    return @extern(*const fn (simd.Vector(i16), simd.Vector(i16)) callconv(.c) simd.Vector(i16), .{
        .name = "llvm.aarch64.neon.sqdmulh.v8i16",
    }).*(a, b);
}

pub fn mulhiShift(a: simd.Vector(i16), b: simd.Vector(i16), comptime shift: anytype) simd.Vector(i16) {
    const shifted = a << @splat(shift - 1);
    return sqdmulh(shifted, b);
}
