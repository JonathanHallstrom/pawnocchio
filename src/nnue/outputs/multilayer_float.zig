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
const arch = @import("../arch.zig");
const simd = @import("../../simd.zig");
const Board = @import("../../Board.zig");
const evaluation = @import("../../evaluation.zig");

const ALIGNMENT = 64;

pub const Weights = extern struct {
    l1w: [arch.OUTPUT_BUCKET_COUNT][arch.L2_SIZE * arch.L1_SIZE]i8 align(ALIGNMENT),
    l1b: [arch.OUTPUT_BUCKET_COUNT][arch.L2_SIZE]f32 align(ALIGNMENT),
    l2w: [arch.OUTPUT_BUCKET_COUNT][2 * arch.L3_SIZE * arch.L2_SIZE]f32 align(ALIGNMENT),
    l2b: [arch.OUTPUT_BUCKET_COUNT][arch.L3_SIZE]f32 align(ALIGNMENT),
    l3w: [arch.OUTPUT_BUCKET_COUNT][arch.L3_SIZE]f32 align(ALIGNMENT),
    l3b: [arch.OUTPUT_BUCKET_COUNT]f32 align(ALIGNMENT),

    fn l1wInference(self: *Weights) *align(ALIGNMENT) [arch.OUTPUT_BUCKET_COUNT][arch.L2_SIZE * arch.L1_SIZE]i8 {
        return @ptrCast(&self.l1w);
    }

    fn l1wDisk(self: *Weights) *align(ALIGNMENT) [arch.L1_SIZE][arch.OUTPUT_BUCKET_COUNT][arch.L2_SIZE]i8 {
        return @ptrCast(&self.l1w);
    }

    fn l2wInference(self: *Weights) *align(ALIGNMENT) [arch.OUTPUT_BUCKET_COUNT][2 * arch.L3_SIZE * arch.L2_SIZE]f32 {
        return @ptrCast(&self.l2w);
    }

    fn l2wDisk(self: *Weights) *align(ALIGNMENT) [2 * arch.L2_SIZE][arch.OUTPUT_BUCKET_COUNT][arch.L3_SIZE]f32 {
        return @ptrCast(&self.l2w);
    }

    fn l3wInference(self: *Weights) *align(ALIGNMENT) [arch.OUTPUT_BUCKET_COUNT][arch.L3_SIZE]f32 {
        return @ptrCast(&self.l3w);
    }

    fn l3wDisk(self: *Weights) *align(ALIGNMENT) [arch.L3_SIZE][arch.OUTPUT_BUCKET_COUNT]f32 {
        return @ptrCast(&self.l3w);
    }

    pub fn transform(self: *Weights, target_kind: simd.Target, endian: std.builtin.Endian) void {
        _ = target_kind;

        if (endian != .little) {
            inline for (.{
                &self.l1w,
                &self.l1b,
                &self.l2w,
                &self.l2b,
                &self.l3w,
                &self.l3b,
            }) |field| {
                arch.endianSwap(field);
            }
        }

        {
            const l1w_disk = self.l1wDisk().*;
            const l1w_inf = self.l1wInference();

            for (0..arch.OUTPUT_BUCKET_COUNT) |ob| {
                for (0..arch.L1_SIZE / 4) |i| {
                    for (0..arch.L2_SIZE) |j| {
                        for (0..4) |k| {
                            l1w_inf[ob][i * 4 * arch.L2_SIZE + j * 4 + k] = l1w_disk[i * 4 + k][ob][j];
                        }
                    }
                }
            }
        }

        {
            const l2w_disk = self.l2wDisk().*;
            const l2w_inf = self.l2wInference();

            for (0..arch.OUTPUT_BUCKET_COUNT) |ob| {
                for (0..2 * arch.L2_SIZE) |i| {
                    for (0..arch.L3_SIZE) |j| {
                        l2w_inf[ob][i * arch.L3_SIZE + j] = l2w_disk[i][ob][j];
                    }
                }
            }
        }

        {
            const l3w_disk = self.l3wDisk().*;
            const l3w_inf = self.l3wInference();

            for (0..arch.OUTPUT_BUCKET_COUNT) |ob| {
                for (0..arch.L3_SIZE) |i| {
                    l3w_inf[ob][i] = l3w_disk[i][ob];
                }
            }
        }
    }

    pub const SIZE_BYTES = @sizeOf(Weights);
    pub const WEIGHT_COUNT = blk: {
        var size = 0;
        var res = 0;
        for (std.meta.fields(Weights)) |field| {
            res += arch.totalElements(field.type);
            size += arch.totalElements(field.type) * @sizeOf(arch.UltimateChild(field.type));
        }
        std.debug.assert(std.mem.alignForward(usize, size, 64) == SIZE_BYTES);
        break :blk res;
    };
};

const L1_NORM: f32 = @as(f32, 1 << 9) / (@as(f32, arch.Q0) * @as(f32, arch.Q0) * @as(f32, arch.Q1));

pub fn forward(
    resolved: anytype,
    weights: *const arch.Weights,
    board: *const Board,
) i16 {
    const output_bucket: usize = arch.whichOutputBucket(@popCount(board.occupancy()));
    const ow = &weights.output;

    var activated_ft: [arch.L1_SIZE]u8 align(64) = undefined;
    {
        const items_per_iter: usize = simd.vecSize(i16) * 2;
        var i: usize = 0;
        const LO: simd.Vector(i16) = @splat(0);
        const HI: simd.Vector(i16) = @splat(arch.Q0);
        while (i < arch.L1_SIZE / 2) : (i += items_per_iter) {
            var s1 = resolved.read(.stm, i);
            var s2 = resolved.read(.stm, i + arch.L1_SIZE / 2);
            var s3 = resolved.read(.stm, i + simd.vecSize(i16));
            var s4 = resolved.read(.stm, i + simd.vecSize(i16) + arch.L1_SIZE / 2);

            var n1 = resolved.read(.ntm, i);
            var n2 = resolved.read(.ntm, i + arch.L1_SIZE / 2);
            var n3 = resolved.read(.ntm, i + simd.vecSize(i16));
            var n4 = resolved.read(.ntm, i + simd.vecSize(i16) + arch.L1_SIZE / 2);

            s1 = std.math.clamp(s1, LO, HI);
            s2 = @min(s2, HI);
            s3 = std.math.clamp(s3, LO, HI);
            s4 = @min(s4, HI);

            n1 = std.math.clamp(n1, LO, HI);
            n2 = @min(n2, HI);
            n3 = std.math.clamp(n3, LO, HI);
            n4 = @min(n4, HI);

            const sp1: simd.Vector(i16) = simd.mulhiShift(s1, s2, 7);
            const sp2: simd.Vector(i16) = simd.mulhiShift(s3, s4, 7);

            const np1: simd.Vector(i16) = simd.mulhiShift(n1, n2, 7);
            const np2: simd.Vector(i16) = simd.mulhiShift(n3, n4, 7);

            const p1: simd.Vector(u8) = simd.packus(sp1, sp2);
            const p2: simd.Vector(u8) = simd.packus(np1, np2);

            activated_ft[i..][0..simd.vecSize(u8)].* = p1;
            activated_ft[i + arch.L1_SIZE / 2 ..][0..simd.vecSize(u8)].* = p2;
        }
    }

    const L2_UNROLL = 4;
    var l1_intermediate: [arch.L2_SIZE / simd.vecSize(i32)][L2_UNROLL]simd.Vector(i32) = @splat(@splat(@splat(0)));
    {
        const w: [*]const i8 = &ow.l1w[output_bucket];
        const ft_i32: [*]i32 = @ptrCast(&activated_ft);

        const nonzero_indices: [arch.L1_SIZE / 4]u16, const num_nonzero_indices: usize = @import("../sparse.zig").findNonZeroIndices(&activated_ft);

        var i_outer: usize = 0;

        while (i_outer + 2 * L2_UNROLL <= num_nonzero_indices) : (i_outer += 2 * L2_UNROLL) {
            for (0..arch.L2_SIZE / simd.vecSize(i32)) |j| {
                for (0..L2_UNROLL) |i_inner| {
                    const i_1: u16 = nonzero_indices[i_outer + 2 * i_inner];
                    const i_2: u16 = nonzero_indices[i_outer + 2 * i_inner + 1];
                    const ft_vec_1: simd.Vector(u8) = @bitCast(@as(simd.Vector(i32), @splat(ft_i32[i_1])));
                    const ft_vec_2: simd.Vector(u8) = @bitCast(@as(simd.Vector(i32), @splat(ft_i32[i_2])));
                    l1_intermediate[j][i_inner] = simd.dpbusdx2(
                        l1_intermediate[j][i_inner],
                        ft_vec_1,
                        w[i_1 * arch.L2_SIZE * 4 + j * simd.vecSize(i8) ..][0..simd.vecSize(i8)].*,
                        ft_vec_2,
                        w[i_2 * arch.L2_SIZE * 4 + j * simd.vecSize(i8) ..][0..simd.vecSize(i8)].*,
                    );
                }
            }
        }
        while (i_outer < num_nonzero_indices) : (i_outer += 1) {
            const i = nonzero_indices[i_outer];
            const ft_vec: simd.Vector(u8) = @bitCast(@as(simd.Vector(i32), @splat(ft_i32[i])));

            for (0..arch.L2_SIZE / simd.vecSize(i32)) |j| {
                l1_intermediate[j][0] = simd.dpbusd(
                    l1_intermediate[j][0],
                    ft_vec,
                    w[i * arch.L2_SIZE * 4 + j * simd.vecSize(i8) ..][0..simd.vecSize(i8)].*,
                );
            }
        }
    }

    @setFloatMode(.optimized);
    const l1_dot: [arch.L2_SIZE]i32 = blk: {
        var reduced: [arch.L2_SIZE / simd.vecSize(i32)]simd.Vector(i32) = @splat(@splat(0));
        for (0..arch.L2_SIZE / simd.vecSize(i32)) |j| {
            for (l1_intermediate[j]) |e| reduced[j] += e;
        }
        break :blk @bitCast(reduced);
    };

    var l1_out: [2 * arch.L2_SIZE]f32 = undefined;
    {
        const l1b: *const [arch.L2_SIZE]f32 = &ow.l1b[output_bucket];
        for (0..arch.L2_SIZE) |j| {
            const l2res = @as(f32, @floatFromInt(l1_dot[j])) * L1_NORM + l1b[j];
            l1_out[j] = std.math.clamp(l2res, 0.0, 1.0);
            l1_out[j + arch.L2_SIZE] = std.math.clamp(l2res * l2res, 0.0, 1.0);
        }
    }

    var l3_neurons: [arch.L3_SIZE]f32 = ow.l2b[output_bucket];
    {
        const l2w: *const [2 * arch.L2_SIZE * arch.L3_SIZE]f32 = &ow.l2w[output_bucket];
        for (0..2 * arch.L2_SIZE) |i| {
            const a = l1_out[i];
            for (0..arch.L3_SIZE) |j| {
                l3_neurons[j] += a * l2w[i * arch.L3_SIZE + j];
            }
        }
    }

    var result: f32 = ow.l3b[output_bucket];
    {
        const l3w: *const [arch.L3_SIZE]f32 = &ow.l3w[output_bucket];
        for (0..arch.L3_SIZE) |j| {
            const a = std.math.clamp(l3_neurons[j], 0.0, 1.0);
            result += a * a * l3w[j];
        }
    }

    return evaluation.clampScore(@as(i32, @intFromFloat(result * @as(f32, @floatFromInt(arch.SCALE)))));
}
