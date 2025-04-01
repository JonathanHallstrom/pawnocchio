// Pawnocchio, UCI chess engine
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

const Hashes = struct {
    piece_hashes: [64][6][2]u64,
    halfmove_hashes: [128]u64, // >100 because power of two
    castling_hashes: [16]u64,
    ep_hashes: [8]u64,
    turn_hash: u64,
};

fn fillRecursive(arr: anytype, rng: anytype) void {
    if (std.meta.Elem(@TypeOf(arr)) == u64) {
        rng.bytes(std.mem.asBytes(arr));
    } else {
        for (arr) |*elem| {
            fillRecursive(elem, rng);
        }
    }
}

const hashes = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: Hashes = undefined;
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

    fillRecursive(&res.piece_hashes, prng.random());
    fillRecursive(&res.halfmove_hashes, prng.random());
    fillRecursive(&res.castling_hashes, prng.random());
    fillRecursive(&res.ep_hashes, prng.random());
    res.turn_hash = prng.random().int(u64);
    for (0..16) |i| {
        if (@popCount(i) != 1) {
            res.castling_hashes[i] = 0;
            for (0..4) |j| {
                if (i & (1 << j) != 0) {
                    res.castling_hashes[i] ^= res.castling_hashes[1 << j];
                }
            }
        }
    }
    break :blk res;
};

pub fn printDiff(diff: u64) void {
    for (0..64) |i| {
        for (0..64) |p| {
            for (0..2) |s| {
                if (diff == hashes.piece_hashes[i][p][s]) {
                    std.debug.print("{} {} {}\n", .{});
                }
            }
        }
    }
}

pub fn piece(stm: Colour, pt: PieceType, sq: Square) u64 {
    return (&(&(&hashes.piece_hashes)[sq.toInt()])[pt.toInt()])[stm.toInt()];
}

pub fn castling(rights: u8) u64 {
    return (&hashes.castling_hashes)[rights];
}

pub fn ep(sq: Square) u64 {
    return (&hashes.ep_hashes)[sq.getFile().toInt()];
}

pub fn turn() u64 {
    return hashes.turn_hash;
}

pub fn halfmove(clock: u8) u64 {
    return (&hashes.halfmove_hashes)[clock];
}
