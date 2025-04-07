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

const PieceType = root.PieceType;
const Square = root.Square;
const Bitboard = root.Bitboard;
const attacks = root.attacks;
const Board = root.Board;
const Move = root.Move;

const SEE_weight = [_]i16{ 93, 308, 346, 521, 994, 0 };

inline fn getAttacks(comptime turn: anytype, comptime tp: PieceType, sq: Square, occ: u64) u64 {
    return switch (tp) {
        .pawn => Bitboard.move(sq.toBitboard(), if (turn == .white) -1 else 1, 1) | Bitboard.move(sq.toBitboard(), if (turn == .white) -1 else 1, -1),
        .knight => Bitboard.knightMoves(sq),
        .bishop => attacks.getBishopAttacks(sq, occ),
        .rook => attacks.getRookAttacks(sq, occ),
        .queen => attacks.getBishopAttacks(sq, occ) | attacks.getRookAttacks(sq, occ),
        .king => Bitboard.kingMoves(sq),
    };
}

pub fn value(pt: PieceType) i16 {
    return SEE_weight[pt.toInt()];
}

pub fn scoreMove(board: *const Board, move: Move, threshold: i32) bool {
    const from = move.from();
    const to = move.to();
    const from_type = (&board.mailbox)[from.toInt()].?.toPieceType();
    var captured_type: ?PieceType = null;
    var captured_value: i16 = 0;
    if (board.isEnPassant(move)) {
        captured_type = .pawn;
        captured_value = value(.pawn);
    } else if (board.isCapture(move)) {
        captured_type = (&board.mailbox)[to.toInt()].?.toPieceType();
        captured_value = value(captured_type.?);
    }

    var score = captured_value - threshold;
    if (board.isPromo(move)) {
        const pt = move.promoType();
        const promo_value = SEE_weight[pt.toInt()];
        score += promo_value - SEE_weight[0]; // add promoted piece, remove pawn since it disappears
        if (score < 0) return false; // if we're worse off than we need to be even just after promoting and possibly capturing, theres no point continuing

        score -= promo_value; // remove the promoted piece, assuming it was captured, if we're still okay even assuming we lose it immeditely, we're good!
        if (score >= 0) return true;
    } else {
        if (score < 0) return false; // if the capture is immeditely not good enough just return
        score -= SEE_weight[from_type.toInt()];
        if (score >= 0) return true; // if we can lose the piece we used to capture and still be okay, we're good!
    }

    var occ = board.occupancy() & ~from.toBitboard() & ~to.toBitboard();
    const kings = board.kings();
    const queens = board.queens();
    const rooks = board.rooks() | queens;
    const bishops = board.bishops() | queens;
    const knights = board.knights();

    var stm = board.stm.flipped();

    var attackers =
        (getAttacks(undefined, .king, to, occ) & kings) |
        (getAttacks(undefined, .knight, to, occ) & knights) |
        (getAttacks(undefined, .bishop, to, occ) & bishops) |
        (getAttacks(undefined, .rook, to, occ) & rooks) |
        (getAttacks(.white, .pawn, to, occ) & board.pawnsFor(.white)) |
        (getAttacks(.black, .pawn, to, occ) & board.pawnsFor(.black));

    var attacker: PieceType = undefined;
    while (true) {
        if (attackers & board.occupancyFor(stm) == 0) {
            break;
        }
        for (PieceType.all) |pt| {
            const potential_attacker_board = board.pieces[pt.toInt()] & board.occupancyFor(stm) & attackers;
            if (potential_attacker_board != 0) {
                occ ^= potential_attacker_board & -%potential_attacker_board;
                attacker = pt;
                break;
            }
        }
        // if our last attacker is the king, and they still have an attacker, we can't actually recapture
        if (attacker == .king and attackers & board.occupancyFor(stm.flipped()) != 0) {
            break;
        }

        switch (attacker) {
            .pawn, .bishop => attackers |= getAttacks(undefined, .bishop, to, occ),
            .rook => attackers |= getAttacks(undefined, .rook, to, occ),
            .queen => attackers |= getAttacks(undefined, .queen, to, occ),
            else => {},
        }

        attackers &= occ;
        score = -score - 1 - SEE_weight[attacker.toInt()];
        stm = stm.flipped();

        if (score >= 0) {
            break;
        }
    }
    return stm != board.stm;
}

test scoreMove {
    try std.testing.expect(scoreMove(&(Board.parseFen("k6b/8/8/8/8/8/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2p5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k7/8/8/8/8/2p5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(scoreMove(&(Board.parseFen("k7/8/8/8/8/2q5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2q5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k3n2r/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), 500));
    try std.testing.expect(scoreMove(&(Board.parseFen("k3n3/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), 500));
}
