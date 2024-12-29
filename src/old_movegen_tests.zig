const std = @import("std");
const zobrist = @import("zobrist.zig");
const assert = std.debug.assert;

const Move = @import("Move.zig");
const Board = @import("Board.zig");

const testing = std.testing;

fn expectNumCaptures(moves: []Move, count: usize) !void {
    var actual_count: usize = 0;
    for (moves) |move| actual_count += @intFromBool(move.isCapture());
    if (count != actual_count) {
        std.log.err("Expected {} captures, found {}. Captures found:\n", .{ count, actual_count });
        for (moves) |move| {
            if (move.isCapture()) {
                std.log.err("{}\n", .{move});
            }
        }
        return error.WrongNumberCaptures;
    }
}

fn expectNumCastling(moves: []Move, count: usize) !void {
    var actual_count: usize = 0;
    for (moves) |move| actual_count += @intFromBool(move.isCastlingMove());
    if (count != actual_count) {
        std.log.err("Expected {} castling moves, found {}. Castling moves found:\n", .{ count, actual_count });
        for (moves) |move| {
            if (move.isCastlingMove()) {
                std.log.err("{}\n", .{move});
            }
        }
        return error.WrongNumberCastling;
    }
}

fn expectMovesInvertible(board: Board, moves: []Move) !void {
    const hash_before = board.zobrist;
    for (moves) |move| {
        var tmp = board;
        const inv = tmp.playMove(move);
        tmp.undoMove(inv);
        try std.testing.expectEqual(board.fullmove_clock, tmp.fullmove_clock);
        try std.testing.expectEqual(board.halfmove_clock, tmp.halfmove_clock);
        try std.testing.expectEqual(board.turn, tmp.turn);
        try std.testing.expectEqual(board.castling_squares, tmp.castling_squares);
        try std.testing.expectEqual(board.white, tmp.white);
        try std.testing.expectEqual(board.black, tmp.black);
        try std.testing.expectEqualDeep(board, tmp);
        try testing.expectEqual(tmp.zobrist, hash_before);
        tmp.resetZobrist();
        try testing.expectEqual(tmp.zobrist, hash_before);
    }
}

fn expectCapturesImplyAttacked(board: Board, moves: []Move) !void {
    for (moves) |move| {
        if (move.isCapture()) {
            try std.testing.expect(board.areSquaresAttacked(move.to().getBoard(), .flip));
        }
    }
}

fn expectMovesCompressible(board: Board, moves: []Move) !void {
    for (moves) |move| {
        try std.testing.expect(move.eql(board.decompressMove(board.compressMove(move))));
    }
}

fn testCase(fen: []const u8, func: anytype, expected_moves: usize, expected_captures: usize, expected_castling: usize) !void {
    var buf: [400]Move = undefined;
    const board = try Board.parseFen(fen);
    try testing.expectEqualSlices(u8, fen, board.toFen().slice());
    const num_moves = func(board, &buf, board.getSelfCheckSquares());
    testing.expectEqual(expected_moves, num_moves) catch |e| {
        for (buf[0..num_moves]) |move| {
            std.debug.print("{}\n", .{move});
        }
        return e;
    };
    const moves = buf[0..num_moves];
    try expectNumCaptures(moves, expected_captures);
    try expectNumCastling(moves, expected_castling);
    try expectMovesInvertible(board, moves);
    try expectCapturesImplyAttacked(board, moves);
    try expectMovesCompressible(board, moves);
}

fn expectZobristResetInvertible(board: Board) !void {
    var tmp = board;
    const before = board.zobrist;
    tmp.resetZobrist();
    try testing.expectEqual(before, tmp.zobrist);
}

test "failing" {}

test "fen parsing" {
    try testing.expectError(error.NotEnoughRows, Board.parseFen(""));
    try testing.expectError(error.EnPassantTargetDoesntExist, Board.parseFen("8/k7/8/4P3/8/8/K7/8 w - d6 0 1"));
    try testing.expect(!std.meta.isError(Board.parseFen("8/k7/8/3pP3/8/8/K7/8 w - d6 0 1")));
}

test "quiet pawn moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getQuietPawnMovesUnchecked, 16, 0, 0);
    try testCase("8/8/p7/P1P5/2K2kP1/5P2/2P4P/8 w - - 0 1", Board.getQuietPawnMovesUnchecked, 5, 0, 0);
    try testCase("8/8/p7/P7/2K2k2/2P5/8/8 w - - 0 1", Board.getQuietPawnMovesUnchecked, 0, 0, 0);
    try testCase("8/P7/8/8/2K2k2/8/8/8 w - - 0 1", Board.getQuietPawnMovesUnchecked, 4, 0, 0);
}

test "pawn captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getPawnCapturesUnchecked, 0, 0, 0);
    try testCase("8/8/p7/P1P5/2K2kP1/5P2/2P4P/8 w - - 0 1", Board.getPawnCapturesUnchecked, 0, 0, 0);
    try testCase("8/8/p7/P7/2K2k2/2P5/8/8 w - - 0 1", Board.getPawnCapturesUnchecked, 0, 0, 0);
    try testCase("8/8/p1q5/1P1P4/2K2k2/2P5/8/8 w - - 0 1", Board.getPawnCapturesUnchecked, 3, 3, 0);
    try testCase("8/k7/8/3pP3/8/8/K7/8 w - d6 0 1", Board.getPawnCapturesUnchecked, 1, 1, 0);
    try testCase("8/k7/8/8/3pP3/8/K7/8 b - e3 0 1", Board.getPawnCapturesUnchecked, 1, 1, 0);
    try testCase("1p6/P7/8/8/2K2k2/8/8/8 w - - 0 1", Board.getPawnCapturesUnchecked, 4, 4, 0);
    try testCase("p1p5/1P6/8/8/2K2k2/8/8/8 w - - 0 1", Board.getPawnCapturesUnchecked, 8, 8, 0);
}

test "quiet knight moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getQuietKnightMovesUnchecked, 4, 0, 0);
    try testCase("8/6k1/8/8/8/3N4/1K6/8 w - - 0 1", Board.getQuietKnightMovesUnchecked, 7, 0, 0);
    try testCase("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1", Board.getQuietKnightMovesUnchecked, 14, 0, 0);
    try testCase("K7/6k1/8/8/8/8/8/NN6 w - - 0 1", Board.getQuietKnightMovesUnchecked, 5, 0, 0);
    try testCase("K7/6k1/8/8/8/ppp5/2pp4/NN6 w - - 0 1", Board.getQuietKnightMovesUnchecked, 0, 0, 0);
    try testCase("K7/6k1/8/8/8/ppp5/3p4/NN6 w - - 0 1", Board.getQuietKnightMovesUnchecked, 1, 0, 0);
}

test "knight captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getKnightCapturesUnchecked, 0, 0, 0);
    try testCase("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1", Board.getKnightCapturesUnchecked, 1, 1, 0);
    try testCase("K7/6k1/8/8/8/8/8/NN6 w - - 0 1", Board.getKnightCapturesUnchecked, 0, 0, 0);
    try testCase("K7/6k1/8/8/8/ppp5/2pp4/NN6 w - - 0 1", Board.getKnightCapturesUnchecked, 5, 5, 0);
    try testCase("K7/6k1/8/8/8/ppp5/3p4/NN6 w - - 0 1", Board.getKnightCapturesUnchecked, 4, 4, 0);
    try testCase("K1k5/8/8/8/8/8/6p1/N7 w - - 0 1", Board.getKnightCapturesUnchecked, 0, 0, 0);
    try testCase("K1k4N/8/8/8/8/8/6p1/8 w - - 0 1", Board.getKnightCapturesUnchecked, 0, 0, 0);
}

test "all knight moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllKnightMovesUnchecked, 4, 0, 0);
    try testCase("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1", Board.getAllKnightMovesUnchecked, 15, 1, 0);
    try testCase("K7/6k1/8/8/8/8/8/NN6 w - - 0 1", Board.getAllKnightMovesUnchecked, 5, 0, 0);
    try testCase("K7/6k1/8/8/8/ppp5/2pp4/NN6 w - - 0 1", Board.getAllKnightMovesUnchecked, 5, 5, 0);
    try testCase("K7/6k1/8/8/8/ppp5/3p4/NN6 w - - 0 1", Board.getAllKnightMovesUnchecked, 5, 4, 0);
    try testCase("K1k5/8/8/8/8/8/6p1/N7 w - - 0 1", Board.getAllKnightMovesUnchecked, 2, 0, 0);
    try testCase("K1k4N/8/8/8/8/8/6p1/8 w - - 0 1", Board.getAllKnightMovesUnchecked, 2, 0, 0);
}

test "bishop captures" {
    try testCase("k7/8/8/5p2/8/3B4/8/K7 w - - 0 1", Board.getBishopCapturesUnchecked, 1, 1, 0);
    try testCase("7r/2k3p1/8/b7/8/2B5/8/1K6 w - - 0 1", Board.getBishopCapturesUnchecked, 2, 2, 0);
    try testCase("7r/2k3p1/8/b7/8/2B5/8/1K6 b - - 0 1", Board.getBishopCapturesUnchecked, 1, 1, 0);
}

test "all bishop moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllBishopMovesUnchecked, 0, 0, 0);
    try testCase("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3", Board.getAllBishopMovesUnchecked, 5, 0, 0);
    try testCase("k7/8/8/8/8/3B4/8/K7 w - - 0 1", Board.getAllBishopMovesUnchecked, 11, 0, 0);
    try testCase("k7/8/8/5p2/8/3B4/8/K7 w - - 0 1", Board.getAllBishopMovesUnchecked, 9, 1, 0);
    try testCase("7r/2k3p1/8/b7/8/2B5/8/1K6 b - - 0 1", Board.getAllBishopMovesUnchecked, 3, 1, 0);
}

test "rook captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getRookCapturesUnchecked, 0, 0, 0);
    try testCase("k7/8/8/3R1p2/8/8/8/K7 w - - 0 1", Board.getRookCapturesUnchecked, 1, 1, 0);
    try testCase("k7/8/8/3RRp2/8/8/8/K7 w - - 0 1", Board.getRookCapturesUnchecked, 1, 1, 0);
    try testCase("7k/8/8/8/3rrP2/8/8/7K b - - 0 1", Board.getRookCapturesUnchecked, 1, 1, 0);
}

test "all rook moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllRookMovesUnchecked, 0, 0, 0);
    try testCase("k7/8/8/3R1p2/8/8/8/K7 w - - 0 1", Board.getAllRookMovesUnchecked, 12, 1, 0);
    try testCase("k7/8/8/3RRp2/8/8/8/K7 w - - 0 1", Board.getAllRookMovesUnchecked, 18, 1, 0);
    try testCase("7k/8/8/8/3rrP2/8/8/7K b - - 0 1", Board.getAllRookMovesUnchecked, 18, 1, 0);
}

test "queen captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getQueenCapturesUnchecked, 0, 0, 0);
    try testCase("8/k7/8/3Q1p2/8/8/8/K7 w - - 0 1", Board.getQueenCapturesUnchecked, 1, 1, 0);
    try testCase("8/k7/8/3QQp2/8/8/8/K7 w - - 0 1", Board.getQueenCapturesUnchecked, 1, 1, 0);
    try testCase("7k/8/8/8/3qqP2/8/7K/8 b - - 0 1", Board.getQueenCapturesUnchecked, 1, 1, 0);
}

test "all queen moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllQueenMovesUnchecked, 0, 0, 0);
    try testCase("7k/8/8/3q4/8/8/7K/8 b - - 0 1", Board.getAllQueenMovesUnchecked, 27, 0, 0);
    try testCase("7k/8/8/3q2P1/8/8/7K/8 b - - 0 1", Board.getAllQueenMovesUnchecked, 26, 1, 0);
}

test "quiet king moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getQuietKingMovesUnchecked, 0, 0, 0);
    try testCase("8/1k6/8/8/8/8/PPP5/1K6 w - - 0 1", Board.getQuietKingMovesUnchecked, 2, 0, 0);
    try testCase("k7/8/8/3K4/8/8/8/8 w - - 0 1", Board.getQuietKingMovesUnchecked, 8, 0, 0);
    try testCase("K7/8/8/3k4/8/8/8/8 b - - 0 1", Board.getQuietKingMovesUnchecked, 8, 0, 0);
}

test "king captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getKingCapturesUnchecked, 0, 0, 0);
    try testCase("8/1k6/8/8/8/8/1p6/1K6 w - - 0 1", Board.getKingCapturesUnchecked, 1, 1, 0);
    try testCase("8/1k6/8/8/8/2pKp3/2p1p3/8 w - - 0 1", Board.getKingCapturesUnchecked, 4, 4, 0);
    try testCase("8/1k6/8/8/2p5/2pKp3/2p1p3/8 w - - 0 1", Board.getKingCapturesUnchecked, 5, 5, 0);
    try testCase("K7/8/8/2Pk4/8/8/8/8 b - - 0 1", Board.getKingCapturesUnchecked, 1, 1, 0);
}

test "all king moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllKingMovesUnchecked, 0, 0, 0);
    try testCase("8/1k6/8/8/8/8/1p6/1K6 w - - 0 1", Board.getAllKingMovesUnchecked, 5, 1, 0);
    try testCase("8/1k6/8/8/8/2pKp3/2p1p3/8 w - - 0 1", Board.getAllKingMovesUnchecked, 8, 4, 0);
    try testCase("8/1k6/8/8/2p5/2pKp3/2p1p3/8 w - - 0 1", Board.getAllKingMovesUnchecked, 8, 5, 0);
    try testCase("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1", Board.getAllKingMovesUnchecked, 6, 0, 1);
    try testCase("r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", Board.getAllKingMovesUnchecked, 3, 0, 1);
    try testCase("3k4/8/8/8/8/8/3PPPPP/3QK2R w - - 0 1", Board.getAllKingMovesUnchecked, 1, 0, 0);
    try testCase("3k4/8/8/8/8/8/3PPPPP/3QK2R w K - 0 1", Board.getAllKingMovesUnchecked, 2, 0, 1);
    try testCase("3k4/8/8/8/8/8/8/R3K2R w KQ - 0 1", Board.getAllKingMovesUnchecked, 7, 0, 2);
    try testCase("rnN2k1r/pp2bppp/2p5/8/2B5/8/PPP1NnPP/RNBqK2R w KQ - 0 9", Board.getAllKingMoves, 1, 1, 0);
    try testCase("5k2/8/8/8/8/8/5n2/3qK2R w K - 0 9", Board.getAllMoves, 1, 1, 0);
}

test "en passant on d6" {
    var board = Board.init();
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("E2")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("E4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("A7")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("A6")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("E4")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("E5")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("D7")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("D5")), true));
    var buf: [400]Move = undefined;
    const pawn_captures = board.getPawnCapturesUnchecked(&buf, board.getSelfCheckSquares());
    try testing.expectEqual(1, pawn_captures);
    try expectMovesInvertible(board, buf[0..pawn_captures]);
    try expectCapturesImplyAttacked(board, buf[0..pawn_captures]);
}

test "en passant on a6" {
    var board = Board.init();
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("B2")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("B4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("H7")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("H6")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("B4")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("B5")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("A7")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("A5")), true));
    var buf: [400]Move = undefined;
    const pawn_captures = board.getPawnCapturesUnchecked(&buf, board.getSelfCheckSquares());
    try testing.expectEqual(1, pawn_captures);
    try expectMovesInvertible(board, buf[0..pawn_captures]);
    try expectCapturesImplyAttacked(board, buf[0..pawn_captures]);
}

test "en passant on h6" {
    var board = Board.init();
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("G2")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("G4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("A7")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("A6")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("G4")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("G5")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("H7")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("H5")), true));
    var buf: [400]Move = undefined;
    const pawn_captures = board.getPawnCapturesUnchecked(&buf, board.getSelfCheckSquares());
    try testing.expectEqual(1, pawn_captures);
    try expectMovesInvertible(board, buf[0..pawn_captures]);
    try expectCapturesImplyAttacked(board, buf[0..pawn_captures]);
}

test "en passant on d3" {
    var board = Board.init();
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("G2")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("G3")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("E7")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("E5")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("G3")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("G4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("E5")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("E4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("D2")), Piece.pawnFromBitboard(Bitboard.fromSquareUnchecked("D4")), true));
    var buf: [400]Move = undefined;
    const pawn_moves = board.getAllPawnMovesUnchecked(&buf, board.getSelfCheckSquares());
    try testing.expectEqual(16, pawn_moves);
    try expectMovesInvertible(board, buf[0..pawn_moves]);
    try expectCapturesImplyAttacked(board, buf[0..pawn_moves]);
}

test "cant castle when in between square is attacked by knight" {
    try testCase("r3k2r/p1ppqpb1/bnN1pnp1/3P4/1p2P3/2N2Q1p/PPPBBPPP/R3K2R b KQkq - 1 1", Board.getAllMoves, 41, 8, 1);
}

test "castling blocked by bishop" {
    try testCase("5k2/8/b7/8/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 7, 0, 0);
    try testCase("5k2/8/1b6/8/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 8, 0, 0);
    try testCase("5k2/8/8/b7/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 4, 0, 0);
    try testCase("5k2/8/8/3b4/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 10, 0, 1);
    try testCase("5k2/8/8/3b4/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 10, 0, 1);
}

test "fools mate" {
    var board = Board.init();
    var buf: [1024]Move = undefined;
    _ = try board.playMoveFromSquare("f2f3", &buf);
    _ = try board.playMoveFromSquare("e7e6", &buf);
    _ = try board.playMoveFromSquare("g2g4", &buf);
    _ = try board.playMoveFromSquare("d8h4", &buf);

    try testing.expectEqual(.black, board.gameOver());
}

comptime {
    // @compileLog(@sizeOf(Board));
    // @compileLog(@sizeOf(Board) + 50 * @sizeOf(usize) + 1);

    std.testing.refAllDeclsRecursive(@This());
}
