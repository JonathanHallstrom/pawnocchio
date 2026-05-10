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

pub fn loadMasked(comptime T: type, comptime N: usize, ptr: [*]const T, mask: std.meta.Int(.unsigned, N)) @Vector(N, T) {
    const instr = comptime switch (@bitSizeOf([1]T)) {
        8 => "vmovdqu8",
        16 => "vmovdqu16",
        32 => "vmovdqu32",
        64 => "vmovdqu64",
        else => @compileError("unsupported element size"),
    };

    return asm (instr ++ " (%[ptr]), %[dst] {%[mask]} {z}"
        : [dst] "=x" (-> @Vector(N, T)),
        : [ptr] "r" (ptr),
          [mask] "{k1}" (mask),
    );
}

pub fn loadN(comptime T: type, comptime N: usize, ptr: [*]const T, n: usize) @Vector(N, T) {
    return loadMasked(T, N, ptr, simd.prefixMask(N, n));
}

pub fn maddubs(u: simd.vector(u8), i: simd.vector(i8)) simd.vector(i16) {
    return asm ("vpmaddubsw %[i], %[u], %[ret]"
        : [ret] "=x" (-> simd.vector(i16)),
        : [u] "x" (u),
          [i] "x" (i),
    );
}

pub fn maddwd(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i32) {
    return asm ("vpmaddwd %[b], %[a], %[ret]"
        : [ret] "=x" (-> simd.vector(i32)),
        : [a] "x" (a),
          [b] "x" (b),
    );
}

pub fn mulhi(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i16) {
    return asm ("vpmulhw %[b], %[a], %[ret]"
        : [ret] "=x" (-> simd.vector(i16)),
        : [a] "x" (a),
          [b] "x" (b),
    );
}

pub fn packus(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(u8) {
    return asm ("vpackuswb %[b], %[a], %[ret]"
        : [ret] "=x" (-> simd.vector(u8)),
        : [a] "x" (a),
          [b] "x" (b),
    );
}

pub fn dpbusd(sum: simd.vector(i32), u: simd.vector(u8), i: simd.vector(i8)) simd.vector(i32) {
    var s = sum;
    asm ("vpdpbusd %[i], %[u], %[s]"
        : [s] "+x" (s),
        : [u] "x" (u),
          [i] "x" (i),
    );
    return s;
}

pub fn vpcompressw(src: @Vector(32, u16), mask: u32) @Vector(32, u16) {
    return asm ("vpcompressw %[src], %[ret] {%[mask]} {z}"
        : [ret] "=x" (-> @Vector(32, u16)),
        : [src] "x" (src),
          [mask] "{k1}" (mask),
    );
}
