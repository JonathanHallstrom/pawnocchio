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
const root = @import("../root.zig");
const arch = @import("arch.zig");
const simd = root.simd;

const L1_SIZE = arch.L1_SIZE;

const NONZERO_INDICES = blk: {
    var res: [256]@Vector(8, u16) = @splat(@splat(0));

    @setEvalBranchQuota(256 * 8 * 2);
    for (0..256) |i| {
        var count = 0;
        for (0..8) |j| {
            if (i & 1 << j != 0) {
                res[i][count] = j;
                count += 1;
            }
        }
    }
    break :blk res;
};

fn getMask(vals: simd.Vector(u8)) simd.MaskInt(simd.Vector(i32)) {
    const as_i32: simd.Vector(i32) = @bitCast(vals);
    const zero: simd.Vector(i32) = @splat(0);
    return @bitCast(as_i32 != zero);
}

const USE_VBMI2_NNZ = simd.HAS_VBMI2 and simd.vecSize(i32) == 16 and L1_SIZE % 128 == 0;

pub inline fn findNonZeroIndices(
    ft: *align(64) const [L1_SIZE]u8,
) struct {
    [L1_SIZE / 4]u16,
    usize,
} {
    const impl = if (comptime USE_VBMI2_NNZ) findNonZeroIndicesVBMI2 else findNonZeroIndicesLUT;
    return impl(ft);
}

fn findNonZeroIndicesLUT(
    ft: *align(64) const [L1_SIZE]u8,
) struct {
    [L1_SIZE / 4]u16,
    usize,
} {
    var indices: [L1_SIZE / 4]u16 = undefined;
    var count: usize = 0;
    var base: @Vector(8, u16) = @splat(0);

    var i: usize = 0;
    const UNROLL = @max(1, 8 / simd.vecSize(i32));
    while (i < L1_SIZE) {
        var mask: u64 = 0;
        for (0..UNROLL) |j| {
            mask |= @as(u64, getMask(ft[i..][0..simd.vecSize(i8)].*)) << @intCast(j * simd.vecSize(i32));
            i += simd.vecSize(i8);
        }

        inline for (0..UNROLL * simd.vecSize(i32) / 8) |j| {
            const byte = mask >> (8 * j) & 0xff;

            const mask_indices = NONZERO_INDICES[byte];

            const actual_indices: [8]u16 = mask_indices + base;
            @memcpy(indices[count..][0..8], &actual_indices);

            count += @popCount(byte);
            base += @splat(8);
        }
    }

    return .{ indices, count };
}

fn findNonZeroIndicesVBMI2(
    ft: *align(64) const [L1_SIZE]u8,
) struct {
    [L1_SIZE / 4]u16,
    usize,
} {
    const ZERO: simd.Vector(i32) = @splat(0);
    const groups: [*]align(64) const simd.Vector(i32) = @ptrCast(ft);

    var indices: [L1_SIZE / 4]u16 = undefined;
    var count: usize = 0;

    inline for (0..L1_SIZE / 128) |i| {
        const lo: simd.MaskInt(simd.Vector(i32)) = @bitCast(groups[2 * i] != ZERO);
        const hi: simd.MaskInt(simd.Vector(i32)) = @bitCast(groups[2 * i + 1] != ZERO);
        const mask: simd.MaskInt(simd.Vector(u16)) = @as(u32, lo) | @as(u32, hi) << 16;

        const base: simd.Vector(u16) = std.simd.iota(u16, 32) + @as(simd.Vector(u16), @splat(32 * i));
        const compressed: [32]u16 = simd.vpcompress(base, mask);
        @memcpy(indices[count..][0..32], &compressed);

        count += @popCount(mask);
    }

    return .{ indices, count };
}
