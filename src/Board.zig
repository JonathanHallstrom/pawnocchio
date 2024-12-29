const std = @import("std");
const assert = std.debug.assert;
const Side = @import("side.zig").Side;
const PieceSet = @import("PieceSet.zig");
const PieceType = @import("piece_type.zig").PieceType;
const Move = @import("Move.zig");
const Board = @This();
const Square = @import("square.zig").Square;
const File = @import("square.zig").File;
const Bitboard = @import("Bitboard.zig");

// starting pos
// 8 r n b q k b n r
// 7 p p p p p p p p
// 6
// 5
// 4
// 3
// 2 P P P P P P P P
// 1 R N B Q K B N R
//   A B C D E F G H

// indices
// 8 56 57 58 59 60 61 62 63
// 7 48 49 50 51 52 53 54 55
// 6 40 41 42 43 44 45 46 47
// 5 32 33 34 35 36 37 38 39
// 4 24 25 26 27 28 39 30 31
// 3 16 17 18 19 20 21 22 23
// 2  8  9 10 11 12 13 14 15
// 1  0  1  2  3  4  5  6  7
//    A  B  C  D  E  F  G  H

turn: Side = .white,
castling_rights: u4 = 0,
left_rook_file: File = File.a,
right_rook_file: File = File.h,
en_passant_target: ?Square = null,

halfmove_clock: u8 = 0,
fullmove_clock: u64 = 1,
zobrist: u64 = 0,

white: PieceSet = .{},
black: PieceSet = .{},
mailbox: [8][8]?PieceType = .{.{null} ** 8} ** 8,

const Self = @This();

pub fn init() Board {
    return parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") catch unreachable;
}

pub fn parseFen(fen: []const u8) !Board {
    var iter = std.mem.tokenizeAny(u8, fen, " /");
    var rows: [8][]const u8 = undefined;
    for (0..8) |i| {
        rows[i] = iter.next() orelse return error.NotEnoughRows;
    }

    var res: Self = .{};
    for (0..8) |r| {
        // why not support it?
        // if (rows[r].len == 0) return error.emptyRow;

        var c: usize = 0;
        for (rows[7 - r]) |ch| {
            if (std.ascii.isLower(ch)) {
                res.black.addPiece(PieceType.fromLetter(ch), Square.fromInt(@intCast(8 * r + c)));
                c += 1;
            } else if (std.ascii.isUpper(ch)) {
                res.white.addPiece(PieceType.fromLetter(ch), Square.fromInt(@intCast(8 * r + c)));
                c += 1;
            } else switch (ch) {
                '1'...'8' => |n| c += n - '0',
                else => return error.InvalidCharacter,
            }
        }
    }

    const turn_str = iter.next() orelse return error.MissingTurn;
    assert(turn_str.len > 0); // tokenize should only return non-empty strings
    if (turn_str.len > 1)
        return error.TurnStringTooBig;
    if (std.ascii.toLower(turn_str[0]) == 'w') {
        res.turn = .white;
    } else if (std.ascii.toLower(turn_str[0]) == 'b') {
        res.turn = .black;
    } else {
        return error.InvalidTurn;
    }

    const castling_string = iter.next() orelse return error.MissingCastling;
    _ = castling_string; // autofix
    // if (castling_string.len > 4) return error.CastlingStringTooBig;
    // if (!std.mem.eql(u8, "-", castling_string)) {
    //     for (castling_string) |castle_ch| {
    //         res.castling_squares |= switch (castle_ch) {
    //             'Q' => queenside_white_castle,
    //             'q' => queenside_black_castle,
    //             'K' => kingside_white_castle,
    //             'k' => kingside_black_castle,
    //             else => return error.InvalidCharacter,
    //         };
    //     }
    // }

    const en_passant_target_square_string = iter.next() orelse return error.MissingEnPassantTarget;
    if (std.mem.eql(u8, en_passant_target_square_string, "-")) {
        res.en_passant_target = null;
    } else {
        const correct_row: u8 = if (res.turn == .white) '6' else '3';
        if (en_passant_target_square_string.len != 2 or
            en_passant_target_square_string[1] != correct_row)
            return error.InvalidEnPassantTarget;

        const board = Bitboard.fromSquare(try Square.parse(en_passant_target_square_string));
        const should_overlap = if (res.turn == .white) Bitboard.forward(res.black.getBoard(.pawn), 1) else Bitboard.backward(res.white.getBoard(.pawn), 1);
        if (board & should_overlap == 0) return error.EnPassantTargetDoesntExist;
        res.en_passant_target = Square.fromInt(@intCast(@ctz(board)));
    }

    const halfmove_clock_string = iter.next() orelse "0";
    res.halfmove_clock = try std.fmt.parseInt(u8, halfmove_clock_string, 10);
    const fullmove_clock_str = iter.next() orelse "1";
    const fullmove = try std.fmt.parseInt(u64, fullmove_clock_str, 10);
    if (fullmove == 0)
        return error.InvalidFullMove;
    res.fullmove_clock = fullmove;
    // res.resetZobrist();

    return res;
}

pub fn currentSide(self: Self) PieceSet {
    return self.getSide(self.turn);
}

pub fn getSide(self: Self, turn: Side) PieceSet {
    return switch (turn) {
        .white => self.white,
        .black => self.black,
    };
}

pub fn playMove(self: *Self, move: Move) void {
    _ = self; // autofix
    _ = move; // autofix

}
