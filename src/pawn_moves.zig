const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const Bitboard = @import("Bitboard.zig");
const Square = @import("square.zig").Square;
const Rank = @import("square.zig").Rank;
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const assert = std.debug.assert;

const magics = @import("magics.zig");

pub fn getPawnMovesImpl(comptime turn: Side, comptime captures_only: bool, comptime count_only: bool, board: Board, move_buf: []Move, check_mask: u64, pinned_by_bishop_mask: u64, pinned_by_rook_mask: u64) usize {
    const us = board.getSide(turn);
    const them = board.getSide(turn.flipped());
    const pawns = us.getBoard(.pawn);
    const pin_mask = pinned_by_bishop_mask | pinned_by_rook_mask;
    const pinned_pawns = pawns & pin_mask;
    const unpinned_pawns = pawns & ~pin_mask;
    var move_count: usize = 0;

    const d_rank: i8 = if (turn == .white) 1 else -1;
    const promotion_rank = comptime Bitboard.forward(255, if (turn == .white) 6 else 1);
    const double_move_rank = comptime Bitboard.forward(255, if (turn == .white) 1 else 6);

    const empty_squares = ~(us.all | them.all);
    const promoting_pawns = unpinned_pawns & promotion_rank;
    const promoting_pinned_pawns = pinned_pawns & promotion_rank;
    const non_promoting_unpinned_pawns = unpinned_pawns & ~promotion_rank;
    const non_promoting_pinned_pawns = pinned_pawns & ~promotion_rank;

    const promotion_target_types = [_]PieceType{ .queen, .knight, .rook, .bishop };
    { // pawns that capture to the left and promote
        const legal = promoting_pawns & Bitboard.move(check_mask & them.all, -d_rank, 1);
        if (count_only) {
            move_count += @popCount(legal) * 4;
        } else {
            var iter = Bitboard.iterator(legal);
            while (iter.next()) |from| {
                for (promotion_target_types) |promo_type| {
                    move_buf[move_count] = Move.initPromotionCapture(from, from.move(d_rank, -1), promo_type);
                    move_count += 1;
                }
            }
        }
    }

    { // pawns that capture to the right and promote
        const legal = promoting_pawns & Bitboard.move(check_mask & them.all, -d_rank, -1);
        if (count_only) {
            move_count += @popCount(legal) * 4;
        } else {
            var iter = Bitboard.iterator(legal);
            while (iter.next()) |from| {
                for (promotion_target_types) |promo_type| {
                    move_buf[move_count] = Move.initPromotionCapture(from, from.move(d_rank, 1), promo_type);
                    move_count += 1;
                }
            }
        }
    }

    { // pawns that capture to the left
        const legal = non_promoting_unpinned_pawns & Bitboard.move(check_mask & them.all, -d_rank, 1);
        if (count_only) {
            move_count += @popCount(legal);
        } else {
            var iter = Bitboard.iterator(legal);
            while (iter.next()) |from| {
                move_buf[move_count] = Move.initCapture(from, from.move(d_rank, -1));
                move_count += 1;
            }
        }
    }

    { // pawns that capture to the right
        const legal = non_promoting_unpinned_pawns & Bitboard.move(check_mask & them.all, -d_rank, -1);
        if (count_only) {
            move_count += @popCount(legal);
        } else {
            var iter = Bitboard.iterator(legal);
            while (iter.next()) |from| {
                move_buf[move_count] = Move.initCapture(from, from.move(d_rank, 1));
                move_count += 1;
            }
        }
    }

    if (board.en_passant_target) |to| {
        // if this is false then we're counting moves for mobility calculation
        if (to.getRank() == (if (turn == .white) Rank.sixth else Rank.third)) {
            const ep_pawn_square = to.move(-d_rank, 0);
            const ep_pawn_bb = ep_pawn_square.toBitboard();

            assert(Bitboard.contains(them.getBoard(.pawn), ep_pawn_square));

            const king = us.getBoard(.king);
            const occ = us.all | them.all;
            for ([2]i8{ -1, 1 }) |d_file| {
                if (Bitboard.move(ep_pawn_bb, 0, d_file) & pawns != 0) {
                    const from = ep_pawn_square.move(0, d_file);

                    const occ_change = ep_pawn_bb | to.toBitboard() | from.toBitboard();

                    const occ_after = occ ^ occ_change;

                    var attacked: u64 = 0;

                    var iter = Bitboard.iterator(them.getBoard(.bishop) | them.getBoard(.queen));
                    while (iter.next()) |attacker| {
                        attacked |= magics.getBishopAttacks(attacker, occ_after);
                    }
                    iter = Bitboard.iterator(them.getBoard(.rook) | them.getBoard(.queen));
                    while (iter.next()) |attacker| {
                        attacked |= magics.getRookAttacks(attacker, occ_after);
                    }

                    if (king & attacked == 0) {
                        if (!count_only)
                            move_buf[move_count] = Move.initEnPassant(from, to);
                        move_count += 1;
                    }
                }
            }
        }
    }

    if (!captures_only) { // pawns that go straight ahead and promote
        const legal = promoting_pawns & Bitboard.move(check_mask & empty_squares, -d_rank, 0);
        if (count_only) {
            move_count += @popCount(legal) * 4;
        } else {
            var iter = Bitboard.iterator(legal);
            while (iter.next()) |from| {
                for (promotion_target_types) |promo_type| {
                    move_buf[move_count] = Move.initPromotion(from, from.move(d_rank, 0), promo_type);
                    move_count += 1;
                }
            }
        }
    }

    if (!captures_only) { // pawns that go straight ahead
        const pawns_that_can_go_one = non_promoting_unpinned_pawns & Bitboard.move(check_mask & empty_squares, -d_rank, 0);
        const pawns_that_can_go_two = non_promoting_unpinned_pawns & double_move_rank & Bitboard.move(empty_squares, -d_rank, 0) & Bitboard.move(check_mask & empty_squares, -d_rank * 2, 0);
        if (count_only) {
            move_count += @popCount(pawns_that_can_go_one);
            move_count += @popCount(pawns_that_can_go_two);
        } else {
            var iter = Bitboard.iterator(pawns_that_can_go_one);
            while (iter.next()) |from| {
                move_buf[move_count] = Move.initQuiet(from, from.move(d_rank, 0));
                move_count += 1;
            }
            iter = Bitboard.iterator(pawns_that_can_go_two);
            while (iter.next()) |from| {
                move_buf[move_count] = Move.initQuiet(from, from.move(2 * d_rank, 0));
                move_count += 1;
            }
        }
    }
    if (pinned_pawns != 0 and !captures_only) {
        const non_promoting_pawns_that_can_capture_left = non_promoting_pinned_pawns & Bitboard.move(check_mask & them.all & pinned_by_bishop_mask, -d_rank, 1);
        const non_promoting_pawns_that_can_capture_right = non_promoting_pinned_pawns & Bitboard.move(check_mask & them.all & pinned_by_bishop_mask, -d_rank, -1);
        const promoting_pawns_that_can_capture_left = promoting_pinned_pawns & Bitboard.move(check_mask & them.all & pinned_by_bishop_mask, -d_rank, 1);
        const promoting_pawns_that_can_capture_right = promoting_pinned_pawns & Bitboard.move(check_mask & them.all & pinned_by_bishop_mask, -d_rank, -1);
        var iter = Bitboard.iterator(0);
        if (count_only) {
            move_count += @popCount(non_promoting_pawns_that_can_capture_left);
            move_count += @popCount(non_promoting_pawns_that_can_capture_right);
            move_count += @popCount(promoting_pawns_that_can_capture_left) * 4;
            move_count += @popCount(promoting_pawns_that_can_capture_right) * 4;
        } else {
            iter = Bitboard.iterator(non_promoting_pawns_that_can_capture_left);
            while (iter.next()) |from| {
                move_buf[move_count] = Move.initCapture(from, from.move(d_rank, -1));
                move_count += 1;
            }
            iter = Bitboard.iterator(non_promoting_pawns_that_can_capture_right);
            while (iter.next()) |from| {
                move_buf[move_count] = Move.initCapture(from, from.move(d_rank, 1));
                move_count += 1;
            }
            iter = Bitboard.iterator(promoting_pawns_that_can_capture_left);
            while (iter.next()) |from| {
                for (promotion_target_types) |promo_type| {
                    move_buf[move_count] = Move.initPromotionCapture(from, from.move(d_rank, -1), promo_type);
                    move_count += 1;
                }
            }
            iter = Bitboard.iterator(promoting_pawns_that_can_capture_right);
            while (iter.next()) |from| {
                for (promotion_target_types) |promo_type| {
                    move_buf[move_count] = Move.initPromotionCapture(from, from.move(d_rank, 1), promo_type);
                    move_count += 1;
                }
            }
        }
        if (!captures_only) {
            const pinned_pawns_that_can_move_one = non_promoting_pinned_pawns & Bitboard.move(check_mask & empty_squares & pinned_by_rook_mask, -d_rank, 0);
            const pinned_pawns_that_can_move_two = pinned_pawns_that_can_move_one & double_move_rank & Bitboard.move(check_mask & empty_squares, -d_rank * 2, 0);
            if (count_only) {
                move_count += @popCount(pinned_pawns_that_can_move_one);
                move_count += @popCount(pinned_pawns_that_can_move_two);
            } else {
                iter = Bitboard.iterator(pinned_pawns_that_can_move_one);
                while (iter.next()) |from| {
                    move_buf[move_count] = Move.initQuiet(from, from.move(d_rank, 0));
                    move_count += 1;
                }
                iter = Bitboard.iterator(pinned_pawns_that_can_move_two);
                while (iter.next()) |from| {
                    move_buf[move_count] = Move.initQuiet(from, from.move(2 * d_rank, 0));
                    move_count += 1;
                }
            }
        }
    }

    return move_count;
}

pub fn getPawnMoves(comptime turn: Side, comptime captures_only: bool, board: Board, move_buf: []Move, check_mask: u64, pinned_by_bishop_mask: u64, pinned_by_rook_mask: u64) usize {
    return getPawnMovesImpl(turn, captures_only, false, board, move_buf, check_mask, pinned_by_bishop_mask, pinned_by_rook_mask);
}

pub fn countPawnMoves(comptime turn: Side, comptime captures_only: bool, board: Board, check_mask: u64, pinned_by_bishop_mask: u64, pinned_by_rook_mask: u64) usize {
    return getPawnMovesImpl(turn, captures_only, true, board, &.{}, check_mask, pinned_by_bishop_mask, pinned_by_rook_mask);
}

// manually giving the pin and check masks, as thats not whats being tested here
test "pawn moves" {
    var buf: [256]Move = undefined;
    const zero: u64 = 0;

    try std.testing.expectEqual(16, getPawnMoves(.white, false, try Board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), &buf, ~zero, zero, zero));
    try std.testing.expectEqual(16, getPawnMoves(.black, false, try Board.parseFen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1"), &buf, ~zero, zero, zero));
    try std.testing.expectEqual(2, getPawnMoves(.white, false, try Board.parseFen("4k3/8/8/4Pp2/8/8/8/4K3 w - f6 0 1"), &buf, ~zero, zero, zero));
    try std.testing.expectEqual(2, getPawnMoves(.black, false, try Board.parseFen("4k3/8/8/8/4Pp2/8/8/4K3 b - e3 0 1"), &buf, ~zero, zero, zero));
    try std.testing.expectEqual(1, getPawnMoves(.white, false, try Board.parseFen("4k3/4r3/8/4Pp2/8/8/8/4K3 w - f6 0 1"), &buf, ~zero, zero, Bitboard.all_forward[Square.e1.toInt()] & ~Square.e8.toBitboard()));
    try std.testing.expectEqual(1, getPawnMoves(.black, false, try Board.parseFen("4k3/8/8/8/3Pp3/8/4R3/4K3 b - d3 0 1"), &buf, ~zero, zero, Bitboard.all_forward[Square.e1.toInt()] & ~Square.e8.toBitboard()));
    try std.testing.expectEqual(2, getPawnMoves(.white, false, try Board.parseFen("4k3/4r3/8/8/8/8/4P3/4K3 w - - 0 1"), &buf, ~zero, zero, Bitboard.all_forward[Square.e1.toInt()] & ~Square.e8.toBitboard()));
    try std.testing.expectEqual(2, getPawnMoves(.black, false, try Board.parseFen("4k3/4p3/8/8/8/8/4R3/4K3 b - - 0 1"), &buf, ~zero, zero, Bitboard.all_forward[Square.e1.toInt()] & ~Square.e8.toBitboard()));
    try std.testing.expectEqual(2, getPawnMoves(.white, false, try Board.parseFen("4k3/8/8/b7/8/8/PPP5/4K3 w - - 0 1"), &buf, Bitboard.ray(Square.d2.toBitboard(), 1, -1), zero, zero));
    try std.testing.expectEqual(3, getPawnMoves(.white, false, try Board.parseFen("4k3/8/8/1b6/P7/8/2PP4/5K2 w - - 0 1"), &buf, Bitboard.ray(Square.e2.toBitboard(), 1, -1), zero, zero));
    try std.testing.expectEqual(1, getPawnMoves(.white, true, try Board.parseFen("4k3/8/8/1b6/P7/8/2PP4/5K2 w - - 0 1"), &buf, Bitboard.ray(Square.e2.toBitboard(), 1, -1), zero, zero));
    try std.testing.expectEqual(1, getPawnMoves(.white, false, try Board.parseFen("4k3/8/8/1b6/P7/8/r2PK3/8 w - - 0 1"), &buf, Bitboard.ray(Square.e2.toBitboard(), 1, -1), Bitboard.all_left[Square.e2.toInt()], zero));
    try std.testing.expectEqual(1, getPawnMoves(.white, false, try Board.parseFen("1k6/8/8/8/8/3b4/2P5/1K6 w - - 0 1"), &buf, ~zero, Square.c2.toBitboard() | Square.d3.toBitboard(), zero));
    try std.testing.expectEqual(0, getPawnMoves(.white, false, try Board.parseFen("1k6/8/8/8/4b3/8/2P5/1K6 w - - 0 1"), &buf, ~zero, Square.c2.toBitboard() | Square.d3.toBitboard() | Square.e4.toBitboard(), zero));
    try std.testing.expectEqual(1, getPawnMoves(.white, false, try Board.parseFen("8/8/8/kr2Pp1K/8/8/8/8 w - - 0 1"), &buf, ~zero, zero, zero));
    try std.testing.expectEqual(1, getPawnMoves(.white, false, try Board.parseFen("4k3/5b2/8/3Pp3/8/1K6/8/8 w - e6 0 1"), &buf, ~zero, Square.c4.toBitboard() | Square.d5.toBitboard() | Square.e6.toBitboard() | Square.f7.toBitboard(), zero));
    try std.testing.expectEqual(1, getPawnMoves(.black, false, try Board.parseFen("3k4/3np3/3Q1B2/8/8/8/3K4/8 b - - 0 1"), &buf, ~zero, Square.e7.toBitboard() | Square.f6.toBitboard(), Square.d6.toBitboard() | Square.d7.toBitboard()));
}
