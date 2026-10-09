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
const root = @import("root");

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

pub fn hasPext(cpu: std.Target.Cpu) bool {
    if (cpu.arch != .x86_64 and cpu.arch != .x86) return false;
    const llvm_name = cpu.model.llvm_name orelse "";
    return cpu.has(.x86, .bmi2) and
        !std.mem.eql(u8, "znver1", llvm_name) and
        !std.mem.eql(u8, "znver2", llvm_name);
}

pub const TARGET = target(@import("builtin").target.cpu);

pub const INTRINSIC_CALLCONV: std.lang.CallingConvention = if (@import("builtin").target.cpu.arch == .x86_64)
    .{ .x86_64_sysv = .{} }
else
    .c;

pub const HAS_PEXT = hasPext(@import("builtin").target.cpu);

pub fn vecBytes(comptime cpu: std.Target.Cpu) comptime_int {
    return switch (target(cpu)) {
        .avx512vbmi, .avx512 => 64,
        .avx2 => 32,
        .aarch64, .ssse3, .sse2 => 16,
        .fallback => std.simd.suggestVectorLengthForCpu(u8, cpu) orelse 4,
    };
}

const VEC_BYTES: comptime_int = vecBytes(@import("builtin").target.cpu);

pub fn vecSize(comptime T: type) comptime_int {
    return VEC_BYTES / @sizeOf(T);
}

fn hasVnni(cpu: std.Target.Cpu) bool {
    return cpu.has(.x86, .avx512vnni) or cpu.has(.x86, .avxvnni);
}

fn hasI8mm(cpu: std.Target.Cpu) bool {
    return cpu.has(.aarch64, .i8mm);
}

const HAS_VNNI = hasVnni(@import("builtin").target.cpu);
const HAS_I8MM = hasI8mm(@import("builtin").target.cpu);
const HAS_DOTPROD = @import("builtin").target.cpu.has(.aarch64, .dotprod);
pub const HAS_VBMI2 = @import("builtin").target.cpu.has(.x86, .avx512vbmi2);
pub const HAS_AVX512 = @import("builtin").target.cpu.has(.x86, .avx512f);
pub const HAS_NT_STORES = switch (TARGET) {
    .avx512vbmi, .avx512, .avx2, .ssse3, .sse2 => true,
    .aarch64, .fallback => false,
};

const x86 = @import("simd/x86.zig");
const avx512 = @import("simd/avx512.zig");
const neon = @import("simd/neon.zig");
const fallback = @import("simd/fallback.zig");

pub fn Vector(comptime T: type) type {
    return @Vector(vecSize(T), T);
}

pub fn MaskInt(comptime V: type) type {
    return @Int(.unsigned, @typeInfo(V).vector.len);
}
pub inline fn maskInt(vec: anytype) MaskInt(@TypeOf(vec)) {
    return @bitCast(vec);
}

pub inline fn maskVec(comptime N: usize, bits: @Int(.unsigned, N)) @Vector(N, bool) {
    return @bitCast(bits);
}

pub inline fn prefixLaneMask(comptime N: usize, n: usize) @Vector(N, bool) {
    return maskVec(N, prefixMask(N, n));
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
    if (HAS_DOTPROD) {
        return neon.sdot(sum, @bitCast(u), i);
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
    return dpbusd(dpbusd(sum, u_1, i_1), u_2, i_2);
}

pub fn ntStore(comptime T: type, dst: *T, val: Vector(T)) void {
    return switch (TARGET) {
        .avx512vbmi, .avx512, .avx2, .ssse3, .sse2 => x86.ntStore(T, dst, val),
        .aarch64, .fallback => comptime unreachable,
    };
}

pub fn ntFence() void {
    return switch (TARGET) {
        .avx512vbmi, .avx512, .avx2, .ssse3, .sse2 => x86.ntFence(),
        .aarch64, .fallback => comptime unreachable,
    };
}

pub const vpshufbMask = avx512.vpshufbMask;
pub const vpermb = avx512.vpermb;
pub const vpcompress = avx512.vpcompress;
pub const pshufb = x86.pshufb;
pub const tbl1 = neon.tbl1;
pub const tbl4 = neon.tbl4;

pub fn prefixMask(
    comptime N: usize,
    n: usize,
) @Int(.unsigned, N) {
    const M: @Int(.unsigned, N) = (1 << N) - 1;
    if (n >= N) {
        @branchHint(.unpredictable);
        return M;
    }
    return ~(M << @intCast(n));
}

pub fn ChunkIter(comptime T: type, comptime N: usize) type {
    return struct {
        ptr: [*]const T,
        len: usize,
        i: usize = 0,

        pub inline fn init(s: []const T) @This() {
            return .{ .ptr = s.ptr, .len = s.len };
        }

        pub inline fn isEmpty(self: @This()) bool {
            return self.i >= self.len;
        }

        pub inline fn hasFullChunk(self: *@This()) bool {
            return self.i + N <= self.len;
        }

        inline fn chunk(self: @This()) @Vector(N, T) {
            return self.ptr[self.i..][0..N].*;
        }

        inline fn overlappingChunkUnchecked(self: *@This()) @Vector(N, T) {
            std.debug.assert(self.len >= N);
            defer self.i += N;
            return self.ptr[@min(self.i, self.len - N)..][0..N].*;
        }

        pub inline fn fullChunk(self: *@This()) ?@Vector(N, T) {
            if (!self.hasFullChunk()) return null;
            defer self.i += N;
            return self.chunk();
        }
    };
}

pub fn IndexedChunkIter(comptime T: type, comptime N: usize) type {
    return struct {
        const Index = if (@typeInfo(T) == .int) T else @Int(.unsigned, @bitSizeOf(T));

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

        pub inline fn tail(self: *@This()) Chunk {
            return self.maskedChunkImpl();
        }
    };
}

pub fn chunkIter(comptime T: type, comptime N: usize, slice: []const T) ChunkIter(T, N) {
    return .init(slice);
}

pub fn indexedChunkIter(comptime T: type, comptime N: usize, slice: []const T) IndexedChunkIter(T, N) {
    return .init(slice);
}

fn containsScalar(comptime T: type, haystack: []const T, needle: T) bool {
    var res = false;
    for (haystack) |h| {
        if (h == needle) {
            @branchHint(.unpredictable);
            res = true;
        }
    }
    return res;
}

pub fn containsSmall(comptime T: type, haystack: []const T, needle: T) bool {
    const N = vecSize(T);
    if (haystack.len < N or N <= 1) {
        @branchHint(.likely);
        return containsScalar(T, haystack, needle);
    }
    const Vi = @Vector(N, @Int(.signed, @bitSizeOf(T)));

    const V = Vector(T);
    const needle_vec: V = @splat(needle);

    var res_vec: Vi = @splat(0);

    var iter = chunkIter(T, N, haystack);
    while (!iter.isEmpty()) {
        const chunk = iter.overlappingChunkUnchecked();
        const eq: Vi = @intFromBool(chunk == needle_vec);
        res_vec |= -eq;
    }

    return @reduce(.Or, res_vec) != 0;
}

test maskInt {
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..64) |_| {
        var b: [vecSize(u8)]u8 = undefined;
        prng.fill(std.mem.asBytes(&b));
        const v: Vector(u8) = b;
        const ZERO: Vector(u8) = @splat(0);
        const mask = maskInt(v != ZERO);
        for (0..vecSize(u8)) |k| {
            const bit = mask >> @intCast(k) & 1 != 0;
            try std.testing.expectEqual(b[k] != 0, bit);
        }
    }
}

test maskVec {
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..64) |_| {
        const bits: MaskInt(Vector(u8)) = prng.random().int(MaskInt(Vector(u8)));
        const lanes: [vecSize(u8)]bool = maskVec(vecSize(u8), bits);
        for (0..vecSize(u8)) |k| {
            try std.testing.expectEqual(bits >> @intCast(k) & 1 != 0, lanes[k]);
        }
    }
}

test prefixLaneMask {
    @setEvalBranchQuota(1 << 16);
    inline for (0..vecSize(u8) + 1) |n| {
        const lanes: [vecSize(u8)]bool = prefixLaneMask(vecSize(u8), n);
        for (0..vecSize(u8)) |k| {
            try std.testing.expectEqual(k < n, lanes[k]);
        }
    }
}
