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

pub fn hasUpcomingRepetition(
    b: *const Board,
    ply: usize,
    prev_hashes: []const u64,
) bool {
    const num_to_check = @min(b.halfmove, prev_hashes.len - 1);
    if (num_to_check < 3) {
        return false;
    }
    const occ: u64 = b.occupancy();
    const original = b.hash;

    var other_diffs_hash = ~(b.hash ^ prev_hashes[prev_hashes.len - 2]);

    var i: usize = 3;
    while (i <= num_to_check) : (i += 2) {
        const cur = prev_hashes[prev_hashes.len - i - 1];

        other_diffs_hash ^= ~(cur ^ prev_hashes[prev_hashes.len - i]);

        if (other_diffs_hash != 0) {
            continue;
        }

        const diff = original ^ cur;
        var slot = h1(diff);
        slot = if (diff == keys[slot]) slot else h2(diff);

        if (diff != keys[slot]) {
            continue;
        }

        const move = moves[slot];

        if (occ & root.Bitboard.queenRayBetweenExclusive(move.from(), move.to()) == 0) {
            if (ply > i) {
                return true;
            }

            return b.occupancyFor(b.stm) & (move.from().toBitboard() | move.to().toBitboard()) != 0;
        }
    }
    return false;
}
