// TODO: actual magic bitboards

const std = @import("std");
const Square = @import("square.zig").Square;
const Bitboard = @import("Bitboard.zig");

fn getAttacks(square: Square, blockers: u64, d_ranks: anytype, d_files: anytype) u64 {
    var res: u64 = 0;

    inline for (d_ranks, d_files) |d_rank, d_file| {
        const squares = Bitboard.rayArrayPtr(d_rank, d_file);
        const blockers_dir = squares[square.toInt()] & blockers;

        const square_diff = 8 * d_rank + d_file;

        res |= squares[square.toInt()];
        if (blockers_dir != 0) {
            const relevant_blocker_idx: u6 = @intCast(if (square_diff > 0) @ctz(blockers_dir) else 63 - @clz(blockers_dir));
            res &= ~squares[relevant_blocker_idx];
        }
    }

    return res;
}

pub fn getBishopAttacks(square: Square, blockers: u64) u64 {
    return getAttacks(square, blockers, Bitboard.bishop_d_ranks, Bitboard.bishop_d_files);
}

pub fn getRookAttacks(square: Square, blockers: u64) u64 {
    return getAttacks(square, blockers, Bitboard.rook_d_ranks, Bitboard.rook_d_files);
}

comptime {
    std.debug.assert(getRookAttacks(.f5, 0x20004400002000) == 9042779302797312);
    std.debug.assert(getRookAttacks(.f5, 0x221004400002803) == 9042779302797312);
    std.debug.assert(getRookAttacks(.f5, 0x221008400002803) == 9043329058611200);
    std.debug.assert(getRookAttacks(.f5, 0x221000400002803) == 9043329058611200);
}

export fn getRookAttacksExp(square: u8, blockers: u64) u64 {
    return getRookAttacks(Square.fromInt(@intCast(square)), blockers);
}
