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
        inline .array, .vector => |i| {
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
pub const L1_PAIR_ORDER: [L1_PAIR_COUNT]u16 = .{ 69, 326, 30, 14, 43, 374, 341, 329, 422, 382, 403, 468, 502, 485, 358, 170, 80, 133, 269, 5, 408, 221, 246, 122, 15, 473, 149, 320, 278, 125, 424, 357, 226, 23, 20, 252, 379, 483, 391, 346, 224, 193, 165, 243, 123, 48, 413, 300, 112, 508, 330, 28, 425, 201, 102, 350, 447, 64, 79, 57, 260, 316, 100, 289, 38, 85, 191, 145, 268, 510, 315, 258, 67, 157, 467, 71, 181, 325, 399, 107, 471, 498, 445, 431, 446, 280, 305, 415, 143, 505, 409, 463, 141, 494, 206, 337, 444, 256, 34, 148, 331, 363, 302, 309, 12, 449, 99, 61, 116, 176, 167, 17, 188, 267, 311, 319, 121, 334, 108, 428, 389, 233, 458, 371, 136, 56, 412, 472, 192, 282, 396, 235, 457, 318, 194, 129, 106, 60, 94, 274, 18, 139, 263, 414, 9, 367, 126, 35, 434, 436, 101, 240, 55, 166, 393, 364, 475, 352, 450, 236, 292, 132, 45, 27, 469, 259, 421, 44, 142, 344, 275, 159, 160, 31, 351, 453, 16, 88, 58, 248, 53, 511, 342, 368, 333, 37, 124, 46, 359, 294, 147, 349, 273, 501, 33, 488, 404, 380, 385, 455, 271, 135, 209, 486, 495, 204, 323, 87, 11, 430, 234, 19, 178, 227, 465, 285, 306, 83, 297, 212, 200, 250, 489, 207, 128, 478, 441, 387, 115, 386, 120, 26, 208, 343, 500, 231, 262, 370, 137, 356, 184, 151, 503, 270, 476, 355, 175, 317, 89, 228, 288, 287, 383, 286, 177, 77, 185, 239, 459, 435, 384, 504, 419, 310, 360, 199, 411, 304, 336, 51, 68, 186, 54, 426, 172, 438, 49, 198, 405, 253, 474, 335, 1, 216, 308, 484, 496, 190, 418, 369, 158, 410, 91, 480, 456, 70, 509, 439, 96, 324, 232, 332, 392, 180, 195, 372, 328, 265, 119, 339, 245, 314, 237, 114, 73, 82, 437, 481, 134, 499, 217, 254, 406, 152, 281, 146, 144, 36, 32, 113, 29, 381, 130, 373, 6, 255, 62, 466, 266, 197, 401, 440, 66, 313, 477, 340, 153, 293, 3, 98, 162, 164, 131, 482, 348, 487, 63, 173, 279, 492, 138, 230, 303, 95, 402, 189, 205, 276, 90, 347, 345, 362, 272, 442, 187, 183, 111, 78, 378, 299, 291, 251, 353, 448, 229, 290, 140, 218, 203, 416, 219, 257, 127, 8, 117, 52, 377, 42, 182, 400, 210, 277, 75, 2, 354, 423, 93, 225, 213, 47, 238, 214, 375, 86, 366, 103, 407, 163, 376, 161, 155, 361, 461, 24, 490, 390, 13, 398, 156, 223, 432, 171, 110, 247, 298, 150, 84, 92, 493, 202, 169, 479, 301, 10, 222, 244, 211, 312, 242, 452, 397, 464, 365, 196, 394, 429, 97, 497, 307, 433, 451, 264, 174, 443, 50, 39, 491, 22, 327, 104, 109, 105, 454, 215, 0, 41, 59, 40, 283, 506, 417, 296, 7, 72, 118, 470, 4, 168, 460, 220, 65, 395, 295, 284, 427, 322, 261, 154, 249, 338, 462, 21, 420, 321, 388, 241, 81, 74, 25, 76, 179, 507 };

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
