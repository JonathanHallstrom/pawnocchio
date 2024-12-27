const std = @import("std");
const Move = @import("Move.zig");
const Board = @import("Board.zig");
const BitBoard = @import("BitBoard.zig");
const Square = @import("square.zig").Square;
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const assert = std.debug.assert;

pub fn getAllPawnMoves(comptime turn: Side, comptime captures_only: bool, board: Board, move_buf: []Move, check_mask: u64, pin_mask: u64) usize {
    // TODO: correct pins for EP

    const current = board.getSide(turn);
    const opponent = board.getSide(turn.flipped());
    const pawns = current.getBoard(.pawn);
    const pinned_pawns = pawns & pin_mask;
    const unpinned_pawns = pawns & ~pin_mask;
    var move_count: usize = 0;

    const d_rank: i8 = if (turn == .white) 1 else -1;
    const promotion_rank = comptime BitBoard.forward(255, if (turn == .white) 6 else 1);
    const double_move_rank = comptime BitBoard.forward(255, if (turn == .white) 1 else 6);

    const empty_squares = ~(current.all | opponent.all);
    const promoting_pawns = unpinned_pawns & promotion_rank;
    const non_promoting_unpinned_pawns = unpinned_pawns & ~promotion_rank;
    const non_promoting_pinned_pawns = pinned_pawns & ~promotion_rank;
    _ = non_promoting_pinned_pawns; // autofix

    const promotion_target_types = [_]PieceType{ .queen, .knight, .rook, .bishop };
    { // pawns that capture to the left and promote
        var iter = BitBoard.iterator(promoting_pawns & BitBoard.move(check_mask & opponent.all, -d_rank, 1));
        while (iter.next()) |from| {
            for (promotion_target_types) |promo_type| {
                move_buf[move_count] = Move.initPromotionCapture(from, Square.fromInt(@intCast(from.toInt() + 8 * d_rank - 1)), promo_type);
                move_count += 1;
            }
        }
    }

    { // pawns that capture to the right and promote
        var iter = BitBoard.iterator(promoting_pawns & BitBoard.move(check_mask & opponent.all, -d_rank, -1));
        while (iter.next()) |from| {
            for (promotion_target_types) |promo_type| {
                move_buf[move_count] = Move.initPromotionCapture(from, Square.fromInt(@intCast(from.toInt() + 8 * d_rank + 1)), promo_type);
                move_count += 1;
            }
        }
    }

    { // pawns that capture to the left
        var iter = BitBoard.iterator(non_promoting_unpinned_pawns & BitBoard.move(check_mask & opponent.all, -d_rank, 1));
        while (iter.next()) |from| {
            move_buf[move_count] = Move.initCapture(from, Square.fromInt(@intCast(from.toInt() + 8 * d_rank - 1)));
            move_count += 1;
        }
    }

    { // pawns that capture to the right
        var iter = BitBoard.iterator(non_promoting_unpinned_pawns & BitBoard.move(check_mask & opponent.all, -d_rank, -1));
        while (iter.next()) |from| {
            move_buf[move_count] = Move.initCapture(from, Square.fromInt(@intCast(from.toInt() + 8 * d_rank + 1)));
            move_count += 1;
        }
    }

    if (board.en_passant_target) |from| {
        // en passant to the left
        const left_attacker_square = Square.fromInt(@intCast(from.toInt() - 8 * d_rank + 1));
        move_buf[move_count] = Move.initEnPassant(left_attacker_square, from);
        move_count += @intCast(unpinned_pawns >> left_attacker_square.toInt() & 1);
        // en passant to the right
        const right_attacker_square = Square.fromInt(@intCast(from.toInt() - 8 * d_rank - 1));
        move_buf[move_count] = Move.initEnPassant(right_attacker_square, from);
        move_count += @intCast(unpinned_pawns >> right_attacker_square.toInt() & 1);
    }

    if (!captures_only) { // pawns that go straight ahead and promote
        var iter = BitBoard.iterator(promoting_pawns & BitBoard.move(check_mask & empty_squares, -d_rank, 0));
        while (iter.next()) |from| {
            for (promotion_target_types) |promo_type| {
                move_buf[move_count] = Move.initPromotion(from, Square.fromInt(@intCast(from.toInt() + 8 * d_rank)), promo_type);
                move_count += 1;
            }
        }
    }

    if (!captures_only) { // pawns that go straight ahead
        const pawns_that_can_go_one = non_promoting_unpinned_pawns & BitBoard.move(check_mask & empty_squares, -d_rank, 0);
        var iter = BitBoard.iterator(pawns_that_can_go_one);
        while (iter.next()) |from| {
            move_buf[move_count] = Move.initQuiet(from, Square.fromInt(@intCast(from.toInt() + 8 * d_rank)));
            move_count += 1;
        }
        const pawns_that_can_go_two = non_promoting_unpinned_pawns & double_move_rank & BitBoard.move(empty_squares, -d_rank, 0) & BitBoard.move(check_mask & empty_squares, -d_rank * 2, 0);
        iter = BitBoard.iterator(pawns_that_can_go_two);
        while (iter.next()) |from| {
            move_buf[move_count] = Move.initQuiet(from, Square.fromInt(@intCast(from.toInt() + 16 * d_rank)));
            move_count += 1;
        }
    }
    if (pinned_pawns != 0) {
        const pinned_pawns_that_can_move_one = pinned_pawns & BitBoard.move(check_mask & empty_squares & pin_mask, -d_rank, 0);
        var iter = BitBoard.iterator(pinned_pawns_that_can_move_one);
        while (iter.next()) |from| {
            move_buf[move_count] = Move.initQuiet(from, Square.fromInt(@intCast(from.toInt() + 8 * d_rank)));
            move_count += 1;
        }
        const pawns_that_can_go_two = pinned_pawns_that_can_move_one & double_move_rank & BitBoard.move(check_mask & empty_squares, -d_rank * 2, 0);
        iter = BitBoard.iterator(pawns_that_can_go_two);
        while (iter.next()) |from| {
            move_buf[move_count] = Move.initQuiet(from, Square.fromInt(@intCast(from.toInt() + 16 * d_rank)));
            move_count += 1;
        }
    }

    return move_count;
}

test "pawn moves" {
    var buf: [256]Move = undefined;
    const zero: u64 = 0;

    // TODO
    // try std.testing.expectEqual(1, getAllPawnMoves(.white, false, try Board.parseFen("8/8/8/kr2Pp1K/8/8/8/8 w - - 0 1"), &buf, ~zero, Square.e5.toBitBoard(), .e6));

    try std.testing.expectEqual(16, getAllPawnMoves(.white, false, try Board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(16, getAllPawnMoves(.black, false, try Board.parseFen("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(2, getAllPawnMoves(.white, false, try Board.parseFen("4k3/8/8/4Pp2/8/8/8/4K3 w - f6 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(2, getAllPawnMoves(.black, false, try Board.parseFen("4k3/8/8/8/4Pp2/8/8/4K3 b - e3 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(1, getAllPawnMoves(.white, false, try Board.parseFen("4k3/4r3/8/4Pp2/8/8/8/4K3 w - f6 0 1"), &buf, ~zero, BitBoard.all_forward[Square.e2.toInt()] & ~Square.e8.toBitBoard()));
    try std.testing.expectEqual(1, getAllPawnMoves(.black, false, try Board.parseFen("4k3/8/8/8/3Pp3/8/4R3/4K3 b - d3 0 1"), &buf, ~zero, BitBoard.all_forward[Square.e2.toInt()] & ~Square.e8.toBitBoard()));
    try std.testing.expectEqual(2, getAllPawnMoves(.white, false, try Board.parseFen("4k3/4r3/8/8/8/8/4P3/4K3 w - - 0 1"), &buf, ~zero, BitBoard.all_forward[Square.e2.toInt()] & ~Square.e8.toBitBoard()));
    try std.testing.expectEqual(2, getAllPawnMoves(.black, false, try Board.parseFen("4k3/4p3/8/8/8/8/4R3/4K3 b - - 0 1"), &buf, ~zero, BitBoard.all_forward[Square.e2.toInt()] & ~Square.e8.toBitBoard()));
    try std.testing.expectEqual(2, getAllPawnMoves(.white, false, try Board.parseFen("4k3/8/8/b7/8/8/PPP5/4K3 w - - 0 1"), &buf, BitBoard.allDirection(Square.d2.toBitBoard(), 1, -1), zero));
    try std.testing.expectEqual(3, getAllPawnMoves(.white, false, try Board.parseFen("4k3/8/8/1b6/P7/8/2PP4/5K2 w - - 0 1"), &buf, BitBoard.allDirection(Square.e2.toBitBoard(), 1, -1), zero));
    try std.testing.expectEqual(1, getAllPawnMoves(.white, true, try Board.parseFen("4k3/8/8/1b6/P7/8/2PP4/5K2 w - - 0 1"), &buf, BitBoard.allDirection(Square.e2.toBitBoard(), 1, -1), zero));
    try std.testing.expectEqual(1, getAllPawnMoves(.white, false, try Board.parseFen("4k3/8/8/1b6/P7/8/r2PK3/8 w - - 0 1"), &buf, BitBoard.allDirection(Square.e2.toBitBoard(), 1, -1), BitBoard.all_left[Square.d2.toInt()]));
    @memset(std.mem.asBytes(&buf), 0);
    for (buf) |m| {
        if (m.getFrom() == m.getTo()) break;
        std.debug.print("{}\n", .{m});
    }
}
