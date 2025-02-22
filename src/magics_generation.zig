const std = @import("std");
const Bitboard = @import("Bitboard.zig");
const Random = std.Random;
const PieceType = @import("piece_type.zig").PieceType;
const Square = @import("square.zig").Square;
const magics = @import("magics.zig");
const MagicEntry = magics.MagicEntry;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

fn computeAttacks(square: Square, blockers: u64, d_ranks: anytype, d_files: anytype) u64 {
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

pub fn computeBishopAttacks(square: Square, blockers: u64) u64 {
    return computeAttacks(square, blockers, Bitboard.bishop_d_ranks, Bitboard.bishop_d_files);
}

pub fn computeRookAttacks(square: Square, blockers: u64) u64 {
    return computeAttacks(square, blockers, Bitboard.rook_d_ranks, Bitboard.rook_d_files);
}

pub fn generateBishopAttackArrayInPlace(ms: [64]MagicEntry, arr: []u64) void {
    for (ms, 0..) |m, i| {
        var blockers: u64 = 0;
        while (true) {
            arr[m.getIndex(blockers)] = computeBishopAttacks(Square.fromInt(@intCast(i)), blockers);
            blockers = blockers -% m.mask & m.mask;
            if (blockers == 0) break;
        }
    }
}

pub fn generateRookAttackArrayInPlace(ms: [64]MagicEntry, arr: []u64) void {
    for (ms, 0..) |m, i| {
        var blockers: u64 = 0;
        while (true) {
            arr[m.getIndex(blockers)] = computeRookAttacks(Square.fromInt(@intCast(i)), blockers);
            blockers = blockers -% m.mask & m.mask;
            if (blockers == 0) break;
        }
    }
}

pub fn generateBishopAttackArray(comptime ms: [64]MagicEntry, comptime len: comptime_int) [len]u64 {
    comptime { // enforce this only being run at compile time
        @setEvalBranchQuota(1 << 30);
        var arr: [len]u64 = .{0} ** len;
        for (ms, 0..) |m, i| {
            var blockers: u64 = 0;
            while (true) {
                arr[m.getIndex(blockers)] = computeBishopAttacks(Square.fromInt(i), blockers);
                blockers = blockers -% m.mask & m.mask;
                if (blockers == 0) break;
            }
        }
        return arr;
    }
}

pub fn generateRookAttackArray(comptime ms: [64]MagicEntry, comptime len: comptime_int) [len]u64 {
    comptime { // enforce this only being run at compile time
        @setEvalBranchQuota(1 << 30);
        var arr: [len]u64 = .{0} ** len;
        for (ms, 0..) |m, i| {
            var blockers: u64 = 0;
            while (true) {
                arr[m.getIndex(blockers)] = computeRookAttacks(Square.fromInt(i), blockers);
                blockers = blockers -% m.mask & m.mask;
                if (blockers == 0) break;
            }
        }
        return arr;
    }
}
fn random(r: Random) u64 {
    return r.int(u64) & r.int(u64) & r.int(u64);
}

fn validRandom(r: Random, b: u64) u64 {
    var res = random(r);
    while (@popCount(@as(u128, res) * b >> 56 & 0xff) < 6) res = random(r);
    return res;
}

fn neededArrayLen(bishops: bool, s: Square, m: MagicEntry) ?u32 {
    var arr: [1 << 12]?u64 = .{null} ** (1 << 12);
    var blockers: u64 = 0;
    const len = @as(u64, 1) << @intCast(@popCount(m.mask));
    var biggest_i: u32 = 0;
    while (true) {
        const i = m.getIndex(blockers);
        if (i >= len) {
            return null;
        }
        biggest_i = @max(biggest_i, @as(u32, @intCast(i)));
        const attacks = if (bishops) computeBishopAttacks(s, blockers) else computeRookAttacks(s, blockers);
        if (arr[i]) |existing| {
            if (existing != attacks) {
                return null;
            }
        } else {
            arr[i] = attacks;
        }

        blockers = blockers -% m.mask & m.mask;
        if (blockers == 0) break;
    }
    return biggest_i;
}

fn findMagic(bishops: bool, s: Square, b: u64, r: anytype) struct { MagicEntry, u32 } {
    const bits = @popCount(b);
    var m = MagicEntry{
        .magic = validRandom(r, b),
        .mask = b,
        .offs = 0,
        .shift = 64 - bits,
    };

    var len = neededArrayLen(bishops, s, m);
    while (len == null) {
        m = MagicEntry{
            .magic = validRandom(r, b),
            .mask = b,
            .offs = 0,
            .shift = 64 - bits,
        };
        len = neededArrayLen(bishops, s, m);
    }
    return .{ m, len.? };
}

fn findMagics(bishops: bool, r: Random) struct { [64]MagicEntry, usize } {
    var res: [64]MagicEntry = undefined;

    var offs: u32 = 0;
    inline for (0..64) |i| {
        // std.debug.print("{s}: {}\n", .{ if (bishops) "bishop" else "rook", i });
        const s = Square.fromInt(i);
        const mask = if (bishops) Bitboard.bishopRelevantSquares(s.toBitboard()) else Bitboard.rookRelevantSquares(s.toBitboard());

        res[i], const len = findMagic(bishops, s, mask, r);
        res[i].offs = offs;
        offs += len + 1;
    }
    return .{ res, offs };
}

pub fn main() void {
    var rng = std.Random.DefaultCsprng.init(.{
        83,  8,   124, 62,
        209, 228, 102, 90,
        139, 94,  247, 234,
        23,  237, 227, 83,
        185, 187, 249, 170,
        187, 168, 131, 116,
        40,  160, 121, 239,
        88,  54,  185, 83,
    });

    for (0..1024) |_|
        rng.addEntropy(&std.mem.toBytes(std.time.nanoTimestamp()));

    const bishop_magics, const bishop_arr_len = findMagics(true, rng.random());
    const rook_magics, const rook_arr_len = findMagics(false, rng.random());

    std.debug.print("{any}\n", .{bishop_magics});
    std.debug.print("\n", .{});
    std.debug.print("{any}\n", .{rook_magics});
    std.debug.print("bishop arr: {} rook arr: {}\n", .{ bishop_arr_len, rook_arr_len });
}
