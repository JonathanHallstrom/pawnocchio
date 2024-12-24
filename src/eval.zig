const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const lib = @import("lib.zig");

const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const BitBoard = lib.BitBoard;
const Piece = lib.Piece;
const PieceType = lib.PieceType;
const Move = lib.Move;
const Board = lib.Board;

const PieceValues: [PieceType.all.len]i16 = .{
    100,
    300,
    300,
    500,
    900,
    10000,
};

pub fn eval(board: Board) i16 {
    var res: i16 = 0;
    for (PieceType.all) |pt| {
        res += PieceValues[@intFromEnum(pt)] * @popCount(board.white.getBoard(pt).toInt());
        res -= PieceValues[@intFromEnum(pt)] * @popCount(board.black.getBoard(pt).toInt());
    }
    return if (board.turn == .white) res else -res;
}
