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
    return asm ("pmaddubsw %[i], %[u]"
        : [ret] "=x" (-> simd.vector(i16)),
        : [u] "0" (u),
          [i] "x" (i),
    );
}

pub fn maddwd(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i32) {
    return asm ("pmaddwd %[b], %[a]"
        : [ret] "=x" (-> simd.vector(i32)),
        : [a] "0" (a),
          [b] "x" (b),
    );
}

pub fn mulhi(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i16) {
    return asm ("pmulhw %[b], %[a]"
        : [ret] "=x" (-> simd.vector(i16)),
        : [a] "0" (a),
          [b] "x" (b),
    );
}

pub fn packus(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(u8) {
    return asm ("packuswb %[b], %[a]"
        : [ret] "=x" (-> simd.vector(u8)),
        : [a] "0" (a),
          [b] "x" (b),
    );
}
