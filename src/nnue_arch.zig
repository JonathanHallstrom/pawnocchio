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
const root = @import("root.zig");

const ALIGNMENT = 64;
pub const Weights = extern struct {
    ft_w: [INPUT_BUCKET_COUNT][2][6][64]RawAccumulator align(ALIGNMENT),
    ft_b: [L1_SIZE]i16 align(ALIGNMENT),
    l1w: [OUTPUT_BUCKET_COUNT][L2_SIZE * L1_SIZE]i8 align(ALIGNMENT),
    l1b: [OUTPUT_BUCKET_COUNT][L2_SIZE]i32 align(ALIGNMENT),
    l2w: [OUTPUT_BUCKET_COUNT][2 * L3_SIZE * L2_SIZE]i32 align(ALIGNMENT),
    l2b: [OUTPUT_BUCKET_COUNT][L3_SIZE]i32 align(ALIGNMENT),
    l3w: [OUTPUT_BUCKET_COUNT][L3_SIZE]i32 align(ALIGNMENT),
    l3b: [OUTPUT_BUCKET_COUNT]i32 align(ALIGNMENT),

    fn l1wInferenceLayout(self: *Weights) *align(ALIGNMENT) [OUTPUT_BUCKET_COUNT][L2_SIZE * L1_SIZE]i8 {
        return @ptrCast(&self.l1w);
    }

    fn l1wDiskLayout(self: *Weights) *align(ALIGNMENT) [L1_SIZE][OUTPUT_BUCKET_COUNT][L2_SIZE]i8 {
        return @ptrCast(&self.l1w);
    }

    fn l2wInferenceLayout(self: *Weights) *align(ALIGNMENT) [OUTPUT_BUCKET_COUNT][2 * L3_SIZE * L2_SIZE]i32 {
        return @ptrCast(&self.l2w);
    }

    fn l2wDiskLayout(self: *Weights) *align(ALIGNMENT) [2 * L2_SIZE][OUTPUT_BUCKET_COUNT][L3_SIZE]i32 {
        return @ptrCast(&self.l2w);
    }

    fn l3wInferenceLayout(self: *Weights) *align(ALIGNMENT) [OUTPUT_BUCKET_COUNT][L3_SIZE]i32 {
        return @ptrCast(&self.l3w);
    }

    fn l3wDiskLayout(self: *Weights) *align(ALIGNMENT) [L3_SIZE][OUTPUT_BUCKET_COUNT]i32 {
        return @ptrCast(&self.l3w);
    }

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

pub const Target = enum {
    avx512vnni,
    avx512,
    avx2,
    aarch64,
    ssse3,
    sse2,
    fallback,
};

pub fn target(cpu: std.Target.Cpu) Target {
    // disabled, slower
    if (cpu.has(.x86, .avx512vnni) and false) {
        return .avx512vnni;
    }
    if (cpu.has(.x86, .avx512f)) {
        return .avx512;
    }
    if (cpu.has(.x86, .avx2)) {
        return .avx2;
    }
    if (cpu.has(.aarch64, .neon)) {
        return .aarch64;
    }
    if (cpu.has(.x86, .ssse3)) {
        return .ssse3;
    }
    if (cpu.has(.x86, .sse2)) {
        return .sse2;
    }
    return .fallback;
}

const LONGEST_PERMUTE_LEN = 8;

pub fn permuteOrderFor(target_kind: Target) []const u8 {
    return switch (target_kind) {
        .avx512vnni, .avx512 => &.{ 0, 2, 4, 6, 1, 3, 5, 7 },
        .avx2 => &.{ 0, 2, 1, 3 },
        .aarch64, .ssse3, .sse2, .fallback => &.{},
    };
}

pub fn needsPermutingFor(target_kind: Target) bool {
    return switch (target_kind) {
        .avx512vnni, .avx512, .avx2 => true,
        .aarch64, .ssse3, .sse2, .fallback => false,
    };
}

pub fn parseTarget(name: []const u8) ?Target {
    return std.meta.stringToEnum(Target, name);
}

pub fn parseEndian(name: []const u8) ?std.builtin.Endian {
    return std.meta.stringToEnum(std.builtin.Endian, name);
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
            vecs[i + j] = weights[order[j]];
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

pub fn transformNetFor(target_kind: Target, endian: std.builtin.Endian, net: *Weights) void {
    if (needsPermutingFor(target_kind)) {
        const order = permuteOrderFor(target_kind);
        inline for (.{ &net.ft_w, &net.ft_b }) |ptr| {
            permuteBuffer(ptr, order);
        }
    }

    if (endian != .little) {
        inline for (.{
            &net.ft_w,
            &net.ft_b,
            &net.l1w,
            &net.l1b,
            &net.l2w,
            &net.l2b,
            &net.l3w,
            &net.l3b,
        }) |field| {
            const T = UltimateChild(@TypeOf(field));

            const Int = std.meta.Int(.unsigned, @bitSizeOf(T));

            const p: *[totalElements(@TypeOf(field))]T = @ptrCast(field);
            for (p) |*e| {
                e.* = @bitCast(@byteSwap(@as(Int, @bitCast(e.*))));
            }
        }
    }

    // permute l1w for dpbusd
    {
        // [L1_SIZE][OUTPUT_BUCKET_COUNT][L2_SIZE]i8
        const l1w_disk = net.l1wDiskLayout().*;

        // [OUTPUT_BUCKET_COUNT][L2_SIZE * L1_SIZE]i8
        const l1w_inf = net.l1wInferenceLayout();

        for (0..OUTPUT_BUCKET_COUNT) |ob| {
            for (0..L1_SIZE / 4) |i| {
                for (0..L2_SIZE) |j| {
                    for (0..4) |k| {
                        l1w_inf[ob][i * 4 * L2_SIZE + j * 4 + k] = l1w_disk[i * 4 + k][ob][j];
                    }
                }
            }
        }
    }

    // transpose l2w
    {
        // [2 * L2_SIZE][OUTPUT_BUCKET_COUNT][L3_SIZE]i32
        const l2w_disk = net.l2wDiskLayout().*;

        // [OUTPUT_BUCKET_COUNT][2 * L3_SIZE * L2_SIZE]i32
        const l2w_inf = net.l2wInferenceLayout();

        for (0..OUTPUT_BUCKET_COUNT) |ob| {
            for (0..2 * L2_SIZE) |i| {
                for (0..L3_SIZE) |j| {
                    l2w_inf[ob][i * L3_SIZE + j] = l2w_disk[i][ob][j];
                }
            }
        }
    }

    // transpose l3w
    {
        // [L3_SIZE][OUTPUT_BUCKET_COUNT]i32
        const l3w_disk = net.l3wDiskLayout().*;

        // [OUTPUT_BUCKET_COUNT][L3_SIZE]i32
        const l3w_inf = net.l3wInferenceLayout();

        for (0..OUTPUT_BUCKET_COUNT) |ob| {
            for (0..L3_SIZE) |i| {
                l3w_inf[ob][i] = l3w_disk[i][ob];
            }
        }
    }
}

pub const AccumulatorVec = @Vector(@import("simd.zig").vecSize(i16), i16);
pub const ACCUMULATOR_VECTOR_COUNT = L1_SIZE / @import("simd.zig").vecSize(i16);
pub const RawAccumulator = [ACCUMULATOR_VECTOR_COUNT]AccumulatorVec;

pub const HORIZONTAL_MIRRORING = true;
pub const INPUT_BUCKET_COUNT: usize = 16;
pub const OUTPUT_BUCKET_COUNT: usize = 8;
pub const INPUT_SIZE: usize = 768;
pub const L1_SIZE: usize = 2048;
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

pub inline fn whichInputBucket(stm: root.Colour, king_square: root.Square) usize {
    return @min(INPUT_BUCKET_COUNT - 1, INPUT_BUCKET_LAYOUT[(if (stm == .white) king_square else king_square.flipRank()).toInt()]);
}

pub inline fn whichOutputBucket(board: *const root.Board) usize {
    const divisor = (32 + OUTPUT_BUCKET_COUNT - 1) / OUTPUT_BUCKET_COUNT;
    return @min(OUTPUT_BUCKET_COUNT - 1, (@popCount(board.occupancy()) - 2) / divisor);
}
