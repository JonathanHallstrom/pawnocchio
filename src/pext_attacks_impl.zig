const std = @import("std");
const magics_generation = @import("magics_generation.zig");
const Square = @import("square.zig").Square;
const Bitboard = @import("Bitboard.zig");

pub const MagicEntry = struct {
    mask: u64,
    mask_full: u64,
    offs: u32,

    pub fn isMaskInverted() bool {
        return false;
    }

    pub inline fn getRookIndex(self: MagicEntry, occ: u64) u64 {
        return self.offs + Bitboard.pext(occ, self.mask);
    }

    pub inline fn getBishopIndex(self: MagicEntry, occ: u64) u64 {
        return self.offs + Bitboard.pext(occ, self.mask);
    }
};

const bishop_magics = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]MagicEntry = undefined;
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
const rook_magics = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]MagicEntry = undefined;
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

const compressed_rook_attacks = false;

var bishop_attacks: [bishop_array_size]u64 = undefined;
var rook_attacks: [rook_array_size]if (compressed_rook_attacks) u16 else u64 = undefined;

pub fn init() void {
    magics_generation.generateBishopAttackArrayInPlace(bishop_magics, &bishop_attacks);
    if (compressed_rook_attacks) {
        magics_generation.generateRookAttackArrayInPlaceCompressed(rook_magics, &rook_attacks);
    } else {
        magics_generation.generateRookAttackArrayInPlace(rook_magics, &rook_attacks);
    }
}

pub fn getBishopAttacks(square: Square, blockers: u64) u64 {
    return (&bishop_attacks)[@intCast(bishop_magics[square.toInt()].getBishopIndex(blockers))];
}
pub fn getRookAttacks(square: Square, blockers: u64) u64 {
    if (compressed_rook_attacks) {
        const magic = rook_magics[square.toInt()];
        return Bitboard.pdep((&rook_attacks)[@intCast(magic.getRookIndex(blockers))], magic.mask_full);
    } else {
        return (&rook_attacks)[@intCast(rook_magics[square.toInt()].getRookIndex(blockers))];
    }
}
