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
const arch = @import("nnue_arch.zig");

pub const TARGET = arch.target(@import("builtin").cpu);

pub fn vecBytes(comptime cpu: std.Target.Cpu) comptime_int {
    return switch (arch.target(cpu)) {
        .avx512vnni, .avx512vbmi, .avx512 => 64,
        .avx2 => 32,
        .aarch64, .ssse3, .sse2 => 16,
        .fallback => if (cpu.arch.endian() != .little) 4 else std.simd.suggestVectorLengthForCpu(u8, cpu) orelse 4,
    };
}

const VEC_BYTES: comptime_int = vecBytes(@import("builtin").cpu);

pub fn vecSize(comptime T: type) comptime_int {
    return VEC_BYTES / @sizeOf(T);
}

const avx512 = @import("simd/avx512.zig");
const avx2 = @import("simd/avx2.zig");
const sse = @import("simd/sse.zig");
const neon = @import("simd/neon.zig");
const fallback = @import("simd/fallback.zig");

pub fn vector(comptime T: type) type {
    return @Vector(vecSize(T), T);
}

pub fn maskInt(comptime V: type) type {
    return std.meta.Int(.unsigned, @typeInfo(V).vector.len);
}

pub fn maddubs(u: vector(u8), i: vector(i8)) vector(i16) {
    return switch (TARGET) {
        .avx512vnni, .avx512vbmi, .avx512 => avx512.maddubs(u, i),
        .avx2 => avx2.maddubs(u, i),
        .ssse3 => sse.maddubs(u, i),
        .aarch64 => neon.maddubs(u, i),
        .sse2, .fallback => fallback.maddubs(u, i),
    };
}

pub fn maddwd(a: vector(i16), b: vector(i16)) vector(i32) {
    return switch (TARGET) {
        .avx512vnni, .avx512vbmi, .avx512 => avx512.maddwd(a, b),
        .avx2 => avx2.maddwd(a, b),
        .ssse3, .sse2 => sse.maddwd(a, b),
        .aarch64 => neon.maddwd(a, b),
        .fallback => fallback.maddwd(a, b),
    };
}

pub fn mulhi(a: vector(i16), b: vector(i16)) vector(i16) {
    return switch (TARGET) {
        .avx512vnni, .avx512vbmi, .avx512 => avx512.mulhi(a, b),
        .avx2 => avx2.mulhi(a, b),
        .ssse3, .sse2 => sse.mulhi(a, b),
        .aarch64 => neon.mulhi(a, b),
        .fallback => fallback.mulhi(a, b),
    };
}

pub fn mulhiShift(a: vector(i16), b: vector(i16), comptime shift: anytype) vector(i16) {
    if (TARGET == .aarch64) {
        return neon.mulhiShift(a, b, shift);
    }
    return mulhi(a << @splat(shift), b);
}

pub fn packus(a: vector(i16), b: vector(i16)) vector(u8) {
    return switch (TARGET) {
        .avx512vnni, .avx512vbmi, .avx512 => avx512.packus(a, b),
        .avx2 => avx2.packus(a, b),
        .ssse3, .sse2 => sse.packus(a, b),
        .aarch64 => neon.packus(a, b),
        .fallback => fallback.packus(a, b),
    };
}

pub fn dpbusd(sum: vector(i32), u: vector(u8), i: vector(i8)) vector(i32) {
    return switch (TARGET) {
        .avx512vnni => avx512.dpbusd(sum, u, i),
        .avx512vbmi, .avx512, .avx2, .ssse3, .sse2, .fallback => sum + maddwd(maddubs(u, i), @splat(1)),
        .aarch64 => neon.dpbusd(sum, u, i),
    };
}

pub fn dpbusdx2(
    sum: vector(i32),
    u_1: vector(u8),
    i_1: vector(i8),
    u_2: vector(u8),
    i_2: vector(i8),
) vector(i32) {
    return switch (TARGET) {
        .avx512vnni => dpbusd(dpbusd(sum, u_1, i_1), u_2, i_2),
        .avx512vbmi, .avx512, .avx2, .aarch64, .ssse3, .sse2, .fallback => sum + maddwd(maddubs(u_1, i_1) + maddubs(u_2, i_2), @splat(1)),
    };
}

pub const vpcompressw = avx512.vpcompressw;
pub const vpshufbMask = avx512.vpshufbMask;
pub const vpcompressb = avx512.vpcompressb;
pub const vpermb = avx512.vpermb;

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
            const data: @Vector(N, T) = switch (TARGET) {
                .avx512vnni, .avx512vbmi, .avx512 => avx512.loadN(T, N, self.ptr + last_idx, remaining),
                else => fallback.loadN(T, N, self.ptr + last_idx, remaining),
            };
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
            const data: @Vector(N, T) = switch (TARGET) {
                .avx512vnni, .avx512vbmi, .avx512 => avx512.loadN(T, N, self.inner.ptr + self.inner.i, remaining),
                else => fallback.loadN(T, N, self.inner.ptr + self.inner.i, remaining),
            };
            return .{ .data = data, .indices = self.indices, .mask = @bitCast(mask_int) };
        }
    };
}

pub fn chunkIter(comptime T: type, comptime N: usize, slice: []const T) ChunkIter(T, N) {
    return .init(slice);
}

pub fn indexedChunkIter(comptime T: type, comptime N: usize, slice: []const T) IndexedChunkIter(T, N) {
    return .init(slice);
}
