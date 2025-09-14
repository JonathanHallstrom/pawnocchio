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

pub const Mode = enum {
    pruning,
    ordering,
};

pub fn value(pt: PieceType, comptime mode: Mode) i16 {
    const SEE_weight = if (mode == .pruning) [_]i16{
        @intCast(root.tunable_constants.see_pawn_pruning),
        @intCast(root.tunable_constants.see_knight_pruning),
        @intCast(root.tunable_constants.see_bishop_pruning),
        @intCast(root.tunable_constants.see_rook_pruning),
        @intCast(root.tunable_constants.see_queen_pruning),
        0,
    } else [_]i16{
        @intCast(root.tunable_constants.see_pawn_ordering),
        @intCast(root.tunable_constants.see_knight_ordering),
        @intCast(root.tunable_constants.see_bishop_ordering),
        @intCast(root.tunable_constants.see_rook_ordering),
        @intCast(root.tunable_constants.see_queen_ordering),
        0,
    };
    return (if (root.tuning.do_tuning) SEE_weight else comptime SEE_weight)[pt.toInt()];
}

const psqts: [6][64]i16 = .{
    .{
        0,   0,   0,   0,   0,   0,   0,  0,
        86,  122, 49,  83,  56,  114, 22, -23,
        -18, -5,  14,  19,  53,  44,  13, -32,
        -26, 1,   -6,  9,   11,  0,   5,  -35,
        -39, -14, -17, 0,   5,   -6,  -2, -37,
        -38, -16, -16, -22, -9,  -9,  21, -24,
        -47, -13, -32, -35, -27, 12,  26, -34,
        0,   0,   0,   0,   0,   0,   0,  0,
    },
    .{
        -166, -88, -33, -48, 62,  -96, -14, -106,
        -72,  -40, 73,  37,  24,  63,  8,   -16,
        -46,  61,  38,  66,  85,  130, 74,  45,
        -8,   18,  20,  54,  38,  70,  19,  23,
        -12,  5,   17,  14,  29,  20,  22,  -7,
        -22,  -8,  13,  11,  20,  18,  26,  -15,
        -28,  -52, -11, -2,  0,   19,  -13, -18,
        -104, -20, -57, -32, -16, -27, -18, -22,
    },
    .{
        -34, -1, -87, -42, -30, -47, 2,   -13,
        -31, 11, -23, -18, 25,  54,  13,  -52,
        -21, 32, 38,  35,  30,  45,  32,  -7,
        -9,  0,  14,  45,  32,  32,  2,   -7,
        -11, 8,  8,   21,  29,  7,   5,   -1,
        -5,  10, 10,  10,  9,   22,  13,  5,
        -1,  10, 11,  -5,  2,   16,  28,  -4,
        -38, -8, -19, -26, -18, -17, -44, -26,
    },
    .{
        24,  34,  24,  43,  55, 1,   23,  35,
        19,  24,  50,  54,  72, 59,  18,  36,
        -13, 11,  18,  28,  9,  37,  53,  8,
        -32, -19, -1,  18,  16, 27,  -16, -28,
        -44, -34, -20, -9,  1,  -15, -2,  -31,
        -53, -33, -24, -25, -5, -8,  -13, -41,
        -52, -24, -28, -17, -9, 3,   -14, -79,
        -27, -21, -7,  9,   8,  -1,  -45, -34,
    },
    .{
        -30, -2,  27,  10,  57,  42,  41,  43,
        -26, -41, -7,  -1,  -18, 55,  26,  52,
        -15, -19, 5,   6,   27,  54,  45,  55,
        -29, -29, -18, -18, -3,  15,  -4,  -1,
        -11, -28, -11, -12, -4,  -6,  1,   -5,
        -16, 0,   -13, -4,  -7,  0,   12,  3,
        -37, -10, 9,   0,   6,   13,  -5,  -1,
        -3,  -20, -11, 8,   -17, -27, -33, -52,
    },
    .{
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
    },
};

fn valuePSQT(stm: Colour, pt: PieceType, sqi: Square, comptime mode: Mode) i16 {
    var sq = sqi;
    if (stm == .black) {
        sq = sq.flipRank();
    }
    return value(pt, mode) + psqts[pt.toInt()][sq.toInt()];
}

fn pickFirstScalar(pieces: *const [6]u64, mask: u64) u8 {
    var res: u8 = 0;
    while (res < 6) {
        if (pieces[res] & mask != 0) {
            break;
        }
        res += 1;
    }
    return res;
}

fn pickFirstVectorized(pieces: *const [6]u64, mask: u64) u8 {
    const mask_vec: @Vector(8, u64) = @splat(mask);
    const zero: @Vector(8, u64) = @splat(0);
    const eql: u8 = @bitCast(mask_vec & (pieces.* ++ .{0} ** 2) != zero);
    return @ctz(eql);
}

// if we have SIMD support use it otherwise use the scalar version
const pickFirst = if (std.simd.suggestVectorLength(u8) orelse 0 >= 1) pickFirstVectorized else pickFirstScalar;

pub fn scoreMove(board: *const Board, move: Move, threshold: i32, comptime mode: Mode) bool {
    const from = move.from();
    const to = move.to();
    const from_type = (&board.mailbox)[from.toInt()].toColouredPieceType().toPieceType();
    var captured_type: ?PieceType = null;
    var captured_value: i16 = 0;
    if (board.isEnPassant(move)) {
        captured_type = .pawn;
        captured_value = valuePSQT(board.stm.flipped(), .pawn, move.getEnPassantPawnSquare(board.stm), mode);
    } else if (board.isCapture(move)) {
        captured_type = (&board.mailbox)[to.toInt()].toColouredPieceType().toPieceType();
        captured_value = valuePSQT(board.stm.flipped(), captured_type.?, move.to(), mode);
    }

    var score = captured_value - threshold;
    if (board.isPromo(move)) {
        const pt = move.promoType();
        const promo_value = valuePSQT(board.stm, pt, move.to(), mode);
        score += promo_value - valuePSQT(board.stm, .pawn, move.from(), mode); // add promoted piece, remove pawn since it disappears
        if (score < 0) return false; // if we're worse off than we need to be even just after promoting and possibly capturing, theres no point continuing

        score -= promo_value; // remove the promoted piece, assuming it was captured, if we're still okay even assuming we lose it immeditely, we're good!
        if (score >= 0) return true;
    } else {
        if (score < 0) return false; // if the capture is immeditely not good enough just return
        score -= valuePSQT(board.stm, from_type, move.from(), mode);
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
        const our_attackers = board.occupancyFor(stm) & attackers;
        const attacker_i = pickFirst(&board.pieces, our_attackers);
        const attacker_bb = board.pieces[attacker_i] & our_attackers;
        const chosen_attacker = attacker_bb & -%attacker_bb;
        occ ^= chosen_attacker;

        attacker = PieceType.fromInt(attacker_i);
        // if our last attacker is the king, and they still have an attacker, we can't actually recapture
        if (attacker == .king and attackers & board.occupancyFor(stm.flipped()) != 0) {
            break;
        }

        if (attacker == .pawn or attacker == .bishop or attacker == .queen)
            attackers |= getAttacks(undefined, .bishop, to, occ) & bishops;
        if (attacker == .rook or attacker == .queen)
            attackers |= getAttacks(undefined, .rook, to, occ) & rooks;

        attackers &= occ;
        score = -score - 1 - valuePSQT(stm, attacker, Square.fromBitboard(chosen_attacker), mode);
        stm = stm.flipped();

        if (score >= 0) {
            break;
        }
    }
    return stm != board.stm;
}

// test scoreMove {
//     root.init();
//     try std.testing.expect(scoreMove(&(Board.parseFen("k6b/8/8/8/8/8/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .pruning), .pruning));
//     try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2p5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .pruning), .pruning));
//     try std.testing.expect(!scoreMove(&(Board.parseFen("k7/8/8/8/8/2p5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .pruning), .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("k7/8/8/8/8/2q5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .pruning), .pruning));
//     try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2q5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .pruning), .pruning));
//     try std.testing.expect(!scoreMove(&(Board.parseFen("k3n2r/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), value(.rook, .pruning), .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("k3n3/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), value(.rook, .pruning), .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("k3n3/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), value(.rook, .pruning), .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("rn2k2r/p3bpp1/2p4p/8/2P3Q1/1P1q4/P4P1P/RNB1K2R w KQkq - 0 8", false) catch unreachable), Move.capture(.g4, .g7), 0, .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("r1bq1rk1/pppp1Npp/2nb1n2/4p3/2B1P3/2P5/PP1P1PPP/RNBQK2R b KQ - 0 6", false) catch unreachable), Move.capture(.f8, .f7), 0, .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("r1bqkb1r/ppp1pppp/2n2n2/8/2BPP3/5P2/PP4PP/RNBQK1NR b KQkq - 0 5", false) catch unreachable), Move.capture(.c6, .d4), 0, .pruning));
//     try std.testing.expect(!scoreMove(&(Board.parseFen("3b2k1/1b6/8/3R2p1/4K3/5N2/8/8 w - - 0 1", false) catch unreachable), Move.capture(.f3, .g5), 0, .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("5k2/1b6/8/3B4/4K3/8/8/8 w - - 0 1", false) catch unreachable), Move.capture(.d5, .b7), 0, .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("6b1/k7/8/3Pp3/2K2N1r/8/8/8 w - e6 0 1", false) catch unreachable), Move.enPassant(.d5, .e6), 0, .pruning));
//     try std.testing.expect(!scoreMove(&(Board.parseFen("6b1/k7/8/3Pp3/2K2N1r/8/8/8 w - e6 0 1", false) catch unreachable), Move.enPassant(.d5, .e6), 1, .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("6b1/k7/8/3Pp3/2K2N2/8/8/8 w - e6 0 1", false) catch unreachable), Move.enPassant(.d5, .e6), value(.pawn, .pruning), .pruning));
//     try std.testing.expect(scoreMove(&(Board.parseFen("8/8/8/1k6/6b1/4N3/2p3K1/3n4 w - - 0 1", false) catch unreachable), Move.capture(.e3, .c2), value(.pawn, .pruning) - value(.queen, .pruning), .pruning));
// }
