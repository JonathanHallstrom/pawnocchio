// Pawnocchio, UCI chess engine
// Copyright (C) 2025 Jonathan Hallström
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const assert = std.debug.assert;

const root = @import("root.zig");
const Colour = root.Colour;
const File = root.File;
const Rank = root.Rank;
const Square = root.Square;
const Bitboard = root.Bitboard;
const PieceType = root.PieceType;
const ColouredPieceType = root.ColouredPieceType;
const Move = root.Move;
const movegen = root.movegen;
const Board = @This();

const white_kingside_castle: u8 = 1;
const black_kingside_castle: u8 = 2;
const white_queenside_castle: u8 = 4;
const black_queenside_castle: u8 = 8;

white: u64 = 0,
black: u64 = 0,
pieces: [6]u64 = .{0} ** 6,
mailbox: [64]?ColouredPieceType = .{null} ** 64,
halfmove: u8 = 0,
fullmove: u32 = 1,
plies: u32 = 0,
frc: bool = false,
ep_target: ?Square = null,
stm: Colour = .white,

hash: u64 = 0,

castling_rights: u8 = 0,
white_kingside_rook_file: File = .h,
black_kingside_rook_file: File = .h,
white_queenside_rook_file: File = .a,
black_queenside_rook_file: File = .a,

pinned: [2]u64 = .{0} ** 2,
pinner: [2]u64 = .{0} ** 2,
checkers: u64 = 0,

pub inline fn occupancyFor(self: Board, col: Colour) u64 {
    return if (col == .white) self.white else self.black;
}

inline fn occupancyPtrFor(self: *Board, col: Colour) *u64 {
    return if (col == .white) &self.white else &self.black;
}

pub inline fn occupancy(self: Board) u64 {
    return self.white | self.black;
}

pub inline fn pawnsFor(self: Board, col: Colour) u64 {
    return self.pieces[0] & self.occupancyFor(col);
}

pub inline fn knightsFor(self: Board, col: Colour) u64 {
    return self.pieces[1] & self.occupancyFor(col);
}

pub inline fn bishopsFor(self: Board, col: Colour) u64 {
    return self.pieces[2] & self.occupancyFor(col);
}

pub inline fn rooksFor(self: Board, col: Colour) u64 {
    return self.pieces[3] & self.occupancyFor(col);
}

pub inline fn queensFor(self: Board, col: Colour) u64 {
    return self.pieces[4] & self.occupancyFor(col);
}

pub inline fn kingFor(self: Board, col: Colour) u64 {
    return self.pieces[5] & self.occupancyFor(col);
}

pub inline fn pawns(self: Board) u64 {
    return self.pieces[0];
}

pub inline fn knights(self: Board) u64 {
    return self.pieces[1];
}

pub inline fn bishops(self: Board) u64 {
    return self.pieces[2];
}

pub inline fn rooks(self: Board) u64 {
    return self.pieces[3];
}

pub inline fn queens(self: Board) u64 {
    return self.pieces[4];
}

pub inline fn king(self: Board) u64 {
    return self.pieces[5];
}

pub inline fn kingsideCastlingFor(self: Board, col: Colour) bool {
    if (col == .white) {
        return self.castling_rights & white_kingside_castle != 0;
    } else {
        return self.castling_rights & black_kingside_castle != 0;
    }
}

pub inline fn queensideCastlingFor(self: Board, col: Colour) bool {
    if (col == .white) {
        return self.castling_rights & white_queenside_castle != 0;
    } else {
        return self.castling_rights & black_queenside_castle != 0;
    }
}

pub inline fn kingsideRookFileFor(self: Board, col: Colour) File {
    if (col == .white) {
        return self.white_kingside_rook_file;
    } else {
        return self.black_kingside_rook_file;
    }
}

pub inline fn queensideRookFileFor(self: Board, col: Colour) File {
    if (col == .white) {
        return self.white_queenside_rook_file;
    } else {
        return self.black_queenside_rook_file;
    }
}

pub inline fn startingRankFor(_: Board, col: Colour) Rank {
    return if (col == .white) .first else .eighth;
}

pub inline fn castlingUpdateFor(self: Board, sq: Square, col: Colour) u8 {
    const queenside_rook_sq = Square.fromRankFile(self.startingRankFor(col), self.queensideRookFileFor(col));
    const kingside_rook_sq = Square.fromRankFile(self.startingRankFor(col), self.kingsideRookFileFor(col));

    var kingside_rook_mask: u8 = @intFromBool(sq == kingside_rook_sq);
    kingside_rook_mask <<= @intCast(col.toInt());

    var queenside_rook_mask: u8 = @intFromBool(sq == queenside_rook_sq);
    queenside_rook_mask <<= @intCast(col.toInt() + 2);

    return ~(kingside_rook_mask | queenside_rook_mask);
}

pub fn parseFen(fen: []const u8, permissive: bool) !Board {
    if (std.ascii.eqlIgnoreCase(fen, "startpos")) return startpos();
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
    var self: Board = .{};
    for (0..8) |r| {
        var c: usize = 0;
        for (ranks[7 - r]) |ch| {
            if (c >= 8) return error.TooManyPiecesOnRank;
            const current_square = Square.fromInt(@intCast(8 * r + c));
            const cpt = ColouredPieceType.fromAsciiLetter(ch);
            self.mailbox[8 * r + c] = cpt;
            if (std.ascii.isLower(ch)) {
                self.black |= current_square.toBitboard();
                self.pieces[cpt.?.toPieceType().toInt()] |= current_square.toBitboard();
                if (ch == 'k') black_king_square = current_square;
                if (ch == 'r' and current_square.getRank() == .eighth) black_rooks_on_last_rank.append(current_square.getFile()) catch return error.TooManyRooks;
                c += 1;
            } else if (std.ascii.isUpper(ch)) {
                self.white |= current_square.toBitboard();
                self.pieces[cpt.?.toPieceType().toInt()] |= current_square.toBitboard();
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
        self.stm = .white;
    } else if (std.ascii.toLower(turn_str[0]) == 'b') {
        self.stm = .black;
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
            self.castling_rights |= switch (castle_ch) {
                'K' => white_kingside_castle,
                'k' => black_kingside_castle,
                'Q' => white_queenside_castle,
                'q' => black_queenside_castle,
                else => blk: {
                    const file = File.parse(castle_ch) catch return error.InvalidCharacter;
                    const king_square, const kingside_castle, const queenside_castle, const rook_array = if (std.ascii.isUpper(castle_ch)) .{
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

                    if (!permissive and std.mem.count(File, rook_array.slice(), &.{file}) == 0)
                        return error.NoRookForCastling;

                    if (@intFromEnum(file) > @intFromEnum(king_square.getFile())) {
                        if (self.stm == .white) {
                            white_kingside_file = file;
                        } else {
                            black_kingside_file = file;
                        }
                        break :blk kingside_castle;
                    }
                    if (@intFromEnum(file) < @intFromEnum(king_square.getFile())) {
                        if (self.stm == .white) {
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
        if (self.castling_rights & white_queenside_castle != 0 and white_queenside_file == null) {
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
        if (self.castling_rights & white_kingside_castle != 0 and white_kingside_file == null) {
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

        if (self.castling_rights & black_queenside_castle != 0 and black_queenside_file == null) {
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
        if (self.castling_rights & black_kingside_castle != 0 and black_kingside_file == null) {
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
        self.white_kingside_rook_file = white_kingside_file orelse white_king_square.?.getFile();
        self.white_queenside_rook_file = white_queenside_file orelse white_king_square.?.getFile();
        self.black_kingside_rook_file = black_kingside_file orelse black_king_square.?.getFile();
        self.black_queenside_rook_file = black_queenside_file orelse black_king_square.?.getFile();
    }

    const ep_target_square_string = iter.next() orelse return error.MissingEnPassantTarget;
    if (std.mem.eql(u8, ep_target_square_string, "-")) {
        self.ep_target = null;
    } else {
        const correct_rank: u8 = if (self.stm == .white) '6' else '3';
        const EPError = error{ InvalidEnPassantTarget, EnPassantTargetDoesntExist, EnPassantCantBeCaptured };
        var err_opt: ?EPError = null;
        if (ep_target_square_string.len != 2 or
            ep_target_square_string[1] != correct_rank)
            err_opt = err_opt orelse error.InvalidEnPassantTarget;

        const en_passant_bitboard = (try Square.parse(ep_target_square_string)).toBitboard();
        const pawn_d_rank: i8 = if (self.stm == .white) 1 else -1;
        const us_pawns = self.pawnsFor(self.stm);
        const them_pawns = self.pawnsFor(self.stm.flipped());

        if (!permissive and en_passant_bitboard & Bitboard.move(them_pawns, pawn_d_rank, 0) == 0)
            err_opt = err_opt orelse error.EnPassantTargetDoesntExist;
        if (!permissive and en_passant_bitboard & (Bitboard.move(us_pawns, pawn_d_rank, 1) | Bitboard.move(us_pawns, pawn_d_rank, -1)) == 0)
            err_opt = err_opt orelse error.EnPassantCantBeCaptured;
        if (err_opt) |err| {
            if (permissive) {
                self.ep_target = null;
            } else {
                return err;
            }
        } else {
            self.ep_target = Square.fromBitboard(en_passant_bitboard);
        }
    }

    const halfmove_clock_string = iter.next() orelse "0";
    self.halfmove = try std.fmt.parseInt(u8, halfmove_clock_string, 10);
    const fullmove_clock_str = iter.next() orelse "1";
    const fullmove = try std.fmt.parseInt(u32, fullmove_clock_str, 10);
    if (!permissive and fullmove == 0)
        return error.InvalidFullMove;
    self.plies = fullmove * 2 + self.stm.toInt();
    self.resetHash();
    self.updateMasks(self.stm);

    return self;
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
                var char = pt.toAsciiLetter();
                if (self.white & sq.toBitboard() != 0) {
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
    out.appendAssumeCapacity(if (self.stm == .white) 'w' else 'b');
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
    if (self.ep_target) |ep_target| {
        var valid = false;
        switch (self.stm) {
            inline else => |stm_comptime| {
                var rec = movegen.MoveListReceiver{};
                movegen.generateAllNoisies(stm_comptime, &self, &rec);

                for (rec.vals.slice()) |move| {
                    if (self.isEnPassant(move) and self.isLegal(stm_comptime, move)) {
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
    out.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{self.halfmove}) catch unreachable);
    out.appendAssumeCapacity(' ');
    out.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{self.fullmove}) catch unreachable);

    return out;
}

pub fn startpos() Board {
    return frcPosition(518);
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

pub fn dfrcPosition(n: u20) Board {
    const white_rank = frcBackrank(n % 960);
    const black_rank = frcBackrank(n / 960);

    var res: Board = .{};
    var white_rook = false;
    var black_rook = false;
    inline for (0..8) |c| {
        res.mailbox[c] = ColouredPieceType.fromPieceType(white_rank[c], .white);
        res.mailbox[8 + c] = ColouredPieceType.fromPieceType(.pawn, .white);
        res.white |= Square.fromInt(c).toBitboard();
        res.white |= Square.fromInt(8 + c).toBitboard();
        res.pieces[white_rank[c].toInt()] |= Square.fromInt(c).toBitboard();
        res.pieces[PieceType.pawn.toInt()] |= Square.fromInt(8 + c).toBitboard();
        if (white_rank[c] == .rook) {
            if (white_rook) {
                res.white_kingside_rook_file = File.fromInt(c);
            } else {
                res.white_queenside_rook_file = File.fromInt(c);
            }
            white_rook = true;
        }
        res.mailbox[56 + c] = ColouredPieceType.fromPieceType(black_rank[c], .black);
        res.mailbox[48 + c] = ColouredPieceType.fromPieceType(.pawn, .black);
        res.black |= Square.fromInt(56 + c).toBitboard();
        res.black |= Square.fromInt(48 + c).toBitboard();

        res.pieces[black_rank[c].toInt()] |= Square.fromInt(56 + c).toBitboard();
        res.pieces[PieceType.pawn.toInt()] |= Square.fromInt(48 + c).toBitboard();

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
    res.halfmove = 0;
    res.fullmove = 1;
    res.stm = .white;
    res.resetHash();
    res.updateMasks(.white);
    return res;
}

pub fn frcPosition(n: u10) Board {
    assert(n < 960);
    return dfrcPosition(@as(u20, n) * 960 + n);
}

pub fn frcPositionComptime(comptime n: u10) if (n < 960) Board else @compileError("there are only 960 positions in frc") {
    return frcPosition(n);
}

pub fn updatePieceHash(self: *Board, comptime stm: Colour, pt: PieceType, sq: Square) void {
    self.hash ^= root.zobrist.piece(stm, pt, sq);
}

pub fn updateCastlingHash(self: *Board) void {
    self.hash ^= root.zobrist.castling(self.castling_rights);
}

pub fn updateTurnHash(self: *Board) void {
    self.hash ^= root.zobrist.turn();
}

pub fn updateEPHash(self: *Board) void {
    if (self.ep_target) |target|
        self.hash ^= root.zobrist.ep(target);
}

pub fn getHash(self: *Board) u64 {
    return self.hash ^ root.zobrist.halfmove(self.halfmove);
}

pub inline fn isEnPassant(_: Board, move: Move) bool {
    return move.flag() == Move.ep_flag;
}

pub inline fn isCastling(_: Board, move: Move) bool {
    return move.flag() == Move.castling_flag;
}

pub inline fn isPromo(_: Board, move: Move) bool {
    return move.flag() & Move.promotion_flag == Move.promotion_flag;
}

pub inline fn isCapture(self: Board, move: Move) bool {
    return self.isEnPassant(move) or !self.isCastling(move) and (&self.mailbox)[move.to().toInt()] != null;
}

pub inline fn isNoisy(self: Board, move: Move) bool {
    return self.isCapture(move) or (self.isPromo(move) and move.promoType() == .queen);
}

pub inline fn isQuiet(self: Board, move: Move) bool {
    return !self.isNoisy(move);
}

pub inline fn getCapturedType(self: Board, move: Move) ?PieceType {
    if (self.isEnPassant(move)) {
        return .pawn;
    }
    if (self.mailbox[move.to().toInt()]) |cpt| {
        return cpt.toPieceType();
    }
    return null;
}

pub inline fn kingsideKingDestFor(self: Board, col: Colour) Square {
    return Square.fromRankFile(self.startingRankFor(col), File.g);
}

pub inline fn queensideKingDestFor(self: Board, col: Colour) Square {
    return Square.fromRankFile(self.startingRankFor(col), File.c);
}

pub inline fn castlingKingDestFor(self: Board, move: Move, col: Colour) Square {
    if (move.from().toInt() < move.to().toInt()) {
        return self.kingsideKingDestFor(col);
    } else {
        return self.queensideKingDestFor(col);
    }
}

pub inline fn kingsideRookDestFor(self: Board, col: Colour) Square {
    return Square.fromRankFile(self.startingRankFor(col), File.f);
}

pub inline fn queensideRookDestFor(self: Board, col: Colour) Square {
    return Square.fromRankFile(self.startingRankFor(col), File.d);
}

pub inline fn castlingRookDestFor(self: Board, move: Move, col: Colour) Square {
    if (move.from().toInt() < move.to().toInt()) {
        return self.kingsideRookDestFor(col);
    } else {
        return self.queensideRookDestFor(col);
    }
}

pub fn addPiece(self: *Board, comptime col: Colour, pt: PieceType, sq: Square) void {
    const bb = sq.toBitboard();
    self.occupancyPtrFor(col).* |= bb;
    self.pieces[pt.toInt()] |= bb;
    self.hash ^= root.zobrist.piece(col, pt, sq);
    (&self.mailbox)[sq.toInt()] = ColouredPieceType.fromPieceType(pt, col);
}

pub fn removePiece(self: *Board, comptime col: Colour, pt: PieceType, sq: Square) void {
    const bb = sq.toBitboard();
    self.occupancyPtrFor(col).* ^= bb;
    self.pieces[pt.toInt()] ^= bb;
    self.hash ^= root.zobrist.piece(col, pt, sq);
    (&self.mailbox)[sq.toInt()] = null;
}

pub fn movePiece(self: *Board, comptime col: Colour, pt: PieceType, from: Square, to: Square) void {
    const bb = from.toBitboard() ^ to.toBitboard();
    self.occupancyPtrFor(col).* ^= bb;
    self.pieces[pt.toInt()] ^= bb;
    self.hash ^= root.zobrist.piece(col, pt, from) ^ root.zobrist.piece(col, pt, to);
    (&self.mailbox)[from.toInt()] = null;
    (&self.mailbox)[to.toInt()] = ColouredPieceType.fromPieceType(pt, col);
}

pub inline fn updatePins(self: *Board, comptime col: Colour) void {
    const occ = self.occupancy();
    const us_occ = self.occupancyFor(col);
    const king_bb = self.kingFor(col);
    const king_sq = Square.fromBitboard(king_bb);
    const king_as_rook_attacks = Bitboard.rookAttacks(king_sq);
    const king_as_bishop_attacks = Bitboard.bishopAttacks(king_sq.toInt());
    const rook_sliders = (self.rooks() | self.queens()) & self.occupancyFor(col.flipped());
    const bishop_sliders = (self.bishops() | self.queens()) & self.occupancyFor(col.flipped());
    var pinned: u64 = 0;
    var pinner: u64 = 0;
    for ([_]u64{
        king_as_rook_attacks & rook_sliders,
        king_as_bishop_attacks & bishop_sliders,
    }) |potential_pinners| {
        var iter = Bitboard.iterator(potential_pinners);
        while (iter.next()) |potential_pinner| {
            const ray_between = Bitboard.queenRayBetweenExclusive(king_sq, potential_pinner);
            const pieces_between = occ & ray_between;
            if (@popCount(pieces_between) == 1) {
                if (pieces_between & us_occ != 0) {
                    pinned |= pieces_between;
                    pinner |= potential_pinner.toBitboard();
                }
            }
        }
    }
    self.pinned[col.toInt()] = pinned;
    self.pinner[col.flipped().toInt()] = pinner;
}

pub fn updateMasks(self: *Board, col: Colour) void {
    self.updatePins(.white);
    self.updatePins(.black);
    self.checkers = switch (col) {
        inline else => |col_comptime| movegen.attackersFor(col_comptime.flipped(), self, Square.fromBitboard(self.kingFor(col)), self.occupancy()),
    };
}

pub fn resetHash(self: *Board) void {
    self.hash = 0;
    self.updateEPHash();
    self.updateCastlingHash();
    if (self.stm == .black)
        self.updateTurnHash();
    inline for (0..6) |p| {
        const pt = PieceType.fromInt(@intCast(p));
        var iter = Bitboard.iterator(self.pieces[p]);
        while (iter.next()) |sq| {
            self.hash ^= root.zobrist.piece((&self.mailbox)[sq.toInt()].?.toColour(), pt, sq);
        }
    }
}

fn resetHashDbg(self: *Board) !void {
    self.hash = 0;
    self.updateEPHash();
    self.updateCastlingHash();
    if (self.stm == .black)
        self.updateTurnHash();
    inline for (0..6) |p| {
        const pt = PieceType.fromInt(@intCast(p));
        var iter = Bitboard.iterator(self.pieces[p]);
        while (iter.next()) |sq| {
            if (self.mailbox[sq.toInt()] == null) {
                return error.Broken;
            }
            self.hash ^= root.zobrist.piece(self.mailbox[sq.toInt()].?.toColour(), pt, sq);
        }
    }
}

pub inline fn makeMove(self: *Board, comptime stm: Colour, move: Move) void {
    self.plies += 1;
    var updated_halfmove = self.halfmove + 1;
    var updated_castling_rights = self.castling_rights;
    self.updateEPHash();
    self.ep_target = null;

    switch (move.tp()) {
        .default => {
            const from = move.from();
            const to = move.to();
            const pt = (&self.mailbox)[from.toInt()].?.toPieceType();

            const cap_opt = (&self.mailbox)[to.toInt()];

            updated_castling_rights &= self.castlingUpdateFor(from, stm);
            if (cap_opt) |cap| {
                updated_halfmove = 0;
                updated_castling_rights &= self.castlingUpdateFor(to, stm.flipped());
                self.removePiece(stm.flipped(), cap.toPieceType(), to);
            }
            self.movePiece(stm, pt, from, to);

            if (pt == .pawn) {
                updated_halfmove = 0;
                const pawn_d_rank = if (stm == .white) 1 else -1;
                const from_double_pushed = from.move(2 * pawn_d_rank, 0);
                const target = from.move(pawn_d_rank, 0);
                if (from_double_pushed == to) {
                    if (Bitboard.pawnAttacks(target, stm) & self.pawnsFor(stm.flipped()) != 0) {
                        self.ep_target = target;
                        self.updateEPHash();
                    }
                }
            }
            if (pt == .king) {
                updated_castling_rights &= ~@as(u8, 0b101 << comptime stm.toInt());
            }
        },
        .ep => {
            const from = move.from();
            const to = move.to();
            updated_halfmove = 0;
            self.removePiece(stm.flipped(), .pawn, move.getEnPassantPawnSquare(stm));
            self.movePiece(stm, .pawn, from, to);
        },
        .castling => {
            const king_from = move.from();
            const king_to = self.castlingKingDestFor(move, stm);
            const rook_from = move.to();
            const rook_to = self.castlingRookDestFor(move, stm);
            updated_castling_rights &= ~@as(u8, 0b101 << comptime stm.toInt());
            self.removePiece(stm, .rook, rook_from); // cant be a movePiece due to FRC
            self.movePiece(stm, .king, king_from, king_to);
            self.addPiece(stm, .rook, rook_to);
        },
        .promotion => {
            const from = move.from();
            const to = move.to();
            const pt = (&self.mailbox)[from.toInt()].?.toPieceType();
            const cap_opt = (&self.mailbox)[to.toInt()];
            if (cap_opt) |cap| {
                updated_halfmove = 0;
                updated_castling_rights &= self.castlingUpdateFor(to, stm.flipped());
                self.removePiece(stm.flipped(), cap.toPieceType(), to);
            }
            self.removePiece(stm, pt, from);
            self.addPiece(stm, move.promoType(), to);
        },
    }
    if (updated_castling_rights != self.castling_rights) {
        self.hash ^= root.zobrist.castling(self.castling_rights ^ updated_castling_rights);
    }
    self.halfmove = updated_halfmove;
    self.castling_rights = updated_castling_rights;
    self.stm = stm.flipped();

    self.updateMasks(stm.flipped());
    self.updateTurnHash();
}

pub inline fn makeMoveFromStr(self: *Board, str: []const u8) !void {
    switch (self.stm) {
        inline else => |stm| {
            var rec: movegen.MoveListReceiver = .{};
            movegen.generateAllNoisies(stm, self, &rec);
            movegen.generateAllQuiets(stm, self, &rec);

            for (rec.vals.slice()) |move| {
                if (!self.isLegal(stm, move)) continue;

                if (std.mem.eql(u8, move.toString(self).slice(), str)) {
                    self.makeMove(stm, move);
                    return;
                }
            }
        },
    }
    return error.NoSuchMove;
}

fn isCastlingMoveLegal(self: *const Board, comptime stm: Colour, move: Move) bool {
    const rook_from = move.to();
    if (self.pinned[stm.toInt()] & rook_from.toBitboard() != 0) {
        return false;
    }
    const rook_to = self.castlingRookDestFor(move, stm);
    const king_from = move.from();
    const king_to = self.castlingKingDestFor(move, stm);
    const king_rook_bbs = rook_from.toBitboard() | king_from.toBitboard();

    const king_min = @min(king_from.toInt(), king_to.toInt());
    const king_max = @max(king_from.toInt(), king_to.toInt());

    const rook_min = @min(rook_from.toInt(), rook_to.toInt());
    const rook_max = @max(rook_from.toInt(), rook_to.toInt());

    const leftmost = @min(king_min, rook_min);
    const rightmost = @max(king_max, rook_max);

    const need_to_be_empty = Bitboard.queenRayBetweenInclusive(leftmost, rightmost);
    const occ_without_king_rook = self.occupancy() & ~king_rook_bbs;
    if (occ_without_king_rook & need_to_be_empty != 0) {
        return false;
    }
    const need_to_be_unattacked = king_to.toBitboard() | Bitboard.queenRayBetweenExclusive(king_from, king_to);
    var iter = Bitboard.iterator(need_to_be_unattacked);
    while (iter.next()) |sq| {
        const attackers = movegen.attackersFor(stm.flipped(), self, sq, occ_without_king_rook);
        // std.debug.print("attackers: {}\n", .{attackers});
        if (attackers != 0) {
            return false;
        }
    }
    return true;
}

pub fn isLegal(self: *const Board, comptime stm: Colour, move: Move) bool {
    const move_tp = move.tp();
    if (move_tp == .castling) {
        return self.isCastlingMoveLegal(stm, move);
    }
    const from = move.from();
    const to = move.to();
    const pt = (&self.mailbox)[from.toInt()].?;
    assert(pt.toColour() == stm);
    if (pt.toPieceType() == .king) {
        const attackers = movegen.attackersFor(stm.flipped(), self, to, self.occupancy() ^ from.toBitboard());
        return attackers == 0;
    }

    if (self.checkers == 0) {
        // pinned pieces
        if (Bitboard.extendingRayBb(from, to) & self.kingFor(stm) != 0) {
            return true;
        }
    }

    if (move_tp == .ep) {
        const pawn_d_rank = if (stm == .white) 1 else -1;
        const captured = to.move(-pawn_d_rank, 0);
        const occ_change = from.toBitboard() ^ to.toBitboard() ^ captured.toBitboard();

        const attackers = movegen.slidingAttackersFor(
            stm.flipped(),
            self,
            Square.fromBitboard(self.kingFor(stm)),
            self.occupancy() ^ occ_change,
        );
        return attackers == 0;
    }

    if (pt.toPieceType() == .pawn) {
        return self.pinned[stm.toInt()] & from.toBitboard() == 0;
    }

    return true;
}

fn perft_impl(self: *const Board, comptime is_root: bool, comptime stm: Colour, comptime quiet: bool, depth: i32) u64 {
    if (depth == 0) return 1;
    var movelist = movegen.MoveListReceiver{};
    movegen.generateAllNoisies(stm, self, &movelist);
    movegen.generateAllQuiets(stm, self, &movelist);
    var res: u64 = 0;
    if (depth == 1) {
        for (movelist.vals.slice()) |move| {
            const is_legal = self.isLegal(stm, move);
            res += @intFromBool(is_legal);
            if (is_root and is_legal and !quiet) {
                std.debug.print("{}: 1\n", .{move});
            }
        }
    } else {
        for (movelist.vals.slice()) |move| {
            if (!self.isLegal(stm, move)) continue;
            var cp = self.*;
            cp.makeMove(stm, move);
            // const before_reset = cp.hash;
            // cp.resetHashDbg() catch |e| {
            //     std.debug.print("{}\n", .{move});
            //     return e;
            // };
            // std.testing.expect(before_reset == cp.hash) catch |e| {
            //     std.debug.print("{}\n", .{move});
            //     return e;
            // };
            if (is_root and !quiet) {
                std.debug.print("{s} ", .{cp.toFen().slice()});
                std.debug.print("{s}: ", .{move.toString(self).slice()});
            }
            if (depth != 1) {}
            const count = cp.perft_impl(
                false,
                stm.flipped(),
                quiet,
                depth - 1,
            );
            res += count;
            if (is_root and !quiet) {
                std.debug.print("{}\n", .{count});
            }
        }
    }
    return res;
}

pub fn perft(
    self: Board,
    comptime quiet: bool,
    depth: i32,
) u64 {
    return switch (self.stm) {
        inline else => |stm_comptime| self.perft_impl(
            true,
            stm_comptime,
            quiet,
            depth,
        ),
    };
}

test "basic makemove" {
    var board = startpos();
    board.makeMove(.white, Move.quiet(.e2, .e4));
    try std.testing.expectEqual(board.mailbox[Square.e4.toInt()], ColouredPieceType.white_pawn);
    try std.testing.expectEqual(board.pawnsFor(.white) & Square.e4.toBitboard(), Square.e4.toBitboard());
    try std.testing.expectEqual(board.pawnsFor(.white) & Square.e2.toBitboard(), 0);
}
