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

fn getMask(vals: @Vector(nnue.vecSize(u8), u8)) std.meta.Int(.unsigned, nnue.vecSize(i32)) {
    const as_i32: @Vector(nnue.vecSize(i32), i32) = @bitCast(vals);
    const zero: @Vector(nnue.vecSize(i32), i32) = @splat(0);

    return @bitCast(as_i32 != zero);
}

const Sparse = @This();

indices: [L1_SIZE / 4]u16 = undefined,
len: usize = 0,
base: @Vector(8, u16) = @splat(0),

pub fn init() Sparse {
    return .{};
}

pub inline fn add(
    self: *Sparse,
    vals1: [nnue.vecSize(u8)]u8,
    vals2: [nnue.vecSize(u8)]u8,
) void {
    inline for (.{ getMask(vals1), getMask(vals2) }) |mask| {
        inline for (0..nnue.vecSize(i32) / 8) |j| {
            const byte = mask >> (8 * j) & 0xff;

            const mask_indices = NONZERO_INDICES[byte];

            const actual_indices: [8]u16 = mask_indices + self.base;
            @memcpy(self.indices[self.len..][0..8], &actual_indices);

            self.len += @popCount(byte);
            self.base += @splat(8);
        }
    }
}
