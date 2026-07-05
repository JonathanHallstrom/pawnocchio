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
const Bitboard = root.Bitboard;
const Colour = root.Colour;
const nnue = root.nnue;
const simd = root.simd;

const USE_VBMI2_REFRESH = simd.HAS_VBMI2;
const USE_AVX512F_REFRESH = @import("builtin").cpu.has(.x86, .avx512f);

fn psqIndexVector(mailbox: @Vector(64, u8), stm: Colour, flip_xor: u16) @Vector(64, u16) {
    const c: @Vector(64, u16) = mailbox;
    const side_rel = (c ^ @as(@Vector(64, u16), @splat(stm.toInt()))) & @as(@Vector(64, u16), @splat(1));
    return side_rel * @as(@Vector(64, u16), @splat(384)) +
        ((c >> @splat(1)) << @splat(6)) + (std.simd.iota(u16, 64) ^ @as(@Vector(64, u16), @splat(flip_xor)));
}

const NNCacheEntry = struct {
    accumulator: nnue.Accumulator,
    mailbox: [64]u8,

    fn refresh(noalias self: *NNCacheEntry, weights: *const nnue.arch.Weights, stm: Colour, board: *const Board, mirror: nnue.MirroringType) *const nnue.Accumulator {
        const us_king = Square.fromBitboard(board.kingFor(stm));
        var adds: [64]u16 = undefined;
        var num_adds: usize = 0;
        var subs: [64]u16 = undefined;
        var num_subs: usize = 0;
        const cur: @Vector(64, u8) = board.mailbox;
        const old: @Vector(64, u8) = self.mailbox;
        const EMPTY_VEC: @Vector(64, u8) = @splat(Board.MAILBOX_EMPTY);
        const diff: u64 = @bitCast(cur != old);
        const adds_mask = diff & @as(u64, @bitCast(cur != EMPTY_VEC));
        const subs_mask = diff & @as(u64, @bitCast(old != EMPTY_VEC));
        if (USE_VBMI2_REFRESH) {
            const flip_xor: u16 = @as(u16, if (stm == .black) 56 else 0) | @as(u16, if (mirror.read()) 7 else 0);
            const cur_idx: [2]@Vector(32, u16) = @bitCast(psqIndexVector(cur, stm, flip_xor));
            const old_idx: [2]@Vector(32, u16) = @bitCast(psqIndexVector(old, stm, flip_xor));

            inline for (0..2) |h| {
                const am: u32 = @truncate(adds_mask >> (32 * h));
                const ac: [32]u16 = simd.vpcompress(cur_idx[h], am);
                @memcpy(adds[num_adds..][0..32], &ac);
                num_adds += @popCount(am);

                const sm: u32 = @truncate(subs_mask >> (32 * h));
                const sc: [32]u16 = simd.vpcompress(old_idx[h], sm);
                @memcpy(subs[num_subs..][0..32], &sc);
                num_subs += @popCount(sm);
            }
        } else if (USE_AVX512F_REFRESH) {
            const flip_xor: u16 = @as(u16, if (stm == .black) 56 else 0) | @as(u16, if (mirror.read()) 7 else 0);
            const cur_q: [4]@Vector(16, u16) = @bitCast(psqIndexVector(cur, stm, flip_xor));
            const old_q: [4]@Vector(16, u16) = @bitCast(psqIndexVector(old, stm, flip_xor));

            inline for (0..4) |q| {
                const am: u16 = @truncate(adds_mask >> (16 * q));
                const ac: [16]u16 = @as(@Vector(16, u16), @intCast(simd.vpcompress(@as(@Vector(16, u32), cur_q[q]), am)));
                @memcpy(adds[num_adds..][0..16], &ac);
                num_adds += @popCount(am);

                const sm: u16 = @truncate(subs_mask >> (16 * q));
                const sc: [16]u16 = @as(@Vector(16, u16), @intCast(simd.vpcompress(@as(@Vector(16, u32), old_q[q]), sm)));
                @memcpy(subs[num_subs..][0..16], &sc);
                num_subs += @popCount(sm);
            }
        } else {
            var adds_iter = Bitboard.iterator(adds_mask);
            while (adds_iter.next()) |sq| {
                adds[num_adds] = nnue.featureIndex(stm, .psqt, .initColoured(.fromInt(board.mailbox[sq.toInt()]), sq), mirror);
                num_adds += 1;
            }
            var subs_iter = Bitboard.iterator(subs_mask);
            while (subs_iter.next()) |sq| {
                subs[num_subs] = nnue.featureIndex(stm, .psqt, .initColoured(.fromInt(self.mailbox[sq.toInt()]), sq), mirror);
                num_subs += 1;
            }
        }
        self.accumulator.addSubInPlace(
            weights.input.flatPSQWeights(nnue.arch.inputs.whichInputBucket(stm, us_king)),
            adds[0..num_adds],
            subs[0..num_subs],
        );
        self.mailbox = board.mailbox;
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
                        @memset(&e.mailbox, Board.MAILBOX_EMPTY);
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
