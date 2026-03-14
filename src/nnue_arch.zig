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

pub const RawWeights = extern struct {
    ft_w: [INPUT_BUCKET_COUNT * INPUT_SIZE * L1_SIZE]f32,
    ft_b: [L1_SIZE]f32,
    l1w: [OUTPUT_BUCKET_COUNT * L2_SIZE * L1_SIZE]f32,
    l1b: [OUTPUT_BUCKET_COUNT * L2_SIZE]f32,
    l2w: [OUTPUT_BUCKET_COUNT * L3_SIZE * L2_SIZE]f32,
    l2b: [OUTPUT_BUCKET_COUNT * L3_SIZE]f32,
    l3w: [OUTPUT_BUCKET_COUNT * L3_SIZE]f32,
    l3b: [OUTPUT_BUCKET_COUNT]f32,

    pub const SIZE_BYTES = sizeBytes(RawWeights);
};

pub const RAW_FT_W_COUNT = @typeInfo(@FieldType(RawWeights, "ft_w")).array.len;
pub const RAW_FT_B_COUNT = @typeInfo(@FieldType(RawWeights, "ft_b")).array.len;
pub const RAW_L1W_COUNT = @typeInfo(@FieldType(RawWeights, "l1w")).array.len;
pub const RAW_L1B_COUNT = @typeInfo(@FieldType(RawWeights, "l1b")).array.len;
pub const RAW_L2W_COUNT = @typeInfo(@FieldType(RawWeights, "l2w")).array.len;
pub const RAW_L2B_COUNT = @typeInfo(@FieldType(RawWeights, "l2b")).array.len;
pub const RAW_L3W_COUNT = @typeInfo(@FieldType(RawWeights, "l3w")).array.len;
pub const RAW_L3B_COUNT = @typeInfo(@FieldType(RawWeights, "l3b")).array.len;

pub const Weights = extern struct {
    ft_w: [L1_SIZE * INPUT_SIZE * INPUT_BUCKET_COUNT]i16 align(ALIGNMENT),
    ft_b: [L1_SIZE]i16 align(ALIGNMENT),
    l1w: [OUTPUT_BUCKET_COUNT][L2_SIZE * L1_SIZE]i8 align(ALIGNMENT),
    l1b: [OUTPUT_BUCKET_COUNT][L2_SIZE]f32 align(ALIGNMENT),
    l2w: [OUTPUT_BUCKET_COUNT][L2_SIZE][L3_SIZE]f32 align(ALIGNMENT),
    l2b: [OUTPUT_BUCKET_COUNT][L3_SIZE]f32 align(ALIGNMENT),
    l3w: [OUTPUT_BUCKET_COUNT][L3_SIZE]f32 align(ALIGNMENT),
    l3b: [OUTPUT_BUCKET_COUNT]f32 align(ALIGNMENT),

    fn l1wInference(self: *Weights) *align(64) [OUTPUT_BUCKET_COUNT][L2_SIZE * L1_SIZE]i8 {
        return @ptrCast(&self.l1w);
    }

    fn l1wDisk(self: *Weights) *align(64) [L1_SIZE][OUTPUT_BUCKET_COUNT][L2_SIZE]i8 {
        return @ptrCast(&self.l1w);
    }

    pub const SIZE_BYTES = sizeBytes(Weights);
};

fn sizeBytes(comptime T: type) comptime_int {
    var res = 0;
    for (std.meta.fields(T)) |field| {
        const array_info = @typeInfo(field.type).array;
        res += array_info.len * @sizeOf(array_info.child);
    }
    return res;
}

pub fn vecBytes(comptime cpu: std.Target.Cpu) comptime_int {
    if (cpu.has(.x86, .avx512f)) {
        return 64;
    }
    if (cpu.has(.x86, .avx2)) {
        return 32;
    }
    if (cpu.has(.aarch64, .neon)) {
        return 16;
    }
    return 1;
}

const LONGEST_PERMUTE_LEN = 8;

pub fn permuteOrder(cpu: std.Target.Cpu) []const u8 {
    if (cpu.has(.x86, .avx512f)) {
        return &[_]u8{ 0, 2, 4, 6, 1, 3, 5, 7 };
    }
    if (cpu.has(.x86, .avx2)) {
        return &[_]u8{ 0, 2, 1, 3 };
    }
    if (cpu.has(.aarch64, .neon)) {
        return &[_]u8{0};
    }
    return &[_]u8{};
}

pub fn needsPermuting(cpu: std.Target.Cpu) bool {
    if (cpu.has(.x86, .avx512f)) {
        return true;
    }
    if (cpu.has(.x86, .avx2)) {
        return true;
    }
    if (cpu.has(.aarch64, .neon)) {
        return false;
    }
    return false;
}

pub fn hasSupportedSimd(cpu: std.Target.Cpu) bool {
    if (cpu.has(.x86, .avx512f)) {
        return true;
    }
    if (cpu.has(.x86, .avx2)) {
        return true;
    }
    if (cpu.has(.aarch64, .neon)) {
        return true;
    }
    return false;
}

pub fn permuteBuffer(ptr: anytype, order: anytype) void {
    const Block = @Vector(16, u8);

    const num_blocks = @sizeOf(@TypeOf(ptr.*)) / @sizeOf(Block);
    const vecs: *[num_blocks]Block = @ptrCast(ptr);

    var i: usize = 0;
    var weights: [LONGEST_PERMUTE_LEN]Block = undefined;
    while (i < num_blocks) : (i += order.len) {
        @memcpy(weights[0..order.len], vecs[i..][0..order.len]);

        for (0..order.len) |j| {
            vecs[i + j] = (&weights)[order[j]];
        }
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

fn quantize(comptime T: type, value: f32, scale: f32) T {
    return @intFromFloat(@round(value * scale));
}

pub fn permuteNet(cpu: std.Target.Cpu, raw_bytes: []align(ALIGNMENT) const u8, net: *Weights) void {
    @memset(std.mem.asBytes(net), 0);
    std.debug.assert(raw_bytes.len == RawWeights.SIZE_BYTES);
    const raw_all = raw_bytes[0..RawWeights.SIZE_BYTES];
    const raw_floats: []const f32 = std.mem.bytesAsSlice(f32, raw_all);
    var remaining = raw_floats;

    const ft_w = remaining[0..RAW_FT_W_COUNT];
    remaining = remaining[RAW_FT_W_COUNT..];

    const ft_b = remaining[0..RAW_FT_B_COUNT];
    remaining = remaining[RAW_FT_B_COUNT..];

    const l1w = remaining[0..RAW_L1W_COUNT];
    remaining = remaining[RAW_L1W_COUNT..];

    const l1b = remaining[0..RAW_L1B_COUNT];
    remaining = remaining[RAW_L1B_COUNT..];

    const l2w = remaining[0..RAW_L2W_COUNT];
    remaining = remaining[RAW_L2W_COUNT..];

    const l2b = remaining[0..RAW_L2B_COUNT];
    remaining = remaining[RAW_L2B_COUNT..];

    const l3w = remaining[0..RAW_L3W_COUNT];
    remaining = remaining[RAW_L3W_COUNT..];

    const l3b = remaining[0..RAW_L3B_COUNT];
    remaining = remaining[RAW_L3B_COUNT..];
    std.debug.assert(remaining.len == 0);

    for (0..INPUT_BUCKET_COUNT) |bucket| {
        for (0..INPUT_SIZE) |input| {
            for (0..L1_SIZE) |l1| {
                const raw_idx = (bucket * INPUT_SIZE + input) * L1_SIZE + l1;
                net.ft_w[(bucket * INPUT_SIZE + input) * L1_SIZE + l1] =
                    quantize(i16, ft_w[raw_idx], Q0);
            }
        }
    }
    for (0..L1_SIZE) |l1| {
        net.ft_b[l1] = quantize(i16, ft_b[l1], Q0);
    }

    if (needsPermuting(cpu)) {
        inline for (.{ &net.ft_w, &net.ft_b }) |ptr| {
            permuteBuffer(ptr, permuteOrder(cpu));
        }
    }

    if (hasSupportedSimd(cpu)) {
        for (0..OUTPUT_BUCKET_COUNT) |ob| {
            for (0..L1_SIZE / 4) |i| {
                for (0..L2_SIZE) |j| {
                    for (0..4) |k| {
                        const raw_idx = (ob * L2_SIZE + j) * L1_SIZE + i * 4 + k;
                        net.l1w[ob][i * 4 * L2_SIZE + j * 4 + k] =
                            quantize(i8, l1w[raw_idx], Q1);
                    }
                }
            }
        }
    } else {
        for (0..OUTPUT_BUCKET_COUNT) |ob| {
            for (0..L1_SIZE) |i| {
                for (0..L2_SIZE) |j| {
                    const raw_idx = (ob * L2_SIZE + j) * L1_SIZE + i;
                    net.l1w[ob][i * L2_SIZE + j] = quantize(i8, l1w[raw_idx], Q1);
                }
            }
        }
    }

    for (0..OUTPUT_BUCKET_COUNT) |ob| {
        for (0..L2_SIZE) |l2| {
            net.l1b[ob][l2] = l1b[ob * L2_SIZE + l2];
        }
    }
    for (0..OUTPUT_BUCKET_COUNT) |ob| {
        for (0..L2_SIZE) |l2| {
            for (0..L3_SIZE) |l3| {
                const raw_idx = (ob * L3_SIZE + l3) * L2_SIZE + l2;
                net.l2w[ob][l2][l3] = l2w[raw_idx];
            }
        }
    }
    for (0..OUTPUT_BUCKET_COUNT) |ob| {
        for (0..L3_SIZE) |l3| {
            net.l2b[ob][l3] = l2b[ob * L3_SIZE + l3];
            net.l3w[ob][l3] = l3w[ob * L3_SIZE + l3];
        }
        net.l3b[ob] = l3b[ob];
    }
}

pub const HORIZONTAL_MIRRORING = true;
pub const INPUT_BUCKET_COUNT: usize = 13;
pub const OUTPUT_BUCKET_COUNT: usize = 8;
pub const INPUT_SIZE: usize = 768;
pub const L1_SIZE: usize = 1536;
pub const L2_SIZE: usize = 16;
pub const L3_SIZE: usize = 32;
pub const SCALE: i64 = 400;
pub const Q0 = 255;
pub const Q1 = 128;
pub const INPUT_BUCKET_LAYOUT: [64]u8 = .{
    12, 12, 12, 12, 12, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12,
    11, 11, 11, 11, 11, 11, 11, 11,
    11, 11, 11, 11, 11, 11, 11, 11,
    10, 10, 10, 10, 10, 10, 10, 10,
    8,  8,  9,  9,  9,  9,  8,  8,
    4,  5,  6,  7,  7,  6,  5,  4,
    0,  1,  2,  3,  3,  2,  1,  0,
};
