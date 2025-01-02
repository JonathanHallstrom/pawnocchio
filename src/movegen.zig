const Move = @import("Move.zig");
const Side = @import("side.zig").Side;
const Board = @import("Board.zig");
const mask_generation = @import("mask_generation.zig");

const knight_moves = @import("knight_moves.zig");
const pawn_moves = @import("pawn_moves.zig");
const sliding_moves = @import("sliding_moves.zig");
const king_moves = @import("king_moves.zig");

pub const getKnightMoves = knight_moves.getKnightMoves;
pub const getPawnMoves = pawn_moves.getPawnMoves;
pub const getSlidingMoves = sliding_moves.getSlidingMoves;
pub const getKingMoves = king_moves.getKingMoves;

fn getMovesImpl(comptime turn: Side, comptime captures_only: bool, board: Board, move_buf: []Move) usize {
    const masks = mask_generation.getMasks(turn, board);
    var res: usize = 0;
    res += getPawnMoves(turn, captures_only, board, move_buf[res..], masks.checks, masks.bishop_pins, masks.rook_pins);
    res += getKnightMoves(turn, captures_only, board, move_buf[res..], masks.checks, masks.bishop_pins | masks.rook_pins);
    res += getSlidingMoves(turn, captures_only, board, move_buf[res..], masks.checks, masks.bishop_pins, masks.rook_pins);
    res += getKingMoves(turn, captures_only, board, move_buf[res..], masks.rook_pins);
    return res;
}

pub fn getMoves(comptime turn: Side, board: Board, move_buf: []Move) usize {
    return getMovesImpl(turn, false, board, move_buf);
}

pub fn getMovesWithoutTurn(board: Board, move_buf: []Move) usize {
    return switch (board.turn) {
        inline else => |turn| getMovesImpl(turn, false, board, move_buf),
    };
}

pub fn getCaptures(comptime turn: Side, board: Board, move_buf: []Move) usize {
    return getMovesImpl(turn, true, board, move_buf);
}

test "all movegen tests" {
    _ = knight_moves;
    _ = pawn_moves;
    _ = sliding_moves;
    _ = king_moves;
}
