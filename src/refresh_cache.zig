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
const Board = root.Board;
const Square = root.Square;
const PieceType = root.PieceType;
const Bitboard = root.Bitboard;
const Colour = root.Colour;
const nnue = @import("nnue.zig");

const NNCacheEntry = struct {
    accumulator: [nnue.HIDDEN_SIZE]i16,
    pieces: [6]u64,
    sides: [2]u64,

    fn store(noalias self: *NNCacheEntry, board: *const Board, acc: [*]i16) void {
        self.pieces = board.pieces;
        self.sides = .{ board.white, board.black };
        @memcpy(&self.accumulator, acc);
    }

    fn refresh(noalias self: *const NNCacheEntry, comptime stm: Colour, board: *const Board, noalias acc: [*]i16, mirror: nnue.MirroringType) void {
        const us_king = Square.fromBitboard(board.kingFor(stm));
        // std.debug.print("{any}\n", .{self.accumulator});
        @memcpy(acc, &self.accumulator);
        // if (@reduce(.Or, @as(@Vector(6, u64), self.pieces)) != 0) {
        //     std.debug.print("actual refresh\n", .{});
        // }
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
                        // std.debug.print("refresh add {} {}\n", .{ add_idx, nnue.weights.hidden_layer_weights[add_idx * nnue.HIDDEN_SIZE] });
                        adds[num_adds] = add_idx;
                        num_adds += 1;
                        // for (0..nnue.HIDDEN_SIZE) |i| {
                        //     acc[i] += nnue.weights.hidden_layer_weights[add_idx * nnue.HIDDEN_SIZE + i];
                        // }
                    }
                }
                {
                    var iter = Bitboard.iterator(~current & cached);
                    while (iter.next()) |sq| {
                        const sub_idx = nnue.idx(stm, col, us_king, pt, sq, mirror);
                        // std.debug.print("refresh sub {}\n", .{sub_idx});
                        subs[num_subs] = sub_idx;
                        num_subs += 1;
                        // for (0..nnue.HIDDEN_SIZE) |i| {
                        //     acc[i] -= nnue.weights.hidden_layer_weights[sub_idx * nnue.HIDDEN_SIZE + i];
                        // }
                    }
                }
            }
        }
        while (num_adds >= 4) : (num_adds -= 4) {
            for (0..nnue.HIDDEN_SIZE) |i| {
                acc[i] +=
                    nnue.weights.hidden_layer_weights[adds[num_adds - 4] * nnue.HIDDEN_SIZE + i] +
                    nnue.weights.hidden_layer_weights[adds[num_adds - 3] * nnue.HIDDEN_SIZE + i] +
                    nnue.weights.hidden_layer_weights[adds[num_adds - 2] * nnue.HIDDEN_SIZE + i] +
                    nnue.weights.hidden_layer_weights[adds[num_adds - 1] * nnue.HIDDEN_SIZE + i];
            }
        }
        while (num_adds >= 1) : (num_adds -= 1) {
            for (0..nnue.HIDDEN_SIZE) |i| {
                acc[i] +=
                    nnue.weights.hidden_layer_weights[adds[num_adds - 1] * nnue.HIDDEN_SIZE + i];
            }
        }
        while (num_subs >= 4) : (num_subs -= 4) {
            for (0..nnue.HIDDEN_SIZE) |i| {
                acc[i] -=
                    nnue.weights.hidden_layer_weights[subs[num_subs - 4] * nnue.HIDDEN_SIZE + i] +
                    nnue.weights.hidden_layer_weights[subs[num_subs - 3] * nnue.HIDDEN_SIZE + i] +
                    nnue.weights.hidden_layer_weights[subs[num_subs - 2] * nnue.HIDDEN_SIZE + i] +
                    nnue.weights.hidden_layer_weights[subs[num_subs - 1] * nnue.HIDDEN_SIZE + i];
            }
        }
        while (num_subs >= 1) : (num_subs -= 1) {
            for (0..nnue.HIDDEN_SIZE) |i| {
                acc[i] -=
                    nnue.weights.hidden_layer_weights[subs[num_subs - 1] * nnue.HIDDEN_SIZE + i];
            }
        }
    }
};

pub fn refreshCache(comptime mirrored: bool, comptime bucket_count: usize) type {
    const empty = !mirrored and bucket_count < 2;
    return struct {
        const Self = @This();

        data: if (empty) void else [2][@as(usize, 1) + @intFromBool(mirrored)][bucket_count]NNCacheEntry,

        pub fn initInPlace(self: *Self) void {
            for (&self.data) |*stm| {
                for (stm) |*subarray| {
                    for (subarray) |*e| {
                        std.debug.assert(nnue.weights.hidden_layer_biases[0] != 0);
                        @memcpy(&e.accumulator, &nnue.weights.hidden_layer_biases);
                        @memset(&e.pieces, 0);
                        @memset(&e.sides, 0);
                    }
                }
            }
        }

        pub inline fn refresh(noalias self: *const Self, comptime stm: Colour, board: *const Board, acc: [*]i16) void {
            if (empty) return;
            const bucket = nnue.whichInputBucket(stm, Square.fromBitboard(board.kingFor(stm)));
            var mirror: nnue.MirroringType = undefined;
            mirror.write(Square.fromBitboard(board.kingFor(stm)).getFile().toInt() >= 4);
            const mirror_idx = if (mirrored) @intFromBool(mirror.read()) else 0;
            return (&self.data)[stm.toInt()][mirror_idx][bucket].refresh(stm, board, acc, mirror);
        }

        pub inline fn store(noalias self: *Self, comptime stm: Colour, board: *const Board, acc: [*]i16) void {
            if (empty) return;
            const bucket = nnue.whichInputBucket(stm, Square.fromBitboard(board.kingFor(stm)));
            var mirror: nnue.MirroringType = undefined;
            mirror.write(Square.fromBitboard(board.kingFor(stm)).getFile().toInt() >= 4);
            const mirror_idx = if (mirrored) @intFromBool(mirror.read()) else 0;
            (&self.data)[stm.toInt()][mirror_idx][bucket].store(board, acc);
        }
    };
}
