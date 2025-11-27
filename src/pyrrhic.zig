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
const Square = root.Square;
const ScoredMove = root.ScoredMove;

const use_tbs = root.use_tbs;

const c = if (use_tbs) @cImport(@cInclude("tbprobe.h")) else undefined;

var tbs_init = false;
pub fn init(path: [*:0]const u8) error{TBInitializationFailed}!void {
    if (!use_tbs) {
        return;
    }
    tbs_init = true;
    if (!c.tb_init(path)) {
        return error.TBInitializationFailed;
    }
}

pub fn deinit() void {
    if (!use_tbs) {
        return;
    }

    if (tbs_init) {
        tbs_init = false;
        c.tb_free();
    }
}

pub fn probeWDL(board: *const Board) ?WDL {
    if (!use_tbs or !tbs_init) {
        return null;
    }
    if (board.halfmove > 0 or
        board.castling_rights.rawCastlingAvailability() != 0 or
        @popCount(board.white | board.black) > c.TB_LARGEST)
    {
        return null;
    }

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
        board.stm == .white,
    );

    return switch (probe_result) {
        c.TB_WIN => .win,

        c.TB_DRAW,
        c.TB_CURSED_WIN,
        c.TB_BLESSED_LOSS,
        => .draw,

        c.TB_LOSS => .loss,
        c.TB_RESULT_FAILED => null,
        else => unreachable,
    };
}

pub fn probeRootDTZ(
    board: *const Board,
    has_repetition: bool,
) ?struct { WDL, root.BoundedArray(ScoredMove, c.TB_MAX_MOVES) } {
    if (!use_tbs or !tbs_init) {
        return null;
    }
    if (board.castling_rights.rawCastlingAvailability() != 0 or
        @popCount(board.white | board.black) > c.TB_LARGEST)
    {
        return null;
    }
    var tb_results = std.mem.zeroes(c.TbRootMoves);

    const probe_result = c.tb_probe_root_dtz(
        board.white,
        board.black,
        board.kings(),
        board.queens(),
        board.rooks(),
        board.bishops(),
        board.knights(),
        board.pawns(),
        board.halfmove,
        if (board.ep_target) |ep| ep.toInt() else 0,
        board.stm == .white,
        has_repetition,
        &tb_results,
    );

    if (tb_results.size == 0) {
        return null;
    }
    if (probe_result == c.TB_RESULT_FAILED) {
        return null;
    }

    var scored: root.movegen.MoveListReceiver = .{};
    switch (board.stm) {
        inline else => |stm| {
            root.movegen.generateAllNoisies(stm, board, &scored);
            root.movegen.generateAllQuiets(stm, board, &scored);
        },
    }

    const tb_moves = tb_results.moves[0..tb_results.size];
    var res: root.BoundedArray(ScoredMove, c.TB_MAX_MOVES) = .{};
    for (tb_moves) |tb_move| {
        const from = Square.fromInt(@intCast(c.PYRRHIC_MOVE_FROM(tb_move.move)));
        const to = Square.fromInt(@intCast(c.PYRRHIC_MOVE_TO(tb_move.move)));
        const is_ep = c.PYRRHIC_MOVE_IS_ENPASS(tb_move.move);
        var promo_type_opt: ?root.PieceType = null;
        if (c.PYRRHIC_MOVE_IS_NPROMO(tb_move.move)) promo_type_opt = .knight;
        if (c.PYRRHIC_MOVE_IS_BPROMO(tb_move.move)) promo_type_opt = .bishop;
        if (c.PYRRHIC_MOVE_IS_RPROMO(tb_move.move)) promo_type_opt = .rook;
        if (c.PYRRHIC_MOVE_IS_QPROMO(tb_move.move)) promo_type_opt = .queen;
        const capture = board.occupancyFor(board.stm.flipped()) & @as(u64, 1) << to.toInt() != 0;
        var move = root.Move.quiet(from, to);
        if (is_ep) {
            move = root.Move.enPassant(from, to);
        } else if (promo_type_opt) |promo_type| {
            move = root.Move.promo(from, to, promo_type);
        } else if (capture) {
            move = root.Move.capture(from, to);
        }

        res.appendAssumeCapacity(.{
            .move = move,
            .score = tb_move.tbRank,
        });
    }
    std.mem.sort(ScoredMove, res.slice(), void{}, struct {
        fn impl(_: void, lhs: ScoredMove, rhs: ScoredMove) bool {
            return lhs.score > rhs.score;
        }
    }.impl);
    if (res.slice().len > 0) {
        while (res.slice()[res.slice().len - 1].score < res.slice()[0].score) {
            _ = res.pop();
        }
    }
    const win = 262144 - 100;
    var wdl: WDL = .draw;
    if (res.slice()[0].score > win) {
        wdl = .win;
    } else if (res.slice()[0].score < -win) {
        wdl = .loss;
    }

    return .{ wdl, res };
}

// exports
pub export fn popcount(x: u64) u8 {
    return @popCount(x);
}
pub export fn getlsb(x: u64) u8 {
    return @ctz(x);
}
pub export fn poplsb(x: *u64) u8 {
    const res = @ctz(x.*);
    x.* &= x.* -% 1;
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
