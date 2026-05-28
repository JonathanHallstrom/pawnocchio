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

pub fn dpbusd(sum: simd.vector(i32), u: simd.vector(u8), i: simd.vector(i8)) simd.vector(i32) {
    return @extern(*const fn (simd.vector(i32), simd.vector(u8), simd.vector(i8)) callconv(.c) simd.vector(i32), .{
        .name = "llvm.x86.avx512.vpdpbusd.512",
    }).*(sum, u, i);
}

pub fn vpermb(idx: anytype, src: @TypeOf(idx)) @TypeOf(idx) {
    const V = @TypeOf(idx);
    const L = @typeInfo(V).vector.len;
    return @extern(*const fn (V, V) callconv(.c) V, .{ .name = switch (L) {
        64 => "llvm.x86.avx512.permvar.qi.512",
        32 => "llvm.x86.avx512.permvar.qi.256",
        else => unreachable,
    } }).*(src, idx);
}

pub fn vpshufb(idx: @Vector(64, u8), src: @Vector(64, u8)) @Vector(64, u8) {
    return @extern(*const fn (@Vector(64, u8), @Vector(64, u8)) callconv(.c) @Vector(64, u8), .{
        .name = "llvm.x86.avx512.pshuf.b.512",
    }).*(src, idx);
}

pub fn vpshufbMask(idx: @Vector(64, u8), src: @Vector(64, u8), mask: u64) @Vector(64, u8) {
    const zero: @Vector(64, u8) = @splat(0);
    return @extern(*const fn (@Vector(64, u8), @Vector(64, u8), @Vector(64, u8), u64) callconv(.c) @Vector(64, u8), .{
        .name = "llvm.x86.avx512.mask.pshuf.b.512",
    }).*(src, idx, zero, mask);
}

pub fn vpcompress(src: anytype, mask: simd.maskInt(@TypeOf(src))) @TypeOf(src) {
    const V = @TypeOf(src);
    const info = @typeInfo(V).vector;
    const zero: V = @splat(0);
    const elem_char = switch (@bitSizeOf(info.child)) {
        8 => "b",
        16 => "w",
        32 => "d",
        64 => "q",
        else => unreachable,
    };
    const total_bits = std.fmt.comptimePrint("{d}", .{info.len * @bitSizeOf(info.child)});
    return @extern(*const fn (V, V, simd.maskInt(V)) callconv(.c) V, .{
        .name = "llvm.x86.avx512.mask.compress." ++ elem_char ++ "." ++ total_bits,
    }).*(src, zero, mask);
}
