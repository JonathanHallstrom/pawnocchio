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
const attack_array_generation = @import("attack_array_generation.zig");
const root = @import("root.zig");
const Square = root.Square;
const Bitboard = root.Bitboard;

const nnue = @import("nnue.zig");

const L1_SIZE = nnue.L1_SIZE;

const NONZERO_INDICES = blk: {
    var res: [256]struct { @Vector(8, u16), u16 } = @splat(.{ @splat(0), 0 });

    @setEvalBranchQuota(256 * 8 * 2);
    for (0..256) |i| {
        var count = 0;
        for (0..8) |j| {
            if (i & 1 << j != 0) {
                res[i].@"0"[count] = j;
                count += 1;
            }
        }
        res[i].@"1" = count;
    }
    break :blk res;
};

fn getMask(vals: @Vector(nnue.vecSize(u8), u8)) std.meta.Int(.unsigned, nnue.vecSize(i32)) {
    const as_i32: @Vector(nnue.vecSize(i32), i32) = @bitCast(vals);
    const zero: @Vector(nnue.vecSize(i32), i32) = @splat(0);

    return @bitCast(as_i32 != zero);
}

pub inline fn findNonZeroIndices(
    ft: *align(64) const [L1_SIZE]u8,
) struct {
    [L1_SIZE / 4]u16,
    usize,
} {
    var indices: [L1_SIZE / 4]u16 = undefined;
    var count: usize = 0;
    var base: @Vector(8, u16) = @splat(0);

    var i: usize = 0;
    while (i < nnue.L1_SIZE) : (i += nnue.vecSize(u8)) {
        const mask = getMask(ft[i..][0..nnue.vecSize(i8)].*);

        inline for (0..nnue.vecSize(i32) / 8) |j| {
            const byte = mask >> (8 * j) & 0xff;

            const mask_indices, const mask_count = NONZERO_INDICES[byte];

            const actual_indices: [8]u16 = mask_indices + base;
            @memcpy(indices[count..][0..8], &actual_indices);

            std.debug.assert(mask_count == @popCount(byte));

            count += mask_count;
            base += @splat(8);
        }
    }

    return .{ indices, count };
}
