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
const Colour = root.Colour;

const SEE_weight = [_]i16{ 93, 308, 346, 521, 994, 0 };

inline fn getAttacks(comptime stm: Colour, comptime tp: PieceType, sq: Square, occ: u64) u64 {
    return switch (tp) {
        .pawn => Bitboard.pawnAttacks(sq, stm),
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
        const promo_value = value(pt);
        score += promo_value - value(.pawn); // add promoted piece, remove pawn since it disappears
        if (score < 0) return false; // if we're worse off than we need to be even just after promoting and possibly capturing, theres no point continuing

        score -= promo_value; // remove the promoted piece, assuming it was captured, if we're still okay even assuming we lose it immeditely, we're good!
        if (score >= 0) return true;
    } else {
        if (score < 0) return false; // if the capture is immeditely not good enough just return
        score -= value(from_type);
        if (score >= 0) return true; // if we can lose the piece we used to capture and still be okay, we're good!
    }

    var occ = board.occupancy() & ~from.toBitboard() & ~to.toBitboard();
    const kings = board.kings();
    const queens = board.queens();
    const rooks = board.rooks() | queens;
    const bishops = board.bishops() | queens;
    const knights = board.knights();

    var stm = board.stm.flipped();

    const all_pinned = board.pinned[0] | board.pinned[1];

    const white_king_to_ray = Bitboard.extendingRayBb(Square.fromBitboard(board.kingFor(.white)), to);
    const black_king_to_ray = Bitboard.extendingRayBb(Square.fromBitboard(board.kingFor(.black)), to);

    const white_allowed_pinned = board.pinned[0] & white_king_to_ray;
    const black_allowed_pinned = board.pinned[1] & black_king_to_ray;

    const allowed_pinned = all_pinned & (white_allowed_pinned | black_allowed_pinned);

    const allowed = ~all_pinned | allowed_pinned;

    var attackers =
        (getAttacks(undefined, .king, to, occ) & kings) |
        (getAttacks(undefined, .knight, to, occ) & knights) |
        (getAttacks(undefined, .bishop, to, occ) & bishops) |
        (getAttacks(undefined, .rook, to, occ) & rooks) |
        (getAttacks(.white, .pawn, to, occ) & board.pawnsFor(.black)) |
        (getAttacks(.black, .pawn, to, occ) & board.pawnsFor(.white));

    attackers &= allowed;

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

        if (attacker == .pawn or attacker == .bishop or attacker == .queen)
            attackers |= getAttacks(undefined, .bishop, to, occ) & bishops;
        if (attacker == .rook or attacker == .queen)
            attackers |= getAttacks(undefined, .rook, to, occ) & rooks;

        attackers &= occ;
        score = -score - 1 - value(attacker);
        stm = stm.flipped();

        if (score >= 0) {
            break;
        }
    }
    return stm != board.stm;
}

test scoreMove {
    root.init();
    try std.testing.expect(scoreMove(&(Board.parseFen("k6b/8/8/8/8/8/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2p5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k7/8/8/8/8/2p5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(scoreMove(&(Board.parseFen("k7/8/8/8/8/2q5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2q5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k3n2r/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), 500));
    try std.testing.expect(scoreMove(&(Board.parseFen("k3n3/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), 500));
    try std.testing.expect(scoreMove(&(Board.parseFen("k3n3/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), 500));
    try std.testing.expect(scoreMove(&(Board.parseFen("rn2k2r/p3bpp1/2p4p/8/2P3Q1/1P1q4/P4P1P/RNB1K2R w KQkq - 0 8", false) catch unreachable), Move.capture(.g4, .g7), 0));
    try std.testing.expect(scoreMove(&(Board.parseFen("r1bq1rk1/pppp1Npp/2nb1n2/4p3/2B1P3/2P5/PP1P1PPP/RNBQK2R b KQ - 0 6", false) catch unreachable), Move.capture(.f8, .f7), 0));
    try std.testing.expect(scoreMove(&(Board.parseFen("r1bqkb1r/ppp1pppp/2n2n2/8/2BPP3/5P2/PP4PP/RNBQK1NR b KQkq - 0 5", false) catch unreachable), Move.capture(.c6, .d4), 0));
    try std.testing.expect(!scoreMove(&(Board.parseFen("3b2k1/1b6/8/3R2p1/4K3/5N2/8/8 w - - 0 1", false) catch unreachable), Move.capture(.f3, .g5), 0));
    try std.testing.expect(scoreMove(&(Board.parseFen("6k1/1b6/8/3B4/4K3/8/8/8 w - - 0 1", false) catch unreachable), Move.capture(.d5, .b7), 0));
}
