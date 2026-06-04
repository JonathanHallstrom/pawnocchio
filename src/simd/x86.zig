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

pub fn pshufb(src: anytype, idx: @TypeOf(src)) @TypeOf(src) {
    const V = @TypeOf(src);
    return @extern(*const fn (V, V) callconv(.c) V, .{ .name = switch (@typeInfo(V).vector.len) {
        64 => "llvm.x86.avx512.pshuf.b.512",
        32 => "llvm.x86.avx2.pshuf.b",
        16 => "llvm.x86.ssse3.pshuf.b.128",
        else => unreachable,
    } }).*(src, idx);
}

pub fn maddubs(u: simd.Vector(u8), i: simd.Vector(i8)) simd.Vector(i16) {
    return @extern(*const fn (simd.Vector(u8), simd.Vector(i8)) callconv(.c) simd.Vector(i16), .{ .name = switch (simd.vecSize(u8)) {
        64 => "llvm.x86.avx512.pmaddubs.w.512",
        32 => "llvm.x86.avx2.pmadd.ub.sw",
        16 => "llvm.x86.ssse3.pmadd.ub.sw.128",
        else => unreachable,
    } }).*(u, i);
}

pub fn maddwd(a: simd.Vector(i16), b: simd.Vector(i16)) simd.Vector(i32) {
    return @extern(*const fn (simd.Vector(i16), simd.Vector(i16)) callconv(.c) simd.Vector(i32), .{ .name = switch (simd.vecSize(i16)) {
        32 => "llvm.x86.avx512.pmaddw.d.512",
        16 => "llvm.x86.avx2.pmadd.wd",
        8 => "llvm.x86.sse2.pmadd.wd",
        else => unreachable,
    } }).*(a, b);
}

pub fn mulhi(a: simd.Vector(i16), b: simd.Vector(i16)) simd.Vector(i16) {
    return @extern(*const fn (simd.Vector(i16), simd.Vector(i16)) callconv(.c) simd.Vector(i16), .{ .name = switch (simd.vecSize(i16)) {
        32 => "llvm.x86.avx512.pmulh.w.512",
        16 => "llvm.x86.avx2.pmulh.w",
        8 => "llvm.x86.sse2.pmulh.w",
        else => unreachable,
    } }).*(a, b);
}

pub fn packus(a: simd.Vector(i16), b: simd.Vector(i16)) simd.Vector(u8) {
    return @extern(*const fn (simd.Vector(i16), simd.Vector(i16)) callconv(.c) simd.Vector(u8), .{ .name = switch (simd.vecSize(i16)) {
        32 => "llvm.x86.avx512.packuswb.512",
        16 => "llvm.x86.avx2.packuswb",
        8 => "llvm.x86.sse2.packuswb.128",
        else => unreachable,
    } }).*(a, b);
}

pub fn dpbusd(sum: simd.Vector(i32), u: simd.Vector(u8), i: simd.Vector(i8)) simd.Vector(i32) {
    return @extern(*const fn (simd.Vector(i32), simd.Vector(i32), simd.Vector(i32)) callconv(.c) simd.Vector(i32), .{ .name = switch (simd.vecSize(i32)) {
        16 => "llvm.x86.avx512.vpdpbusd.512",
        8 => "llvm.x86.avx512.vpdpbusd.256",
        else => unreachable,
    } }).*(sum, @bitCast(u), @bitCast(i));
}
