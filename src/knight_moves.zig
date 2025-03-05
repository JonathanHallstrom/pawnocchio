const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const Bitboard = @import("Bitboard.zig");
const Square = @import("square.zig").Square;
const Side = @import("side.zig").Side;
const assert = std.debug.assert;

pub const knight_moves_arr: [64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]u64 = .{0} ** 64;

    for (Bitboard.knight_d_ranks, Bitboard.knight_d_files) |d_rank, d_file| {
        for (0..64) |i| {
            res[i] |= Bitboard.move(1 << i, d_rank, d_file);
        }
    }
    break :blk res;
};

fn getKnightMovesImpl(comptime turn: Side, comptime captures_only: bool, comptime quiets_only: bool, comptime count_only: bool, board: Board, move_buf: anytype, check_mask: u64, pin_mask: u64) usize {
    const MoveBufT = @TypeOf(move_buf);
    const MoveT: type = switch (@typeInfo(MoveBufT)) {
        .Pointer => std.meta.Elem(@TypeOf(move_buf)),
        else => undefined,
    };

    const us = board.getSide(turn);
    const them = board.getSide(turn.flipped());
    const knights = us.getBoard(.knight) & ~pin_mask;
    var iter = Bitboard.iterator(knights);
    var move_count: usize = 0;

    comptime assert(!captures_only or !quiets_only);
    var allowed = check_mask & if (captures_only) them.all else ~us.all;
    if (quiets_only) allowed &= ~them.all;

    while (iter.next()) |from| {
        const moves = knight_moves_arr[from.toInt()];
        const legal = moves & allowed;

        if (count_only) {
            move_count += @popCount(legal);
        } else {
            var to_iter = Bitboard.iterator(legal);
            while (to_iter.next()) |to| {
                move_buf[move_count] = MoveT.init(Move.initWithFlag(from, to, if (captures_only or Bitboard.contains(them.all, to)) .capture else .quiet));
                move_count += 1;
            }
        }
    }

    return move_count;
}

pub fn getKnightMoves(comptime turn: Side, comptime captures_only: bool, comptime quiets_only: bool, board: Board, move_buf: anytype, check_mask: u64, pin_mask: u64) usize {
    return getKnightMovesImpl(
        turn,
        captures_only,
        quiets_only,
        false,
        board,
        move_buf,
        check_mask,
        pin_mask,
    );
}

pub fn countKnightMoves(comptime turn: Side, comptime captures_only: bool, comptime quiets_only: bool, board: Board, check_mask: u64, pin_mask: u64) usize {
    return getKnightMovesImpl(
        turn,
        captures_only,
        quiets_only,
        true,
        board,
        &.{},
        check_mask,
        pin_mask,
    );
}

test "knight moves" {
    var buf: [256]Move = undefined;
    const zero: u64 = 0;
    try std.testing.expectEqual(8, getKnightMoves(.white, false, false, try Board.parseFen("8/1k6/8/8/3N4/8/1K6/8 w - - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(0, getKnightMoves(.white, false, false, try Board.parseFen("8/1k6/5b2/8/3N4/8/1K6/8 w - - 0 1"), &buf, ~zero, Square.d4.toBitboard()));
    try std.testing.expectEqual(16, getKnightMoves(.white, false, false, try Board.parseFen("8/1k6/5b2/8/3N4/2N5/1K6/8 w - - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(4, getKnightMoves(.white, false, false, try Board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(0, getKnightMoves(.white, true, false, try Board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(2, getKnightMoves(.white, false, false, try Board.parseFen("4k3/8/8/8/4N2b/8/8/4K3 w - - 0 1"), &buf, Square.f2.toBitboard() | Square.g3.toBitboard() | Square.h4.toBitboard(), zero));
    try std.testing.expectEqual(7, getKnightMoves(.white, false, false, try Board.parseFen("4k3/8/8/8/4N2b/8/5N2/4K3 w - - 0 1"), &buf, ~zero, Square.f2.toBitboard()));
    try std.testing.expectEqual(8, getKnightMoves(.white, false, false, try Board.parseFen("4k3/8/8/5N2/7b/8/5N2/4K3 w - - 0 1"), &buf, ~zero, Square.f2.toBitboard()));
}
