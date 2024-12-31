const std = @import("std");
const assert = std.debug.assert;
const Side = @import("side.zig").Side;
const PieceSet = @import("PieceSet.zig");
const PieceType = @import("piece_type.zig").PieceType;
const Move = @import("Move.zig");
const Board = @This();
const Square = @import("square.zig").Square;
const File = @import("square.zig").File;
const Rank = @import("square.zig").Rank;
const Bitboard = @import("Bitboard.zig");
const MoveInverse = @import("MoveInverse.zig");

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
white_queenside_rook_file: File = File.a,
white_kingside_rook_file: File = File.h,
black_queenside_rook_file: File = File.a,
black_kingside_rook_file: File = File.h,
en_passant_target: ?Square = null,

halfmove_clock: u8 = 0,
fullmove_clock: u64 = 1,
zobrist: u64 = 0,

white: PieceSet = .{},
black: PieceSet = .{},
mailbox: [8][8]?PieceType = .{.{null} ** 8} ** 8,

pub const white_kingside_castle: u4 = 1;
pub const black_kingside_castle: u4 = 2;
pub const white_queenside_castle: u4 = 4;
pub const black_queenside_castle: u4 = 8;

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

    var white_king_square: ?Square = null;
    var black_king_square: ?Square = null;
    var white_rooks_on_first_rank = try std.BoundedArray(File, 64).init(0);
    var black_rooks_on_last_rank = try std.BoundedArray(File, 64).init(0);
    var res: Self = .{};
    for (0..8) |r| {
        var c: usize = 0;
        for (rows[7 - r]) |ch| {
            const current_square = Square.fromInt(@intCast(8 * r + c));
            if (std.ascii.isLower(ch)) {
                res.black.addPiece(PieceType.fromLetter(ch), current_square);
                res.mailbox[r][c] = PieceType.fromLetter(ch);
                if (ch == 'k') black_king_square = current_square;
                if (ch == 'r' and current_square.getRank() == .eighth) black_rooks_on_last_rank.append(current_square.getFile()) catch return error.TooManyRooks;
                c += 1;
            } else if (std.ascii.isUpper(ch)) {
                res.white.addPiece(PieceType.fromLetter(ch), current_square);
                res.mailbox[r][c] = PieceType.fromLetter(ch);
                if (ch == 'K') white_king_square = current_square;
                if (ch == 'R' and current_square.getRank() == .first) white_rooks_on_first_rank.append(current_square.getFile()) catch return error.TooManyRooks;
                c += 1;
            } else switch (ch) {
                '1'...'8' => |n| c += n - '0',
                else => return error.InvalidCharacter,
            }
        }
    }

    if (white_king_square == null or black_king_square == null) return error.MissingKing;

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
    if (castling_string.len > 4) return error.CastlingStringTooBig;
    if (!std.mem.eql(u8, "-", castling_string)) {
        var white_queenside_file: ?File = null;
        var white_kingside_file: ?File = null;
        var black_queenside_file: ?File = null;
        var black_kingside_file: ?File = null;
        for (castling_string) |castle_ch| {
            res.castling_rights |= switch (castle_ch) {
                'K' => white_kingside_castle,
                'k' => black_kingside_castle,
                'Q' => white_queenside_castle,
                'q' => black_queenside_castle,
                else => blk: {
                    const file = File.parse(castle_ch) catch return error.InvalidCharacter;
                    const king_square, const kingside_castle, const queenside_castle, const rooks = if (std.ascii.isUpper(castle_ch)) .{
                        white_king_square.?,
                        white_kingside_castle,
                        white_queenside_castle,
                        &white_rooks_on_first_rank,
                    } else .{
                        black_king_square.?,
                        black_kingside_castle,
                        black_queenside_castle,
                        &black_rooks_on_last_rank,
                    };

                    if (std.mem.count(File, rooks.slice(), &.{file}) == 0)
                        return error.NoRookForCastling;

                    if (@intFromEnum(file) > @intFromEnum(king_square.getFile())) {
                        if (res.turn == .white) {
                            white_kingside_file = file;
                        } else {
                            black_kingside_file = file;
                        }
                        break :blk kingside_castle;
                    }
                    if (@intFromEnum(file) < @intFromEnum(king_square.getFile())) {
                        if (res.turn == .white) {
                            white_queenside_file = file;
                        } else {
                            black_queenside_file = file;
                        }
                        break :blk queenside_castle;
                    }
                    return error.CastlingRightsOverLapKing;
                },
            };
        }
        // determine the white queenside castling file
        if (res.castling_rights & white_queenside_castle != 0 and white_queenside_file == null) {
            const king_file = white_king_square.?.getFile();
            var candidate_rook: File = .a;
            var num_candidates: usize = 0;
            for (white_rooks_on_first_rank.slice()) |rook| {
                if (rook.toInt() < king_file.toInt()) {
                    num_candidates += 1;
                    candidate_rook = rook;
                }
            }
            if (num_candidates == 0) return error.NoRookForCastling;
            if (num_candidates > 1) return error.AmbiguousRookCastlingFile;
            white_queenside_file = candidate_rook;
        }
        if (res.castling_rights & white_kingside_castle != 0 and white_kingside_file == null) {
            const king_file = white_king_square.?.getFile();
            var candidate_rook: File = .a;
            var num_candidates: usize = 0;
            for (white_rooks_on_first_rank.slice()) |rook| {
                if (rook.toInt() > king_file.toInt()) {
                    num_candidates += 1;
                    candidate_rook = rook;
                }
            }
            if (num_candidates == 0) return error.NoRookForCastling;
            if (num_candidates > 1) return error.AmbiguousRookCastlingFile;
            white_kingside_file = candidate_rook;
        }

        if (res.castling_rights & black_queenside_castle != 0 and black_queenside_file == null) {
            const king_file = black_king_square.?.getFile();
            var candidate_rook: File = .a;
            var num_candidates: usize = 0;
            for (black_rooks_on_last_rank.slice()) |rook| {
                if (rook.toInt() < king_file.toInt()) {
                    num_candidates += 1;
                    candidate_rook = rook;
                }
            }
            if (num_candidates == 0) return error.NoRookForCastling;
            if (num_candidates > 1) return error.AmbiguousRookCastlingFile;
            black_queenside_file = candidate_rook;
        }
        if (res.castling_rights & black_kingside_castle != 0 and black_kingside_file == null) {
            const king_file = black_king_square.?.getFile();
            var candidate_rook: File = .a;
            var num_candidates: usize = 0;
            for (black_rooks_on_last_rank.slice()) |rook| {
                if (rook.toInt() > king_file.toInt()) {
                    num_candidates += 1;
                    candidate_rook = rook;
                }
            }
            if (num_candidates == 0) return error.NoRookForCastling;
            if (num_candidates > 1) return error.AmbiguousRookCastlingFile;
            black_kingside_file = candidate_rook;
        }
        res.white_kingside_rook_file = white_kingside_file orelse white_king_square.?.getFile();
        res.white_queenside_rook_file = white_queenside_file orelse white_king_square.?.getFile();
        res.black_kingside_rook_file = black_kingside_file orelse black_king_square.?.getFile();
        res.black_queenside_rook_file = black_queenside_file orelse black_king_square.?.getFile();
    }

    const en_passant_target_square_string = iter.next() orelse return error.MissingEnPassantTarget;
    if (std.mem.eql(u8, en_passant_target_square_string, "-")) {
        res.en_passant_target = null;
    } else {
        const correct_row: u8 = if (res.turn == .white) '6' else '3';
        if (en_passant_target_square_string.len != 2 or
            en_passant_target_square_string[1] != correct_row)
            return error.InvalidEnPassantTarget;

        const en_passant_bitboard = Bitboard.fromSquare(try Square.parse(en_passant_target_square_string));
        const pawn_d_rank: i8 = if (res.turn == .white) 1 else -1;
        const us_pawns = res.getSide(res.turn).getBoard(.pawn);
        const them_pawns = res.getSide(res.turn.flipped()).getBoard(.pawn);

        if (en_passant_bitboard & Bitboard.move(them_pawns, pawn_d_rank, 0) == 0)
            return error.EnPassantTargetDoesntExist;
        if (en_passant_bitboard & (Bitboard.move(us_pawns, pawn_d_rank, 1) | Bitboard.move(us_pawns, pawn_d_rank, -1)) == 0)
            return error.EnPassantCantBeCaptured;
        res.en_passant_target = Square.fromBitboard(en_passant_bitboard);
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

pub fn playMove(self: *Self, move: Move) MoveInverse {
    _ = self; // autofix
    _ = move; // autofix

}

test "ambiguous castling" {
    try std.testing.expect(std.meta.isError(Board.parseFen("3k4/8/8/8/8/8/8/1RRK4 w Q - 0 1,")));
}

test "correctly take shredder fen castling" {
    try std.testing.expectEqual(.a, (try Board.parseFen("3k4/8/8/8/8/8/8/RR1K4 w A - 0 1")).white_queenside_rook_file);
    try std.testing.expectEqual(.b, (try Board.parseFen("3k4/8/8/8/8/8/8/RR1K4 w B - 0 1")).white_queenside_rook_file);
    try std.testing.expectEqual(.g, (try Board.parseFen("3k4/8/8/8/8/8/8/3K2RR w G - 0 1")).white_kingside_rook_file);
    try std.testing.expectEqual(.h, (try Board.parseFen("3k4/8/8/8/8/8/8/3K2RR w H - 0 1")).white_kingside_rook_file);
    try std.testing.expectEqual(.b, (try Board.parseFen("3k4/8/8/8/8/8/8/1R1K2R1 w QK - 0 1")).white_queenside_rook_file);
    try std.testing.expectEqual(.g, (try Board.parseFen("3k4/8/8/8/8/8/8/1R1K2R1 w QK - 0 1")).white_kingside_rook_file);
    try std.testing.expect(std.meta.isError(Board.parseFen("3k4/8/8/8/8/8/8/1R1K2R1 w AQ - 0 1")));
    try std.testing.expect(std.meta.isError(Board.parseFen("3k4/8/8/8/8/8/8/1R1K2R1 w KH - 0 1")));
}
