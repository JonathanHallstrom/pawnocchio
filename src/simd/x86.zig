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

pub fn maddubs(u: simd.vector(u8), i: simd.vector(i8)) simd.vector(i16) {
    return @extern(*const fn (simd.vector(u8), simd.vector(i8)) callconv(.c) simd.vector(i16), .{ .name = switch (simd.vecSize(u8)) {
        64 => "llvm.x86.avx512.pmaddubs.w.512",
        32 => "llvm.x86.avx2.pmadd.ub.sw",
        16 => "llvm.x86.ssse3.pmadd.ub.sw.128",
        else => unreachable,
    } }).*(u, i);
}

pub fn maddwd(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i32) {
    return @extern(*const fn (simd.vector(i16), simd.vector(i16)) callconv(.c) simd.vector(i32), .{ .name = switch (simd.vecSize(i16)) {
        32 => "llvm.x86.avx512.pmaddw.d.512",
        16 => "llvm.x86.avx2.pmadd.wd",
        8 => "llvm.x86.sse2.pmadd.wd",
        else => unreachable,
    } }).*(a, b);
}

pub fn mulhi(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i16) {
    return @extern(*const fn (simd.vector(i16), simd.vector(i16)) callconv(.c) simd.vector(i16), .{ .name = switch (simd.vecSize(i16)) {
        32 => "llvm.x86.avx512.pmulh.w.512",
        16 => "llvm.x86.avx2.pmulh.w",
        8 => "llvm.x86.sse2.pmulh.w",
        else => unreachable,
    } }).*(a, b);
}

pub fn packus(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(u8) {
    return @extern(*const fn (simd.vector(i16), simd.vector(i16)) callconv(.c) simd.vector(u8), .{ .name = switch (simd.vecSize(i16)) {
        32 => "llvm.x86.avx512.packuswb.512",
        16 => "llvm.x86.avx2.packuswb",
        8 => "llvm.x86.sse2.packuswb.128",
        else => unreachable,
    } }).*(a, b);
}
