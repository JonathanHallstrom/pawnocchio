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
pub const fullDotProd = simd.fullDotProd;

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

    pub fn transform(self: *Weights, target_kind: simd.Target, endian: std.builtin.Endian, full_dotprod: bool) void {
        self.input.transform(target_kind, endian, full_dotprod and outputs.NEEDS_L1_PERMUTE, outputs.NEEDS_FT_PERMUTE);
        self.output.transform(target_kind, endian, full_dotprod);
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

pub fn transformNetFor(target_kind: Target, endian: std.builtin.Endian, full_dotprod: bool, net: *Weights) void {
    net.transform(target_kind, endian, full_dotprod);
}

pub const AccumulatorVec = @Vector(simd.vecSize(i16), i16);
pub const PSQTWeightVec = AccumulatorVec;
pub const ThreatWeightVec = @Vector(simd.vecSize(i16), i8);
pub const ACCUMULATOR_VECTOR_COUNT = L1_SIZE / simd.vecSize(i16);

pub const ACCUMULATOR_TILE = @min(ACCUMULATOR_VECTOR_COUNT, switch (simd.TARGET) {
    .avx512vbmi, .avx512 => 32,
    else => 8,
});

pub const RawAccumulator = [ACCUMULATOR_VECTOR_COUNT]AccumulatorVec;
pub const PSQTWeight = RawAccumulator;
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

const IDENTITY: [L1_PAIR_COUNT]u16 = std.simd.iota(u16, L1_PAIR_COUNT);
pub const L1_PAIR_ORDER: [L1_PAIR_COUNT]u16 = .{ 248, 213, 69, 388, 165, 143, 242, 391, 268, 452, 50, 398, 203, 477, 334, 491, 500, 306, 67, 341, 372, 346, 379, 481, 72, 299, 71, 88, 335, 507, 294, 43, 187, 175, 239, 240, 24, 415, 60, 470, 137, 135, 220, 318, 27, 345, 460, 352, 205, 219, 270, 421, 459, 190, 83, 328, 424, 293, 342, 319, 430, 446, 146, 510, 227, 168, 210, 163, 387, 142, 371, 125, 474, 47, 366, 221, 243, 256, 172, 286, 212, 54, 473, 273, 100, 432, 230, 99, 11, 455, 467, 82, 170, 429, 136, 257, 151, 278, 102, 290, 502, 115, 81, 392, 373, 348, 320, 140, 406, 21, 374, 4, 499, 201, 51, 68, 304, 42, 280, 501, 343, 453, 253, 61, 116, 106, 144, 330, 434, 199, 111, 78, 301, 340, 229, 435, 206, 472, 12, 225, 411, 355, 322, 358, 360, 397, 0, 13, 121, 418, 15, 122, 202, 96, 23, 173, 505, 94, 395, 17, 233, 282, 383, 313, 484, 8, 367, 185, 234, 314, 376, 449, 44, 179, 30, 283, 228, 19, 150, 149, 235, 444, 440, 271, 127, 288, 45, 448, 307, 419, 193, 36, 86, 226, 433, 354, 478, 465, 211, 384, 369, 109, 255, 231, 407, 182, 312, 167, 263, 252, 417, 362, 486, 511, 489, 84, 166, 178, 26, 87, 14, 79, 59, 302, 266, 476, 454, 403, 275, 279, 487, 281, 192, 132, 296, 25, 506, 118, 3, 64, 245, 337, 186, 412, 222, 197, 321, 34, 184, 174, 108, 48, 336, 413, 124, 498, 251, 456, 189, 441, 157, 120, 80, 158, 1, 494, 254, 188, 214, 131, 325, 133, 422, 152, 207, 405, 161, 479, 181, 138, 496, 35, 141, 162, 353, 285, 92, 269, 258, 399, 349, 85, 90, 393, 93, 208, 368, 218, 463, 431, 471, 70, 114, 447, 332, 145, 483, 148, 361, 32, 311, 436, 359, 277, 344, 98, 156, 33, 130, 103, 147, 241, 272, 385, 180, 323, 284, 171, 303, 396, 339, 128, 439, 380, 169, 237, 46, 101, 317, 107, 139, 216, 274, 504, 458, 316, 488, 10, 262, 276, 386, 200, 357, 416, 364, 420, 333, 194, 9, 91, 408, 493, 503, 260, 427, 291, 153, 65, 247, 126, 39, 223, 204, 423, 508, 160, 390, 410, 356, 475, 117, 89, 76, 370, 292, 480, 428, 400, 305, 58, 327, 287, 457, 196, 22, 394, 244, 461, 450, 134, 224, 6, 236, 365, 295, 110, 159, 298, 7, 324, 261, 442, 183, 104, 49, 75, 497, 363, 414, 56, 401, 249, 310, 215, 338, 409, 265, 113, 250, 485, 426, 495, 40, 482, 264, 77, 464, 331, 445, 404, 2, 402, 73, 37, 238, 309, 468, 55, 351, 217, 232, 31, 155, 347, 53, 382, 329, 209, 95, 28, 129, 490, 119, 389, 466, 469, 438, 437, 177, 308, 105, 198, 195, 267, 52, 425, 29, 462, 315, 74, 289, 164, 123, 492, 443, 97, 62, 191, 20, 41, 112, 176, 5, 509, 326, 381, 297, 378, 246, 300, 375, 154, 66, 18, 451, 259, 377, 63, 57, 16, 350, 38 };

pub const L1_NEURON_ORDER: [L1_SIZE]u16 = blk: {
    var o: [L1_SIZE]u16 = undefined;
    for (0..L1_PAIR_COUNT) |i| {
        o[i] = L1_PAIR_ORDER[i];
        o[i + L1_PAIR_COUNT] = L1_PAIR_ORDER[i] + L1_PAIR_COUNT;
    }
    break :blk o;
};

pub const L1_IDENTITY_ORDER: [L1_SIZE]u16 = blk: {
    @setEvalBranchQuota(4 * L1_SIZE);
    var o: [L1_SIZE]u16 = undefined;
    for (&o, 0..) |*e, i| e.* = @intCast(i);
    break :blk o;
};

pub fn l1OrderFor(full_dotprod: bool) *const [L1_SIZE]u16 {
    return if (full_dotprod) &L1_NEURON_ORDER else &L1_IDENTITY_ORDER;
}

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
