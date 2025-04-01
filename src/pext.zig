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
const attack_table_generation = @import("attack_array_generation.zig");
const root = @import("root.zig");
const Square = root.Square;
const Bitboard = root.Bitboard;

pub const AttackEntry = struct {
    mask: u64,
    mask_full: u64,
    offs: u32,

    pub fn isMaskInverted() bool {
        return false;
    }

    pub inline fn getRookIndex(self: AttackEntry, occ: u64) u64 {
        return self.offs + Bitboard.pext(occ, self.mask);
    }

    pub inline fn getBishopIndex(self: AttackEntry, occ: u64) u64 {
        return self.offs + Bitboard.pext(occ, self.mask);
    }
};

const bishop_attack_entries = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]AttackEntry = undefined;
    var offs: u32 = 0;
    for (0..64) |sq| {
        const relevant = Bitboard.bishopRelevantSquares(1 << sq);
        const full = Bitboard.bishopAttackSquares(1 << sq);
        res[sq] = .{
            .mask = relevant,
            .mask_full = full,
            .offs = offs,
        };
        offs += @as(u32, 1) << @intCast(@popCount(relevant));
    }

    if (offs != bishop_array_size) @compileError("bug");

    break :blk res;
};
const rook_attack_entries = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]AttackEntry = undefined;
    var offs: u32 = 0;
    for (0..64) |sq| {
        const relevant = Bitboard.rookRelevantSquares(1 << sq);
        const full = Bitboard.rookAttackSquares(1 << sq);
        res[sq] = .{
            .mask = relevant,
            .mask_full = full,
            .offs = offs,
        };
        offs += @as(u32, 1) << @intCast(@popCount(relevant));
    }

    if (offs != rook_array_size) @compileError("bug");

    break :blk res;
};
const rook_array_size = 102400;
const bishop_array_size = 5248;

const compressed_rook_attacks = true;

var bishop_attacks: [bishop_array_size]u64 = undefined;
var rook_attacks: [rook_array_size]if (compressed_rook_attacks) u16 else u64 = undefined;

pub fn init() void {
    attack_table_generation.generateBishopAttackArrayInPlace(bishop_attack_entries, &bishop_attacks);
    if (compressed_rook_attacks) {
        attack_table_generation.generateRookAttackArrayInPlaceCompressed(rook_attack_entries, &rook_attacks);
    } else {
        attack_table_generation.generateRookAttackArrayInPlace(rook_attack_entries, &rook_attacks);
    }
}

pub fn getBishopAttacks(square: Square, blockers: u64) u64 {
    return (&bishop_attacks)[@intCast((&bishop_attack_entries)[square.toInt()].getBishopIndex(blockers))];
}
pub fn getRookAttacks(square: Square, blockers: u64) u64 {
    if (compressed_rook_attacks) {
        const magic = (&rook_attack_entries)[square.toInt()];
        return Bitboard.pdep((&rook_attacks)[@intCast(magic.getRookIndex(blockers))], magic.mask_full);
    } else {
        return (&rook_attacks)[@intCast((&rook_attack_entries)[square.toInt()].getRookIndex(blockers))];
    }
}
