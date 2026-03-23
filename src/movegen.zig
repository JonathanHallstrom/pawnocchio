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
const PieceType = root.PieceType;

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

pub inline fn legalMoveList(noalias board: *const Board) MoveListReceiver {
    var move_receiver = MoveListReceiver{};
    generateAll(board, &move_receiver);
    return move_receiver;
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
        (attacks.bishopAttacks(square, occ) & (board.bishops() | board.queens())) |
        (attacks.rookAttacks(square, occ) & (board.rooks() | board.queens()));
    return attacks_from_square & board.occupancyFor(col);
}

pub fn attackersFor(comptime col: Colour, noalias board: *const Board, square: Square, occ: u64) u64 {
    const attacks_from_square =
        (attacks.bishopAttacks(square, occ) & (board.bishops() | board.queens())) |
        (attacks.rookAttacks(square, occ) & (board.rooks() | board.queens())) |
        (Bitboard.pawnAttacks(square, col.flipped()) & board.pawns()) |
        (Bitboard.knightMoves(square) & board.knights()) |
        (Bitboard.kingMoves(square) & board.kings());

    return attacks_from_square & board.occupancyFor(col);
}

pub inline fn getAttacks(comptime col: Colour, pt: PieceType, square: Square, occ: u64) u64 {
    return switch (pt) {
        .pawn => Bitboard.pawnAttacks(square, col.flipped()),
        .bishop => attacks.bishopAttacks(square, occ),
        .knight => Bitboard.knightMoves(square),
        .rook => attacks.rookAttacks(square, occ),
        .queen => attacks.bishopAttacks(square, occ) | attacks.rookAttacks(square, occ),
        .king => Bitboard.kingMoves(square),
    };
}

fn pawnPinMasks(comptime stm: Colour, noalias board: *const Board) struct { u64, u64, u64, u64 } {
    const king_sq = Square.fromBitboard(board.kingFor(stm));
    const ki = king_sq.toInt();
    const pinned = board.pinnedFor(stm);
    const file_pin_mask = @as(u64, 0x0101010101010101) << @intCast(king_sq.getFile().toInt());
    const ne_sw_diag = Bitboard.rayArrayPtr(1, 1)[ki] | Bitboard.rayArrayPtr(-1, -1)[ki] | king_sq.toBitboard();
    const nw_se_diag = Bitboard.rayArrayPtr(1, -1)[ki] | Bitboard.rayArrayPtr(-1, 1)[ki] | king_sq.toBitboard();
    const left_pin_mask = if (stm == .white) nw_se_diag else ne_sw_diag;
    const right_pin_mask = if (stm == .white) ne_sw_diag else nw_se_diag;
    return .{ pinned, file_pin_mask, left_pin_mask, right_pin_mask };
}

pub inline fn generatePawnQuiets(comptime stm: Colour, noalias board: *const Board, check_mask: u64, noalias move_receiver: anytype) void {
    const d_rank = if (stm == .white) 1 else -1;

    const double_move_destination_rank = if (stm == .white) 3 else 4;
    const double_move_mask: u64 = 0b11111111 << 8 * double_move_destination_rank;

    const final_rank: u6 = board.startingRankFor(stm.flipped()).toInt();
    const promo_mask: u64 = @as(u64, 0b11111111) << 8 * final_rank;

    const pawns = board.pawnsFor(stm);
    const occ = board.occupancy();
    const pinned, const file_pin_mask, _, _ = pawnPinMasks(stm, board);
    const pushable = (pawns & ~pinned) | (pawns & pinned & file_pin_mask);

    const one_forward = Bitboard.move(pushable, d_rank, 0) & ~occ & ~promo_mask;
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

    const under_promos = Bitboard.move(pushable, d_rank, 0) & ~occ & promo_mask & check_mask;
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
    const pinned, const file_pin_mask, const left_pin_mask, const right_pin_mask = pawnPinMasks(stm, board);
    const left_movable = (pawns & ~pinned) | (pawns & pinned & left_pin_mask);
    const right_movable = (pawns & ~pinned) | (pawns & pinned & right_pin_mask);
    const pushable = (pawns & ~pinned) | (pawns & pinned & file_pin_mask);

    const left_captures = Bitboard.move(left_movable, d_rank, -1) & them & check_mask;
    const left_captures_non_promo = left_captures & ~promo_mask;
    {
        var iter = Bitboard.iterator(left_captures_non_promo);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.capture(sq.move(-d_rank, 1), sq));
        }
    }
    const right_captures = Bitboard.move(right_movable, d_rank, 1) & them & check_mask;
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

    const queen_promos = Bitboard.move(pushable, d_rank, 0) & ~occ & promo_mask & check_mask;
    {
        var iter = Bitboard.iterator(queen_promos);
        while (iter.next()) |sq| {
            move_receiver.receive(Move.promo(sq.move(-d_rank, 0), sq, .queen));
        }
    }

    if (board.ep_target) |target| {
        const captured_sq = target.move(-d_rank, 0);
        const captured_bb = captured_sq.toBitboard();
        if (board.checkers & ~captured_bb != 0) return;

        if (Bitboard.move(left_movable, d_rank, -1) & target.toBitboard() != 0) {
            const from = target.move(-d_rank, 1);
            if (isEpLegal(stm, board, from, target, captured_sq, occ)) {
                move_receiver.receive(Move.enPassant(from, target));
            }
        }
        if (Bitboard.move(right_movable, d_rank, 1) & target.toBitboard() != 0) {
            const from = target.move(-d_rank, -1);
            if (isEpLegal(stm, board, from, target, captured_sq, occ)) {
                move_receiver.receive(Move.enPassant(from, target));
            }
        }
    }
}

fn isEpLegal(comptime stm: Colour, noalias board: *const Board, from: Square, to: Square, captured: Square, occ: u64) bool {
    const king_sq = Square.fromBitboard(board.kingFor(stm));
    const occ_after = occ ^ from.toBitboard() ^ to.toBitboard() ^ captured.toBitboard();
    return slidingAttackersFor(stm.flipped(), board, king_sq, occ_after) == 0;
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
    const their_threats = board.threatsFor(stm.flipped());

    var to_iter = Bitboard.iterator(Bitboard.kingMoves(king_sq) & ~occ & ~their_threats);
    while (to_iter.next()) |to| {
        move_receiver.receive(Move.quiet(king_sq, to));
    }

    if (board.checkers == 0) {
        const home_rank: Rank = board.startingRankFor(stm);

        const kingside_rook_file = board.castling_rights.kingsideRookFileFor(stm);
        const queenside_rook_file = board.castling_rights.queensideRookFileFor(stm);

        const kingside_rook_square = Square.fromRankFile(home_rank, kingside_rook_file);
        const queenside_rook_square = Square.fromRankFile(home_rank, queenside_rook_file);

        if (board.castling_rights.kingsideCastlingFor(stm)) {
            const castle_move = Move.castlingKingside(stm, king_sq, kingside_rook_square);
            if (board.isCastlingMoveLegal(stm, castle_move)) {
                move_receiver.receive(castle_move);
            }
        }
        if (board.castling_rights.queensideCastlingFor(stm)) {
            const castle_move = Move.castlingQueenside(stm, king_sq, queenside_rook_square);
            if (board.isCastlingMoveLegal(stm, castle_move)) {
                move_receiver.receive(castle_move);
            }
        }
    }
}

pub inline fn generateKingNoisies(comptime stm: Colour, noalias board: *const Board, noalias move_receiver: anytype) void {
    const king = board.kingFor(stm);
    const them = board.occupancyFor(stm.flipped());
    const their_threats = board.threatsFor(stm.flipped());
    const king_sq = Square.fromBitboard(king);

    var to_iter = Bitboard.iterator(Bitboard.kingMoves(king_sq) & them & ~their_threats);
    while (to_iter.next()) |to| {
        move_receiver.receive(Move.capture(king_sq, to));
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
            var reachable = attacks.rookAttacks(from, occ) & ~occ & check_mask;
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
            var reachable = attacks.bishopAttacks(from, occ) & ~occ & check_mask;
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
            var reachable = attacks.rookAttacks(from, occ) & them & check_mask;
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
            var reachable = attacks.bishopAttacks(from, occ) & them & check_mask;
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
