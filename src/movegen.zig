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
const Board = root.Board;
const Colour = root.Colour;
const Move = root.Move;
const Bitboard = root.Bitboard;
const attacks = root.attacks;
const Square = root.Square;
const Rank = root.Rank;

pub const MoveListReceiver = struct {
    vals: BoundedArray(Move, 256) = .{},

    fn receive(self: *@This(), move: Move) void {
        self.vals.appendAssumeCapacity(move);
    }
};

pub const CountReceiver = struct {
    count: usize = 0,

    fn receive(self: *@This(), _: Move) void {
        self.count += 1;
    }
};

pub inline fn generateAll(noalias board: *const Board, noalias move_receiver: anytype) void {
    switch (board.stm) {
        inline else => |stm| {
            generateAllNoisies(stm, board, move_receiver);
            generateAllQuiets(stm, board, move_receiver);
        },
    }
}

pub inline fn generateAllQuiets(comptime stm: Colour, noalias board: *const Board, noalias move_receiver: anytype) void {
    var check_mask = ~@as(u64, 0);
    if (board.checkers != 0) {
        if (board.checkers & board.checkers -% 1 != 0) {
            generateKingQuiets(stm, board, move_receiver);
            return;
        }
        check_mask = Bitboard.checkMask(Square.fromBitboard(board.kingFor(stm)), Square.fromBitboard(board.checkers));
    }
    generateSliderQuiets(stm, board, check_mask, move_receiver);
    generateKnightQuiets(stm, board, check_mask, move_receiver);
    generatePawnQuiets(stm, board, check_mask, move_receiver);
    generateKingQuiets(stm, board, move_receiver);
}

pub inline fn generateAllNoisies(comptime stm: Colour, noalias board: *const Board, noalias move_receiver: anytype) void {
    var check_mask = ~@as(u64, 0);
    if (board.checkers != 0) {
        if (board.checkers & board.checkers -% 1 != 0) {
            generateKingNoisies(stm, board, move_receiver);
            return;
        }
        check_mask = Bitboard.checkMask(Square.fromBitboard(board.kingFor(stm)), Square.fromBitboard(board.checkers));
    }
    generateSliderNoisies(stm, board, check_mask, move_receiver);
    generateKnightNoisies(stm, board, check_mask, move_receiver);
    generatePawnNoisies(stm, board, check_mask, move_receiver);
    generateKingNoisies(stm, board, move_receiver);
}

pub inline fn generateAllQuietsWithMask(comptime stm: Colour, noalias board: *const Board, noalias move_receiver: anytype, mask: u64) void {
    var check_mask = mask;
    if (board.checkers != 0) {
        if (board.checkers & board.checkers -% 1 != 0) {
            generateKingQuiets(stm, board, move_receiver);
            return;
        }
        check_mask &= Bitboard.checkMask(Square.fromBitboard(board.kingFor(stm)), Square.fromBitboard(board.checkers));
    }
    generateSliderQuiets(stm, board, check_mask, move_receiver);
    generateKnightQuiets(stm, board, check_mask, move_receiver);
    generatePawnQuiets(stm, board, check_mask, move_receiver);
    generateKingQuiets(stm, board, move_receiver);
}

pub inline fn generateAllNoisiesWithMask(comptime stm: Colour, noalias board: *const Board, noalias move_receiver: anytype, mask: u64) void {
    var check_mask = mask;
    if (board.checkers != 0) {
        if (board.checkers & board.checkers -% 1 != 0) {
            generateKingNoisies(stm, board, move_receiver);
            return;
        }
        check_mask &= Bitboard.checkMask(Square.fromBitboard(board.kingFor(stm)), Square.fromBitboard(board.checkers));
    }
    generateSliderNoisies(stm, board, check_mask, move_receiver);
    generateKnightNoisies(stm, board, check_mask, move_receiver);
    generatePawnNoisies(stm, board, check_mask, move_receiver);
    generateKingNoisies(stm, board, move_receiver);
}
pub fn slidingAttackersFor(comptime col: Colour, noalias board: *const Board, square: Square, occ: u64) u64 {
    const attacks_from_square =
        (attacks.getBishopAttacks(square, occ) & (board.bishops() | board.queens())) |
        (attacks.getRookAttacks(square, occ) & (board.rooks() | board.queens()));
    return attacks_from_square & board.occupancyFor(col);
}

pub fn attackersFor(comptime col: Colour, noalias board: *const Board, square: Square, occ: u64) u64 {
    const attacks_from_square =
        (attacks.getBishopAttacks(square, occ) & (board.bishops() | board.queens())) |
        (attacks.getRookAttacks(square, occ) & (board.rooks() | board.queens())) |
        (Bitboard.pawnAttacks(square, col.flipped()) & board.pawns()) |
        (Bitboard.knightMoves(square) & board.knights()) |
        (Bitboard.kingMoves(square) & board.kings());

    return attacks_from_square & board.occupancyFor(col);
}

pub inline fn generatePawnQuiets(comptime stm: Colour, noalias board: *const Board, check_mask: u64, noalias move_receiver: anytype) void {
    const d_rank = if (stm == .white) 1 else -1;

    const double_move_destination_rank = if (stm == .white) 3 else 4;
    const double_move_mask: u64 = 0b11111111 << 8 * double_move_destination_rank;

    const final_rank: u6 = board.startingRankFor(stm.flipped()).toInt();
    const promo_mask: u64 = @as(u64, 0b11111111) << 8 * final_rank;

    const pawns = board.pawnsFor(stm);
    const occ = board.occupancy();

    const one_forward = Bitboard.move(pawns, d_rank, 0) & ~occ & ~promo_mask;
    {
        var iter = Bitboard.iterator(one_forward & check_mask);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.quiet(sq.move(-d_rank, 0), sq));
        }
    }

    const two_forward = Bitboard.move(one_forward, d_rank, 0) & ~occ & double_move_mask & check_mask;
    {
        var iter = Bitboard.iterator(two_forward);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.quiet(sq.move(2 * -d_rank, 0), sq));
        }
    }

    const under_promos = Bitboard.move(pawns, d_rank, 0) & ~occ & promo_mask & check_mask;
    {
        var iter = Bitboard.iterator(under_promos);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.promo(sq.move(-d_rank, 0), sq, .knight));
            move_receiver.receive(Move.promo(sq.move(-d_rank, 0), sq, .bishop));
            move_receiver.receive(Move.promo(sq.move(-d_rank, 0), sq, .rook));
        }
    }
}

pub inline fn generatePawnNoisies(comptime stm: Colour, noalias board: *const Board, check_mask: u64, noalias move_receiver: anytype) void {
    const d_rank = if (stm == .white) 1 else -1;

    const final_rank: u6 = board.startingRankFor(stm.flipped()).toInt();
    const promo_mask: u64 = @as(u64, 0b11111111) << 8 * final_rank;

    const pawns = board.pawnsFor(stm);
    const them = board.occupancyFor(stm.flipped());
    const occ = board.occupancy();

    const left_captures = Bitboard.move(pawns, d_rank, -1) & them & check_mask;
    const left_captures_non_promo = left_captures & ~promo_mask;
    {
        var iter = Bitboard.iterator(left_captures_non_promo);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.capture(sq.move(-d_rank, 1), sq));
        }
    }
    const right_captures = Bitboard.move(pawns, d_rank, 1) & them & check_mask;
    const right_captures_non_promo = right_captures & ~promo_mask;
    {
        var iter = Bitboard.iterator(right_captures_non_promo);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.capture(sq.move(-d_rank, -1), sq));
        }
    }

    const left_capture_promos = left_captures & promo_mask;
    {
        var iter = Bitboard.iterator(left_capture_promos);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.promo(sq.move(-d_rank, 1), sq, .queen));
            move_receiver.receive(Move.promo(sq.move(-d_rank, 1), sq, .knight));
            move_receiver.receive(Move.promo(sq.move(-d_rank, 1), sq, .bishop));
            move_receiver.receive(Move.promo(sq.move(-d_rank, 1), sq, .rook));
        }
    }

    const right_capture_promos = right_captures & promo_mask;
    {
        var iter = Bitboard.iterator(right_capture_promos);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.promo(sq.move(-d_rank, -1), sq, .queen));
            move_receiver.receive(Move.promo(sq.move(-d_rank, -1), sq, .knight));
            move_receiver.receive(Move.promo(sq.move(-d_rank, -1), sq, .bishop));
            move_receiver.receive(Move.promo(sq.move(-d_rank, -1), sq, .rook));
        }
    }

    const queen_promos = Bitboard.move(pawns, d_rank, 0) & ~occ & promo_mask & check_mask;
    {
        var iter = Bitboard.iterator(queen_promos);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.promo(sq.move(-d_rank, 0), sq, .queen));
        }
    }

    if (board.ep_target) |target| {
        if (Bitboard.move(pawns, d_rank, -1) & target.toBitboard() != 0) {
            move_receiver.receive(Move.enPassant(target.move(-d_rank, 1), target));
        }
        if (Bitboard.move(pawns, d_rank, 1) & target.toBitboard() != 0) {
            move_receiver.receive(Move.enPassant(target.move(-d_rank, -1), target));
        }
    }
}

pub inline fn generateKnightQuiets(comptime stm: Colour, noalias board: *const Board, check_mask: u64, noalias move_receiver: anytype) void {
    const knights = board.knightsFor(stm) & ~(&board.pinned)[stm.toInt()];
    const occ = board.occupancy();

    var from_iter = Bitboard.iterator(knights);
    while (from_iter.next()) |from| {
        var to_iter = Bitboard.iterator(Bitboard.knightMoves(from) & ~occ & check_mask);
        while (to_iter.next()) |to| {
            move_receiver.receive(Move.quiet(from, to));
        }
    }
}

pub inline fn generateKnightNoisies(comptime stm: Colour, noalias board: *const Board, check_mask: u64, noalias move_receiver: anytype) void {
    const knights = board.knightsFor(stm);
    const them = board.occupancyFor(stm.flipped());

    var from_iter = Bitboard.iterator(knights & ~(&board.pinned)[stm.toInt()]);
    while (from_iter.next()) |from| {
        var to_iter = Bitboard.iterator(Bitboard.knightMoves(from) & them & check_mask);
        while (to_iter.next()) |to| {
            move_receiver.receive(Move.capture(from, to));
        }
    }
}

pub inline fn generateKingQuiets(comptime stm: Colour, noalias board: *const Board, noalias move_receiver: anytype) void {
    const king = board.kingFor(stm);
    const king_sq = Square.fromBitboard(king);
    const occ = board.occupancy();

    var to_iter = Bitboard.iterator(Bitboard.kingMoves(king_sq) & ~occ);
    while (to_iter.next()) |to| {
        move_receiver.receive(Move.quiet(king_sq, to));
    }

    if (board.checkers == 0) {
        const home_rank: Rank = board.startingRankFor(stm);

        const kingside_rook_file = board.castling_rights.kingsideRookFileFor(stm);
        const queenside_rook_file = board.castling_rights.queensideRookFileFor(stm);

        const kingside_rook_square = Square.fromRankFile(home_rank, kingside_rook_file);
        const queenside_rook_square = Square.fromRankFile(home_rank, queenside_rook_file);

        const can_kingside_castle = board.castling_rights.kingsideCastlingFor(stm) and
            Bitboard.queenRayBetweenExclusive(king_sq, kingside_rook_square) & occ == 0;
        const can_queenside_castle = board.castling_rights.queensideCastlingFor(stm) and
            Bitboard.queenRayBetweenExclusive(king_sq, queenside_rook_square) & occ == 0;

        if (can_kingside_castle) {
            move_receiver.receive(Move.castlingKingside(stm, king_sq, kingside_rook_square));
        }
        if (can_queenside_castle) {
            move_receiver.receive(Move.castlingQueenside(stm, king_sq, queenside_rook_square));
        }
    }
}

pub inline fn generateKingNoisies(comptime stm: Colour, noalias board: *const Board, noalias move_receiver: anytype) void {
    const king = board.kingFor(stm);
    const them = board.occupancyFor(stm.flipped());

    var from_iter = Bitboard.iterator(king);
    while (from_iter.next()) |from| {
        var to_iter = Bitboard.iterator(Bitboard.kingMoves(from) & them);
        while (to_iter.next()) |to| {
            move_receiver.receive(Move.quiet(from, to));
        }
    }
}

pub inline fn generateSliderQuiets(comptime stm: Colour, noalias board: *const Board, check_mask: u64, noalias move_receiver: anytype) void {
    const queens = board.queensFor(stm);
    const rooks = board.rooksFor(stm);
    const bishops = board.bishopsFor(stm);

    const rook_sliders = rooks | queens;
    const bishop_sliders = bishops | queens;

    const occ = board.occupancy();
    {
        var from_iter = Bitboard.iterator(rook_sliders);
        while (from_iter.next()) |from| {
            var reachable = attacks.getRookAttacks(from, occ) & ~occ & check_mask;
            if (from.toBitboard() & (&board.pinned)[stm.toInt()] != 0)
                reachable &= Bitboard.extendingRayBb(Square.fromBitboard(board.kingFor(stm)), from);
            var to_iter = Bitboard.iterator(reachable);
            while (to_iter.next()) |to| {
                move_receiver.receive(Move.quiet(from, to));
            }
        }
    }
    {
        var from_iter = Bitboard.iterator(bishop_sliders);
        while (from_iter.next()) |from| {
            var reachable = attacks.getBishopAttacks(from, occ) & ~occ & check_mask;
            if (from.toBitboard() & (&board.pinned)[stm.toInt()] != 0)
                reachable &= Bitboard.extendingRayBb(Square.fromBitboard(board.kingFor(stm)), from);
            var to_iter = Bitboard.iterator(reachable);
            while (to_iter.next()) |to| {
                move_receiver.receive(Move.quiet(from, to));
            }
        }
    }
}

pub inline fn generateSliderNoisies(comptime stm: Colour, noalias board: *const Board, check_mask: u64, noalias move_receiver: anytype) void {
    const queens = board.queensFor(stm);
    const rooks = board.rooksFor(stm);
    const bishops = board.bishopsFor(stm);

    const rook_sliders = rooks | queens;
    const bishop_slides = bishops | queens;

    const occ = board.occupancy();
    const them = board.occupancyFor(stm.flipped());

    {
        var from_iter = Bitboard.iterator(rook_sliders);
        while (from_iter.next()) |from| {
            var reachable = attacks.getRookAttacks(from, occ) & them & check_mask;
            if (from.toBitboard() & (&board.pinned)[stm.toInt()] != 0)
                reachable &= Bitboard.extendingRayBb(Square.fromBitboard(board.kingFor(stm)), from);
            var to_iter = Bitboard.iterator(reachable);
            while (to_iter.next()) |to| {
                move_receiver.receive(Move.quiet(from, to));
            }
        }
    }
    {
        var from_iter = Bitboard.iterator(bishop_slides);
        while (from_iter.next()) |from| {
            var reachable = attacks.getBishopAttacks(from, occ) & them & check_mask;
            if (from.toBitboard() & (&board.pinned)[stm.toInt()] != 0)
                reachable &= Bitboard.extendingRayBb(Square.fromBitboard(board.kingFor(stm)), from);

            var to_iter = Bitboard.iterator(reachable);
            while (to_iter.next()) |to| {
                move_receiver.receive(Move.quiet(from, to));
            }
        }
    }
}

test "startpos 16 pawn moves" {
    root.init();
    var rec = MoveListReceiver{};
    const board = Board.startpos();
    const full_mask = ~@as(u64, 0);
    generatePawnQuiets(.white, &board, full_mask, &rec);
    try std.testing.expectEqual(16, rec.vals.len);
    generatePawnNoisies(.white, &board, full_mask, &rec);
    try std.testing.expectEqual(16, rec.vals.len);
}

test "startpos 20 moves" {
    root.init();
    var rec = MoveListReceiver{};
    const board = Board.startpos();
    generateAllQuiets(.white, &board, &rec);

    try std.testing.expectEqual(20, rec.vals.len);

    generateAllNoisies(.white, &board, &rec);
    try std.testing.expectEqual(20, rec.vals.len);
}

test "kiwipete 48 moves" {
    root.init();
    var rec = MoveListReceiver{};
    const board = try Board.parseFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - ", false);
    generateAllNoisies(.white, &board, &rec);
    try std.testing.expectEqual(8, rec.vals.len);

    generateAllQuiets(.white, &board, &rec);
    try std.testing.expectEqual(48, rec.vals.len);
}

test "pos5 44 moves" {
    root.init();
    var rec = MoveListReceiver{};
    const board = try Board.parseFen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", false);
    generateAllNoisies(.white, &board, &rec);
    generateAllQuiets(.white, &board, &rec);
    try std.testing.expectEqual(44, rec.vals.len);
}
