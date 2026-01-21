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
const builtin = @import("builtin");

const ALIGNMENT = 64;
pub const Weights = extern struct {
    ft_w: [L1_SIZE * INPUT_SIZE * INPUT_BUCKET_COUNT]i16 align(ALIGNMENT),
    ft_b: [L1_SIZE]i16 align(ALIGNMENT),
    l1w: [OUTPUT_BUCKET_COUNT][L2_SIZE][L1_SIZE]i8 align(ALIGNMENT),
    l1b: [OUTPUT_BUCKET_COUNT][L2_SIZE]f32 align(ALIGNMENT),
    l2w: [OUTPUT_BUCKET_COUNT][L3_SIZE][L2_SIZE]f32 align(ALIGNMENT),
    l2b: [OUTPUT_BUCKET_COUNT][L3_SIZE]f32 align(ALIGNMENT),
    l3w: [OUTPUT_BUCKET_COUNT][L3_SIZE]f32 align(ALIGNMENT),
    l3b: [OUTPUT_BUCKET_COUNT]f32 align(ALIGNMENT),

    pub const WEIGHT_COUNT = blk: {
        var res = 0;
        for (std.meta.fields(Weights)) |field| {
            res += @typeInfo(field.type).array.len;
        }
        break :blk res;
    };
    pub const SIZE_BYTES = blk: {
        var res = 0;
        for (std.meta.fields(Weights)) |field| {
            const array_info = @typeInfo(field.type).array;
            res += array_info.len * @sizeOf(array_info.child);
        }
        break :blk res;
    };
};

const cpu = builtin.cpu;
pub const IS_AVX512 = cpu.has(.x86, .avx512f);
pub const IS_AVX2 = cpu.has(.x86, .avx2);
pub const IS_NEON = cpu.has(.arm, .neon);
pub const VEC_BYTES = blk: {
    if (IS_AVX512) {
        break :blk 64;
    }
    if (IS_AVX2) {
        break :blk 32;
    }
    if (IS_NEON) {
        break :blk 16;
    }
    break :blk 1;
};

pub const PERMUTE_ORDER = blk: {
    if (IS_AVX512) {
        break :blk [_]u8{ 0, 2, 4, 6, 1, 3, 5, 7 };
    }
    if (IS_AVX2) {
        break :blk [_]u8{ 0, 2, 1, 3 };
    }
    if (IS_NEON) {
        break :blk [_]u8{0};
    }
    break :blk [_]u8{};
};

pub const NEEDS_PERMUTING = blk: {
    if (IS_AVX512) {
        break :blk true;
    }
    if (IS_AVX2) {
        break :blk true;
    }
    if (IS_NEON) {
        break :blk false;
    }
    break :blk false;
};

pub fn permuteBuffer(ptr: anytype, order: anytype) void {
    const Block = @Vector(16, u8);

    const vecs: [*]Block = @ptrCast(ptr);

    var i: usize = 0;
    const num_blocks = @sizeOf(@TypeOf(ptr.*)) / @sizeOf(Block);
    while (i < num_blocks) : (i += order.len) {
        const weights = vecs[i..][0..order.len].*;

        for (0..order.len) |j| {
            vecs[i + j] = weights[order[j]];
        }
    }
}

pub fn permuteNet(net: *Weights) void {
    if (!NEEDS_PERMUTING or true) return;

    inline for (.{ &net.ft_w, &net.ft_b }) |ptr| {
        permuteBuffer(ptr, PERMUTE_ORDER);
    }
}

pub const HORIZONTAL_MIRRORING = true;
pub const INPUT_BUCKET_COUNT: usize = 16;
pub const OUTPUT_BUCKET_COUNT: usize = 8;
pub const INPUT_SIZE: usize = 768;
pub const L1_SIZE: usize = 2048;
pub const L2_SIZE: usize = 16;
pub const L3_SIZE: usize = 32;
pub const SCALE = 400;
pub const QA = 255;
pub const QB = 64;
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
