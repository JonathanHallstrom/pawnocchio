const std = @import("std");
const Square = @import("square.zig").Square;
const Bitboard = @import("Bitboard.zig");
const magics_generation = @import("magics_generation.zig");

pub const magic_impl = @import("classical_magics_impl.zig");
pub const rook_magics = magic_impl.rook_magics;
pub const bishop_magics = magic_impl.bishop_magics;
pub const MagicEntry = magic_impl.MagicEntry;

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

const use_magics = true;
var init_once = std.once(init);

var bishop_attacks: [magic_impl.bishop_array_size]u64 = undefined;
var rook_attacks: [magic_impl.rook_array_size]u64 = undefined;

pub fn getBishopAttacks(square: Square, blockers: u64) u64 {
    if (@import("builtin").is_test and !@inComptime()) init_once.call();
    if (use_magics and !@inComptime()) {
        const from_magics = (&bishop_attacks)[@intCast(bishop_magics[square.toInt()].getIndex(blockers))];
        return from_magics;
    } else {
        const from_compute = getAttacks(square, blockers, Bitboard.bishop_d_ranks, Bitboard.bishop_d_files);
        return from_compute;
    }
}

pub fn getRookAttacks(square: Square, blockers: u64) u64 {
    if (@import("builtin").is_test and !@inComptime()) init_once.call();
    if (use_magics and !@inComptime()) {
        const from_magics = (&rook_attacks)[@intCast(rook_magics[square.toInt()].getIndex(blockers))];
        return from_magics;
    } else {
        const from_compute = getAttacks(square, blockers, Bitboard.rook_d_ranks, Bitboard.rook_d_files);
        return from_compute;
    }
}

pub fn init() void {
    magics_generation.generateBishopAttackArrayInPlace(bishop_magics, &bishop_attacks);
    magics_generation.generateRookAttackArrayInPlace(rook_magics, &rook_attacks);
}

export fn getRookAttacksExp(square: u8, blockers: u64) u64 {
    return getRookAttacks(Square.fromInt(@intCast(square)), blockers);
}
