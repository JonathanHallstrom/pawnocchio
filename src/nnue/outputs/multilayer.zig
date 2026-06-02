const std = @import("std");
const arch = @import("../arch.zig");
const simd = @import("../../simd.zig");
const Board = @import("../../Board.zig");
const evaluation = @import("../../evaluation.zig");

const ALIGNMENT = 64;

pub const Weights = extern struct {
    l1w: [arch.OUTPUT_BUCKET_COUNT][arch.L2_SIZE * arch.L1_SIZE]i8 align(ALIGNMENT),
    l1b: [arch.OUTPUT_BUCKET_COUNT][arch.L2_SIZE]i32 align(ALIGNMENT),
    l2w: [arch.OUTPUT_BUCKET_COUNT][2 * arch.L3_SIZE * arch.L2_SIZE]i32 align(ALIGNMENT),
    l2b: [arch.OUTPUT_BUCKET_COUNT][arch.L3_SIZE]i32 align(ALIGNMENT),
    l3w: [arch.OUTPUT_BUCKET_COUNT][arch.L3_SIZE]i32 align(ALIGNMENT),
    l3b: [arch.OUTPUT_BUCKET_COUNT]i32 align(ALIGNMENT),

    fn l1wInference(self: *Weights) *align(ALIGNMENT) [arch.OUTPUT_BUCKET_COUNT][arch.L2_SIZE * arch.L1_SIZE]i8 {
        return @ptrCast(&self.l1w);
    }

    fn l1wDisk(self: *Weights) *align(ALIGNMENT) [arch.L1_SIZE][arch.OUTPUT_BUCKET_COUNT][arch.L2_SIZE]i8 {
        return @ptrCast(&self.l1w);
    }

    fn l2wInference(self: *Weights) *align(ALIGNMENT) [arch.OUTPUT_BUCKET_COUNT][2 * arch.L3_SIZE * arch.L2_SIZE]i32 {
        return @ptrCast(&self.l2w);
    }

    fn l2wDisk(self: *Weights) *align(ALIGNMENT) [2 * arch.L2_SIZE][arch.OUTPUT_BUCKET_COUNT][arch.L3_SIZE]i32 {
        return @ptrCast(&self.l2w);
    }

    fn l3wInference(self: *Weights) *align(ALIGNMENT) [arch.OUTPUT_BUCKET_COUNT][arch.L3_SIZE]i32 {
        return @ptrCast(&self.l3w);
    }

    fn l3wDisk(self: *Weights) *align(ALIGNMENT) [arch.L3_SIZE][arch.OUTPUT_BUCKET_COUNT]i32 {
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
        std.debug.assert(size == SIZE_BYTES);
        break :blk res;
    };
};

const Q_BITS: comptime_int = std.math.log2_int_ceil(u32, arch.Q);
const Q0_BITS: comptime_int = std.math.log2_int_ceil(u32, arch.Q0);
const Q1_BITS: comptime_int = std.math.log2_int_ceil(u32, arch.Q1);

pub const PRECISION_MARGIN: comptime_int = blk: {
    const L1OUT_MAX = arch.Q * arch.Q;
    const WEIGHT_MAX = 1.98;
    const L2W_MAX: comptime_int = @round(arch.Q * WEIGHT_MAX);
    const MAX_ACC: comptime_int = (2 * arch.L2_SIZE) * L1OUT_MAX * L2W_MAX;
    const PM: comptime_int = @floor(@log2(@as(comptime_float, std.math.maxInt(i32)) / @as(comptime_float, MAX_ACC)));
    std.debug.assert((MAX_ACC << PM) <= std.math.maxInt(i32));
    break :blk PM;
};

pub fn forward(
    resolved: anytype,
    weights: *const arch.Weights,
    board: *const Board,
) i16 {
    const timer = @import("../../root.zig").engine.time("eval_forward");
    defer timer.register();
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

    var l1_out_vec: [2 * arch.L2_SIZE / simd.vecSize(i32)]simd.Vector(i32) = undefined;
    {
        const l1_bias_vec: [*]const simd.Vector(i32) = @ptrCast(@alignCast(&ow.l1b[output_bucket]));

        const EXPLICIT_MULHI_SHIFT_UP = 7;
        const IMPLIED_MULHI_SHIFT_DOWN = 16;
        const MULHI_SHIFT = EXPLICIT_MULHI_SHIFT_UP - IMPLIED_MULHI_SHIFT_DOWN;

        const SHIFT = Q0_BITS * 2 + MULHI_SHIFT + Q1_BITS - Q_BITS;
        const LO: simd.Vector(i32) = @splat(0);
        const ONE: simd.Vector(i32) = @splat(1);
        const HI: simd.Vector(i32) = ONE << @splat(SHIFT + Q_BITS);
        for (0..arch.L2_SIZE / simd.vecSize(i32)) |i| {
            const biases: simd.Vector(i32) = l1_bias_vec[i];

            var intermediate: simd.Vector(i32) = @splat(0);
            for (l1_intermediate[i]) |e| {
                intermediate += e;
            }

            const biased = intermediate + biases;

            const crelu = std.math.shr(simd.Vector(i32), std.math.clamp(biased, LO, HI), SHIFT - Q_BITS - PRECISION_MARGIN);

            const clamped: simd.Vector(i32) = std.math.clamp(biased, -HI, HI);
            const csrelu = std.math.shr(simd.Vector(i32), clamped * clamped, SHIFT * 2 - PRECISION_MARGIN);

            l1_out_vec[i] = crelu;
            l1_out_vec[i + arch.L2_SIZE / simd.vecSize(i32)] = csrelu;
        }
    }

    var l2_intermediate: [arch.L3_SIZE / simd.vecSize(i32)]simd.Vector(i32) = @splat(@splat(0));
    {
        const l1_out: *const [2 * arch.L2_SIZE]i32 = @ptrCast(&l1_out_vec);
        const l2_weight_vec: *const [2 * arch.L2_SIZE][arch.L3_SIZE / simd.vecSize(i32)]simd.Vector(i32) = @ptrCast(@alignCast(&ow.l2w[output_bucket]));
        for (0..arch.L2_SIZE * 2) |i| {
            const l1_vec: simd.Vector(i32) = @splat(l1_out[i]);
            for (0..arch.L3_SIZE / simd.vecSize(i32)) |j| {
                l2_intermediate[j] += l1_vec * l2_weight_vec[i][j];
            }
        }
    }

    var l3_sum: simd.Vector(i32) = @splat(0);
    {
        const l2_biases: *const [arch.L3_SIZE / simd.vecSize(i32)]simd.Vector(i32) = @ptrCast(&ow.l2b[output_bucket]);
        const l3_weight_vec: *const [arch.L3_SIZE / simd.vecSize(i32)]simd.Vector(i32) = @ptrCast(&ow.l3w[output_bucket]);
        const LO: simd.Vector(i32) = @splat(0);
        const ONE: simd.Vector(i32) = @splat(1);
        const HI3: simd.Vector(i32) = ONE << @splat(3 * Q_BITS);
        for (0..arch.L3_SIZE / simd.vecSize(i32)) |i| {
            const shifted = std.math.shr(simd.Vector(i32), l2_intermediate[i], PRECISION_MARGIN) + l2_biases[i];
            const activated = std.math.clamp(shifted, LO, HI3);
            l3_sum += activated * l3_weight_vec[i];
        }
    }

    const bias: i32 = ow.l3b[output_bucket];
    const scaled: i64 = (@reduce(.Add, l3_sum) + bias) * arch.SCALE;

    return evaluation.clampScore(@divTrunc(scaled, arch.Q * arch.Q * arch.Q * arch.Q));
}
