const std = @import("std");
const Move = @import("Move.zig");
const Board = @import("Board.zig");
const Bitboard = @import("Bitboard.zig");
const Square = @import("square.zig").Square;
const Side = @import("side.zig").Side;
const magics = @import("magics.zig");
const knight_moves = @import("knight_moves.zig");
const assert = std.debug.assert;
const mask_generation = @import("mask_generation.zig");

const king_moves_arr = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]u64 = undefined;
    for (0..64) |i| {
        res[i] = 1 << i;
        res[i] |= Bitboard.move(res[i], 0, 1);
        res[i] |= Bitboard.move(res[i], 0, -1);
        res[i] |= Bitboard.move(res[i], 1, 0);
        res[i] |= Bitboard.move(res[i], -1, 0);
        res[i] ^= 1 << i;
    }
    break :blk res;
};

pub fn getKingMoves(comptime turn: Side, comptime captures_only: bool, board: Board, move_buf: []Move) usize {
    const us = board.getSide(turn);
    const them = board.getSide(turn.flipped());
    const king = us.getBoard(.king);
    const king_square = Square.fromBitboard(king);
    const occ = us.all | them.all & ~king;

    var move_count: usize = 0;

    const allowed = if (captures_only) them.all else ~us.all;
    var attacked: u64 = 0;

    { // knight threats
        var iter = Bitboard.iterator(them.getBoard(.knight));
        while (iter.next()) |from| {
            attacked |= knight_moves.knight_moves_arr[from.toInt()];
        }
    }
    { // bishop threats
        var iter = Bitboard.iterator(them.getBoard(.bishop) | them.getBoard(.queen));
        while (iter.next()) |from| {
            attacked |= magics.getBishopAttacks(from, occ);
        }
    }
    { // rook threats
        var iter = Bitboard.iterator(them.getBoard(.rook) | them.getBoard(.queen));
        while (iter.next()) |from| {
            attacked |= magics.getRookAttacks(from, occ);
        }
    }
    { // pawn threats
        const d_rank = if (turn == .white) -1 else 1;
        attacked |= Bitboard.move(them.getBoard(.pawn), d_rank, 1);
        attacked |= Bitboard.move(them.getBoard(.pawn), d_rank, -1);
    }

    { // king "threats"
        const opponent_king = them.getBoard(.king);
        attacked |= king_moves_arr[@ctz(opponent_king)];
    }

    { // normal king moves
        var iter = Bitboard.iterator(king_moves_arr[king_square.toInt()] & allowed & ~attacked);
        while (iter.next()) |to| {
            move_buf[move_count] = Move.initWithFlag(king_square, to, if (captures_only or Bitboard.contains(them.all, to)) .capture else .quiet);
            move_count += 1;
        }
    }

    if (!captures_only) { // castling
        const can_kingside_castle = 0 != board.castling_rights & if (turn == .white) Board.white_kingside_castle else Board.black_kingside_castle;
        const can_queenside_castle = 0 != board.castling_rights & if (turn == .white) Board.white_queenside_castle else Board.black_queenside_castle;

        if (can_kingside_castle) {
            const rook_square = Square.fromInt(if (turn == .white) board.white_kingside_rook_file.toInt() else @as(u6, board.black_kingside_rook_file.toInt()) + 56);
            const destination = if (turn == .white) Square.g1 else Square.g8;
            const need_to_be_unattacked = Bitboard.rook_ray_between_inclusive[king_square.toInt()][destination.toInt()];
            const need_to_be_empty = Bitboard.rook_ray_between_inclusive[king_square.toInt()][rook_square.toInt()] & ~rook_square.toBitboard();
            if (need_to_be_unattacked & (allowed | king) & ~attacked == need_to_be_unattacked and need_to_be_empty & occ == 0) {
                move_buf[move_count] = Move.initCastlingKingside(king_square, rook_square);
                move_count += 1;
            }
        }
        if (can_queenside_castle) {
            const rook_square = Square.fromInt(if (turn == .white) board.white_queenside_rook_file.toInt() else @as(u6, board.black_queenside_rook_file.toInt()) + 56);
            const destination = if (turn == .white) Square.c1 else Square.c8;
            const need_to_be_unattacked = Bitboard.rook_ray_between_inclusive[king_square.toInt()][destination.toInt()];
            const need_to_be_empty = Bitboard.rook_ray_between_inclusive[king_square.toInt()][rook_square.toInt()] & ~rook_square.toBitboard();
            if (need_to_be_unattacked & (allowed | king) & ~attacked == need_to_be_unattacked and need_to_be_empty & occ == 0) {
                move_buf[move_count] = Move.initCastlingQueenside(king_square, rook_square);
                move_count += 1;
            }
        }
    }

    return move_count;
}

test "king moves" {
    var buf: [256]Move = undefined;
    try std.testing.expectEqual(5, getKingMoves(.white, false, try Board.parseFen("4k3/8/8/4pP2/8/8/8/4K3 w - e6 0 1"), &buf));
    try std.testing.expectEqual(5, getKingMoves(.white, false, try Board.parseFen("4k3/8/8/4pP2/8/8/8/4K3 w - e6 0 1"), &buf));
    try std.testing.expectEqual(3, getKingMoves(.white, false, try Board.parseFen("k7/8/8/3nnn2/4K3/8/8/8 w - - 0 1"), &buf));
    try std.testing.expectEqual(6, getKingMoves(.white, false, try Board.parseFen("k7/8/8/8/8/8/8/1R1K4 w Q - 0 1"), &buf));
    try std.testing.expectEqual(6, getKingMoves(.white, false, try Board.parseFen("1r1k4/8/8/8/8/8/8/1R1K4 w Qq - 0 1"), &buf));
    try std.testing.expectEqual(3, getKingMoves(.white, false, try Board.parseFen("2rk4/8/8/8/8/8/8/1R1K4 w Q - 0 1"), &buf));
    try std.testing.expectEqual(5, getKingMoves(.white, false, try Board.parseFen("2rk4/8/8/8/8/8/2P5/1R1K4 w Q - 0 1"), &buf));
    try std.testing.expectEqual(6, getKingMoves(.white, false, try Board.parseFen("r2k4/8/8/8/8/8/8/R2K4 w Qq - 0 1"), &buf));
    try std.testing.expectEqual(6, getKingMoves(.black, false, try Board.parseFen("r2k4/8/8/8/8/8/8/R2K4 b Qq - 0 1"), &buf));
    try std.testing.expectEqual(5, getKingMoves(.white, false, try Board.parseFen("r2k4/7b/8/8/8/8/8/R2K4 w Qq - 0 1"), &buf));
    @memset(std.mem.asBytes(&buf), 0);
    for (buf) |m| {
        if (m.getFrom() == m.getTo()) break;
        std.debug.print("{}\n", .{m});
    }
}
