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
    const u_lo: @Vector(8, u16) = asm (
        \\ushll %[ret].8h, %[v].8b, #0
        : [ret] "=w" (-> @Vector(8, u16)),
        : [v] "w" (u),
    );
    const u_hi: @Vector(8, u16) = asm (
        \\ushll2 %[ret].8h, %[v].16b, #0
        : [ret] "=w" (-> @Vector(8, u16)),
        : [v] "w" (u),
    );
    const i_lo: @Vector(8, i16) = asm (
        \\sshll %[ret].8h, %[v].8b, #0
        : [ret] "=w" (-> @Vector(8, i16)),
        : [v] "w" (i),
    );
    const i_hi: @Vector(8, i16) = asm (
        \\sshll2 %[ret].8h, %[v].16b, #0
        : [ret] "=w" (-> @Vector(8, i16)),
        : [v] "w" (i),
    );
    const prod_lo: @Vector(8, i16) = @as(@Vector(8, i16), @bitCast(u_lo)) * i_lo;
    const prod_hi: @Vector(8, i16) = @as(@Vector(8, i16), @bitCast(u_hi)) * i_hi;
    return asm (
        \\addp %[ret].8h, %[lo].8h, %[hi].8h
        : [ret] "=w" (-> simd.vector(i16)),
        : [lo] "w" (prod_lo),
          [hi] "w" (prod_hi),
    );
}

pub fn maddwd(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i32) {
    const lo: @Vector(4, i32) = asm (
        \\smull %[ret].4s, %[a].4h, %[b].4h
        : [ret] "=w" (-> @Vector(4, i32)),
        : [a] "w" (a),
          [b] "w" (b),
    );
    const hi: @Vector(4, i32) = asm (
        \\smull2 %[ret].4s, %[a].8h, %[b].8h
        : [ret] "=w" (-> @Vector(4, i32)),
        : [a] "w" (a),
          [b] "w" (b),
    );
    return asm (
        \\addp %[ret].4s, %[lo].4s, %[hi].4s
        : [ret] "=w" (-> simd.vector(i32)),
        : [lo] "w" (lo),
          [hi] "w" (hi),
    );
}

pub fn mulhi(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(i16) {
    const lo: @Vector(4, i32) = asm (
        \\smull %[ret].4s, %[a].4h, %[b].4h
        : [ret] "=w" (-> @Vector(4, i32)),
        : [a] "w" (a),
          [b] "w" (b),
    );
    const hi: @Vector(4, i32) = asm (
        \\smull2 %[ret].4s, %[a].8h, %[b].8h
        : [ret] "=w" (-> @Vector(4, i32)),
        : [a] "w" (a),
          [b] "w" (b),
    );
    const lo_as_i16: simd.vector(i16) = @bitCast(lo);
    const hi_as_i16: simd.vector(i16) = @bitCast(hi);
    return asm (
        \\uzp2 %[ret].8h, %[lo].8h, %[hi].8h
        : [ret] "=w" (-> simd.vector(i16)),
        : [lo] "w" (lo_as_i16),
          [hi] "w" (hi_as_i16),
    );
}

pub fn mulhiShift(a: simd.vector(i16), b: simd.vector(i16), comptime shift: anytype) simd.vector(i16) {
    const shifted = a << @splat(shift - 1);
    return asm (
        \\sqdmulh %[ret].8h, %[a].8h, %[b].8h
        : [ret] "=w" (-> simd.vector(i16)),
        : [a] "w" (shifted),
          [b] "w" (b),
    );
}

pub fn packus(a: simd.vector(i16), b: simd.vector(i16)) simd.vector(u8) {
    const lo: @Vector(8, u8) = asm (
        \\sqxtun %[ret].8b, %[v].8h
        : [ret] "=w" (-> @Vector(8, u8)),
        : [v] "w" (a),
    );
    return asm (
        \\sqxtun2 %[ret].16b, %[v].8h
        : [ret] "=w" (-> simd.vector(u8)),
        : [v] "w" (b),
          [_] "0" (lo),
    );
}

pub fn dpbusd(sum: simd.vector(i32), u: simd.vector(u8), i: simd.vector(i8)) simd.vector(i32) {
    const u_i8: simd.vector(i8) = @bitCast(u);
    const lo: @Vector(8, i16) = asm (
        \\smull %[ret].8h, %[u].8b, %[i].8b
        : [ret] "=w" (-> @Vector(8, i16)),
        : [u] "w" (u_i8),
          [i] "w" (i),
    );
    const hi: @Vector(8, i16) = asm (
        \\smull2 %[ret].8h, %[u].16b, %[i].16b
        : [ret] "=w" (-> @Vector(8, i16)),
        : [u] "w" (u_i8),
          [i] "w" (i),
    );
    const pairwise: @Vector(8, i16) = asm (
        \\addp %[ret].8h, %[lo].8h, %[hi].8h
        : [ret] "=w" (-> @Vector(8, i16)),
        : [lo] "w" (lo),
          [hi] "w" (hi),
    );
    return asm (
        \\sadalp %[s].4s, %[p].8h
        : [s] "=w" (-> simd.vector(i32)),
        : [p] "w" (pairwise),
          [_] "0" (sum),
    );
}
