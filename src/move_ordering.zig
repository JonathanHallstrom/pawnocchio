const std = @import("std");
const Move = @import("Move.zig");
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;

fn mvvLvaValue(board: *const Board, move: Move) u8 {
    if (!move.isCapture()) return 0;
    const captured_type: PieceType = if (move.isEnPassant()) .pawn else board.mailbox[move.getTo().toInt()].?;
    const moved_type = board.mailbox[move.getFrom().toInt()].?;
    return @intCast(@as(i16, @intFromEnum(captured_type)) * 8 - @intFromEnum(moved_type));
}

fn mvvLvaCompare(board: *const Board, lhs: Move, rhs: Move) bool {
    return mvvLvaValue(board, lhs) > mvvLvaValue(board, rhs);
}

pub fn mvvLva(board: *const Board, moves: []Move) void {
    std.sort.pdq(Move, moves, board, mvvLvaCompare);
}
