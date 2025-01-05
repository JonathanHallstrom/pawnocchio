const std = @import("std");
const Move = @import("Move.zig").Move;
const Side = @import("side.zig").Side;
const Board = @import("Board.zig");
const mask_generation = @import("mask_generation.zig");

const knight_moves = @import("knight_moves.zig");
const pawn_moves = @import("pawn_moves.zig");
const sliding_moves = @import("sliding_moves.zig");
const king_moves = @import("king_moves.zig");

pub const getKnightMoves = knight_moves.getKnightMoves;
pub const countKnightMoves = knight_moves.countKnightMoves;
pub const getPawnMoves = pawn_moves.getPawnMoves;
pub const countPawnMoves = pawn_moves.countPawnMoves;
pub const getSlidingMoves = sliding_moves.getSlidingMoves;
pub const countSlidingMoves = sliding_moves.countSlidingMoves;
pub const getKingMoves = king_moves.getKingMoves;
pub const countKingMoves = king_moves.countKingMoves;

fn getMovesImpl(comptime turn: Side, comptime captures_only: bool, board: Board, move_buf: []Move) usize {
    const masks = mask_generation.getMasks(turn, board);
    var res: usize = 0;
    res += getPawnMoves(turn, captures_only, board, move_buf[res..], masks.checks, masks.bishop_pins, masks.rook_pins);
    res += getKnightMoves(turn, captures_only, board, move_buf[res..], masks.checks, masks.bishop_pins | masks.rook_pins);
    res += getSlidingMoves(turn, captures_only, board, move_buf[res..], masks.checks, masks.bishop_pins, masks.rook_pins);
    res += getKingMoves(turn, captures_only, board, move_buf[res..], masks.rook_pins);
    return res;
}

fn countMovesImpl(comptime turn: Side, comptime captures_only: bool, board: Board) usize {
    const masks = mask_generation.getMasks(turn, board);
    var res: usize = 0;
    res += countPawnMoves(turn, captures_only, board, masks.checks, masks.bishop_pins, masks.rook_pins);
    res += countKnightMoves(turn, captures_only, board, masks.checks, masks.bishop_pins | masks.rook_pins);
    res += countSlidingMoves(turn, captures_only, board, masks.checks, masks.bishop_pins, masks.rook_pins);
    res += countKingMoves(turn, captures_only, board, masks.rook_pins);
    return res;
}

pub fn getMoves(comptime turn: Side, board: Board, move_buf: []Move) usize {
    return getMovesImpl(turn, false, board, move_buf);
}

pub fn countMoves(comptime turn: Side, board: Board) usize {
    return countMovesImpl(turn, false, board);
}

pub fn getMovesWithInfo(comptime turn: Side, comptime captures_only: bool, board: Board, move_buf: []Move) struct { usize, mask_generation.Masks } {
    const masks = mask_generation.getMasks(turn, board);
    var res: usize = 0;
    res += getPawnMoves(turn, captures_only, board, move_buf[res..], masks.checks, masks.bishop_pins, masks.rook_pins);
    res += getKnightMoves(turn, captures_only, board, move_buf[res..], masks.checks, masks.bishop_pins | masks.rook_pins);
    res += getSlidingMoves(turn, captures_only, board, move_buf[res..], masks.checks, masks.bishop_pins, masks.rook_pins);
    res += getKingMoves(turn, captures_only, board, move_buf[res..], masks.rook_pins);
    return .{ res, masks };
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

test "double attack promotion" {
    var buf: [256]Move = undefined;
    try std.testing.expectEqual(1, getMoves(.black, try Board.parseFen("r4kQr/p1ppq1b1/bn4p1/4N3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R b KQ - 0 3"), &buf));
}

test "pinned pawn can't capture" {
    var buf: [256]Move = undefined;
    try std.testing.expectEqual(49, getMoves(.black, try Board.parseFen("r6r/p1pkqpb1/bnp1pnp1/3P4/1p2P1B1/2NQ3p/PPPB1PPP/R3K2R b KQ - 3 3"), &buf));
}

test "perft" {
    _ = @import("perft_tests.zig");
}
