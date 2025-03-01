const std = @import("std");
const assert = std.debug.assert;
const Side = @import("side.zig").Side;
const PieceSet = @import("PieceSet.zig");
const PieceType = @import("piece_type.zig").PieceType;
const Move = @import("Move.zig").Move;
const Board = @This();
const Square = @import("square.zig").Square;
const File = @import("square.zig").File;
const Rank = @import("square.zig").Rank;
const Bitboard = @import("Bitboard.zig");
const MoveInverse = @import("MoveInverse.zig");
const Piece = @import("Piece.zig");
const movegen = @import("movegen.zig");
const Zobrist = @import("Zobrist.zig");
const eval = @import("eval.zig");
const EvalState = eval.PSQTEvalState;
const magics = @import("magics.zig");

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
pawn_zobrist: u64 = 0,

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
// https://github.com/Ciekce/Stormphrax/blob/15e9d26a74198ee01a1205741213d79cbaac1912/src/position/position.cpp

fn frcBackrank(n: anytype) [8]PieceType {
    assert(n < 960);
    const N5n: [10][2]u8 = .{
        .{ 0, 0 },
        .{ 0, 1 },
        .{ 0, 2 },
        .{ 0, 3 },
        .{ 1, 1 },
        .{ 1, 2 },
        .{ 1, 3 },
        .{ 2, 2 },
        .{ 2, 3 },
        .{ 3, 3 },
    };

    const n2 = n / 4;
    const b1 = n % 4;

    const n3 = n2 / 4;
    const b2 = n2 % 4;

    const n4 = n3 / 6;
    const q = n3 % 6;

    var out: [8]PieceType = .{.pawn} ** 8;
    out[b1 * 2 + 1] = .bishop;
    out[b2 * 2] = .bishop;

    {
        var empty: u8 = 0;
        for (0..8) |i| {
            if (out[i] == .pawn) {
                if (empty == q) {
                    out[i] = .queen;
                }
                empty += 1;
            }
        }
    }

    const knight1, const knight2 = N5n[n4];
    {
        var empty: u8 = 0;
        for (0..8) |i| {
            if (out[i] == .pawn) {
                if (empty == knight1) {
                    out[i] = .knight;
                }
                empty += 1;
            }
        }
    }

    {
        var empty: u8 = 0;
        for (0..8) |i| {
            if (out[i] == .pawn) {
                if (empty == knight2) {
                    out[i] = .knight;
                }
                empty += 1;
            }
        }
    }

    out[std.mem.indexOfScalar(PieceType, &out, .pawn) orelse unreachable] = .rook;
    out[std.mem.indexOfScalar(PieceType, &out, .pawn) orelse unreachable] = .king;
    out[std.mem.indexOfScalar(PieceType, &out, .pawn) orelse unreachable] = .rook;
    for (out) |pt| {
        assert(pt != .pawn);
    }
    return out;
}

test "frc" {
    try std.testing.expectEqualDeep(init(), frcPosition(518));
}

pub fn dfrcPosition(n: u20) Board {
    const white_rank = frcBackrank(n % 960);
    const black_rank = frcBackrank(n / 960);

    var res: Board = .{};
    var white_rook = false;
    var black_rook = false;
    inline for (0..8) |c| {
        res.mailbox[c] = white_rank[c];
        res.mailbox[8 + c] = .pawn;
        res.white.all |= Square.fromInt(c).toBitboard();
        res.white.all |= Square.fromInt(8 + c).toBitboard();
        res.white.getBoardPtr(white_rank[c]).* |= Square.fromInt(c).toBitboard();
        res.white.getBoardPtr(.pawn).* |= Square.fromInt(8 + c).toBitboard();
        if (white_rank[c] == .rook) {
            if (white_rook) {
                res.white_kingside_rook_file = File.fromInt(c);
            } else {
                res.white_queenside_rook_file = File.fromInt(c);
            }
            white_rook = true;
        }
        res.mailbox[56 + c] = black_rank[c];
        res.mailbox[48 + c] = .pawn;
        res.black.all |= Square.fromInt(56 + c).toBitboard();
        res.black.all |= Square.fromInt(48 + c).toBitboard();
        res.black.getBoardPtr(black_rank[c]).* |= Square.fromInt(56 + c).toBitboard();
        res.black.getBoardPtr(.pawn).* |= Square.fromInt(48 + c).toBitboard();
        if (black_rank[c] == .rook) {
            if (black_rook) {
                res.black_kingside_rook_file = File.fromInt(c);
            } else {
                res.black_queenside_rook_file = File.fromInt(c);
            }
            black_rook = true;
        }
    }

    res.castling_rights = white_kingside_castle | white_queenside_castle | black_kingside_castle | black_queenside_castle;
    res.halfmove_clock = 0;
    res.fullmove_clock = 1;
    res.turn = .white;
    res.resetZobrist();
    return res;
}

pub fn frcPosition(n: u10) Board {
    assert(n < 960);
    return dfrcPosition(@as(u20, n) * 960 + n);
}

pub fn frcPositionComptime(comptime n: u10) if (n < 960) Board else @compileError("there are only 960 positions in frc") {
    return frcPosition(n);
}

fn parseFenImpl(fen: []const u8, permissive: bool) !Board {
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

    if (!permissive and white_king_square == null or black_king_square == null) return error.MissingKing;

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

                    if (!permissive and std.mem.count(File, rooks.slice(), &.{file}) == 0)
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
        const EPError = error{ InvalidEnPassantTarget, EnPassantTargetDoesntExist, EnPassantCantBeCaptured };
        var err_opt: ?EPError = null;
        if (en_passant_target_square_string.len != 2 or
            en_passant_target_square_string[1] != correct_rank)
            err_opt = err_opt orelse error.InvalidEnPassantTarget;

        const en_passant_bitboard = Bitboard.fromSquare(try Square.parse(en_passant_target_square_string));
        const pawn_d_rank: i8 = if (res.turn == .white) 1 else -1;
        const us_pawns = res.getSide(res.turn).getBoard(.pawn);
        const them_pawns = res.getSide(res.turn.flipped()).getBoard(.pawn);

        if (!permissive and en_passant_bitboard & Bitboard.move(them_pawns, pawn_d_rank, 0) == 0)
            err_opt = err_opt orelse error.EnPassantTargetDoesntExist;
        if (!permissive and en_passant_bitboard & (Bitboard.move(us_pawns, pawn_d_rank, 1) | Bitboard.move(us_pawns, pawn_d_rank, -1)) == 0)
            err_opt = err_opt orelse error.EnPassantCantBeCaptured;
        if (err_opt) |err| {
            if (permissive) {
                res.en_passant_target = null;
            } else {
                return err;
            }
        } else {
            res.en_passant_target = Square.fromBitboard(en_passant_bitboard);
        }
    }

    const halfmove_clock_string = iter.next() orelse "0";
    res.halfmove_clock = try std.fmt.parseInt(u8, halfmove_clock_string, 10);
    const fullmove_clock_str = iter.next() orelse "1";
    const fullmove = try std.fmt.parseInt(u64, fullmove_clock_str, 10);
    if (!permissive and fullmove == 0)
        return error.InvalidFullMove;
    res.fullmove_clock = fullmove;
    res.resetZobrist();

    return res;
}

pub fn toFen(self: Board) std.BoundedArray(u8, 128) {
    var out = std.BoundedArray(u8, 128).init(0) catch unreachable;
    inline for (0..8) |rr| {
        const r = 7 - rr;
        var num_unoccupied: u8 = 0;
        inline for (0..8) |c| {
            const idx = r * 8 + c;
            const sq = Square.fromInt(idx);
            if (self.mailbox[idx]) |pt| {
                var char = pt.toLetter();
                if (self.white.all & sq.toBitboard() != 0) {
                    char = std.ascii.toUpper(char);
                } else {
                    char = std.ascii.toLower(char);
                }
                if (num_unoccupied > 0) out.appendAssumeCapacity('0' + num_unoccupied);
                out.appendAssumeCapacity(char);
                num_unoccupied = 0;
            } else {
                num_unoccupied += 1;
            }
        }
        if (num_unoccupied > 0) out.appendAssumeCapacity('0' + num_unoccupied);
        if (r > 0)
            out.appendAssumeCapacity('/');
    }
    out.appendAssumeCapacity(' ');
    out.appendAssumeCapacity(if (self.turn == .white) 'w' else 'b');
    out.appendAssumeCapacity(' ');
    if (self.castling_rights == 0) {
        out.appendAssumeCapacity('-');
    } else {
        if (self.castling_rights & white_kingside_castle != 0) out.appendAssumeCapacity('K');
        if (self.castling_rights & white_queenside_castle != 0) out.appendAssumeCapacity('Q');
        if (self.castling_rights & black_kingside_castle != 0) out.appendAssumeCapacity('k');
        if (self.castling_rights & black_queenside_castle != 0) out.appendAssumeCapacity('q');
    }
    out.appendAssumeCapacity(' ');
    if (self.en_passant_target) |ep_target| {
        var buf: [256]Move = undefined;
        var valid = false;
        switch (self.turn) {
            inline else => |t| {
                const masks = movegen.getMasks(t, self);
                const num_moves = movegen.getPawnMoves(
                    t,
                    true,
                    self,
                    &buf,
                    masks.checks,
                    masks.bishop_pins,
                    masks.rook_pins,
                );
                for (buf[0..num_moves]) |move| {
                    if (move.isEnPassant()) {
                        valid = true;
                        break;
                    }
                }
            },
        }
        if (valid) {
            out.appendSliceAssumeCapacity(@tagName(ep_target));
        } else {
            out.appendAssumeCapacity('-');
        }
    } else {
        out.appendAssumeCapacity('-');
    }
    var print_buf: [8]u8 = undefined;
    out.appendAssumeCapacity(' ');
    out.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{self.halfmove_clock}) catch unreachable);
    out.appendAssumeCapacity(' ');
    out.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{self.fullmove_clock}) catch unreachable);

    return out;
}

test "toFen" {
    _ = Board.init().toFen();
}

pub fn parseFen(fen: []const u8) !Board {
    return parseFenImpl(fen, false);
}

pub fn parseFenPermissive(fen: []const u8) !Board {
    return parseFenImpl(fen, true);
}

pub fn computePhase(self: Board) u8 {
    return eval.computePhase(&self);
}

pub fn toString(self: Board) [18][35]u8 {
    const row: [35]u8 = ("  +" ++ "---+" ** 8).*;
    var res: [18][35]u8 = .{row} ++ (.{("  |" ++ "   |" ** 8).*} ++ .{row}) ** 8 ++ .{"    a   b   c   d   e   f   g   h  ".*};
    inline for (0..8) |r| {
        res[2 * (7 - r) + 1][0] = r + '1';
        for (0..8) |c| {
            if (self.mailbox[8 * r + c]) |s| {
                if (Bitboard.contains(self.white.all, Square.fromRankFile(r, c))) {
                    res[2 * (7 - r) + 1][2 + 4 * c + 2] = std.ascii.toUpper(s.toLetter());
                } else {
                    res[2 * (7 - r) + 1][2 + 4 * c + 2] = std.ascii.toLower(s.toLetter());
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

pub fn getFromType(self: Self, move: Move) PieceType {
    return self.mailbox[move.getFrom().toInt()].?;
}

pub fn getToType(self: Self, move: Move) PieceType {
    return move.getPromotedPieceType() orelse self.mailbox[move.getFrom().toInt()].?;
}

// approximate, doesn't consider discovered checks
pub fn moveGivesCheck(self: Self, comptime turn: Side, move: Move) bool {
    const tp = self.getToType(move);
    const occ = (self.white.all | self.black.all);
    const opponent_king = self.getSide(turn.flipped()).getBoard(.king);
    const to_bb = move.getTo().toBitboard();
    return 0 != opponent_king & switch (tp) {
        .pawn => blk: {
            const forward = Bitboard.move(to_bb, if (turn == .white) 1 else -1, 0);
            const attacked_squares = Bitboard.move(forward, 0, 1) | Bitboard.move(forward, 0, -1);
            break :blk attacked_squares;
        },
        .knight => @import("knight_moves.zig").knight_moves_arr[move.getTo().toInt()],
        .bishop => magics.getBishopAttacks(move.getTo(), occ),
        .rook => magics.getBishopAttacks(move.getTo(), occ),
        .queen => magics.getBishopAttacks(move.getTo(), occ) | magics.getRookAttacks(move.getTo(), occ),
        .king => 0,
    };
}

pub fn isInsufficientMaterial(self: Self) bool {
    const pawns = self.white.getBoard(.pawn) | self.black.getBoard(.pawn);
    if (pawns != 0)
        return false;

    const rooks = self.white.getBoard(.rook) | self.black.getBoard(.rook);
    const queens = self.white.getBoard(.queen) | self.black.getBoard(.queen);
    if (rooks | queens != 0)
        return false;

    const white_minor_pieces = self.white.getBoard(.knight) | self.white.getBoard(.bishop);
    const black_minor_pieces = self.black.getBoard(.knight) | self.black.getBoard(.bishop);
    // same asm as white_minor_pieces & white_minor_pieces -% 1 != 0
    if (@popCount(white_minor_pieces) >= 2)
        return false;
    if (@popCount(black_minor_pieces) >= 2)
        return false;
    return true;
}

pub fn isKvKNN(self: Self) bool {
    const occ = self.white.all | self.black.all;
    const kings = self.white.getBoard(.king) | self.black.getBoard(.king);
    const knights = @max(self.white.getBoard(.knight), self.black.getBoard(.knight));
    return occ & (kings | knights) == occ and @popCount(knights) == 2;
}

pub fn playMove(self: *Self, comptime turn: Side, move: Move) MoveInverse {
    var inverse = MoveInverse{
        .move = move,
        .castling = self.castling_rights,
        .en_passant = self.en_passant_target,
        .halfmove = self.halfmove_clock,
        .captured = null,
        .zobrist = self.zobrist,
        .pawn_zobrist = self.pawn_zobrist,
    };
    const us = self.getSidePtr(turn);
    const them = self.getSidePtr(turn.flipped());
    const from = move.getFrom();
    const to = move.getTo();

    const update_bb = from.toBitboard() | to.toBitboard();
    us.all ^= update_bb;

    const pawn_double_move_mask: u64 = 255 * (1 << 8 | 1 << 24) * if (turn == .white) 1 else 1 << 24;

    self.updateEnPassantZobrist();
    self.en_passant_target = null;
    self.halfmove_clock += 1;
    self.fullmove_clock += @intFromBool(self.turn == .black);
    self.turn = turn.flipped();
    self.updateTurnZobrist();
    if (move.isCapture()) {
        self.halfmove_clock = 0;
        if (move.isEnPassant()) {
            const ep_pawn_square = move.getEnPassantPawn(turn);
            const ep_pawn_bb = ep_pawn_square.toBitboard();

            them.all ^= ep_pawn_bb;
            them.getBoardPtr(.pawn).* ^= ep_pawn_bb;
            us.getBoardPtr(.pawn).* ^= update_bb;
            self.mailbox[from.toInt()] = null;
            self.mailbox[ep_pawn_square.toInt()] = null;
            self.mailbox[to.toInt()] = .pawn;
            self.updatePieceZobrist(turn, Piece{ .sq = from, .tp = .pawn });
            self.updatePieceZobrist(turn, Piece{ .sq = to, .tp = .pawn });
            self.updatePieceZobrist(turn.flipped(), Piece{ .sq = ep_pawn_square, .tp = .pawn });
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
            us.getBoardPtr(from_type).* ^= from.toBitboard();
            us.getBoardPtr(to_type).* ^= to.toBitboard();

            self.updatePieceZobrist(turn, Piece{ .sq = from, .tp = from_type });
            self.updatePieceZobrist(turn, Piece{ .sq = to, .tp = to_type });
            self.updatePieceZobrist(turn.flipped(), Piece{ .sq = to, .tp = captured_type });
            assert(captured_type != .king);
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
                    self.updateCastlingZobrist();
                    self.castling_rights &= ~if (turn == .black) white_kingside_castle else black_kingside_castle;
                    self.updateCastlingZobrist();
                }
                if (to == them_queenside_rook_starting_square) {
                    self.updateCastlingZobrist();
                    self.castling_rights &= ~if (turn == .black) white_queenside_castle else black_queenside_castle;
                    self.updateCastlingZobrist();
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
                    self.updateCastlingZobrist();
                    self.castling_rights &= ~if (turn == .white) white_kingside_castle else black_kingside_castle;
                    self.updateCastlingZobrist();
                }
                if (from == queenside_rook_starting_square) {
                    self.updateCastlingZobrist();
                    self.castling_rights &= ~if (turn == .white) white_queenside_castle else black_queenside_castle;
                    self.updateCastlingZobrist();
                }
            }

            if (from_type == .king) {
                self.updateCastlingZobrist();
                self.castling_rights &= ~if (turn == .white) white_kingside_castle | white_queenside_castle else black_kingside_castle | black_queenside_castle;
                self.updateCastlingZobrist();
            }
        }
    } else if (move.isCastlingMove()) {
        us.all ^= update_bb;
        const rook_from_square = move.getTo();
        const king_destination = move.getCastlingKingDest(turn);
        const rook_destination = move.getCastlingRookDest(turn);
        us.getBoardPtr(.rook).* ^= rook_from_square.toBitboard() ^ rook_destination.toBitboard();
        us.getBoardPtr(.king).* ^= from.toBitboard() ^ king_destination.toBitboard();
        us.all ^= rook_from_square.toBitboard() ^ rook_destination.toBitboard();
        us.all ^= from.toBitboard() ^ king_destination.toBitboard();
        self.mailbox[rook_from_square.toInt()] = null;
        self.mailbox[from.toInt()] = null;
        self.mailbox[rook_destination.toInt()] = .rook;
        self.mailbox[king_destination.toInt()] = .king;
        self.updatePieceZobrist(turn, Piece{ .sq = rook_from_square, .tp = .rook });
        self.updatePieceZobrist(turn, Piece{ .sq = rook_destination, .tp = .rook });
        self.updatePieceZobrist(turn, Piece{ .sq = from, .tp = .king });
        self.updatePieceZobrist(turn, Piece{ .sq = king_destination, .tp = .king });
        self.updateCastlingZobrist();
        self.castling_rights &= ~if (turn == .white) white_kingside_castle | white_queenside_castle else black_kingside_castle | black_queenside_castle;
        self.updateCastlingZobrist();
    } else {
        const from_type = self.mailbox[from.toInt()].?;
        if (from_type == .pawn and update_bb & pawn_double_move_mask == update_bb) {
            self.en_passant_target = to.move(if (turn == .white) -1 else 1, 0);
            self.updateEnPassantZobrist();
        }
        const to_type = if (move.getPromotedPieceType()) |pt| pt else from_type;
        self.mailbox[from.toInt()] = null;
        self.mailbox[to.toInt()] = to_type;
        us.getBoardPtr(from_type).* ^= from.toBitboard();
        us.getBoardPtr(to_type).* ^= to.toBitboard();
        self.updatePieceZobrist(turn, Piece{ .sq = from, .tp = from_type });
        self.updatePieceZobrist(turn, Piece{ .sq = to, .tp = to_type });

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
                self.updateCastlingZobrist();
                self.castling_rights &= ~if (turn == .white) white_kingside_castle else black_kingside_castle;
                self.updateCastlingZobrist();
            }
            if (from == queenside_rook_starting_square) {
                self.updateCastlingZobrist();
                self.castling_rights &= ~if (turn == .white) white_queenside_castle else black_queenside_castle;
                self.updateCastlingZobrist();
            }
        }

        if (from_type == .king) {
            self.updateCastlingZobrist();
            self.castling_rights &= ~if (turn == .white) white_kingside_castle | white_queenside_castle else black_kingside_castle | black_queenside_castle;
            self.updateCastlingZobrist();
        }

        if (from_type == .pawn)
            self.halfmove_clock = 0;
    }
    return inverse;
}

pub fn playNullMove(self: *Self) ?Square {
    self.fullmove_clock += @intFromBool(self.turn == .black);
    self.turn = self.turn.flipped();
    self.updateTurnZobrist();
    const res = self.en_passant_target;
    self.updateEnPassantZobrist();
    self.en_passant_target = null;
    return res;
}

pub fn undoNullMove(self: *Self, en_passant_target: ?Square) void {
    self.en_passant_target = en_passant_target;
    self.updateEnPassantZobrist();
    self.turn = self.turn.flipped();
    self.fullmove_clock -= @intFromBool(self.turn == .black);
    self.updateTurnZobrist();
}

pub fn playMoveCopy(self: Self, comptime turn: Side, move: Move) Board {
    var res = self;
    _ = res.playMove(turn, move);
    return res;
}

pub fn undoMove(self: *Self, comptime turn: Side, inverse: MoveInverse) void {
    const us = self.getSidePtr(turn);
    const them = self.getSidePtr(turn.flipped());
    const move = inverse.move;
    const from = move.getFrom();
    const to = move.getTo();

    const update_bb = from.toBitboard() | to.toBitboard();
    us.all ^= update_bb;

    self.en_passant_target = null;
    if (move.isCapture()) {
        if (move.isEnPassant()) {
            const pawn_d_rank: i8 = if (turn == .white) 1 else -1;
            const ep_pawn_square = to.move(-pawn_d_rank, 0);

            const ep_pawn_bb = ep_pawn_square.toBitboard();

            them.all ^= ep_pawn_bb;
            them.getBoardPtr(.pawn).* ^= ep_pawn_bb;
            us.getBoardPtr(.pawn).* ^= update_bb;
            self.mailbox[from.toInt()] = .pawn;
            self.mailbox[ep_pawn_square.toInt()] = .pawn;
            self.mailbox[to.toInt()] = null;
        } else {
            const captured_type = inverse.captured.?.tp;

            const to_type = self.mailbox[to.toInt()].?;
            const from_type = if (move.isPromotion()) .pawn else to_type;
            self.mailbox[from.toInt()] = from_type;
            self.mailbox[to.toInt()] = captured_type;
            them.getBoardPtr(captured_type).* ^= to.toBitboard();
            them.all ^= to.toBitboard();
            us.getBoardPtr(from_type).* ^= from.toBitboard();
            us.getBoardPtr(to_type).* ^= to.toBitboard();
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
            self.mailbox[rook_destination.toInt()] = null;
            self.mailbox[king_destination.toInt()] = null;
            self.mailbox[rook_from_square.toInt()] = .rook;
            self.mailbox[from.toInt()] = .king;
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
            self.mailbox[rook_destination.toInt()] = null;
            self.mailbox[king_destination.toInt()] = null;
            self.mailbox[rook_from_square.toInt()] = .rook;
            self.mailbox[from.toInt()] = .king;
        }
    } else {
        const to_type = self.mailbox[to.toInt()].?;
        const from_type = if (move.isPromotion()) .pawn else to_type;
        self.mailbox[from.toInt()] = from_type;
        self.mailbox[to.toInt()] = null;
        us.getBoardPtr(from_type).* ^= from.toBitboard();
        us.getBoardPtr(to_type).* ^= to.toBitboard();
    }
    self.turn = turn;
    self.fullmove_clock -= @intFromBool(self.turn == .black);
    self.castling_rights = inverse.castling;
    self.en_passant_target = inverse.en_passant;
    self.halfmove_clock = inverse.halfmove;
    self.zobrist = inverse.zobrist;
    self.pawn_zobrist = inverse.pawn_zobrist;
}

pub fn updatePieceZobrist(self: *Self, comptime side: Side, piece: Piece) void {
    self.zobrist ^= Zobrist.get(piece, side);
    const mask: u64 = @intFromBool(piece.tp == .pawn);
    self.pawn_zobrist ^= -%mask & Zobrist.get(piece, side);
}

pub fn updateCastlingZobrist(self: *Self) void {
    self.zobrist ^= Zobrist.getCastling(self.castling_rights);
}

pub fn updateEnPassantZobrist(self: *Self) void {
    if (self.en_passant_target) |ep|
        self.zobrist ^= Zobrist.getEnPassant(ep.toInt());
}

pub fn updateTurnZobrist(self: *Self) void {
    self.zobrist ^= Zobrist.getTurn();
}

pub fn resetZobrist(self: *Self) void {
    self.zobrist = 0;
    for (self.white.raw, PieceType.all) |bb, pt| {
        var iter = Bitboard.iterator(bb);
        while (iter.next()) |sq| {
            self.updatePieceZobrist(.white, Piece{ .sq = sq, .tp = pt });
        }
    }
    for (self.black.raw, PieceType.all) |bb, pt| {
        var iter = Bitboard.iterator(bb);
        while (iter.next()) |sq| {
            self.updatePieceZobrist(.black, Piece{ .sq = sq, .tp = pt });
        }
    }
    if (self.turn == .black) self.updateTurnZobrist();
    self.updateCastlingZobrist();
    self.updateEnPassantZobrist();
}

pub fn playMoveFromStr(self: *Self, str: []const u8) !MoveInverse {
    var buf: [256]Move = undefined;
    const num_moves = movegen.getMovesWithoutTurn(self.*, &buf);

    for (buf[0..num_moves]) |move| {
        if (move.isSameAsStr(str, false)) {
            return switch (self.turn) {
                inline else => |turn| self.playMove(turn, move),
            };
        }
    }
    for (buf[0..num_moves]) |move| {
        if (move.isSameAsStr(str, true)) {
            return switch (self.turn) {
                inline else => |turn| self.playMove(turn, move),
            };
        }
    }
    std.debug.print("moves: {any}\n", .{buf[0..num_moves]});
    return error.MoveNotFound;
}

pub fn filterEP(self: *Self) void {
    if (self.en_passant_target != null and !@import("pawn_moves.zig").hasEP(self.*)) {
        self.updateEnPassantZobrist();
        self.en_passant_target = null;
    }
}

pub fn perftSingleThreadedNonBulk(self: *Self, move_buf: []Move, depth: usize, comptime debug: bool) u64 {
    const impl = struct {
        fn impl(board: *Board, comptime turn: Side, cur_depth: u8, moves: []Move, d: usize) u64 {
            if (d == 0) return 1;
            const num_moves = movegen.getMoves(turn, board.*, moves);
            var res: u64 = 0;
            for (moves[0..num_moves]) |move| {
                const inv = board.playMove(turn, move);
                const count = impl(board, turn.flipped(), cur_depth + 1, moves[num_moves..], d - 1);
                if (cur_depth == 0) {
                    if (debug) {
                        std.debug.print("{}: {}\n", .{ move, count });
                    }
                    // std.debug.print("{}\n", .{ new_board });
                }
                res += count;
                board.undoMove(turn, inv);
            }
            return res;
        }
    }.impl;
    return switch (self.turn) {
        inline else => |turn| impl(self, turn, 0, move_buf, depth),
    };
}

pub fn perftSingleThreadedNonBulkCopyMake(self: *Self, move_buf: []Move, depth: usize, comptime debug: bool) u64 {
    const impl = struct {
        fn impl(board: Board, comptime turn: Side, cur_depth: u8, moves: []Move, d: usize) u64 {
            if (d == 0) return 1;
            const num_moves = movegen.getMoves(turn, board, moves);
            var res: u64 = 0;
            for (moves[0..num_moves]) |move| {
                var new_board = board;
                _ = new_board.playMove(turn, move);
                const count = impl(new_board, turn.flipped(), cur_depth + 1, moves[num_moves..], d - 1);
                if (cur_depth == 0) {
                    if (debug) {
                        std.debug.print("{}: {}\n", .{ move, count });
                    }
                    // std.debug.print("{}\n", .{ new_board });
                }
                res += count;
            }
            return res;
        }
    }.impl;
    return switch (self.turn) {
        inline else => |turn| impl(self.*, turn, 0, move_buf, depth),
    };
}

pub fn perftSingleThreadedNonBulkWriteHashes(self: *Self, move_buf: []Move, depth: usize, hash_list: *std.ArrayList(u64)) !void {
    const impl = struct {
        fn impl(board: *Board, comptime turn: Side, cur_depth: u8, moves: []Move, hashes: *std.ArrayList(u64), d: usize) anyerror!void {
            if (d == 0) {
                board.filterEP();
                try hashes.append(board.zobrist);
                return;
            }
            const num_moves = movegen.getMoves(turn, board.*, moves);
            for (moves[0..num_moves]) |move| {
                const inv = board.playMove(turn, move);
                try impl(board, turn.flipped(), cur_depth + 1, moves[num_moves..], hashes, d - 1);
                board.undoMove(turn, inv);
            }
        }
    }.impl;
    return switch (self.turn) {
        inline else => |turn| try impl(self, turn, 0, move_buf, hash_list, depth),
    };
}

pub const pawn_material_idx: usize = (20 + 1) * (20 + 1) * (20 + 1) * (18 + 1);
pub const knight_material_idx: usize = (20 + 1) * (20 + 1) * (18 + 1);
pub const bishop_material_idx: usize = (20 + 1) * (18 + 1);
pub const rook_material_idx: usize = (18 + 1);
pub const queen_material_idx: usize = 1;

pub const max_material_index = (16 + 1) * (20 + 1) * (20 + 1) * (20 + 1) * (18 + 1);

pub fn perftSingleThreadedNonBulkWriteHashesByMaterial(self: *Self, move_buf: []Move, depth: usize, hash_lists: []std.ArrayList(u64)) !void {
    const impl = struct {
        fn impl(board: *Board, comptime turn: Side, cur_depth: u8, moves: []Move, hashes: []std.ArrayList(u64), d: usize, material_idx: usize) anyerror!void {
            if (d == 0) {
                board.filterEP();
                try hashes[material_idx].append(board.zobrist);
                return;
            }
            const num_moves = movegen.getMoves(turn, board.*, moves);
            for (moves[0..num_moves]) |move| {
                var new_material_idx = material_idx;
                if (move.getPromotedPieceType()) |pt| {
                    new_material_idx -= pawn_material_idx;
                    new_material_idx += switch (pt) {
                        .knight => knight_material_idx,
                        .bishop => bishop_material_idx,
                        .rook => rook_material_idx,
                        .queen => rook_material_idx,
                        else => unreachable,
                    };
                }
                if (move.isCapture()) {
                    if (move.isEnPassant()) {
                        new_material_idx -= pawn_material_idx;
                    } else {
                        new_material_idx -= switch (board.mailbox[move.getTo().toInt()].?) {
                            .pawn => pawn_material_idx,
                            .knight => knight_material_idx,
                            .bishop => bishop_material_idx,
                            .rook => rook_material_idx,
                            .queen => rook_material_idx,
                            else => unreachable,
                        };
                    }
                }
                const inv = board.playMove(turn, move);
                try impl(board, turn.flipped(), cur_depth + 1, moves[num_moves..], hashes, d - 1, new_material_idx);
                board.undoMove(turn, inv);
            }
        }
    }.impl;
    var material_idx: usize = 0;
    material_idx += pawn_material_idx * @popCount(self.white.getBoard(.pawn) | self.black.getBoard(.pawn));
    material_idx += knight_material_idx * @popCount(self.white.getBoard(.knight) | self.black.getBoard(.knight));
    material_idx += bishop_material_idx * @popCount(self.white.getBoard(.bishop) | self.black.getBoard(.bishop));
    material_idx += rook_material_idx * @popCount(self.white.getBoard(.rook) | self.black.getBoard(.rook));
    material_idx += queen_material_idx * @popCount(self.white.getBoard(.queen) | self.black.getBoard(.queen));

    return switch (self.turn) {
        inline else => |turn| try impl(self, turn, 0, move_buf, hash_lists, depth, material_idx),
    };
}

pub const PerftTTEntry = struct {
    hash: u64,
    count: u56,
    depth: u8,
};
pub fn perftSingleThreadedTT(self: *Self, move_buf: []Move, depth: usize, transposition_table: []PerftTTEntry, comptime debug: bool) u64 {
    const impl = struct {
        fn impl(board: *Board, comptime turn: Side, cur_depth: u8, moves: []Move, d: usize, tt: []PerftTTEntry) u64 {
            if (d == 0) return 1;
            if (d == 1) {
                if (cur_depth == 0) {
                    const num_moves = movegen.getMoves(turn, board.*, moves);
                    for (moves[0..num_moves]) |move| {
                        if (debug) {
                            std.debug.print("{}: 1\n", .{move});
                        }
                    }
                }
                return movegen.countMoves(turn, board.*);
            }
            const tt_entry = tt[@intCast(board.zobrist & tt.len - 1)];
            if (tt_entry.depth == d and tt_entry.hash == board.zobrist) {
                return tt_entry.count;
            }
            const num_moves = movegen.getMoves(turn, board.*, moves);
            var res: u64 = 0;
            for (moves[0..num_moves]) |move| {
                if (@import("builtin").is_test) {
                    var cp = board.*;
                    const inv = cp.playMove(turn, move);
                    cp.undoMove(turn, inv);
                    assert(std.meta.eql(cp, board.*));
                }
                const inv = board.playMove(turn, move);
                const count = impl(board, turn.flipped(), cur_depth + 1, moves[num_moves..], d - 1, tt);
                if (cur_depth == 0) {
                    if (debug) {
                        std.debug.print("{}: {}\n", .{ move, count });
                    }
                    // std.debug.print("{}\n", .{ new_board });
                }
                res += count;
                board.undoMove(turn, inv);
            }
            tt[@intCast(board.zobrist & tt.len - 1)] = PerftTTEntry{
                .hash = board.zobrist,
                .count = @intCast(res),
                .depth = @intCast(d),
            };
            return res;
        }
    }.impl;
    return switch (self.turn) {
        inline else => |turn| impl(self, turn, 0, move_buf, depth, transposition_table),
    };
}

pub fn perftSingleThreaded(self: *Self, move_buf: []Move, depth: usize, comptime debug: bool) u64 {
    const impl = struct {
        fn impl(board: *Board, comptime turn: Side, cur_depth: u8, moves: []Move, d: usize) u64 {
            if (d == 0) return 1;
            if (d == 1) {
                if (cur_depth == 0) {
                    const num_moves = movegen.getMoves(turn, board.*, moves);
                    for (moves[0..num_moves]) |move| {
                        if (debug) {
                            std.debug.print("{}: 1\n", .{move});
                        }
                    }
                }
                return movegen.countMoves(turn, board.*);
            }
            const num_moves = movegen.getMoves(turn, board.*, moves);
            var res: u64 = 0;
            for (moves[0..num_moves]) |move| {
                if (@import("builtin").is_test) {
                    var cp = board.*;
                    const inv = cp.playMove(turn, move);
                    cp.undoMove(turn, inv);
                    assert(std.meta.eql(cp, board.*));
                }
                const inv = board.playMove(turn, move);
                const count = impl(board, turn.flipped(), cur_depth + 1, moves[num_moves..], d - 1);
                if (cur_depth == 0) {
                    if (debug) {
                        std.debug.print("{}: {}\n", .{ move, count });
                    }
                    // std.debug.print("{}\n", .{ new_board });
                }
                res += count;
                board.undoMove(turn, inv);
            }
            return res;
        }
    }.impl;
    return switch (self.turn) {
        inline else => |turn| impl(self, turn, 0, move_buf, depth),
    };
}

pub fn perftZobrist(self: *Self, move_buf: []Move, hashes: []struct { u64, u64 }, depth: usize) !void {
    const impl = struct {
        fn impl(board: *Board, comptime turn: Side, moves: []Move, h: []struct { u64, u64 }, d: usize) error{ZobristCollision}!void {
            // this makes the tests take way too long
            // const before = board.zobrist;
            // board.resetZobrist();
            // std.testing.expect(before == board.zobrist) catch return error.ZobristCollision;

            var hasher = std.hash.Crc32.init();
            hasher.update(std.mem.asBytes(&board.mailbox));
            hasher.update(std.mem.asBytes(&board.castling_rights));
            hasher.update(std.mem.asBytes(&board.en_passant_target));
            hasher.update(std.mem.asBytes(&board.white));
            hasher.update(std.mem.asBytes(&board.black));
            const first = board.zobrist;
            const second = hasher.final();
            const table_first, const table_second = h[@intCast(@as(u128, first) * h.len >> 64)];
            if (first == table_first and second != table_second) {
                return error.ZobristCollision;
            }
            h[@intCast(@as(u128, first) * h.len >> 64)] = .{ first, second };

            if (d == 0) return;
            const num_moves = movegen.getMoves(turn, board.*, moves);
            for (moves[0..num_moves]) |move| {
                const inv = board.playMove(turn, move);
                impl(board, turn.flipped(), moves[num_moves..], h, d - 1) catch |e| {
                    std.debug.print("{}\n", .{move});
                    return e;
                };
                board.undoMove(turn, inv);
            }
        }
    }.impl;
    return switch (self.turn) {
        inline else => |turn| try impl(
            self,
            turn,
            move_buf,
            hashes,
            depth,
        ),
    };
}

pub fn perftNNUE(self: *Self, move_buf: []Move, depth: usize) u64 {
    const nnue = @import("nnue.zig");
    const impl = struct {
        fn impl(board: *Board, comptime turn: Side, eval_state: nnue.EvalState, cur_depth: u8, moves: []Move, d: usize) u64 {
            if (d == 0) return 1;

            const num_moves = movegen.getMoves(turn, board.*, moves);
            var res: u64 = 0;
            for (moves[0..num_moves]) |move| {
                // std.debug.print("--------------\n", .{});
                const updated_eval_state = eval_state.updateWith(turn, board, move);
                const inv = board.playMove(turn, move);
                const from_scratch = nnue.EvalState.init(board);
                const white_correct = std.meta.eql(from_scratch.white, updated_eval_state.white);
                const black_correct = std.meta.eql(from_scratch.black, updated_eval_state.black);
                std.testing.expectEqualDeep(from_scratch, updated_eval_state) catch |e| std.debug.panic("{} {} {}\n", .{ white_correct, black_correct, e });
                const count = impl(
                    board,
                    turn.flipped(),
                    updated_eval_state,
                    cur_depth + 1,
                    moves[num_moves..],
                    d - 1,
                );
                res += count;
                board.undoMove(turn, inv);
            }
            return res;
        }
    }.impl;
    return switch (self.turn) {
        inline else => |turn| impl(self, turn, nnue.EvalState.init(self), 0, move_buf, depth),
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

test "quiet move increments halfmove" {
    var board = Board.init();
    const before = board.halfmove_clock;
    _ = try board.playMoveFromStr("b1c3");
    try std.testing.expectEqual(before + 1, board.halfmove_clock);
}

test "pawn move resets halfmove" {
    var board = Board.init();
    const before = board.halfmove_clock;
    _ = try board.playMoveFromStr("b1c3");
    try std.testing.expectEqual(before + 1, board.halfmove_clock);
    _ = try board.playMoveFromStr("e7e5");
    const after = board.halfmove_clock;
    try std.testing.expectEqual(0, after);
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
