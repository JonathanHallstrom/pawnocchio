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
const simd = @import("../simd.zig");

pub const Target = simd.Target;
pub const target = simd.target;
pub const parseTarget = simd.parseTarget;

pub const inputs = @import("inputs/psq_threats.zig");
pub const outputs = @import("outputs/multilayer.zig");

pub const PAWN_PAIR_INPUTS = true;
pub const TOTAL_THREATS = if (PAWN_PAIR_INPUTS) 59808 else 60144;
pub const TOTAL_PAWN_PAIRS = if (PAWN_PAIR_INPUTS) 96 * 95 / 2 else 0;

// [0..8) and [56..64) must be zero, cant have pawns there
pub const PP_MASK_BAND: [64]u64 = blk: {
    const A: u64 = 0x0101_0101_0101_0101;
    var table: [64]u64 = @splat(0);
    for (8..56) |sq| {
        const f = sq & 7;
        var m: u64 = A << f;
        if (f > 0) m |= A << (f - 1);
        if (f < 7) m |= A << (f + 1);
        table[sq] = m;
    }
    break :blk table;
};

pub const PP_MASK: [64]u64 = PP_MASK_BAND;

pub const Weights = extern struct {
    input: inputs.Weights,
    output: outputs.Weights,

    pub fn transform(self: *Weights, target_kind: simd.Target, endian: std.builtin.Endian) void {
        self.input.transform(target_kind, endian);
        self.output.transform(target_kind, endian);
    }

    pub const SIZE_BYTES = inputs.Weights.SIZE_BYTES + outputs.Weights.SIZE_BYTES;
    pub const WEIGHT_COUNT = inputs.Weights.WEIGHT_COUNT + outputs.Weights.WEIGHT_COUNT;

    comptime {
        if (@sizeOf(Weights) != SIZE_BYTES) @compileError("unexpected padding in Weights");
    }
};

pub fn parseEndian(name: []const u8) ?std.builtin.Endian {
    return std.meta.stringToEnum(std.builtin.Endian, name);
}

const LONGEST_PERMUTE_LEN = 8;

pub fn permuteOrderFor(target_kind: Target) []const u8 {
    return switch (target_kind) {
        .avx512vbmi, .avx512 => &.{ 0, 2, 4, 6, 1, 3, 5, 7 },
        .avx2 => &.{ 0, 2, 1, 3 },
        .aarch64, .ssse3, .sse2, .fallback => &.{},
    };
}

pub fn needsPermutingFor(target_kind: Target) bool {
    return switch (target_kind) {
        .avx512vbmi, .avx512, .avx2 => true,
        .aarch64, .ssse3, .sse2, .fallback => false,
    };
}

fn permuteBufferWithBlockBytes(comptime block_bytes: usize, ptr: anytype, order: anytype) void {
    const Block = [block_bytes]u8;
    const num_blocks = @sizeOf(@TypeOf(ptr.*)) / @sizeOf(Block);
    const vecs: *[num_blocks]Block = @ptrCast(ptr);

    var i: usize = 0;
    var weights: [LONGEST_PERMUTE_LEN]Block = undefined;
    while (i < num_blocks) : (i += order.len) {
        @memcpy(weights[0..order.len], vecs[i..][0..order.len]);
        for (0..order.len) |j| vecs[i + j] = weights[order[j]];
    }
}

pub fn permuteBufferI8(ptr: anytype, order: anytype) void {
    permuteBufferWithBlockBytes(8, ptr, order);
}

pub fn permuteBuffer(ptr: anytype, order: anytype) void {
    permuteBufferWithBlockBytes(16, ptr, order);
}

pub fn endianSwap(field: anytype) void {
    const T = UltimateChild(@TypeOf(field.*));
    const Int = std.meta.Int(.unsigned, @bitSizeOf(T));
    const p: *[totalElements(@TypeOf(field.*))]T = @ptrCast(field);
    for (p) |*e| {
        e.* = @bitCast(@byteSwap(@as(Int, @bitCast(e.*))));
    }
}

pub fn UltimateChild(comptime T: type) type {
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

pub fn totalElements(comptime T: type) comptime_int {
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
    net.transform(target_kind, endian);
}

pub const AccumulatorVec = @Vector(simd.vecSize(i16), i16);
pub const PSQTWeightVec = @Vector(simd.vecSize(i16), i16);
pub const ThreatWeightVec = @Vector(simd.vecSize(i16), i8);
pub const ACCUMULATOR_VECTOR_COUNT = L1_SIZE / simd.vecSize(i16);

pub const ACCUMULATOR_TILE = @min(ACCUMULATOR_VECTOR_COUNT, switch (simd.TARGET) {
    .avx512vbmi, .avx512 => 32,
    else => 8,
});

pub const RawAccumulator = [ACCUMULATOR_VECTOR_COUNT]AccumulatorVec;
pub const PSQTWeight = [ACCUMULATOR_VECTOR_COUNT]PSQTWeightVec;
pub const ThreatWeight = [ACCUMULATOR_VECTOR_COUNT]ThreatWeightVec;

pub const HORIZONTAL_MIRRORING = true;
pub const INPUT_BUCKET_COUNT: usize = 32;
pub const OUTPUT_BUCKET_COUNT: usize = 8;
pub const L1_SIZE: usize = 1024;
pub const L2_SIZE: usize = 32;
pub const L3_SIZE: usize = 32;
pub const SCALE: i64 = 400;
pub const Q0 = 255;
pub const Q1 = 128;
pub const Q = 64;
pub const INPUT_BUCKET_LAYOUT: [64]u8 = .{
    0,  1,  2,  3,  3,  2,  1,  0,
    4,  5,  6,  7,  7,  6,  5,  4,
    8,  9,  10, 11, 11, 10, 9,  8,
    12, 13, 14, 15, 15, 14, 13, 12,
    16, 17, 18, 19, 19, 18, 17, 16,
    20, 21, 22, 23, 23, 22, 21, 20,
    24, 25, 26, 27, 27, 26, 25, 24,
    28, 29, 30, 31, 31, 30, 29, 28,
};

pub const L1_PAIR_COUNT = L1_SIZE / 2;

pub const L1_PAIR_ORDER: [L1_PAIR_COUNT]u16 = .{ 143, 350, 248, 213, 391, 279, 454, 242, 275, 79, 302, 87, 59, 476, 266, 49, 363, 414, 497, 75, 290, 472, 320, 115, 373, 348, 502, 278, 116, 102, 355, 152, 322, 463, 431, 272, 180, 160, 385, 323, 411, 446, 406, 430, 146, 294, 195, 177, 308, 105, 198, 280, 441, 189, 157, 5, 176, 97, 112, 41, 20, 401, 147, 156, 241, 103, 130, 164, 329, 412, 28, 95, 209, 227, 470, 473, 212, 54, 286, 172, 96, 201, 243, 221, 122, 47, 210, 366, 163, 246, 300, 375, 461, 295, 365, 40, 6, 231, 378, 107, 297, 256, 68, 51, 328, 235, 293, 505, 439, 342, 173, 23, 319, 287, 219, 205, 270, 421, 86, 36, 371, 226, 274, 142, 17, 433, 94, 395, 234, 314, 110, 159, 7, 298, 324, 261, 15, 459, 200, 444, 144, 151, 330, 257, 136, 228, 113, 485, 250, 383, 426, 233, 236, 484, 8, 282, 367, 185, 418, 263, 252, 417, 167, 504, 354, 478, 211, 465, 384, 369, 255, 312, 37, 347, 53, 382, 182, 407, 488, 458, 31, 316, 155, 419, 27, 229, 301, 435, 340, 78, 111, 106, 199, 434, 437, 140, 438, 187, 71, 88, 335, 283, 19, 30, 150, 149, 34, 127, 108, 175, 343, 66, 121, 13, 381, 0, 397, 358, 360, 137, 310, 171, 303, 284, 220, 186, 135, 1, 254, 169, 462, 315, 52, 29, 425, 402, 73, 404, 445, 237, 2, 331, 265, 306, 99, 16, 443, 492, 123, 332, 311, 361, 148, 483, 32, 145, 268, 436, 403, 452, 277, 359, 191, 50, 344, 203, 62, 398, 98, 124, 206, 33, 276, 262, 494, 249, 386, 511, 491, 500, 477, 334, 457, 22, 394, 244, 196, 48, 194, 264, 77, 464, 482, 480, 428, 400, 450, 305, 486, 58, 362, 224, 134, 57, 451, 18, 63, 377, 259, 304, 449, 507, 376, 387, 83, 190, 352, 193, 307, 448, 460, 45, 288, 179, 44, 271, 440, 253, 61, 481, 239, 370, 184, 76, 240, 174, 197, 222, 374, 321, 21, 4, 499, 285, 420, 453, 416, 357, 364, 216, 474, 139, 501, 202, 396, 273, 299, 72, 35, 409, 333, 326, 338, 161, 215, 509, 125, 168, 510, 469, 466, 490, 188, 119, 389, 154, 138, 181, 479, 496, 129, 166, 24, 26, 178, 218, 56, 3, 91, 408, 503, 493, 260, 81, 368, 392, 471, 258, 14, 399, 349, 85, 393, 90, 93, 84, 208, 118, 64, 318, 506, 25, 353, 117, 92, 269, 390, 158, 447, 114, 267, 247, 10, 65, 153, 291, 415, 39, 508, 223, 204, 9, 423, 60, 126, 427, 80, 120, 11, 245, 292, 455, 337, 141, 467, 162, 422, 405, 356, 207, 475, 410, 489, 89, 380, 230, 100, 46, 432, 101, 133, 317, 325, 43, 128, 313, 131, 214, 42, 232, 67, 351, 55, 345, 339, 424, 309, 109, 238, 468, 327, 495, 170, 82, 429, 341, 346, 372, 379, 442, 104, 183, 296, 217, 498, 413, 251, 487, 336, 456, 281, 289, 74, 192, 132, 225, 12, 70, 38, 69, 388, 165 };

pub const L1_NEURON_ORDER: [L1_SIZE]u16 = blk: {
    var o: [L1_SIZE]u16 = undefined;
    for (0..L1_PAIR_COUNT) |i| {
        o[i] = L1_PAIR_ORDER[i];
        o[i + L1_PAIR_COUNT] = L1_PAIR_ORDER[i] + L1_PAIR_COUNT;
    }
    break :blk o;
};

pub fn l1NeedsPermuting() bool {
    for (L1_PAIR_ORDER, 0..) |v, i| if (v != i) return true;
    return false;
}

pub fn permuteL1Neurons(ptr: anytype) void {
    if (!l1NeedsPermuting()) return;
    const Elem = UltimateChild(@TypeOf(ptr.*));
    const total = @sizeOf(@TypeOf(ptr.*)) / @sizeOf(Elem);
    const flat: [*]Elem = @ptrCast(ptr);
    for (0..total / L1_SIZE) |i| {
        var tmp: [L1_SIZE]Elem = undefined;
        const row = flat[i * L1_SIZE ..][0..L1_SIZE];
        for (0..L1_SIZE) |new| tmp[new] = row[L1_NEURON_ORDER[new]];
        row.* = tmp;
    }
}

pub inline fn whichInputBucket(sq_idx: usize) usize {
    return @min(INPUT_BUCKET_COUNT - 1, INPUT_BUCKET_LAYOUT[sq_idx]);
}

pub inline fn whichOutputBucket(piece_count: usize) usize {
    const divisor = (32 + OUTPUT_BUCKET_COUNT - 1) / OUTPUT_BUCKET_COUNT;
    return @min(OUTPUT_BUCKET_COUNT - 1, (piece_count - 2) / divisor);
}
