const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const Bitboard = @import("Bitboard.zig");
const Square = @import("square.zig").Square;
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const assert = std.debug.assert;

const magics = @import("magics.zig");
pub fn getSlidingMovesImpl(comptime turn: Side, comptime captures_only: bool, comptime count_only: bool, board: Board, move_buf: []Move, check_mask: u64, pinned_by_bishop_mask: u64, pinned_by_rook_mask: u64) usize {
    const us = board.getSide(turn);
    const them = board.getSide(turn.flipped());
    const rooks = us.getBoard(.rook) | us.getBoard(.queen);
    const bishops = us.getBoard(.bishop) | us.getBoard(.queen);

    var move_count: usize = 0;

    const allowed = check_mask & if (captures_only) them.all else ~us.all;
    const all_pieces = them.all | us.all;

    const pinned_mask = pinned_by_bishop_mask | pinned_by_rook_mask;

    {
        const unpinned_rooks = rooks & ~pinned_mask;
        var iter = Bitboard.iterator(unpinned_rooks);
        while (iter.next()) |from| {
            const reachable = allowed & magics.getRookAttacks(from, all_pieces);
            if (count_only) {
                move_count += @popCount(reachable);
            } else {
                var to_iter = Bitboard.iterator(reachable);
                while (to_iter.next()) |to| {
                    move_buf[move_count] = Move.initWithFlag(from, to, if (captures_only or Bitboard.contains(them.all, to)) .capture else .quiet);
                    move_count += 1;
                }
            }
        }
    }

    {
        const pinned_rooks = rooks & pinned_by_rook_mask;
        var iter = Bitboard.iterator(pinned_rooks);
        while (iter.next()) |from| {
            const reachable = pinned_by_rook_mask & allowed & magics.getRookAttacks(from, all_pieces);
            if (count_only) {
                move_count += @popCount(reachable);
            } else {
                var to_iter = Bitboard.iterator(reachable);
                while (to_iter.next()) |to| {
                    move_buf[move_count] = Move.initWithFlag(from, to, if (captures_only or Bitboard.contains(them.all, to)) .capture else .quiet);
                    move_count += 1;
                }
            }
        }
    }
    {
        const unpinned_bishops = bishops & ~pinned_mask;
        var iter = Bitboard.iterator(unpinned_bishops);
        while (iter.next()) |from| {
            const reachable = allowed & magics.getBishopAttacks(from, all_pieces);
            if (count_only) {
                move_count += @popCount(reachable);
            } else {
                var to_iter = Bitboard.iterator(reachable);
                while (to_iter.next()) |to| {
                    move_buf[move_count] = Move.initWithFlag(from, to, if (captures_only or Bitboard.contains(them.all, to)) .capture else .quiet);
                    move_count += 1;
                }
            }
        }
    }

    {
        const pinned_bishops = bishops & pinned_by_bishop_mask;
        var iter = Bitboard.iterator(pinned_bishops);
        while (iter.next()) |from| {
            const reachable = pinned_by_bishop_mask & allowed & magics.getBishopAttacks(from, all_pieces);
            if (count_only) {
                move_count += @popCount(reachable);
            } else {
                var to_iter = Bitboard.iterator(reachable);
                while (to_iter.next()) |to| {
                    move_buf[move_count] = Move.initWithFlag(from, to, if (captures_only or Bitboard.contains(them.all, to)) .capture else .quiet);
                    move_count += 1;
                }
            }
        }
    }

    return move_count;
}

pub fn getSlidingMoves(comptime turn: Side, comptime captures_only: bool, board: Board, move_buf: []Move, check_mask: u64, pinned_by_bishop_mask: u64, pinned_by_rook_mask: u64) usize {
    return getSlidingMovesImpl(turn, captures_only, false, board, move_buf, check_mask, pinned_by_bishop_mask, pinned_by_rook_mask);
}

pub fn countSlidingMoves(comptime turn: Side, comptime captures_only: bool, board: Board, check_mask: u64, pinned_by_bishop_mask: u64, pinned_by_rook_mask: u64) usize {
    return getSlidingMovesImpl(turn, captures_only, true, board, &.{}, check_mask, pinned_by_bishop_mask, pinned_by_rook_mask);
}

// manually giving the pin and check masks, as thats not whats being tested here
test "sliding moves" {
    var buf: [256]Move = undefined;
    const zero: u64 = 0;

    try std.testing.expectEqual(0, getSlidingMoves(.white, false, try Board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), &buf, ~zero, zero, zero));
    try std.testing.expectEqual(12, getSlidingMoves(.black, false, try Board.parseFen("1k6/8/8/8/4b3/8/2P5/1K6 b - - 0 1"), &buf, ~zero, zero, zero));
    try std.testing.expectEqual(1, getSlidingMoves(.black, true, try Board.parseFen("1k6/8/8/8/4b3/8/2P5/1K6 b - - 0 1"), &buf, ~zero, zero, zero));
    try std.testing.expectEqual(24, getSlidingMoves(.black, false, try Board.parseFen("1k6/8/8/2q5/8/8/2P5/1K6 b - - 0 1"), &buf, ~zero, zero, zero));
    try std.testing.expectEqual(5, getSlidingMoves(.black, false, try Board.parseFen("1k6/8/3q4/8/8/8/2P4B/1K6 b - - 0 1"), &buf, ~zero, Bitboard.rayArrayPtr(-1, 1)[Square.b8.toInt()], zero));
    try std.testing.expectEqual(1, getSlidingMoves(.black, true, try Board.parseFen("1k6/8/3q4/8/8/8/2P4B/1K6 b - - 0 1"), &buf, ~zero, Bitboard.rayArrayPtr(-1, 1)[Square.b8.toInt()], zero));
    try std.testing.expectEqual(6, getSlidingMoves(.black, false, try Board.parseFen("3k4/8/3q4/8/8/8/2P5/1K1R4 b - - 0 1"), &buf, ~zero, 0, Bitboard.rayArrayPtr(-1, 0)[Square.d8.toInt()]));
    try std.testing.expectEqual(3, getSlidingMoves(.white, false, try Board.parseFen("4k3/8/8/q7/8/8/3B4/4K3 w - - 2 3"), &buf, ~zero, Bitboard.rayArrayPtr(1, -1)[Square.e1.toInt()], zero));
    @memset(std.mem.asBytes(&buf), 0);
    for (buf) |m| {
        if (m.getFrom() == m.getTo()) break;
        std.debug.print("{}\n", .{m});
    }
}
