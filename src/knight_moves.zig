const std = @import("std");
const Move = @import("Move.zig");
const Board = @import("Board.zig");
const BitBoard = @import("BitBoard.zig");
const Square = @import("square.zig").Square;
const Side = @import("side.zig").Side;
const assert = std.debug.assert;

const d_ranks = [_]comptime_int{ 1, 1, -1, -1, 2, 2, -2, -2 };
const d_files = [_]comptime_int{ 2, -2, 2, -2, 1, -1, 1, -1 };

const knight_moves: [64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]u64 = .{0} ** 64;

    for (d_ranks, d_files) |d_rank, d_file| {
        for (0..64) |i| {
            res[i] |= BitBoard.move(1 << i, d_rank, d_file);
        }
    }
    break :blk res;
};

pub fn getAllKnightMoves(comptime turn: Side, comptime captures_only: bool, board: Board, move_buf: []Move, check_mask: u64, pin_mask: u64) usize {
    const current = board.getSide(turn);
    const opponent = board.getSide(turn.flipped());
    const knights = current.getBoard(.knight) & ~pin_mask;
    var iter = BitBoard.iterator(knights);
    var move_count: usize = 0;

    const allowed = check_mask & if (captures_only) opponent.all else ~current.all;

    while (iter.next()) |from| {
        const moves = knight_moves[from.toInt()];
        const legal = moves & allowed;
        var destination_iter = BitBoard.iterator(legal);

        // maybe refactor this to only update the count conditionally?
        while (destination_iter.next()) |to| {
            move_buf[move_count] = Move.initWithFlag(from, to, if (BitBoard.contains(opponent.all, to)) .capture else .quiet);
            move_count += 1;
        }
    }

    return move_count;
}

test "knight moves" {
    var buf: [256]Move = undefined;
    const zero: u64 = 0;
    try std.testing.expectEqual(8, getAllKnightMoves(.white, false, try Board.parseFen("8/1k6/8/8/3N4/8/1K6/8 w - - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(0, getAllKnightMoves(.white, false, try Board.parseFen("8/1k6/5b2/8/3N4/8/1K6/8 w - - 0 1"), &buf, ~zero, Square.d4.toBitBoard()));
    try std.testing.expectEqual(16, getAllKnightMoves(.white, false, try Board.parseFen("8/1k6/5b2/8/3N4/2N5/1K6/8 w - - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(4, getAllKnightMoves(.white, false, try Board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(0, getAllKnightMoves(.white, true, try Board.parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), &buf, ~zero, zero));
    try std.testing.expectEqual(2, getAllKnightMoves(.white, false, try Board.parseFen("4k3/8/8/8/4N2b/8/8/4K3 w - - 0 1"), &buf, Square.f2.toBitBoard() | Square.g3.toBitBoard() | Square.h4.toBitBoard(), zero));
    try std.testing.expectEqual(7, getAllKnightMoves(.white, false, try Board.parseFen("4k3/8/8/8/4N2b/8/5N2/4K3 w - - 0 1"), &buf, ~zero, Square.f2.toBitBoard()));
    try std.testing.expectEqual(8, getAllKnightMoves(.white, false, try Board.parseFen("4k3/8/8/5N2/7b/8/5N2/4K3 w - - 0 1"), &buf, ~zero, Square.f2.toBitBoard()));
}
