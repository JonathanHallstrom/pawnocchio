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

pub const Target = simd.Target;
pub const target = simd.target;
pub const parseTarget = simd.parseTarget;

pub const inputs = @import("inputs/psq_threats.zig");
pub const outputs = @import("outputs/multilayer.zig");

pub const TOTAL_THREATS = 59808;
pub const TOTAL_PAWN_PAIRS = 96 * 95 / 2;

// [0..8) and [56..64) must be zero, cant have pawns there
pub const PP_MASK_BAND: [64]u64 = blk: {
    const A: u64 = 0x0101_0101_0101_0101;
    var table: [64]u64 = @splat(0);
    for (8..56) |sq| {
        const f = sq & 7;
        var m: u64 = A << f;
        if (f > 0) m |= A << (f - 1);
        if (f < 7) m |= A << (f + 1);
        table[sq] = m;
    }
    break :blk table;
};

pub const PP_MASK: [64]u64 = PP_MASK_BAND;

pub const Weights = extern struct {
    input: inputs.Weights,
    output: outputs.Weights,

    pub fn transform(self: *Weights, target_kind: simd.Target, endian: std.builtin.Endian) void {
        self.input.transform(target_kind, endian);
        self.output.transform(target_kind, endian);
    }

    pub const SIZE_BYTES = inputs.Weights.SIZE_BYTES + outputs.Weights.SIZE_BYTES;
    pub const WEIGHT_COUNT = inputs.Weights.WEIGHT_COUNT + outputs.Weights.WEIGHT_COUNT;

    comptime {
        if (@sizeOf(Weights) != SIZE_BYTES) @compileError("unexpected padding in Weights");
    }
};

pub fn parseEndian(name: []const u8) ?std.builtin.Endian {
    return std.meta.stringToEnum(std.builtin.Endian, name);
}

const LONGEST_PERMUTE_LEN = 8;

pub fn permuteOrderFor(target_kind: Target) []const u8 {
    return switch (target_kind) {
        .avx512vbmi, .avx512 => &.{ 0, 2, 4, 6, 1, 3, 5, 7 },
        .avx2 => &.{ 0, 2, 1, 3 },
        .aarch64, .ssse3, .sse2, .fallback => &.{},
    };
}

pub fn needsPermutingFor(target_kind: Target) bool {
    return switch (target_kind) {
        .avx512vbmi, .avx512, .avx2 => true,
        .aarch64, .ssse3, .sse2, .fallback => false,
    };
}

fn permuteBufferWithBlockBytes(comptime block_bytes: usize, ptr: anytype, order: anytype) void {
    const Block = [block_bytes]u8;
    const num_blocks = @sizeOf(@TypeOf(ptr.*)) / @sizeOf(Block);
    const vecs: *[num_blocks]Block = @ptrCast(ptr);

    var i: usize = 0;
    var weights: [LONGEST_PERMUTE_LEN]Block = undefined;
    while (i < num_blocks) : (i += order.len) {
        @memcpy(weights[0..order.len], vecs[i..][0..order.len]);
        for (0..order.len) |j| vecs[i + j] = weights[order[j]];
    }
}

pub fn permuteBufferI8(ptr: anytype, order: anytype) void {
    permuteBufferWithBlockBytes(8, ptr, order);
}

pub fn permuteBuffer(ptr: anytype, order: anytype) void {
    permuteBufferWithBlockBytes(16, ptr, order);
}

pub fn endianSwap(field: anytype) void {
    const T = UltimateChild(@TypeOf(field.*));
    const Int = std.meta.Int(.unsigned, @bitSizeOf(T));
    const p: *[totalElements(@TypeOf(field.*))]T = @ptrCast(field);
    for (p) |*e| {
        e.* = @bitCast(@byteSwap(@as(Int, @bitCast(e.*))));
    }
}

fn UltimateChild(comptime T: type) type {
    const info = @typeInfo(T);

    switch (info) {
        inline else => |i| {
            if (@hasField(@TypeOf(i), "child")) {
                return UltimateChild(i.child);
            }
            return T;
        },
    }
}

fn totalElements(comptime T: type) comptime_int {
    const info = @typeInfo(T);

    switch (info) {
        .array => |i| {
            return i.len * totalElements(i.child);
        },
        inline else => |i| {
            if (!@hasField(@TypeOf(i), "child")) {
                return 1;
            }
            return totalElements(i.child);
        },
    }
}

pub fn transformNetFor(target_kind: Target, endian: std.builtin.Endian, net: *Weights) void {
    net.transform(target_kind, endian);
}

pub const AccumulatorVec = @Vector(simd.vecSize(i16), i16);
pub const PSQTWeightVec = @Vector(simd.vecSize(i16), i16);
pub const ThreatWeightVec = @Vector(simd.vecSize(i16), i8);
pub const ACCUMULATOR_VECTOR_COUNT = L1_SIZE / simd.vecSize(i16);

pub const ACCUMULATOR_TILE = @min(ACCUMULATOR_VECTOR_COUNT, switch (simd.TARGET) {
    .avx512vbmi, .avx512 => 32,
    else => 8,
});

pub const RawAccumulator = [ACCUMULATOR_VECTOR_COUNT]AccumulatorVec;
pub const PSQTWeight = [ACCUMULATOR_VECTOR_COUNT]PSQTWeightVec;
pub const ThreatWeight = [ACCUMULATOR_VECTOR_COUNT]ThreatWeightVec;

pub const HORIZONTAL_MIRRORING = true;
pub const INPUT_BUCKET_COUNT: usize = 16;
pub const OUTPUT_BUCKET_COUNT: usize = 8;
pub const L1_SIZE: usize = 768;
pub const L2_SIZE: usize = 16;
pub const L3_SIZE: usize = 32;
pub const SCALE: i64 = 400;
pub const Q0 = 255;
pub const Q1 = 128;
pub const Q = 64;
pub const INPUT_BUCKET_LAYOUT: [64]u8 = .{
    0,  1,  2,  3,  3,  2,  1,  0,
    4,  5,  6,  7,  7,  6,  5,  4,
    8,  8,  9,  9,  9,  9,  8,  8,
    10, 10, 11, 11, 11, 11, 10, 10,
    12, 12, 13, 13, 13, 13, 12, 12,
    12, 12, 13, 13, 13, 13, 12, 12,
    14, 14, 15, 15, 15, 15, 14, 14,
    14, 14, 15, 15, 15, 15, 14, 14,
};

pub inline fn whichInputBucket(sq_idx: usize) usize {
    return @min(INPUT_BUCKET_COUNT - 1, INPUT_BUCKET_LAYOUT[sq_idx]);
}

pub inline fn whichOutputBucket(piece_count: usize) usize {
    const divisor = (32 + OUTPUT_BUCKET_COUNT - 1) / OUTPUT_BUCKET_COUNT;
    return @min(OUTPUT_BUCKET_COUNT - 1, (piece_count - 2) / divisor);
}
