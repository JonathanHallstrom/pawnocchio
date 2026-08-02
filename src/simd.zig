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
        .fallback => if (cpu.arch.endian() != .little) 8 else std.simd.suggestVectorLengthForCpu(u8, cpu) orelse 4,
    };
}

const VEC_BYTES: comptime_int = vecBytes(@import("builtin").cpu);

pub fn vecSize(comptime T: type) comptime_int {
    return VEC_BYTES / @sizeOf(T);
}

fn hasVnni(cpu: std.Target.Cpu) bool {
    return cpu.has(.x86, .avx512vnni) or cpu.has(.x86, .avxvnni);
}

fn hasI8mm(cpu: std.Target.Cpu) bool {
    return cpu.has(.aarch64, .i8mm);
}

pub fn fullDotProd(cpu: std.Target.Cpu) bool {
    return hasVnni(cpu) or hasI8mm(cpu);
}

const HAS_VNNI = hasVnni(@import("builtin").cpu);
const HAS_I8MM = hasI8mm(@import("builtin").cpu);
pub const HAS_VBMI2 = @import("builtin").cpu.has(.x86, .avx512vbmi2);
pub const HAS_AVX512 = @import("builtin").cpu.has(.x86, .avx512f);
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
    return std.meta.Int(.unsigned, @typeInfo(V).vector.len);
}
pub inline fn maskInt(vec: anytype) MaskInt(@TypeOf(vec)) {
    @setEvalBranchQuota(1 << 16);
    const M = MaskInt(@TypeOf(vec));
    if (@import("builtin").cpu.arch.endian() == .little) {
        return @bitCast(vec);
    }
    const N = @typeInfo(@TypeOf(vec)).vector.len;
    const lanes: [N]bool = vec;
    var res: M = 0;
    for (0..N) |k| {
        res |= @as(M, @intFromBool(lanes[k])) << @intCast(k);
    }
    return res;
}

pub inline fn maskVec(comptime N: usize, bits: std.meta.Int(.unsigned, N)) @Vector(N, bool) {
    @setEvalBranchQuota(1 << 16);
    if (@import("builtin").cpu.arch.endian() == .little) {
        return @bitCast(bits);
    }
    var res: [N]bool = undefined;
    inline for (0..N) |k| {
        res[k] = bits >> @intCast(k) & 1 != 0;
    }
    return res;
}

pub inline fn prefixLaneMask(comptime N: usize, n: usize) @Vector(N, bool) {
    if (@import("builtin").cpu.arch.endian() == .little) {
        return maskVec(N, prefixMask(N, n));
    }

    const idx: @Vector(N, usize) = std.simd.iota(usize, N);
    return idx < @as(@Vector(N, usize), @splat(n));
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

pub fn loadMasked(comptime T: type, comptime N: usize, ptr: [*]const T, mask: std.meta.Int(.unsigned, N)) @Vector(N, T) {
    const V = @Vector(N, T);
    const zero: V = @splat(0);
    if (@import("builtin").cpu.arch.endian() == .big) {
        var res: [N]T = @splat(0);
        for (0..N) |k| {
            if (mask >> @intCast(k) & 1 != 0) res[k] = ptr[k];
        }
        return res;
    }
    const mask_vec: @Vector(N, bool) = maskVec(N, mask);
    const len = std.fmt.comptimePrint("{d}", .{N});
    const bits = std.fmt.comptimePrint("{d}", .{@bitSizeOf(T)});
    return @extern(*const fn ([*]const T, i32, @Vector(N, bool), V) callconv(.c) V, .{
        .name = "llvm.masked.load.v" ++ len ++ "i" ++ bits ++ ".p0",
    }).*(ptr, @alignOf(T), mask_vec, zero);
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

        pub inline fn remainder(self: *@This()) []const T {
            return self.ptr[self.i..self.len];
        }

        pub inline fn tail(self: *@This()) Tail {
            const last_idx = finalIdx(N, self.len);
            const data: @Vector(N, T) = self.ptr[last_idx..][0..N].*;
            return .{ .data = data, .mask = prefixLaneMask(N, self.len - last_idx) };
        }

        pub inline fn tailSafe(self: *@This()) Tail {
            const last_idx = finalIdx(N, self.len);
            const remaining = self.len - last_idx;
            const data: @Vector(N, T) = loadN(T, N, self.ptr + last_idx, remaining);
            return .{ .data = data, .mask = prefixLaneMask(N, self.len - last_idx) };
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
            const data: @Vector(N, T) = loadN(T, N, self.inner.ptr + self.inner.i, remaining);
            return .{ .data = data, .indices = self.indices, .mask = prefixLaneMask(N, remaining) };
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
            const mask: @Vector(N, bool) = prefixLaneMask(N, valid);

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
    const Vi = @Vector(N, std.meta.Int(.signed, @bitSizeOf(T)));

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

test maddubs {
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..64) |_| {
        var ub: [vecSize(u8)]u8 = undefined;
        var ib: [vecSize(i8)]i8 = undefined;
        prng.fill(std.mem.asBytes(&ub));
        prng.fill(std.mem.asBytes(&ib));
        const got: [vecSize(i16)]i16 = maddubs(ub, ib);
        for (0..vecSize(i16)) |k| {
            const want = @as(i16, ub[2 * k]) * @as(i16, ib[2 * k]) +|
                @as(i16, ub[2 * k + 1]) * @as(i16, ib[2 * k + 1]);
            try std.testing.expectEqual(want, got[k]);
        }
    }
}

test maddwd {
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..64) |_| {
        var a: [vecSize(i16)]i16 = undefined;
        var b: [vecSize(i16)]i16 = undefined;
        prng.fill(std.mem.asBytes(&a));
        prng.fill(std.mem.asBytes(&b));
        const got: [vecSize(i32)]i32 = maddwd(a, b);
        for (0..vecSize(i32)) |k| {
            const want = @as(i32, a[2 * k]) * @as(i32, b[2 * k]) +
                @as(i32, a[2 * k + 1]) * @as(i32, b[2 * k + 1]);
            try std.testing.expectEqual(want, got[k]);
        }
    }
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
