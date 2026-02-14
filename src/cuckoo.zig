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

const BoundedArray = root.BoundedArray;
const movegen = root.movegen;
const Move = root.Move;
const Board = root.Board;
const Colour = root.Colour;
const PieceType = root.PieceType;
const Square = root.Square;

const SIZE = 8192;
var keys: [SIZE]u64 = undefined;
var moves: [SIZE]Move = .{Move.init()} ** SIZE;

fn h1(x: u64) usize {
    return @intCast(x % SIZE);
}

fn h2(x: u64) usize {
    return @intCast(x / SIZE % SIZE);
}

pub fn init() void {
    var count: usize = 0;
    inline for ([_]Colour{ .white, .black }) |col| {
        for ([_]PieceType{ .knight, .bishop, .rook, .queen, .king }) |pt| {
            for (0..64) |i| {
                const from = Square.fromInt(@intCast(i));
                var iter = root.Bitboard.iterator(movegen.getAttacks(col, pt, from, 0));
                while (iter.next()) |to| {
                    if (to.toInt() < from.toInt()) {
                        // if we swap to and from it will collide
                        continue;
                    }
                    var key =
                        root.zobrist.piece(col, pt, from) ^
                        root.zobrist.piece(col, pt, to) ^
                        root.zobrist.turn();
                    var move = Move.quiet(from, to);

                    var slot = h1(key);
                    while (true) {
                        std.mem.swap(u64, &keys[slot], &key);
                        std.mem.swap(Move, &moves[slot], &move);

                        if (move.isNull()) {
                            break;
                        }

                        slot = if (slot == h1(key)) h2(key) else h1(key);
                    }

                    count += 1;
                }
            }
        }
    }
    std.debug.assert(count == 3668);
}

fn tryMagic(i: usize, x: u64) struct { u64, bool } {
    var successes: u64 = 0;
    var seen: [256]bool = @splat(false);

    var bb: u64 = 0;
    inline for ([_]Colour{ .white, .black }) |col| {
        for ([_]PieceType{ .knight, .bishop, .rook, .queen, .king }) |pt| {
            const from = Square.fromInt(@intCast(i));
            var iter = root.Bitboard.iterator(movegen.getAttacks(col, pt, from, 0));
            while (iter.next()) |to| {
                if (to.toInt() < from.toInt()) {
                    // if we swap to and from it will collide
                    continue;
                }
                bb |= to.toBitboard();
                const key =
                    root.zobrist.piece(col, pt, from) ^
                    root.zobrist.piece(col, pt, to) ^
                    root.zobrist.turn();
                // var move = Move.quiet(from, to);

                const entry = &seen[(key *% x >> 32) % seen.len];
                if (entry.*) {
                    return .{ successes, false };
                }
                entry.* = true;
                successes += 1;
            }
        }
    }
    std.debug.print("{}\n", .{bb});
    return .{ successes, true };
}

pub fn tryMagics() bool {
    var prng = std.Random.DefaultCsprng.init(@splat(0));

    for (0..64) |i| {
        var highest: u64 = 0;
        for (0..16 << 30) |iter| {
            const val = prng.random().int(u64);
            // const val = iter;

            const successes, const worked = tryMagic(i, val);

            if (worked) {
                std.debug.print("{} {} {}\n", .{ i, successes, iter });
            }
            highest = @max(highest, successes);
            if (worked) {
                break;
            }
        }
    }
    return false;
}

pub fn hasUpcomingRepetition(
    b: *const Board,
    tree_hashes: []const u64,
    before_root_hashes: []const u64,
) bool {
    const occ: u64 = b.occupancy();
    const original = b.hash;

    const num_to_check = @min(b.halfmove, tree_hashes.len - 1);
    if (num_to_check < 3) {
        return false;
    }

    var i: usize = 3;
    while (i <= num_to_check) : (i += 2) {
        const cur = tree_hashes[tree_hashes.len - i - 1];

        const diff = original ^ cur;
        var slot = h1(diff);
        slot = if (diff == keys[slot]) slot else h2(diff);

        if (diff != keys[slot]) {
            continue;
        }

        const move = moves[slot];

        if (occ & root.Bitboard.queenRayBetweenExclusive(move.from(), move.to()) == 0) {
            if (b.occupancyFor(b.stm) & (move.from().toBitboard() | move.to().toBitboard()) != 0) {
                return true;
            }
        }
    }

    for (before_root_hashes) |cur| {
        const diff = original ^ cur;
        var slot = h1(diff);
        slot = if (diff == keys[slot]) slot else h2(diff);

        if (diff != keys[slot]) {
            continue;
        }

        const move = moves[slot];

        if (occ & root.Bitboard.queenRayBetweenExclusive(move.from(), move.to()) == 0) {
            return true;
        }
    }
    return false;
}
