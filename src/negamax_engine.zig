const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const lib = @import("lib.zig");

const Piece = lib.Piece;
const PieceType = lib.PieceType;
const Move = lib.Move;
const Board = lib.Board;

const PieceValues = [_]i32{
    100, // pawn
    300, // knight
    300, // bishop
    500, // rook
    900, // queen
    1000_000, // king
};

const CHECKMATE_EVAL = 1000_000_000;

fn pieceValueEval(comptime turn: lib.Side, board: Board) i32 {
    if (board.gameOver()) |res| return switch (res) {
        .tie => -50,
        .white => if (turn == .white) CHECKMATE_EVAL else -CHECKMATE_EVAL,
        .black => if (turn == .black) CHECKMATE_EVAL else -CHECKMATE_EVAL,
    };
    var res: i32 = 0;
    for (PieceType.all) |pt| {
        res += @popCount(board.white.getBoard(pt).toInt()) * PieceValues[@intFromEnum(pt)];
        res -= @popCount(board.black.getBoard(pt).toInt()) * PieceValues[@intFromEnum(pt)];
    }
    res = if (turn == .white) res else -res;
    if (board.isInCheck(.auto)) res -= 100;
    return res;
}

fn negaMaxImpl(comptime turn: lib.Side, board: *Board, depth: usize, move_buf: []Move) i32 {
    if (depth == 0) return pieceValueEval(turn, board.*);

    const num_moves = board.getAllMovesUnchecked(move_buf, board.getSelfCheckSquares());
    const moves = move_buf[0..num_moves];
    const rem_buf = move_buf[num_moves..];
    var res: i32 = -CHECKMATE_EVAL;
    var res_dumb: i32 = 0;
    for (moves) |move| {
        if (res > 1000_000) return res;
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);

            const cur = -negaMaxImpl(turn.flipped(), board, depth - 1, rem_buf);

            res = @max(res, cur);
            res_dumb = @max(res_dumb + @divTrunc(cur, 1000), cur + @divTrunc(res_dumb, 1000));
        }
    }
    if (res == 0) return res_dumb;
    return res;
}

pub fn negaMax(board: Board, depth: usize, move_buf: []Move) i32 {
    var self = board;
    return switch (self.turn) {
        inline else => |t| negaMaxImpl(t, &self, depth, move_buf),
    };
}

pub fn findMove(board: Board, depth: usize, move_buf: []Move) struct { i32, Move } {
    var self = board;
    const num_moves = board.getAllMovesUnchecked(move_buf, board.getSelfCheckSquares());
    const moves = move_buf[0..num_moves];

    var best_eval: i32 = -CHECKMATE_EVAL;
    var best_move: Move = undefined;
    for (moves) |move| {
        if (self.playMovePossibleSelfCheck(move)) |inv| {
            defer self.undoMove(inv);

            const eval = -negaMax(self, depth - 1, move_buf[num_moves..]);
            if (eval > best_eval) {
                best_eval = eval;
                best_move = move;
            }
        }
    }

    return .{ best_eval, best_move };
}

test "starting position even material" {
    try testing.expectEqual(0, pieceValueEval(.white, Board.init()));
}
