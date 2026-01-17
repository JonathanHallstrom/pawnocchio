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

pub const Weights = extern struct {
    hidden_layer_weights: [L1_SIZE * INPUT_SIZE * INPUT_BUCKET_COUNT]i16 align(std.atomic.cache_line),
    hidden_layer_biases: [L1_SIZE]i16 align(std.atomic.cache_line),
    l1w: [OUTPUT_BUCKET_COUNT][L2_SIZE][L1_SIZE]i8 align(std.atomic.cache_line),
    l1b: [OUTPUT_BUCKET_COUNT][L2_SIZE]f32 align(std.atomic.cache_line),
    l2w: [OUTPUT_BUCKET_COUNT][L3_SIZE][L2_SIZE]f32 align(std.atomic.cache_line),
    l2b: [OUTPUT_BUCKET_COUNT][L3_SIZE]f32 align(std.atomic.cache_line),
    l3w: [OUTPUT_BUCKET_COUNT][L3_SIZE]f32 align(std.atomic.cache_line),
    l3b: [OUTPUT_BUCKET_COUNT]f32 align(std.atomic.cache_line),

    const WEIGHT_COUNT = blk: {
        var res = 0;
        for (std.meta.fields(Weights)) |field| {
            res += @typeInfo(field.type).array.len;
        }
        break :blk res;
    };
};

pub const HORIZONTAL_MIRRORING = true;
pub const INPUT_BUCKET_COUNT: usize = 16;
pub const OUTPUT_BUCKET_COUNT: usize = 8;
pub const INPUT_SIZE: usize = 768;
pub const L1_SIZE: usize = 2048;
pub const L2_SIZE: usize = 16;
pub const L3_SIZE: usize = 32;
pub const SCALE = 400;
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
