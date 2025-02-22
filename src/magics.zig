const std = @import("std");
const Square = @import("square.zig").Square;
const Bitboard = @import("Bitboard.zig");
const magics_generation = @import("magics_generation.zig");

pub const magic_impl = if (std.Target.x86.featureSetHas(@import("builtin").cpu.model.features, .bmi2))
    @import("pext_attacks_impl.zig")
else
    @import("black_magic_attacks_impl.zig");
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

pub fn getBishopAttacks(square: Square, blockers: u64) u64 {
    if (@import("builtin").is_test and !@inComptime()) init_once.call();
    if (use_magics and !@inComptime()) {
        return magic_impl.getBishopAttacks(square, blockers);
    } else {
        const from_compute = getAttacks(square, blockers, Bitboard.bishop_d_ranks, Bitboard.bishop_d_files);
        return from_compute;
    }
}

pub fn getRookAttacks(square: Square, blockers: u64) u64 {
    if (@import("builtin").is_test and !@inComptime()) init_once.call();
    if (use_magics and !@inComptime()) {
        return magic_impl.getRookAttacks(square, blockers);
    } else {
        const from_compute = getAttacks(square, blockers, Bitboard.rook_d_ranks, Bitboard.rook_d_files);
        return from_compute;
    }
}

pub fn init() void {
    magic_impl.init();
}
