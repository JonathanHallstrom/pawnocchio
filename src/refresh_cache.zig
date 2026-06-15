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

const root = @import("root.zig");
const Board = root.Board;
const Square = root.Square;
const PieceType = root.PieceType;
const Bitboard = root.Bitboard;
const Colour = root.Colour;
const nnue = root.nnue;

const NNCacheEntry = struct {
    accumulator: nnue.Accumulator,
    pieces: [6]u64,
    sides: [2]u64,

    fn refresh(noalias self: *NNCacheEntry, weights: *const nnue.arch.Weights, stm: Colour, board: *const Board, mirror: nnue.MirroringType) *const nnue.Accumulator {
        const us_king = Square.fromBitboard(board.kingFor(stm));
        var adds: [32]*const nnue.arch.RawAccumulator = undefined;
        var num_adds: usize = 0;
        var subs: [32]*const nnue.arch.RawAccumulator = undefined;
        var num_subs: usize = 0;
        for (PieceType.all) |pt| {
            inline for ([2]Colour{ .white, .black }) |col| {
                const current = board.pieceFor(col, pt);
                const cached = self.pieces[pt.toInt()] & self.sides[col.toInt()];

                {
                    var iter = Bitboard.iterator(current & ~cached);
                    while (iter.next()) |sq| {
                        adds[num_adds] = nnue.feature(weights, stm, us_king, .psqt, .init(col, pt, sq), mirror);
                        num_adds += 1;
                    }
                }
                {
                    var iter = Bitboard.iterator(~current & cached);
                    while (iter.next()) |sq| {
                        subs[num_subs] = nnue.feature(weights, stm, us_king, .psqt, .init(col, pt, sq), mirror);
                        num_subs += 1;
                    }
                }
            }
        }
        self.accumulator.addSubInPlace(adds[0..num_adds], subs[0..num_subs]);
        self.pieces = board.pieceBBs().*;
        self.sides = .{ board.white(), board.black() };
        return &self.accumulator;
    }
};

pub fn refreshCache(comptime mirrored: bool, comptime bucket_count: usize) type {
    const empty = !mirrored and bucket_count < 2;
    return struct {
        const Self = @This();

        data: if (empty) void else [2][@as(usize, 1) + @intFromBool(mirrored)][bucket_count]NNCacheEntry,
        generation: [2]nnue.AccumulatorHalf.Generation,

        pub fn initInPlace(self: *Self, weights: *const nnue.arch.Weights) void {
            self.generation = .{ 0, 0 };
            if (empty) return;
            for (&self.data) |*stm| {
                for (stm) |*subarray| {
                    for (subarray) |*e| {
                        @memcpy(&e.accumulator.data, &weights.input.ft_b);
                        @memset(&e.pieces, 0);
                        @memset(&e.sides, 0);
                    }
                }
            }
        }

        pub inline fn refresh(noalias self: *Self, weights: *const nnue.arch.Weights, stm: Colour, board: *const Board) nnue.AccumulatorHalf {
            if (empty) unreachable;
            self.generation[stm.toInt()] += 1;
            const king_sq = Square.fromBitboard(board.kingFor(stm));
            const bucket = nnue.arch.whichInputBucket((if (stm == .white) king_sq else king_sq.flipRank()).toInt());
            var mirror: nnue.MirroringType = undefined;
            mirror.write(Square.fromBitboard(board.kingFor(stm)).getFile().toInt() >= 4);
            const mirror_idx = if (mirrored) @intFromBool(mirror.read()) else 0;
            return .{
                .ptr = self.data[stm.toInt()][mirror_idx][bucket].refresh(weights, stm, board, mirror),
                .generation = self.generation[stm.toInt()],
            };
        }

        pub inline fn currentGeneration(self: *const Self, stm: Colour) nnue.AccumulatorHalf.Generation {
            return self.generation[stm.toInt()];
        }
    };
}
