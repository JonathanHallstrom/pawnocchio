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
const Piece = @import("Piece.zig");
const movegen = @import("movegen.zig");

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
mailbox: [64]?PieceType = .{null} ** 64,

pub const white_kingside_castle: u4 = 1;
pub const black_kingside_castle: u4 = 2;
pub const white_queenside_castle: u4 = 4;
pub const black_queenside_castle: u4 = 8;

const Self = @This();

pub fn init() Board {
    return parseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") catch unreachable;
}

pub fn parseFen(fen: []const u8) !Board {
    if (std.ascii.eqlIgnoreCase(fen, "startpos")) return init();
    if (std.mem.count(u8, fen, "/") > 7) return error.TooManyRanks;
    if (std.mem.count(u8, fen, "/") < 7) return error.TooFewRanks;
    var iter = std.mem.tokenizeAny(u8, fen, " /");
    var ranks: [8][]const u8 = undefined;
    for (0..8) |i| {
        ranks[i] = iter.next().?;
    }

    var white_king_square: ?Square = null;
    var black_king_square: ?Square = null;
    var white_rooks_on_first_rank = try std.BoundedArray(File, 64).init(0);
    var black_rooks_on_last_rank = try std.BoundedArray(File, 64).init(0);
    var res: Self = .{};
    for (0..8) |r| {
        var c: usize = 0;
        for (ranks[7 - r]) |ch| {
            if (c >= 8) return error.TooManyPiecesOnRank;
            const current_square = Square.fromInt(@intCast(8 * r + c));
            if (std.ascii.isLower(ch)) {
                res.black.addPiece(PieceType.fromLetter(ch), current_square);
                res.mailbox[8 * r + c] = PieceType.fromLetter(ch);
                if (ch == 'k') black_king_square = current_square;
                if (ch == 'r' and current_square.getRank() == .eighth) black_rooks_on_last_rank.append(current_square.getFile()) catch return error.TooManyRooks;
                c += 1;
            } else if (std.ascii.isUpper(ch)) {
                res.white.addPiece(PieceType.fromLetter(ch), current_square);
                res.mailbox[8 * r + c] = PieceType.fromLetter(ch);
                if (ch == 'K') white_king_square = current_square;
                if (ch == 'R' and current_square.getRank() == .first) white_rooks_on_first_rank.append(current_square.getFile()) catch return error.TooManyRooks;
                c += 1;
            } else switch (ch) {
                '1'...'8' => |n| c += n - '0',
                else => return error.InvalidCharacter,
            }
        }
        if (c > 8) return error.TooManyPiecesOnRank;
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
            var candidate_rook: File = .h;
            var num_candidates: usize = 0;
            for (white_rooks_on_first_rank.slice()) |rook| {
                if (rook.toInt() < king_file.toInt()) {
                    num_candidates += 1;
                    candidate_rook = File.fromInt(@min(candidate_rook.toInt(), rook.toInt()));
                }
            }
            if (num_candidates == 0) return error.NoRookForCastling;
            if (num_candidates > 1 and candidate_rook != .a) return error.AmbiguousRookCastlingFile;
            white_queenside_file = candidate_rook;
        }
        if (res.castling_rights & white_kingside_castle != 0 and white_kingside_file == null) {
            const king_file = white_king_square.?.getFile();
            var candidate_rook: File = .a;
            var num_candidates: usize = 0;
            for (white_rooks_on_first_rank.slice()) |rook| {
                if (rook.toInt() > king_file.toInt()) {
                    num_candidates += 1;
                    candidate_rook = File.fromInt(@max(candidate_rook.toInt(), rook.toInt()));
                }
            }
            if (num_candidates == 0) return error.NoRookForCastling;
            if (num_candidates > 1 and candidate_rook != .h) return error.AmbiguousRookCastlingFile;
            white_kingside_file = candidate_rook;
        }

        if (res.castling_rights & black_queenside_castle != 0 and black_queenside_file == null) {
            const king_file = black_king_square.?.getFile();
            var candidate_rook: File = .h;
            var num_candidates: usize = 0;
            for (black_rooks_on_last_rank.slice()) |rook| {
                if (rook.toInt() < king_file.toInt()) {
                    num_candidates += 1;
                    candidate_rook = File.fromInt(@min(candidate_rook.toInt(), rook.toInt()));
                }
            }
            if (num_candidates == 0) return error.NoRookForCastling;
            if (num_candidates > 1 and candidate_rook != .a) return error.AmbiguousRookCastlingFile;
            black_queenside_file = candidate_rook;
        }
        if (res.castling_rights & black_kingside_castle != 0 and black_kingside_file == null) {
            const king_file = black_king_square.?.getFile();
            var candidate_rook: File = .a;
            var num_candidates: usize = 0;
            for (black_rooks_on_last_rank.slice()) |rook| {
                if (rook.toInt() > king_file.toInt()) {
                    num_candidates += 1;
                    candidate_rook = File.fromInt(@max(candidate_rook.toInt(), rook.toInt()));
                }
            }
            if (num_candidates == 0) return error.NoRookForCastling;
            if (num_candidates > 1 and candidate_rook != .h) return error.AmbiguousRookCastlingFile;
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
        const correct_rank: u8 = if (res.turn == .white) '6' else '3';
        if (en_passant_target_square_string.len != 2 or
            en_passant_target_square_string[1] != correct_rank)
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

pub fn toString(self: Board) [17][33]u8 {
    const row: [33]u8 = ("+" ++ "---+" ** 8).*;
    var res: [17][33]u8 = .{row} ++ (.{("|" ++ "   |" ** 8).*} ++ .{row}) ** 8;
    for (0..8) |r| {
        for (0..8) |c| {
            if (self.mailbox[8 * r + c]) |s| {
                if (Bitboard.contains(self.white.all, Square.fromRankFile(r, c))) {
                    res[2 * (7 - r) + 1][4 * c + 2] = std.ascii.toUpper(s.toLetter());
                } else {
                    res[2 * (7 - r) + 1][4 * c + 2] = std.ascii.toLower(s.toLetter());
                }
            }
        }
    }
    return res;
}

pub fn format(self: Board, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = actual_fmt;
    _ = options;
    for (self.toString()) |row| {
        try writer.print("{s}\n", .{row});
    }
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

pub fn getSidePtr(self: *Self, turn: Side) *PieceSet {
    return switch (turn) {
        .white => &self.white,
        .black => &self.black,
    };
}

pub fn playMove(self: *Self, comptime turn: Side, move: Move) MoveInverse {
    var inverse = MoveInverse{
        .move = move,
        .castling = self.castling_rights,
        .en_passant = self.en_passant_target,
        .halfmove = self.halfmove_clock,
        .captured = null,
    };
    const us = self.getSidePtr(turn);
    const them = self.getSidePtr(turn.flipped());
    const from = move.getFrom();
    const to = move.getTo();

    const update_bb = from.toBitboard() | to.toBitboard();
    us.all ^= update_bb;

    const pawn_double_move_mask: u64 = 255 * (1 << 8 | 1 << 24) * if (turn == .white) 1 else 1 << 24;

    self.en_passant_target = null;

    if (move.isCapture()) {
        if (move.isEnPassant()) {
            const pawn_d_rank: i8 = if (turn == .white) 1 else -1;
            const ep_pawn_square = to.move(-pawn_d_rank, 0);

            const ep_pawn_bb = ep_pawn_square.toBitboard();

            them.all ^= ep_pawn_bb;
            them.getBoardPtr(.pawn).* ^= ep_pawn_bb;
            us.getBoardPtr(.pawn).* ^= update_bb;
            self.mailbox[from.toInt()] = null;
            self.mailbox[ep_pawn_square.toInt()] = null;
            self.mailbox[to.toInt()] = .pawn;
            inverse.captured = Piece{
                .sq = ep_pawn_square,
                .tp = .pawn,
            };
        } else {
            const from_type = self.mailbox[from.toInt()].?;
            const captured_type = self.mailbox[to.toInt()].?;
            const to_type = if (move.getPromotedPieceType()) |pt| pt else from_type;
            self.mailbox[from.toInt()] = null;
            self.mailbox[to.toInt()] = to_type;
            inverse.captured = Piece{
                .sq = to,
                .tp = captured_type,
            };
            them.getBoardPtr(captured_type).* ^= to.toBitboard();
            them.all ^= to.toBitboard();
            if (from_type == to_type) {
                us.getBoardPtr(from_type).* ^= update_bb;
            } else {
                us.getBoardPtr(from_type).* ^= from.toBitboard();
                us.getBoardPtr(to_type).* ^= to.toBitboard();
            }

            if (captured_type == .rook) {
                const them_kingside_rook_starting_square = Square.fromRankFile(
                    if (turn == .black) Rank.first else Rank.eighth,
                    if (turn == .black) self.white_kingside_rook_file else self.black_kingside_rook_file,
                );

                const them_queenside_rook_starting_square = Square.fromRankFile(
                    if (turn == .black) Rank.first else Rank.eighth,
                    if (turn == .black) self.white_queenside_rook_file else self.black_queenside_rook_file,
                );

                if (to == them_kingside_rook_starting_square) {
                    self.castling_rights &= ~if (turn == .black) white_kingside_castle else black_kingside_castle;
                }
                if (to == them_queenside_rook_starting_square) {
                    self.castling_rights &= ~if (turn == .black) white_queenside_castle else black_queenside_castle;
                }
            }

            const kingside_rook_starting_square = Square.fromRankFile(
                if (turn == .white) Rank.first else Rank.eighth,
                if (turn == .white) self.white_kingside_rook_file else self.black_kingside_rook_file,
            );

            const queenside_rook_starting_square = Square.fromRankFile(
                if (turn == .white) Rank.first else Rank.eighth,
                if (turn == .white) self.white_queenside_rook_file else self.black_queenside_rook_file,
            );

            if (from_type == .rook) {
                if (from == kingside_rook_starting_square) {
                    self.castling_rights &= ~if (turn == .white) white_kingside_castle else black_kingside_castle;
                }
                if (from == queenside_rook_starting_square) {
                    self.castling_rights &= ~if (turn == .white) white_queenside_castle else black_queenside_castle;
                }
            }

            if (from_type == .king) {
                self.castling_rights &= ~if (turn == .white) white_kingside_castle | white_queenside_castle else black_kingside_castle | black_queenside_castle;
            }
        }
    } else if (move.isCastlingMove()) {
        if (move.getFlag() == .castle_kingside) {
            us.all ^= update_bb;
            const rook_from_square = Square.fromRankFile(
                if (turn == .white) Rank.first else Rank.eighth,
                if (turn == .white) self.white_kingside_rook_file else self.black_kingside_rook_file,
            );
            const king_destination = if (turn == .white) Square.g1 else Square.g8;
            const rook_destination = if (turn == .white) Square.f1 else Square.f8;
            us.getBoardPtr(.rook).* ^= rook_from_square.toBitboard() ^ rook_destination.toBitboard();
            us.getBoardPtr(.king).* ^= from.toBitboard() ^ king_destination.toBitboard();
            us.all ^= rook_from_square.toBitboard() ^ rook_destination.toBitboard();
            us.all ^= from.toBitboard() ^ king_destination.toBitboard();
            self.mailbox[rook_from_square.toInt()] = null;
            self.mailbox[from.toInt()] = null;
            self.mailbox[rook_destination.toInt()] = .rook;
            self.mailbox[king_destination.toInt()] = .king;
        } else {
            us.all ^= update_bb;
            const rook_from_square = Square.fromRankFile(
                if (turn == .white) Rank.first else Rank.eighth,
                if (turn == .white) self.white_queenside_rook_file else self.black_queenside_rook_file,
            );
            const king_destination = if (turn == .white) Square.c1 else Square.c8;
            const rook_destination = if (turn == .white) Square.d1 else Square.d8;
            us.getBoardPtr(.rook).* ^= rook_from_square.toBitboard() ^ rook_destination.toBitboard();
            us.getBoardPtr(.king).* ^= from.toBitboard() ^ king_destination.toBitboard();
            us.all ^= rook_from_square.toBitboard() ^ rook_destination.toBitboard();
            us.all ^= from.toBitboard() ^ king_destination.toBitboard();
            self.mailbox[rook_from_square.toInt()] = null;
            self.mailbox[from.toInt()] = null;
            self.mailbox[rook_destination.toInt()] = .rook;
            self.mailbox[king_destination.toInt()] = .king;
        }
        self.castling_rights &= ~if (turn == .white) white_kingside_castle | white_queenside_castle else black_kingside_castle | black_queenside_castle;
    } else {
        const from_type = self.mailbox[from.toInt()].?;
        if (from_type == .pawn and update_bb & pawn_double_move_mask == update_bb) {
            self.en_passant_target = to.move(if (turn == .white) -1 else 1, 0);
        }
        const to_type = if (move.getPromotedPieceType()) |pt| pt else from_type;
        self.mailbox[from.toInt()] = null;
        self.mailbox[to.toInt()] = to_type;
        if (from_type == to_type) {
            us.getBoardPtr(from_type).* ^= update_bb;
        } else {
            us.getBoardPtr(from_type).* ^= from.toBitboard();
            us.getBoardPtr(to_type).* ^= to.toBitboard();
        }

        const kingside_rook_starting_square = Square.fromRankFile(
            if (turn == .white) Rank.first else Rank.eighth,
            if (turn == .white) self.white_kingside_rook_file else self.black_kingside_rook_file,
        );

        const queenside_rook_starting_square = Square.fromRankFile(
            if (turn == .white) Rank.first else Rank.eighth,
            if (turn == .white) self.white_queenside_rook_file else self.black_queenside_rook_file,
        );

        if (from_type == .rook) {
            if (from == kingside_rook_starting_square) {
                self.castling_rights &= ~if (turn == .white) white_kingside_castle else black_kingside_castle;
            }
            if (from == queenside_rook_starting_square) {
                self.castling_rights &= ~if (turn == .white) white_queenside_castle else black_queenside_castle;
            }
        }

        if (from_type == .king) {
            self.castling_rights &= ~if (turn == .white) white_kingside_castle | white_queenside_castle else black_kingside_castle | black_queenside_castle;
        }
    }
    self.turn = turn.flipped();

    return inverse;
}

pub fn playMoveCopy(self: Self, comptime turn: Side, move: Move) Board {
    var res = self;
    _ = res.playMove(turn, move);
    return res;
}

pub fn undoMove(self: *Self, inverse: MoveInverse) void {
    _ = self; // autofix
    _ = inverse; // autofix

}

var moves_dbg: [100]Move = undefined;
var num_dbg_moves: usize = 0;

pub fn playMoveFromStr(self: *Self, str: []const u8) !MoveInverse {
    var buf: [256]Move = undefined;
    const num_moves = movegen.getMovesWithoutTurn(self.*, &buf);

    for (buf[0..num_moves]) |move| {
        if (move.isSameAsStr(str)) {
            return switch (self.turn) {
                inline else => |turn| self.playMove(turn, move),
            };
        }
    }
    std.debug.print("moves: {any}\n", .{buf[0..num_moves]});
    return error.MoveNotFound;
}

pub fn perftSingleThreadedNonBulk(self: *Self, move_buf: []Move, depth: usize) u64 {
    const impl = struct {
        fn impl(board: *Board, comptime turn: Side, cur_depth: u8, moves: []Move, d: usize) u64 {
            if (d == 0) return 1;
            const num_moves = movegen.getMoves(turn, board.*, moves);
            var res: u64 = 0;
            for (moves[0..num_moves]) |move| {
                moves_dbg[num_dbg_moves] = move;
                num_dbg_moves += 1;
                var new_board = board.playMoveCopy(turn, move);
                const count = impl(&new_board, turn.flipped(), cur_depth + 1, moves[num_moves..], d - 1);
                if (cur_depth == 0) {
                    std.debug.print("{}: {}\n", .{ move, count });
                    // std.debug.print("{}\n", .{ new_board });
                }
                res += count;
                num_dbg_moves -= 1;
            }
            return res;
        }
    }.impl;
    return switch (self.turn) {
        inline else => |turn| impl(self, turn, 0, move_buf, depth),
    };
}
pub fn perftSingleThreaded(self: *Self, move_buf: []Move, depth: usize, comptime debug: bool) u64 {
    const impl = struct {
        fn impl(board: *Board, comptime turn: Side, cur_depth: u8, moves: []Move, d: usize) u64 {
            if (d == 0) return 1;
            const num_moves = movegen.getMoves(turn, board.*, moves);
            if (d == 1) {
                if (cur_depth == 0) {
                    for (moves[0..num_moves]) |move| {
                        if (debug) {
                            std.debug.print("{}: 1\n", .{move});
                        }
                    }
                }
                return num_moves;
            }
            var res: u64 = 0;
            for (moves[0..num_moves]) |move| {
                moves_dbg[num_dbg_moves] = move;
                num_dbg_moves += 1;
                var new_board = board.playMoveCopy(turn, move);
                const count = impl(&new_board, turn.flipped(), cur_depth + 1, moves[num_moves..], d - 1);
                if (cur_depth == 0) {
                    if (debug) {
                        std.debug.print("{}: {}\n", .{ move, count });
                    } // std.debug.print("{}\n", .{new_board});
                }
                res += count;
                num_dbg_moves -= 1;
            }
            return res;
        }
    }.impl;
    return switch (self.turn) {
        inline else => |turn| impl(self, turn, 0, move_buf, depth),
    };
}

test "debugging" {
    var board = Board.init();
    _ = try board.playMoveFromStr("e2e4");
    _ = try board.playMoveFromStr("f7f5");
    _ = try board.playMoveFromStr("e4e5");
    _ = try board.playMoveFromStr("d7d5");
    _ = try board.playMoveFromStr("e5d6");
}

test "crazy fens" {
    try std.testing.expect(std.meta.isError(Board.parseFen("k7/ppppppppp/8/8/8/8/8/K7 w - - 0 1")));
    try std.testing.expect(std.meta.isError(Board.parseFen("k7/8/8/8/8/8/8/8/K7 w - - 0 1")));
    try std.testing.expect(std.meta.isError(Board.parseFen("kK/8/8/8/8/8/8/8/8 w - - 0 1")));
}

test "ambiguous castling" {
    try std.testing.expect(std.meta.isError(Board.parseFen("3k4/8/8/8/8/8/8/1RRK4 w Q - 0 1")));
}

test "shredder fen castling" {
    try std.testing.expectEqual(.a, (try Board.parseFen("3k4/8/8/8/8/8/8/RR1K4 w A - 0 1")).white_queenside_rook_file);
    try std.testing.expectEqual(.b, (try Board.parseFen("3k4/8/8/8/8/8/8/RR1K4 w B - 0 1")).white_queenside_rook_file);
    try std.testing.expectEqual(.g, (try Board.parseFen("3k4/8/8/8/8/8/8/3K2RR w G - 0 1")).white_kingside_rook_file);
    try std.testing.expectEqual(.h, (try Board.parseFen("3k4/8/8/8/8/8/8/3K2RR w H - 0 1")).white_kingside_rook_file);
    try std.testing.expectEqual(.b, (try Board.parseFen("3k4/8/8/8/8/8/8/1R1K2R1 w B - 0 1")).white_queenside_rook_file);
    try std.testing.expectEqual(.g, (try Board.parseFen("3k4/8/8/8/8/8/8/1R1K2R1 w G - 0 1")).white_kingside_rook_file);
    try std.testing.expect(std.meta.isError(Board.parseFen("3k4/8/8/8/8/8/8/1R1K2R1 w A - 0 1")));
    try std.testing.expect(std.meta.isError(Board.parseFen("3k4/8/8/8/8/8/8/1R1K2R1 w H - 0 1")));
}

test "assume a or h if ambiguous" {
    try std.testing.expectEqual(.a, (try Board.parseFen("4k3/8/8/8/8/8/8/RR2K3 w Q - 0 1")).white_queenside_rook_file);
    try std.testing.expectEqual(.h, (try Board.parseFen("4k3/8/8/8/8/8/8/4K1RR w K - 0 1")).white_kingside_rook_file);
    try std.testing.expectEqual(.a, (try Board.parseFen("rr2k3/8/8/8/8/8/8/4K3 w q - 0 1")).black_queenside_rook_file);
    try std.testing.expectEqual(.h, (try Board.parseFen("4k1rr/8/8/8/8/8/8/4K3 w k - 0 1")).black_kingside_rook_file);
}

test playMoveCopy {
    var buf: [256]Move = undefined;
    const board = Board.init();
    const num_moves = movegen.getMoves(.white, board, &buf);

    try std.testing.expectEqual(20, num_moves);
    for (buf[0..num_moves]) |move| {
        std.mem.doNotOptimizeAway(board.playMoveCopy(.white, move));
    }
}
