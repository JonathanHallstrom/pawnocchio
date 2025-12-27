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

const root = @import("root.zig");

const Colour = root.Colour;
const Square = root.Square;
const PieceType = root.PieceType;

// const Hashes = struct {
//     piece_hashes: [64 * 6 * 2]u64,
//     castling_hashes: [16]u64,
//     ep_hashes: [8]u64,
//     turn_hash: u64,
//     halfmove_hashes: [128]u64, // >100 because power of two
// };

// fn fillRecursive(arr: anytype, rng: anytype) void {
//     if (std.meta.Elem(@TypeOf(arr)) == u64) {
//         rng.bytes(std.mem.asBytes(arr));
//     } else {
//         for (arr) |*elem| {
//             fillRecursive(elem, rng);
//         }
//     }
// }

// const hashes = blk: {
//     @setEvalBranchQuota(1 << 30);
//     var res: Hashes = undefined;
//     var prng = std.Random.DefaultCsprng.init(.{
//         83,  8,   124, 62,
//         209, 228, 102, 90,
//         139, 94,  247, 234,
//         23,  237, 227, 83,
//         185, 187, 249, 170,
//         187, 168, 131, 116,
//         40,  160, 121, 239,
//         88,  54,  185, 83,
//     });

//     prng.random().bytes(std.mem.asBytes(&res.piece_hashes));
//     prng.random().bytes(std.mem.asBytes(&res.castling_hashes));
//     prng.random().bytes(std.mem.asBytes(&res.ep_hashes));
//     prng.random().bytes(std.mem.asBytes(&res.turn_hash));
//     prng.random().bytes(std.mem.asBytes(&res.halfmove_hashes));
//     for (0..16) |i| {
//         if (@popCount(i) != 1) {
//             res.castling_hashes[i] = 0;
//             for (0..4) |j| {
//                 if (i & (1 << j) != 0) {
//                     res.castling_hashes[i] ^= res.castling_hashes[1 << j];
//                 }
//             }
//         }
//     }
//     break :blk res;
// };

// pub fn printDiff(diff: u64) void {
//     for (0..64) |i| {
//         for (0..64) |p| {
//             for (0..2) |s| {
//                 if (diff == hashes.piece_hashes[i][p][s]) {
//                     std.debug.print("{} {} {}\n", .{});
//                 }
//             }
//         }
//     }
// }

// pub fn piece(stm: Colour, pt: PieceType, sq: Square) u64 {
//     const num_piece_types: usize = 6;
//     const num_squares: usize = 64;
//     return (&hashes.piece_hashes)[stm.toInt() * num_piece_types * num_squares + sq.toInt() * num_piece_types + pt.toInt()];
// }

// pub fn castling(rights: u8) u64 {
//     return (&hashes.castling_hashes)[rights];
// }

// pub fn ep(sq: Square) u64 {
//     return (&hashes.ep_hashes)[sq.getFile().toInt()];
// }

// pub fn turn() u64 {
//     return hashes.turn_hash;
// }

// pub fn halfmove(clock: u8) u64 {
//     return (&hashes.halfmove_hashes)[clock];
// }

const piece_entries: usize = 64;
const side_entries: usize = piece_entries * PieceType.all.len;
const castling_entries: usize = 16;
const en_passant_entries: usize = 8;
const turn_entries: usize = 1;
const halfmove_entries: usize = 128;
const piece_offs = 0;
const castling_offs = side_entries * 2;
const ep_offs = castling_offs + castling_entries;
const turn_offs = ep_offs + en_passant_entries;
const halfmove_offs = turn_offs + turn_entries;

const data = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [side_entries * 2 + castling_entries + en_passant_entries + turn_entries + halfmove_entries + @sizeOf(u64) - 1]u8 = undefined;

    var prng = std.Random.DefaultCsprng.init(.{
        83,  8,   124, 62,
        209, 228, 102, 90,
        139, 94,  247, 234,
        23,  237, 227, 83,
        185, 187, 249, 170,
        187, 168, 131, 116,
        40,  160, 121, 239,
        88,  54,  185, 83,
    });
    prng.random().bytes(&res);
    break :blk res;
};

const native_endianness = @import("builtin").cpu.arch.endian();

pub fn piece(col: Colour, pt: PieceType, sq: Square) u64 {
    const offset = @intFromEnum(pt) * piece_entries + sq.toInt() + if (col == .white) side_entries else 0;
    return std.mem.readInt(u64, data[offset..][0..8], native_endianness);
}

pub fn castling(rights: u8) u64 {
    return std.mem.readInt(u64, data[castling_offs..][rights..][0..@sizeOf(u64)], native_endianness);
}

pub fn ep(where: Square) u64 {
    const file = where.toInt() % 8;
    return std.mem.readInt(u64, data[ep_offs..][file..][0..@sizeOf(u64)], native_endianness);
}

pub fn turn() u64 {
    return std.mem.readInt(u64, data[turn_offs..][0..@sizeOf(u64)], native_endianness);
}

pub fn halfmove(clock: u8) u64 {
    const idx = (clock -| 50) / 8;
    const zero_mask: u64 = @intFromBool(idx != 0);
    return -%zero_mask & std.mem.readInt(u64, data[halfmove_offs..][idx..][0..@sizeOf(u64)], native_endianness);
}
