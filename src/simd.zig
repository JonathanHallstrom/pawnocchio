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

pub const Target = enum {
    avx512vbmi,
    avx512,
    avx2,
    aarch64,
    ssse3,
    sse2,
    fallback,
};

pub fn target(cpu: std.Target.Cpu) Target {
    if (cpu.has(.x86, .avx512vbmi)) {
        return .avx512vbmi;
    }
    if (cpu.has(.x86, .avx512f)) {
        return .avx512;
    }
    if (cpu.has(.x86, .avx2)) {
        return .avx2;
    }
    if (cpu.has(.aarch64, .neon)) {
        return .aarch64;
    }
    if (cpu.has(.x86, .ssse3)) {
        return .ssse3;
    }
    if (cpu.has(.x86, .sse2)) {
        return .sse2;
    }
    return .fallback;
}

pub fn parseTarget(name: []const u8) ?Target {
    return std.meta.stringToEnum(Target, name);
}

pub fn hasPext(cpu: std.Target.Cpu) bool {
    if (cpu.arch != .x86_64 and cpu.arch != .x86) return false;
    const llvm_name = cpu.model.llvm_name orelse "";
    return std.Target.x86.featureSetHas(cpu.model.features, .bmi2) and
        !std.mem.eql(u8, "znver1", llvm_name) and
        !std.mem.eql(u8, "znver2", llvm_name);
}

pub const TARGET = target(@import("builtin").cpu);

pub const HAS_PEXT = hasPext(@import("builtin").cpu);

pub fn vecBytes(comptime cpu: std.Target.Cpu) comptime_int {
    return switch (target(cpu)) {
        .avx512vbmi, .avx512 => 64,
        .avx2 => 32,
        .aarch64, .ssse3, .sse2 => 16,
        .fallback => if (cpu.arch.endian() != .little) 4 else std.simd.suggestVectorLengthForCpu(u8, cpu) orelse 4,
    };
}

const VEC_BYTES: comptime_int = vecBytes(@import("builtin").cpu);

pub fn vecSize(comptime T: type) comptime_int {
    return VEC_BYTES / @sizeOf(T);
}

const HAS_AVX512_VNNI = @import("builtin").cpu.has(.x86, .avx512vnni);
const HAS_AVX_VNNI = @import("builtin").cpu.has(.x86, .avxvnni);
const HAS_VNNI = HAS_AVX512_VNNI or HAS_AVX_VNNI;
const HAS_I8MM = @import("builtin").cpu.has(.aarch64, .i8mm);

const x86 = @import("simd/x86.zig");
const avx512 = @import("simd/avx512.zig");
const neon = @import("simd/neon.zig");
const fallback = @import("simd/fallback.zig");

pub fn Vector(comptime T: type) type {
    return @Vector(vecSize(T), T);
}

pub fn MaskInt(comptime V: type) type {
    return std.meta.Int(.unsigned, @typeInfo(V).vector.len);
}

pub fn maddubs(u: Vector(u8), i: Vector(i8)) Vector(i16) {
    return switch (TARGET) {
        .avx512vbmi, .avx512, .avx2, .ssse3 => x86.maddubs(u, i),
        .aarch64, .sse2, .fallback => fallback.maddubs(u, i),
    };
}

pub fn maddwd(a: Vector(i16), b: Vector(i16)) Vector(i32) {
    return switch (TARGET) {
        .avx512vbmi, .avx512, .avx2, .ssse3, .sse2 => x86.maddwd(a, b),
        .aarch64, .fallback => fallback.maddwd(a, b),
    };
}

pub fn mulhi(a: Vector(i16), b: Vector(i16)) Vector(i16) {
    return switch (TARGET) {
        .avx512vbmi, .avx512, .avx2, .ssse3, .sse2 => x86.mulhi(a, b),
        .aarch64, .fallback => fallback.mulhi(a, b),
    };
}

pub fn mulhiShift(a: Vector(i16), b: Vector(i16), comptime shift: anytype) Vector(i16) {
    return switch (TARGET) {
        .aarch64 => neon.mulhiShift(a, b, shift),
        else => mulhi(a << @splat(shift), b),
    };
}

pub fn packus(a: Vector(i16), b: Vector(i16)) Vector(u8) {
    return switch (TARGET) {
        .avx512vbmi, .avx512, .avx2, .ssse3, .sse2 => x86.packus(a, b),
        .aarch64, .fallback => fallback.packus(a, b),
    };
}

pub fn dpbusd(sum: Vector(i32), u: Vector(u8), i: Vector(i8)) Vector(i32) {
    if (HAS_VNNI) {
        return x86.dpbusd(sum, u, i);
    }
    if (HAS_I8MM) {
        return neon.usdot(sum, u, i);
    }
    return sum + maddwd(maddubs(u, i), @splat(1));
}

pub fn dpbusdx2(
    sum: Vector(i32),
    u_1: Vector(u8),
    i_1: Vector(i8),
    u_2: Vector(u8),
    i_2: Vector(i8),
) Vector(i32) {
    if (HAS_VNNI or HAS_I8MM) {
        return dpbusd(dpbusd(sum, u_1, i_1), u_2, i_2);
    }
    return switch (TARGET) {
        .avx512vbmi, .avx512, .avx2, .aarch64, .ssse3, .sse2, .fallback => sum + maddwd(maddubs(u_1, i_1) + maddubs(u_2, i_2), @splat(1)),
    };
}

pub const vpshufbMask = avx512.vpshufbMask;
pub const vpermb = avx512.vpermb;
pub const vpcompress = avx512.vpcompress;
pub const pshufb = x86.pshufb;
pub const tbl1 = neon.tbl1;
pub const tbl4 = neon.tbl4;

pub fn loadMasked(comptime T: type, comptime N: usize, ptr: [*]const T, mask: std.meta.Int(.unsigned, N)) @Vector(N, T) {
    const V = @Vector(N, T);
    const zero: V = @splat(0);
    const mask_vec: @Vector(N, bool) = @bitCast(mask);
    const len = std.fmt.comptimePrint("{d}", .{N});
    const bits = std.fmt.comptimePrint("{d}", .{@bitSizeOf(T)});
    return @extern(*const fn (@Vector(N, bool), [*]const T, i32, V) callconv(.c) V, .{
        .name = "llvm.masked.load.v" ++ len ++ "i" ++ bits ++ ".p0",
    }).*(mask_vec, ptr, @alignOf(T), zero);
}

pub fn loadN(comptime T: type, comptime N: usize, ptr: [*]const T, n: usize) @Vector(N, T) {
    return loadMasked(T, N, ptr, prefixMask(N, n));
}

pub fn prefixMask(
    comptime N: usize,
    n: usize,
) std.meta.Int(.unsigned, N) {
    const M: std.meta.Int(.unsigned, N) = (1 << N) - 1;
    if (n >= N) {
        @branchHint(.unpredictable);
        return M;
    }
    return ~(M << @intCast(n));
}

fn finalIdx(comptime N: usize, n: usize) usize {
    var i: usize = 0;
    while (i + N < n) {
        i += N;
    }
    return i;
}

pub fn ChunkIter(comptime T: type, comptime N: usize) type {
    return struct {
        ptr: [*]const T,
        len: usize,
        i: usize = 0,

        pub const Tail = struct {
            data: @Vector(N, T),
            mask: @Vector(N, bool),

            pub inline fn select(self: @This(), fill: @Vector(N, T)) @Vector(N, T) {
                return @select(T, self.mask, self.data, fill);
            }
        };

        pub inline fn init(s: []const T) @This() {
            return .{ .ptr = s.ptr, .len = s.len };
        }

        pub inline fn isEmpty(self: @This()) bool {
            return self.i >= self.len;
        }

        pub inline fn hasFullChunk(self: *@This()) bool {
            return self.i + N < self.len;
        }

        pub fn preventUnroll(self: @This()) void {
            std.mem.doNotOptimizeAway(self.i * @sizeOf(T));
        }

        inline fn chunk(self: @This()) @Vector(N, T) {
            return self.ptr[self.i..][0..N].*;
        }

        pub inline fn fullChunk(self: *@This()) ?@Vector(N, T) {
            if (!self.hasFullChunk()) return null;
            defer self.i += N;
            return self.chunk();
        }

        pub inline fn tail(self: *@This()) Tail {
            const last_idx = finalIdx(N, self.len);
            const data: @Vector(N, T) = self.ptr[last_idx..][0..N].*;
            return .{ .data = data, .mask = @bitCast(prefixMask(N, self.len - last_idx)) };
        }

        pub inline fn tailSafe(self: *@This()) Tail {
            const last_idx = finalIdx(N, self.len);
            const remaining = self.len - last_idx;
            const data: @Vector(N, T) = loadN(T, N, self.ptr + last_idx, remaining);
            return .{ .data = data, .mask = @bitCast(prefixMask(N, self.len - last_idx)) };
        }
    };
}

pub fn IndexedChunkIter(comptime T: type, comptime N: usize) type {
    return struct {
        const Index = if (@typeInfo(T) == .int) T else std.meta.Int(.unsigned, @bitSizeOf(T));

        inner: ChunkIter(T, N),
        indices: @Vector(N, Index) = std.simd.iota(i32, N),

        pub inline fn init(s: []const T) @This() {
            return .{ .inner = .init(s) };
        }

        pub const Chunk = struct {
            data: @Vector(N, T),
            indices: @Vector(N, Index),
            mask: @Vector(N, bool),

            pub inline fn select(self: @This(), fill: @Vector(N, T)) @Vector(N, T) {
                return @select(T, self.mask, self.data, fill);
            }
        };

        pub inline fn isEmpty(self: @This()) bool {
            return self.inner.isEmpty();
        }

        pub inline fn hasFullChunk(self: @This()) bool {
            return self.inner.hasFullChunk();
        }

        pub inline fn preventUnroll(self: @This()) void {
            self.inner.preventUnroll();
        }

        pub inline fn fullChunk(self: *@This()) ?struct {
            data: @Vector(N, T),
            indices: @Vector(N, Index),
        } {
            const data = self.inner.fullChunk() orelse return null;
            defer self.indices += @splat(N);
            return .{
                .data = data,
                .indices = self.indices,
            };
        }

        inline fn maskedChunkImpl(self: @This()) Chunk {
            const limit: @Vector(N, Index) = @splat(@intCast(self.inner.len));
            const mask: @Vector(N, bool) = self.indices < limit;
            return .{ .data = self.inner.chunk(), .indices = self.indices, .mask = mask };
        }

        pub inline fn maskedChunkUnchecked(self: *@This()) Chunk {
            defer self.inner.i += N;
            defer self.indices += @splat(N);
            const res = self.maskedChunkImpl();
            return res;
        }

        pub inline fn maskedChunk(self: *@This()) ?Chunk {
            if (self.isEmpty()) return null;
            return self.maskedChunkUnchecked();
        }

        pub inline fn tail(self: *@This()) Chunk {
            return self.maskedChunkImpl();
        }

        pub inline fn tailSafe(self: *@This()) Chunk {
            const remaining = self.inner.len - self.inner.i;
            const U = std.meta.Int(.unsigned, N);
            const W = std.meta.Int(.unsigned, 2 * N);
            const mask_int: U = @truncate(~(~@as(W, 0) << @intCast(remaining)));
            const data: @Vector(N, T) = loadN(T, N, self.inner.ptr + self.inner.i, remaining);
            return .{ .data = data, .indices = self.indices, .mask = @bitCast(mask_int) };
        }
    };
}

pub fn ReverseChunkIter(comptime T: type, comptime N: usize) type {
    return struct {
        ptr: [*]const T,
        len: usize,
        i: usize,

        pub const Chunk = struct {
            data: @Vector(N, T),
            mask: @Vector(N, bool),
            start: usize,

            pub inline fn select(self: @This(), fill: @Vector(N, T)) @Vector(N, T) {
                return @select(T, self.mask, self.data, fill);
            }
        };

        pub inline fn init(s: []const T) @This() {
            return .{ .ptr = s.ptr, .len = s.len, .i = finalIdx(N, s.len) };
        }

        pub inline fn isEmpty(self: @This()) bool {
            return self.len == 0;
        }

        pub inline fn maskedChunk(self: *@This()) ?Chunk {
            if (self.len == 0) return null;

            const start = self.i;
            const data: @Vector(N, T) = self.ptr[start..][0..N].*;
            const valid = self.len - start;
            const mask: @Vector(N, bool) = if (valid >= N) @splat(true) else @bitCast(prefixMask(N, valid));

            if (start >= N) {
                self.i = start - N;
                self.len = start;
            } else {
                self.len = 0;
            }

            return .{ .data = data, .mask = mask, .start = start };
        }
    };
}

pub fn chunkIter(comptime T: type, comptime N: usize, slice: []const T) ChunkIter(T, N) {
    return .init(slice);
}

pub fn indexedChunkIter(comptime T: type, comptime N: usize, slice: []const T) IndexedChunkIter(T, N) {
    return .init(slice);
}

pub fn reverseChunkIter(comptime T: type, comptime N: usize, slice: []const T) ReverseChunkIter(T, N) {
    return .init(slice);
}
