const std = @import("std");
const arch = @import("../arch.zig");
const simd = @import("../../simd.zig");
const Board = @import("../../Board.zig");
const evaluation = @import("../../evaluation.zig");

const ALIGNMENT = 64;

pub const NEEDS_FT_PERMUTE = false;

pub const Weights = extern struct {
    output_w: [arch.OUTPUT_BUCKET_COUNT][2 * arch.L1_SIZE]i16 align(ALIGNMENT),
    output_b: [arch.OUTPUT_BUCKET_COUNT]i16 align(ALIGNMENT),

    pub fn transform(self: *Weights, target_kind: simd.Target, endian: std.builtin.Endian) void {
        _ = target_kind;

        if (endian != .little) {
            arch.endianSwap(&self.output_w);
            arch.endianSwap(&self.output_b);
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

pub fn forward(
    resolved: anytype,
    weights: *const arch.Weights,
    board: *const Board,
) i16 {
    const output_bucket = arch.whichOutputBucket(@popCount(board.occupancy()));
    const ow = &weights.output;
    const w = &ow.output_w[output_bucket];

    const LO: simd.Vector(i16) = @splat(0);
    const HI: simd.Vector(i16) = @splat(arch.Q0);

    const UNROLL = @min(4, arch.L1_SIZE / simd.vecSize(i16));
    var accs: [UNROLL]simd.Vector(i32) = @splat(@splat(0));

    var i: usize = 0;
    while (i < arch.L1_SIZE) {
        inline for (&accs) |*acc| {
            const us = std.math.clamp(resolved.read(.stm, i), LO, HI);
            const them = std.math.clamp(resolved.read(.ntm, i), LO, HI);

            const us_w: simd.Vector(i16) = w[i..][0..simd.vecSize(i16)].*;
            const them_w: simd.Vector(i16) = w[i + arch.L1_SIZE ..][0..simd.vecSize(i16)].*;

            acc.* +=
                simd.maddwd(us_w *% us, us) +
                simd.maddwd(them_w *% them, them);

            i += simd.vecSize(i16);
        }
    }

    var sum = accs[0];
    for (accs[1..]) |a| sum += a;
    var res: i32 = @reduce(.Add, sum);

    res = @divTrunc(res, arch.Q0);
    res += ow.output_b[output_bucket];

    return evaluation.clampScore(@divTrunc(res * arch.SCALE, arch.Q0 * arch.Q));
}
