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

    fn refresh(noalias self: *NNCacheEntry, weights: *const nnue.Weights, comptime stm: Colour, board: *const Board, mirror: nnue.MirroringType) *const nnue.Accumulator {
        const us_king = Square.fromBitboard(board.kingFor(stm));
        var adds: [64]usize = undefined;
        var num_adds: usize = 0;
        var subs: [64]usize = undefined;
        var num_subs: usize = 0;
        for (PieceType.all) |pt| {
            inline for ([2]Colour{ .white, .black }) |col| {
                const current = board.pieceFor(col, pt);
                const cached = self.pieces[pt.toInt()] & self.sides[col.toInt()];

                {
                    var iter = Bitboard.iterator(current & ~cached);
                    while (iter.next()) |sq| {
                        const add_idx = nnue.idx(stm, col, us_king, pt, sq, mirror);
                        adds[num_adds] = add_idx;
                        num_adds += 1;
                    }
                }
                {
                    var iter = Bitboard.iterator(~current & cached);
                    while (iter.next()) |sq| {
                        const sub_idx = nnue.idx(stm, col, us_king, pt, sq, mirror);
                        subs[num_subs] = sub_idx;
                        num_subs += 1;
                    }
                }
            }
        }
        while (num_adds >= 4) : (num_adds -= 4) {
            for (0..nnue.L1_SIZE) |i| {
                self.accumulator.data[i] +=
                    (&weights.ft_w)[adds[num_adds - 4] * nnue.L1_SIZE + i] +
                    (&weights.ft_w)[adds[num_adds - 3] * nnue.L1_SIZE + i] +
                    (&weights.ft_w)[adds[num_adds - 2] * nnue.L1_SIZE + i] +
                    (&weights.ft_w)[adds[num_adds - 1] * nnue.L1_SIZE + i];
            }
        }
        while (num_adds >= 1) : (num_adds -= 1) {
            for (0..nnue.L1_SIZE) |i| {
                self.accumulator.data[i] +=
                    (&weights.ft_w)[adds[num_adds - 1] * nnue.L1_SIZE + i];
            }
        }
        while (num_subs >= 4) : (num_subs -= 4) {
            for (0..nnue.L1_SIZE) |i| {
                self.accumulator.data[i] -=
                    (&weights.ft_w)[subs[num_subs - 4] * nnue.L1_SIZE + i] +
                    (&weights.ft_w)[subs[num_subs - 3] * nnue.L1_SIZE + i] +
                    (&weights.ft_w)[subs[num_subs - 2] * nnue.L1_SIZE + i] +
                    (&weights.ft_w)[subs[num_subs - 1] * nnue.L1_SIZE + i];
            }
        }
        while (num_subs >= 1) : (num_subs -= 1) {
            for (0..nnue.L1_SIZE) |i| {
                self.accumulator.data[i] -=
                    (&weights.ft_w)[subs[num_subs - 1] * nnue.L1_SIZE + i];
            }
        }
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

        pub fn initInPlace(self: *Self, weights: *const nnue.Weights) void {
            self.generation = .{ 0, 0 };
            if (empty) return;
            for (&self.data) |*stm| {
                for (stm) |*subarray| {
                    for (subarray) |*e| {
                        @memcpy(&e.accumulator.data, &weights.ft_b);
                        @memset(&e.pieces, 0);
                        @memset(&e.sides, 0);
                    }
                }
            }
        }

        pub inline fn refresh(noalias self: *Self, weights: *const nnue.Weights, comptime stm: Colour, board: *const Board) nnue.AccumulatorHalf {
            if (empty) unreachable;
            (&self.generation)[stm.toInt()] += 1;
            const bucket = nnue.whichInputBucket(stm, Square.fromBitboard(board.kingFor(stm)));
            var mirror: nnue.MirroringType = undefined;
            mirror.write(Square.fromBitboard(board.kingFor(stm)).getFile().toInt() >= 4);
            const mirror_idx = if (mirrored) @intFromBool(mirror.read()) else 0;
            return .{
                .ptr = (&self.data)[stm.toInt()][mirror_idx][bucket].refresh(weights, stm, board, mirror),
                .generation = (&self.generation)[stm.toInt()],
            };
        }

        pub inline fn currentGeneration(self: *const Self, comptime stm: Colour) nnue.AccumulatorHalf.Generation {
            return (&self.generation)[stm.toInt()];
        }
    };
}
