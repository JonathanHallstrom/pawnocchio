const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const lib = @import("lib.zig");

const BitBoard = lib.BitBoard;
const Piece = lib.Piece;
const PieceType = lib.PieceType;
const Move = lib.Move;
const Board = lib.Board;

const PieceValues = [_]i32{
    100, // pawn
    320, // knight
    330, // bishop
    500, // rook
    900, // queen
    100_000, // king
};

const CHECKMATE_EVAL = 1000_000_000;

fn pawnEval(pawns: BitBoard) i32 {
    var res = @popCount(pawns.toInt()) * PieceValues[@intFromEnum(PieceType.pawn)];

    const first = BitBoard.fromSquareUnchecked("A3").allRight()
        .getCombination(BitBoard.fromSquareUnchecked("A5"))
        .getCombination(BitBoard.fromSquareUnchecked("A7"));
    res += @popCount(first.getOverlap(pawns).toInt()) * 5;

    const second = BitBoard.fromSquareUnchecked("A4").allRight()
        .getCombination(BitBoard.fromSquareUnchecked("A5"));
    res += @popCount(second.getOverlap(pawns).toInt()) * 10;

    const third = BitBoard.fromSquareUnchecked("A6").allRight()
        .getCombination(BitBoard.fromSquareUnchecked("A7"));
    res += @popCount(third.getOverlap(pawns).toInt()) * 20;

    const central = comptime blk: {
        var cent = BitBoard.fromSquareUnchecked("D3");
        cent.add(cent.right(1));
        break :blk cent.allForward();
    };
    res += @popCount(central.getOverlap(pawns).toInt()) * 5;
    return res;
}

fn eval(comptime turn: lib.Side, board: Board) i32 {
    if (board.gameOver()) |res| return switch (res) {
        .tie => -50,
        .white => if (turn == .white) CHECKMATE_EVAL else -CHECKMATE_EVAL,
        .black => if (turn == .black) CHECKMATE_EVAL else -CHECKMATE_EVAL,
    };
    var res: i32 = 0;

    res += pawnEval(board.white.pawn);
    res -= pawnEval(board.black.pawn.flipped());

    res += @popCount(board.white.knight.toInt()) * PieceValues[@intFromEnum(PieceType.knight)];
    res -= @popCount(board.black.knight.toInt()) * PieceValues[@intFromEnum(PieceType.knight)];

    res += @popCount(board.white.bishop.toInt()) * PieceValues[@intFromEnum(PieceType.bishop)];
    res -= @popCount(board.black.bishop.toInt()) * PieceValues[@intFromEnum(PieceType.bishop)];

    res += @popCount(board.white.rook.toInt()) * PieceValues[@intFromEnum(PieceType.rook)];
    res -= @popCount(board.black.rook.toInt()) * PieceValues[@intFromEnum(PieceType.rook)];

    res += @popCount(board.white.queen.toInt()) * PieceValues[@intFromEnum(PieceType.queen)];
    res -= @popCount(board.black.queen.toInt()) * PieceValues[@intFromEnum(PieceType.queen)];

    res = if (turn == .white) res else -res;
    if (board.isInCheck(Board.TurnMode.from(turn))) {
        res -= 50;
    }
    return res;
}

fn mvvlvaValue(x: Move) i32 {
    return PieceValues[@intFromEnum(x.captured().?.getType())] - PieceValues[@intFromEnum(x.to().getType())];
}

fn mvvlvaCompare(_: void, lhs: Move, rhs: Move) bool {
    return mvvlvaValue(lhs) > mvvlvaValue(rhs);
}

var q_depth: usize = 0;
var max_depth: usize = 0;
var q_nodes: usize = 0;

fn quiesce(comptime turn: lib.Side, board: *Board, move_buf: []Move, alpha_: i32, beta: i32) i32 {
    q_depth += 1;
    q_nodes += 1;
    if (q_nodes % (1 << 20) == 0) {
        @import("main.zig").log_writer.print("q nodes {}\n", .{q_nodes}) catch {};
    }
    if (q_depth > max_depth) {
        max_depth = q_depth;
        @import("main.zig").log_writer.print("q depth {}\n", .{max_depth}) catch {};
    }
    defer q_depth -= 1;
    var alpha = alpha_;
    const num_moves = board.getAllCapturesUnchecked(move_buf, board.getSelfCheckSquares());
    if (num_moves == 0) return eval(turn, board.*);
    const moves = move_buf[0..num_moves];

    
    std.sort.pdq(Move, moves, void{}, mvvlvaCompare);
    for (moves[0 .. num_moves - 1], moves[1..]) |first, second| {
        std.testing.expect(mvvlvaValue(first) >= mvvlvaValue(second)) catch {
            @import("main.zig").log_writer.print("incorrectly ordered moves\n", .{}) catch {};
            @panic("");
        };
    }

    const rem_buf = move_buf[num_moves..];
    var res: i32 = -CHECKMATE_EVAL;
    for (moves) |move| {
        assert(move.isCapture());
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);

            const cur = -quiesce(
                turn.flipped(),
                board,
                rem_buf,
                -beta,
                -alpha,
            );

            res = @max(res, cur);
            alpha = @max(alpha, cur);
            if (cur > beta) break;
        }
    }
    return res;
}

fn negaMaxImpl(comptime turn: lib.Side, board: *Board, depth: usize, move_buf: []Move, alpha_: i32, beta: i32) i32 {
    if (depth == 0) return quiesce(turn, board, move_buf, alpha_, beta);
    var alpha = alpha_;

    const num_moves = board.getAllMovesUnchecked(move_buf, board.getSelfCheckSquares());
    if (num_moves == 0) return eval(turn, board.*);
    const moves = move_buf[0..num_moves];
    const rem_buf = move_buf[num_moves..];
    var res: i32 = -CHECKMATE_EVAL;
    for (moves) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);

            const cur = -negaMaxImpl(
                turn.flipped(),
                board,
                depth - 1,
                rem_buf,
                -beta,
                -alpha,
            );

            res = @max(res, cur);
            alpha = @max(alpha, cur);
            if (cur > beta) break;
        }
    }
    return res;
}

pub fn negaMax(board: Board, depth: usize, move_buf: []Move) i32 {
    var self = board;
    return switch (self.turn) {
        inline else => |t| negaMaxImpl(t, &self, depth, move_buf, -CHECKMATE_EVAL, CHECKMATE_EVAL),
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

            const cur_eval = -negaMax(self, depth - 1, move_buf[num_moves..]);
            if (cur_eval > best_eval) {
                best_eval = cur_eval;
                best_move = move;
            }
        }
    }

    return .{ best_eval, best_move };
}

test "starting position even material" {
    try testing.expectEqual(0, eval(.white, Board.init()));
}
