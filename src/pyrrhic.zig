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

const WDL = root.WDL;
const Board = root.Board;

const use_tbs = root.use_tbs;

const c = if (use_tbs) @cImport(@cInclude("tbprobe.h")) else undefined;

var needs_deinit = false;
pub fn init(path: []const u8) void {
    if (use_tbs) {
        needs_deinit = true;
        c.tb_init(path.ptr);
    }
}

pub fn deinit() void {
    if (use_tbs) {
        if (needs_deinit) {
            needs_deinit = false;
            c.tb_free();
        }
    }
}

pub fn probeWdl(board: *const Board) WDL {
    if (use_tbs) {
        const probe_result = c.tb_probe_wdl(
            board.white,
            board.black,
            board.kings(),
            board.queens(),
            board.rooks(),
            board.bishops(),
            board.knights(),
            board.pawns(),
            if (board.ep_target) |ep| ep.toInt() else 0,
            colorToPyrrhic(board.stm),
        );
        return switch (probe_result) {
            c.TB_WIN => .win,

            c.TB_DRAW,
            c.TB_CURSED_WIN,
            c.TB_BLESSED_LOSS,
            => .draw,

            c.TB_LOSS => .loss,
            else => unreachable,
        };
    } else {
        return undefined;
    }
}

// exports
pub export fn popcount(x: u64) u8 {
    return @popCount(x);
}
pub export fn getlsb(x: u64) u8 {
    return @clz(x);
}
pub export fn poplsb(x: *u64) u8 {
    const res = @clz(x.*);
    x.* &= x.* - 1;
    return res;
}

pub export fn pawnAttacks(col: u8, sq: u8) u64 {
    return root.Bitboard.pawnAttacks(sq, col);
}
pub export fn knightAttacks(sq: u8) u64 {
    return root.Bitboard.knightMoves(sq);
}
pub export fn bishopAttacks(sq: u8, occ: u64) u64 {
    return root.attacks.getBishopAttacks(root.Square.fromInt(sq), occ);
}
pub export fn rookAttacks(sq: u8, occ: u64) u64 {
    return root.attacks.getRookAttacks(root.Square.fromInt(sq), occ);
}
pub export fn queenAttacks(sq: u8, occ: u64) u64 {
    return root.attacks.getBishopAttacks(root.Square.fromInt(sq), occ) |
        root.attacks.getRookAttacks(root.Square.fromInt(sq), occ);
}
pub export fn kingAttacks(sq: u8) u64 {
    return root.Bitboard.kingMoves(sq);
}

fn colorToPyrrhic(col: root.Colour) bool {
    const PYRRHIC_WHITE: bool = c.PYRRHIC_WHITE != 0;
    const PYRRHIC_BLACK: bool = c.PYRRHIC_BLACK != 0;
    return if (col == .white) PYRRHIC_WHITE else PYRRHIC_BLACK;
}
