// pawnocchio, UCI chess engine
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

const BoundedArray = root.BoundedArray;
const Colour = root.Colour;
const File = root.File;
const Rank = root.Rank;
const Square = root.Square;
const Bitboard = root.Bitboard;
const PieceType = root.PieceType;
const ColouredPieceType = root.ColouredPieceType;
const Move = root.Move;
const movegen = root.movegen;
const CastlingRights = root.CastlingRights;
const attacks = root.attacks;
const Board = @This();

bbs: [8]u64 = @splat(0),

mailbox: [64]u8 = @splat(MAILBOX_EMPTY),

halfmove: u8 = 0,
fullmove: u32 = 1,
plies: u32 = 0,
frc: bool = false,
ep_target: ?Square = null,
stm: Colour = .white,

hash: u64 = 0,
pawn_hash: u64 = 0,
major_hash: u64 = 0,
minor_hash: u64 = 0,
nonpawn_hash: [2]u64 = @splat(0),

castling_rights: CastlingRights = CastlingRights.init(),

pinned: [2]u64 = @splat(0),
// pinner: [2]u64 = @splat(0),
checkers: u64 = 0,
checking_squares: [5]u64 = @splat(0),
threats: [2]u64 = @splat(0),
threats_by: [2][PieceType.all.len]u64 = @splat(@splat(0)),
lesser_threats: [2]u64 = @splat(0),

pub inline fn white(self: *const Board) u64 {
    return (&self.bbs)[6];
}

pub inline fn black(self: *const Board) u64 {
    return (&self.bbs)[7];
}

pub fn whitePtr(self: *Board) *u64 {
    return &self.bbs[6];
}

pub fn blackPtr(self: *Board) *u64 {
    return &self.bbs[7];
}

pub inline fn pieceBB(self: *const Board, piece: PieceType) u64 {
    return (&self.bbs)[piece.toInt()];
}

pub inline fn pieceBBs(self: *const Board) *const [6]u64 {
    return @ptrCast(&self.bbs);
}

pub inline fn pieceBBsMut(self: *Board) *[6]u64 {
    return @ptrCast(&self.bbs);
}

pub inline fn occupancyFor(self: *const Board, col: Colour) u64 {
    return (&self.bbs)[6 + col.toInt()];
}

pub fn occupancyPtrFor(self: *Board, col: Colour) *u64 {
    return &(&self.bbs)[6 + col.toInt()];
}

pub inline fn occupancy(self: *const Board) u64 {
    return (&self.bbs)[6] | (&self.bbs)[7];
}

pub inline fn threatsFor(self: *const Board, col: Colour) u64 {
    return self.threats[col.toInt()];
}

pub inline fn threatsBy(self: *const Board, col: Colour, pt: PieceType) u64 {
    return self.threats_by[col.toInt()][pt.toInt()];
}

pub inline fn lesserThreatsFor(self: *const Board, col: Colour) u64 {
    return self.lesser_threats[col.toInt()];
}

pub inline fn pinnedFor(self: *const Board, col: Colour) u64 {
    return self.pinned[col.toInt()];
}

fn pinnedPtrFor(self: *Board, col: Colour) *u64 {
    return &self.pinned[col.toInt()];
}

pub inline fn checkingSquaresFor(self: *const Board, pt: PieceType) u64 {
    return self.checking_squares[pt.toInt()];
}

pub inline fn pawnsFor(self: *const Board, col: Colour) u64 {
    return self.pieceBB(.pawn) & self.occupancyFor(col);
}

pub inline fn knightsFor(self: *const Board, col: Colour) u64 {
    return self.pieceBB(.knight) & self.occupancyFor(col);
}

pub inline fn bishopsFor(self: *const Board, col: Colour) u64 {
    return self.pieceBB(.bishop) & self.occupancyFor(col);
}

pub inline fn rooksFor(self: *const Board, col: Colour) u64 {
    return self.pieceBB(.rook) & self.occupancyFor(col);
}

pub inline fn queensFor(self: *const Board, col: Colour) u64 {
    return self.pieceBB(.queen) & self.occupancyFor(col);
}

pub inline fn kingFor(self: *const Board, col: Colour) u64 {
    return self.pieceBB(.king) & self.occupancyFor(col);
}

pub inline fn pieceFor(self: *const Board, col: Colour, piece: PieceType) u64 {
    return self.pieceBB(piece) & self.occupancyFor(col);
}

pub inline fn pawns(self: *const Board) u64 {
    return self.pieceBB(.pawn);
}

pub inline fn knights(self: *const Board) u64 {
    return self.pieceBB(.knight);
}

pub inline fn bishops(self: *const Board) u64 {
    return self.pieceBB(.bishop);
}

pub inline fn rooks(self: *const Board) u64 {
    return self.pieceBB(.rook);
}

pub inline fn queens(self: *const Board) u64 {
    return self.pieceBB(.queen);
}

pub inline fn kings(self: *const Board) u64 {
    return self.pieceBB(.king);
}

const MAILBOX_EMPTY: u8 = 1 << 7;

inline fn mailboxValue(pt: PieceType, col: Colour) u8 {
    return ColouredPieceType.fromPieceType(pt, col).toInt();
}

inline fn mailboxIsEmpty(raw: u8) bool {
    assert((raw & MAILBOX_EMPTY != 0) == (raw == MAILBOX_EMPTY));
    return raw == MAILBOX_EMPTY;
}

pub inline fn pieceOn(self: *const Board, sq: Square) ?PieceType {
    const raw = (&self.mailbox)[sq.toInt()];
    return if (mailboxIsEmpty(raw)) null else PieceType.fromInt(raw >> 1);
}

pub inline fn isSquareEmpty(self: *const Board, sq: Square) bool {
    return !Bitboard.contains(self.occupancy(), sq);
}

pub inline fn colouredPieceOn(self: *const Board, sq: Square) ?ColouredPieceType {
    const raw = (&self.mailbox)[sq.toInt()];
    if (mailboxIsEmpty(raw)) return null;
    return ColouredPieceType.fromInt(raw);
}

pub inline fn startingRankFor(self: *const Board, col: Colour) Rank {
    return self.castling_rights.startingRankFor(col);
}

pub fn sumPieces(self: *const Board, values: anytype) std.meta.Child(@TypeOf(values)) {
    var res: std.meta.Child(@TypeOf(values)) = 0;
    for (PieceType.all) |pt| {
        res += (&values)[pt.toInt()] * @popCount(self.pieceBB(pt));
    }
    return res;
}

pub fn phase(self: *const Board) u8 {
    return self.sumPieces([_]u8{ 0, 1, 1, 3, 6, 0 });
}

pub fn classicalMaterial(self: *const Board) u8 {
    return self.sumPieces([_]u8{ 1, 3, 3, 5, 9, 0 });
}

pub fn equal(self: *const Board, other: *const Board) bool {
    if (self.hash != other.hash) {
        @branchHint(.likely);
        return false;
    }

    return std.meta.eql(self.*, other.*);
}

pub fn materialScale(self: *const Board) i32 {
    const tunables = root.tunable_constants;
    @setEvalBranchQuota(1 << 30);
    const vals: [6]i16 = if (root.tuning.do_tuning) .{
        @intCast(tunables.material_scaling_pawn),
        @intCast(tunables.material_scaling_knight),
        @intCast(tunables.material_scaling_bishop),
        @intCast(tunables.material_scaling_rook),
        @intCast(tunables.material_scaling_queen),
        0,
    } else comptime .{
        tunables.material_scaling_pawn,
        tunables.material_scaling_knight,
        tunables.material_scaling_bishop,
        tunables.material_scaling_rook,
        tunables.material_scaling_queen,
        0,
    };

    return self.sumPieces(vals);
}

pub fn parseFen(ifen: []const u8, permissive: bool) !Board {
    const fen = std.mem.trim(u8, ifen, &std.ascii.whitespace);
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
    var white_rooks_on_first_rank = try BoundedArray(File, 64).init(0);
    var black_rooks_on_last_rank = try BoundedArray(File, 64).init(0);
    var self: Board = .{};
    for (0..8) |r| {
        var c: usize = 0;
        for (ranks[7 - r]) |ch| {
            if (c >= 8) return error.TooManyPiecesOnRank;
            const current_square = Square.fromInt(@intCast(8 * r + c));
            const pt = PieceType.fromAsciiLetter(ch);
            if (std.ascii.isLower(ch)) {
                self.addPiece(.black, pt.?, current_square, NullEvalState{});
                if (ch == 'k') black_king_square = current_square;
                if (ch == 'r' and current_square.getRank() == .eighth) black_rooks_on_last_rank.append(current_square.getFile()) catch return error.TooManyRooks;
                c += 1;
            } else if (std.ascii.isUpper(ch)) {
                self.addPiece(.white, pt.?, current_square, NullEvalState{});
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
        var raw_castling_rights: u8 = 0;
        for (castling_string) |castle_ch| {
            raw_castling_rights |= switch (castle_ch) {
                'K' => CastlingRights.white_kingside_castle,
                'k' => CastlingRights.black_kingside_castle,
                'Q' => CastlingRights.white_queenside_castle,
                'q' => CastlingRights.black_queenside_castle,
                else => blk: {
                    self.frc = true;
                    const file = File.parse(castle_ch) catch return error.InvalidCharacter;
                    const king_square, const kingside_castle, const queenside_castle, const rook_array = if (std.ascii.isUpper(castle_ch)) .{
                        white_king_square.?,
                        CastlingRights.white_kingside_castle,
                        CastlingRights.white_queenside_castle,
                        &white_rooks_on_first_rank,
                    } else .{
                        black_king_square.?,
                        CastlingRights.black_kingside_castle,
                        CastlingRights.black_queenside_castle,
                        &black_rooks_on_last_rank,
                    };

                    if (!permissive and std.mem.count(File, rook_array.slice(), &.{file}) == 0)
                        return error.NoRookForCastling;

                    if (@intFromEnum(file) > @intFromEnum(king_square.getFile())) {
                        if (std.ascii.isUpper(castle_ch)) {
                            white_kingside_file = file;
                        } else {
                            black_kingside_file = file;
                        }
                        break :blk kingside_castle;
                    }
                    if (@intFromEnum(file) < @intFromEnum(king_square.getFile())) {
                        if (std.ascii.isUpper(castle_ch)) {
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
        self.castling_rights = CastlingRights.initFromParts(
            raw_castling_rights,
            white_kingside_file orelse white_king_square.?.getFile(),
            black_kingside_file orelse black_king_square.?.getFile(),
            white_queenside_file orelse white_king_square.?.getFile(),
            black_queenside_file orelse black_king_square.?.getFile(),
        );

        // determine the white queenside castling file
        if (self.castling_rights.queensideCastlingFor(.white) and white_queenside_file == null) {
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
        if (self.castling_rights.kingsideCastlingFor(.white) and white_kingside_file == null) {
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

        if (self.castling_rights.queensideCastlingFor(.black) and black_queenside_file == null) {
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
        if (self.castling_rights.kingsideCastlingFor(.black) and black_kingside_file == null) {
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
        self.castling_rights = CastlingRights.initFromParts(
            raw_castling_rights,
            white_kingside_file orelse white_king_square.?.getFile(),
            black_kingside_file orelse black_king_square.?.getFile(),
            white_queenside_file orelse white_king_square.?.getFile(),
            black_queenside_file orelse black_king_square.?.getFile(),
        );
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

pub fn toFen(self: Board) BoundedArray(u8, 128) {
    @setEvalBranchQuota(10000);
    var out = BoundedArray(u8, 128).init(0) catch unreachable;
    inline for (0..8) |rr| {
        const r = 7 - rr;
        var num_unoccupied: u8 = 0;
        inline for (0..8) |c| {
            const idx = r * 8 + c;
            const sq = Square.fromInt(idx);
            if (self.colouredPieceOn(sq)) |cpt| {
                const char = cpt.toAsciiLetter();
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
    if (self.castling_rights.rawCastlingAvailability() == 0) {
        out.appendAssumeCapacity('-');
    } else {
        if (self.castling_rights.kingsideCastlingFor(.white)) {
            out.appendAssumeCapacity(if (self.frc) std.ascii.toUpper(self.castling_rights.kingsideRookFileFor(.white).toAsciiLetter()) else 'K');
        }
        if (self.castling_rights.queensideCastlingFor(.white)) {
            out.appendAssumeCapacity(if (self.frc) std.ascii.toUpper(self.castling_rights.queensideRookFileFor(.white).toAsciiLetter()) else 'Q');
        }
        if (self.castling_rights.kingsideCastlingFor(.black)) {
            out.appendAssumeCapacity(if (self.frc) std.ascii.toLower(self.castling_rights.kingsideRookFileFor(.black).toAsciiLetter()) else 'k');
        }
        if (self.castling_rights.queensideCastlingFor(.black)) {
            out.appendAssumeCapacity(if (self.frc) std.ascii.toLower(self.castling_rights.queensideRookFileFor(.black).toAsciiLetter()) else 'q');
        }
    }
    out.appendAssumeCapacity(' ');
    if (self.ep_target) |ep_target| {
        var valid = false;
        switch (self.stm) {
            inline else => |stm_comptime| {
                var rec = movegen.MoveListReceiver{};
                movegen.generateAllNoisies(stm_comptime, &self, &rec);

                for (rec.vals.slice()) |move| {
                    if (self.isEnPassant(move)) {
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
    var print_buf: [32]u8 = undefined;
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

    var back_rank: [8]?PieceType = @splat(null);
    back_rank[b1 * 2 + 1] = .bishop;
    back_rank[b2 * 2] = .bishop;

    {
        var empty: u8 = 0;
        for (0..8) |i| {
            if (back_rank[i] == null) {
                if (empty == q) {
                    back_rank[i] = .queen;
                }
                empty += 1;
            }
        }
    }

    const knight1, const knight2 = N5n[n4];
    {
        var empty: u8 = 0;
        for (0..8) |i| {
            if (back_rank[i] == null) {
                if (empty == knight1) {
                    back_rank[i] = .knight;
                }
                empty += 1;
            }
        }
    }

    {
        var empty: u8 = 0;
        for (0..8) |i| {
            if (back_rank[i] == null) {
                if (empty == knight2) {
                    back_rank[i] = .knight;
                }
                empty += 1;
            }
        }
    }

    back_rank[std.mem.indexOfScalar(?PieceType, &back_rank, null) orelse unreachable] = .rook;
    back_rank[std.mem.indexOfScalar(?PieceType, &back_rank, null) orelse unreachable] = .king;
    back_rank[std.mem.indexOfScalar(?PieceType, &back_rank, null) orelse unreachable] = .rook;
    var out: [8]PieceType = undefined;
    for (&out, back_rank) |*out_elem, nullable_elem| {
        assert(nullable_elem != null);
        out_elem.* = nullable_elem.?;
    }
    return out;
}

pub fn dfrcPosition(n: u20) Board {
    const white_rank = frcBackrank(n % 960);
    const black_rank = frcBackrank(n / 960);

    var res: Board = .{};
    var white_rook = false;
    var black_rook = false;
    var white_kingside_rook_file: File = undefined;
    var black_kingside_rook_file: File = undefined;
    var white_queenside_rook_file: File = undefined;
    var black_queenside_rook_file: File = undefined;
    inline for (0..8) |c| {
        res.addPiece(.white, white_rank[c], Square.fromInt(c), NullEvalState{});
        res.addPiece(.white, .pawn, Square.fromInt(8 + c), NullEvalState{});
        if (white_rank[c] == .rook) {
            if (white_rook) {
                white_kingside_rook_file = File.fromInt(c);
            } else {
                white_queenside_rook_file = File.fromInt(c);
            }
            white_rook = true;
        }
        res.addPiece(.black, black_rank[c], Square.fromInt(56 + c), NullEvalState{});
        res.addPiece(.black, .pawn, Square.fromInt(48 + c), NullEvalState{});

        if (black_rank[c] == .rook) {
            if (black_rook) {
                black_kingside_rook_file = File.fromInt(c);
            } else {
                black_queenside_rook_file = File.fromInt(c);
            }
            black_rook = true;
        }
    }

    res.castling_rights = CastlingRights.initFromParts(
        0b1111,
        white_kingside_rook_file,
        black_kingside_rook_file,
        white_queenside_rook_file,
        black_queenside_rook_file,
    );
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

fn updateCastlingHash(self: *Board) void {
    self.hash ^= root.zobrist.castling(self.castling_rights.rawCastlingAvailability());
}

fn updateTurnHash(self: *Board) void {
    self.hash ^= root.zobrist.turn();
}

fn updateEPHash(self: *Board) void {
    if (self.ep_target) |target|
        self.hash ^= root.zobrist.ep(target);
}

pub inline fn getHashWithHalfmove(self: *const Board) u64 {
    return self.hash ^ root.zobrist.halfmove(self.halfmove);
}

pub inline fn isEnPassant(_: *const Board, move: Move) bool {
    return move.tp() == .ep;
}

pub inline fn isCastling(_: *const Board, move: Move) bool {
    return move.tp() == .castling;
}

pub inline fn isPromo(_: *const Board, move: Move) bool {
    return move.tp() == .promotion;
}

pub inline fn isCapture(self: *const Board, move: Move) bool {
    if (self.isEnPassant(move)) {
        @branchHint(.unpredictable);
        return true;
    }
    return !self.isCastling(move) and !self.isSquareEmpty(move.to());
}

pub inline fn isNoisy(self: *const Board, move: Move) bool {
    if (self.isCapture(move)) {
        @branchHint(.unpredictable);
        return true;
    }

    if (std.debug.runtime_safety) {
        inline for (.{ .knight, .bishop, .rook, .queen }) |pt| {
            const naive = self.isPromo(move) and move.promoType() == pt;
            std.debug.assert(naive == move.promoTypeEquals(pt));
        }
    }

    return move.promoTypeEquals(.queen);
}

pub inline fn isQuiet(self: *const Board, move: Move) bool {
    return !self.isNoisy(move);
}

pub inline fn getCapturedType(self: *const Board, move: Move) ?PieceType {
    if (self.isEnPassant(move)) {
        return .pawn;
    }
    if (self.colouredPieceOn(move.to())) |cpt| {
        return cpt.toPieceType();
    }
    return null;
}

pub inline fn kingsideKingDestFor(self: *const Board, col: Colour) Square {
    return Square.fromRankFile(self.startingRankFor(col), File.g);
}

pub inline fn queensideKingDestFor(self: *const Board, col: Colour) Square {
    return Square.fromRankFile(self.startingRankFor(col), File.c);
}

pub inline fn castlingKingDestFor(self: *const Board, move: Move, col: Colour) Square {
    if (move.from().toInt() < move.to().toInt()) {
        return self.kingsideKingDestFor(col);
    } else {
        return self.queensideKingDestFor(col);
    }
}

pub inline fn kingsideRookDestFor(self: *const Board, col: Colour) Square {
    return Square.fromRankFile(self.startingRankFor(col), File.f);
}

pub inline fn queensideRookDestFor(self: *const Board, col: Colour) Square {
    return Square.fromRankFile(self.startingRankFor(col), File.d);
}

pub inline fn castlingRookDestFor(self: *const Board, move: Move, col: Colour) Square {
    if (move.from().toInt() < move.to().toInt()) {
        return self.kingsideRookDestFor(col);
    } else {
        return self.queensideRookDestFor(col);
    }
}

fn zobristPiece(self: *Board, comptime col: Colour, pt: PieceType, sq: Square) void {
    const zobrist_update = root.zobrist.piece(col, pt, sq);
    self.hash ^= zobrist_update;
    if (pt == .pawn) {
        self.pawn_hash ^= zobrist_update;
    } else {
        self.nonpawn_hash[col.toInt()] ^= zobrist_update;
    }
    if (pt == .rook or pt == .queen) {
        self.major_hash ^= zobrist_update;
    }
    if (pt == .knight or pt == .bishop) {
        self.minor_hash ^= zobrist_update;
    }
}

pub fn addPiece(self: *Board, comptime col: Colour, pt: PieceType, sq: Square, eval_state: anytype) void {
    const bb = sq.toBitboard();
    self.occupancyPtrFor(col).* |= bb;
    self.pieceBBsMut()[pt.toInt()] |= bb;
    self.zobristPiece(col, pt, sq);
    (&self.mailbox)[sq.toInt()] = mailboxValue(pt, col);
    eval_state.add(col, pt, sq);
}

pub fn removePiece(self: *Board, comptime col: Colour, pt: PieceType, sq: Square, eval_state: anytype) void {
    const bb = sq.toBitboard();
    self.occupancyPtrFor(col).* ^= bb;
    self.pieceBBsMut()[pt.toInt()] ^= bb;
    self.zobristPiece(col, pt, sq);
    (&self.mailbox)[sq.toInt()] = MAILBOX_EMPTY;
    eval_state.sub(col, pt, sq);
}

pub fn movePiece(self: *Board, comptime col: Colour, pt: PieceType, from: Square, to: Square, eval_state: anytype) void {
    const bb = from.toBitboard() ^ to.toBitboard();
    self.occupancyPtrFor(col).* ^= bb;
    self.pieceBBsMut()[pt.toInt()] ^= bb;
    self.zobristPiece(col, pt, from);
    self.zobristPiece(col, pt, to);
    (&self.mailbox)[from.toInt()] = MAILBOX_EMPTY;
    (&self.mailbox)[to.toInt()] = mailboxValue(pt, col);
    eval_state.addSub(col, pt, to, col, pt, from);
}

pub fn movePiecePromo(self: *Board, comptime col: Colour, promo_pt: PieceType, from: Square, to: Square, eval_state: anytype) void {
    const bb = from.toBitboard() ^ to.toBitboard();
    self.occupancyPtrFor(col).* ^= bb;
    self.pieceBBsMut()[PieceType.pawn.toInt()] ^= from.toBitboard();
    self.pieceBBsMut()[promo_pt.toInt()] ^= to.toBitboard();
    self.zobristPiece(col, .pawn, from);
    self.zobristPiece(col, promo_pt, to);
    (&self.mailbox)[from.toInt()] = MAILBOX_EMPTY;
    (&self.mailbox)[to.toInt()] = mailboxValue(promo_pt, col);
    eval_state.addSub(col, promo_pt, to, col, .pawn, from);
}

pub fn movePieceCapture(self: *Board, comptime col: Colour, pt: PieceType, from: Square, to: Square, captured_pt: PieceType, captured_square: Square, eval_state: anytype) void {
    const bb = from.toBitboard() ^ to.toBitboard();
    self.occupancyPtrFor(col).* ^= bb;
    self.occupancyPtrFor(col.flipped()).* ^= captured_square.toBitboard();
    self.pieceBBsMut()[pt.toInt()] ^= bb;
    self.pieceBBsMut()[captured_pt.toInt()] ^= captured_square.toBitboard();
    self.zobristPiece(col, pt, from);
    self.zobristPiece(col, pt, to);
    self.zobristPiece(col.flipped(), captured_pt, captured_square);
    (&self.mailbox)[from.toInt()] = MAILBOX_EMPTY;
    (&self.mailbox)[captured_square.toInt()] = MAILBOX_EMPTY;
    (&self.mailbox)[to.toInt()] = mailboxValue(pt, col);
    eval_state.addSubSub(col, pt, to, col, pt, from, col.flipped(), captured_pt, captured_square);
}

pub fn movePiecePromoCapture(self: *Board, comptime col: Colour, promo_pt: PieceType, from: Square, to: Square, captured_pt: PieceType, captured_square: Square, eval_state: anytype) void {
    const bb = from.toBitboard() ^ to.toBitboard();
    self.occupancyPtrFor(col).* ^= bb;
    self.occupancyPtrFor(col.flipped()).* ^= captured_square.toBitboard();
    self.pieceBBsMut()[PieceType.pawn.toInt()] ^= from.toBitboard();
    self.pieceBBsMut()[promo_pt.toInt()] ^= to.toBitboard();
    self.pieceBBsMut()[captured_pt.toInt()] ^= captured_square.toBitboard();
    self.zobristPiece(col, .pawn, from);
    self.zobristPiece(col, promo_pt, to);
    self.zobristPiece(col.flipped(), captured_pt, captured_square);
    (&self.mailbox)[from.toInt()] = MAILBOX_EMPTY;
    (&self.mailbox)[captured_square.toInt()] = MAILBOX_EMPTY;
    (&self.mailbox)[to.toInt()] = mailboxValue(promo_pt, col);
    eval_state.addSubSub(col, promo_pt, to, col, .pawn, from, col.flipped(), captured_pt, captured_square);
}

pub fn movePieceCastling(self: *Board, comptime col: Colour, king_from: Square, king_to: Square, rook_from: Square, rook_to: Square, eval_state: anytype) void {
    const king_bb = king_from.toBitboard() ^ king_to.toBitboard();
    const rook_bb = rook_from.toBitboard() ^ rook_to.toBitboard();
    self.occupancyPtrFor(col).* ^= king_bb ^ rook_bb;
    self.pieceBBsMut()[PieceType.king.toInt()] ^= king_bb;
    self.pieceBBsMut()[PieceType.rook.toInt()] ^= rook_bb;
    self.zobristPiece(col, .king, king_from);
    self.zobristPiece(col, .king, king_to);
    self.zobristPiece(col, .rook, rook_from);
    self.zobristPiece(col, .rook, rook_to);
    (&self.mailbox)[king_from.toInt()] = MAILBOX_EMPTY;
    (&self.mailbox)[rook_from.toInt()] = MAILBOX_EMPTY;
    (&self.mailbox)[king_to.toInt()] = mailboxValue(.king, col);
    (&self.mailbox)[rook_to.toInt()] = mailboxValue(.rook, col);
    eval_state.addAddSubSub(col, .king, king_to, col, .rook, rook_to, col, .king, king_from, col, .rook, rook_from);
}

pub inline fn updateThreats(noalias self: *Board, comptime col: Colour) void {
    const occ = self.occupancy() ^ self.kingFor(col.flipped());
    const pawn_threats = Bitboard.pawnAttackBitBoard(self.pawnsFor(col), col);
    const knight_threats = Bitboard.knightMoveBitBoard(self.knightsFor(col));
    var bishop_threats: u64 = 0;
    var rook_threats: u64 = 0;
    var queen_threats: u64 = 0;
    const king_threats = Bitboard.kingMoves(Square.fromBitboard(self.kingFor(col)));
    var lesser_threatened: u64 = 0;

    // threatened now has all pieces attacked by pawns
    // so knights and bishops would be worth more
    lesser_threatened |= (self.knights() | self.bishops()) & pawn_threats;
    var iter = Bitboard.iterator(self.bishopsFor(col));
    while (iter.next()) |sq| {
        bishop_threats |= attacks.bishopAttacks(sq, occ);
    }

    // threatened now has all pieces attacked by pawns or by knights or bishops
    // so rooks are worth more than the attacking pieces
    const minor_threats = pawn_threats | knight_threats | bishop_threats;
    lesser_threatened |= self.rooks() & minor_threats;

    iter = Bitboard.iterator(self.rooksFor(col));
    while (iter.next()) |sq| {
        rook_threats |= attacks.rookAttacks(sq, occ);
    }

    // threatened now has all pieces attacked by pawns or by knights or bishops or rooks
    // so queens are worth more than the attacking pieces
    const major_threats = minor_threats | rook_threats;
    lesser_threatened |= self.queens() & major_threats;

    iter = Bitboard.iterator(self.queensFor(col));
    while (iter.next()) |sq| {
        queen_threats |= attacks.bishopAttacks(sq, occ) | attacks.rookAttacks(sq, occ);
    }

    const threatened = pawn_threats | knight_threats | bishop_threats | rook_threats | queen_threats | king_threats;
    self.threats[col.toInt()] = threatened;
    self.threats_by[col.toInt()] = .{
        pawn_threats,
        knight_threats,
        bishop_threats,
        rook_threats,
        queen_threats,
        king_threats,
    };
    self.lesser_threats[col.toInt()] = lesser_threatened;
}

pub fn updateMasks(self: *Board, col: Colour) void {
    self.updateThreats(.white);
    self.updateThreats(.black);
    switch (col) {
        inline else => |stm| self.updateKingThreats(stm),
    }
}

inline fn updateKingThreats(self: *Board, comptime stm: Colour) void {
    const occ = self.occupancy();
    self.pinned = .{0} ** 2;
    self.checkers =
        (Bitboard.pawnAttacks(Square.fromBitboard(self.kingFor(stm)), stm) & self.pawnsFor(stm.flipped())) |
        (Bitboard.knightMoves(Square.fromBitboard(self.kingFor(stm))) & self.knightsFor(stm.flipped()));

    inline for (.{ Colour.white, Colour.black }) |victim| {
        const king_sq = Square.fromBitboard(self.kingFor(victim));
        const attacker = victim.flipped();
        const rook_sliders = (self.rooks() | self.queens()) & self.occupancyFor(attacker);
        const bishop_sliders = (self.bishops() | self.queens()) & self.occupancyFor(attacker);

        var iter = Bitboard.iterator(
            (Bitboard.rookAttacks(king_sq) & rook_sliders) |
                (Bitboard.bishopAttacks(king_sq.toInt()) & bishop_sliders),
        );
        while (iter.next()) |slider_sq| {
            const pieces_between = occ & Bitboard.queenRayBetweenExclusive(king_sq, slider_sq);
            switch (@popCount(pieces_between)) {
                0 => if (victim == stm) {
                    self.checkers |= slider_sq.toBitboard();
                },
                1 => if (pieces_between & occ != 0) {
                    self.pinnedPtrFor(victim).* |= pieces_between;
                },
                else => {},
            }
        }
    }

    const their_king_sq = Square.fromBitboard(self.kingFor(stm.flipped()));
    self.checking_squares[PieceType.pawn.toInt()] = Bitboard.pawnAttacks(their_king_sq, stm.flipped());
    self.checking_squares[PieceType.knight.toInt()] = Bitboard.knightMoves(their_king_sq);
    self.checking_squares[PieceType.bishop.toInt()] = attacks.bishopAttacks(their_king_sq, occ);
    self.checking_squares[PieceType.rook.toInt()] = attacks.rookAttacks(their_king_sq, occ);
    self.checking_squares[PieceType.queen.toInt()] =
        self.checking_squares[PieceType.bishop.toInt()] |
        self.checking_squares[PieceType.rook.toInt()];
}

pub fn resetHash(self: *Board) void {
    self.hash = 0;
    self.pawn_hash = 0;
    self.major_hash = 0;
    self.minor_hash = 0;
    self.nonpawn_hash = .{0} ** 2;
    self.updateEPHash();
    self.updateCastlingHash();
    if (self.stm == .black)
        self.updateTurnHash();
    inline for (0..6) |p| {
        const pt = PieceType.fromInt(@intCast(p));
        var iter = Bitboard.iterator(self.pieceFor(.white, pt));
        while (iter.next()) |sq| {
            self.zobristPiece(.white, pt, sq);
        }
        iter = Bitboard.iterator(self.pieceFor(.black, pt));
        while (iter.next()) |sq| {
            self.zobristPiece(.black, pt, sq);
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
        var iter = Bitboard.iterator(self.pieceBB(pt));
        while (iter.next()) |sq| {
            if (self.mailbox[sq.toInt()] == MAILBOX_EMPTY) {
                return error.Broken;
            }
            self.hash ^= root.zobrist.piece(self.colouredPieceOn(sq).?.toColour(), pt, sq);
        }
    }
}

pub fn makeNullMove(noalias self: *Board, comptime stm: Colour) void {
    self.updateEPHash();
    self.updateTurnHash();
    self.plies += 1;
    self.ep_target = null;
    self.halfmove += 1;
    self.stm = stm.flipped();
    self.updateMasks(stm.flipped());
}

pub inline fn isDirectCheck(noalias self: *const Board, move: Move) bool {
    const piece = if (move.tp() == .promotion) move.promoType() else self.pieceOn(move.from()).?;
    if (piece == .king) return false;
    return (&self.checking_squares)[piece.toInt()] & move.to().toBitboard() != 0;
}

pub inline fn discoveredCheck(noalias self: *const Board, move: Move) bool {
    const stm = self.stm;
    const ntm_king = self.kingFor(stm.flipped());
    const ntm_king_sq = Square.fromBitboard(ntm_king);
    const ray = Bitboard.queenRayBetweenExclusive(
        ntm_king_sq,
        move.from(),
    );

    const fake_discovery = Bitboard.contains(ray, move.to());
    const is_pinned_to_enemy_king = self.pinnedFor(self.stm.flipped()) & move.from().toBitboard() != 0;
    return is_pinned_to_enemy_king and !fake_discovery;
}

pub inline fn givesCheck(noalias self: *const Board, move: Move) bool {
    if (self.discoveredCheck(move)) {
        return true;
    }
    return self.isDirectCheck(move);
}

fn hasDirectCheck(noalias self: *const Board) bool {
    const forward: i8 = if (self.stm == .white) 1 else -1;
    var checks: u64 = self.checkingSquaresFor(.pawn) & Bitboard.move(self.pawnsFor(self.stm), forward, 0);

    inline for ([_]root.PieceType{
        .knight,
        .bishop,
        .rook,
        .queen,
    }) |pt| {
        checks |= self.threatsBy(self.stm, pt) & self.checkingSquaresFor(pt);
    }
    checks &= ~self.occupancyFor(self.stm);

    return checks != 0;
}

test hasDirectCheck {
    root.init();
    inline for (.{
        "3k4/8/8/8/1K1N4/8/8/8 w - - 0 1",
        "3k4/8/8/8/3K4/8/3B4/8 w - - 0 1",
        "3k4/8/3K4/8/8/8/5R2/8 w - - 0 1",
        "3k4/8/4P3/3K4/8/8/8/8 w - - 0 1",
    }) |fen| {
        try std.testing.expect((try parseFen(fen, true)).hasDirectCheck());
    }

    inline for (.{
        "3k4/8/8/3K4/8/8/8/3R4 w - - 0 1",
        "3k4/8/8/3K4/8/8/8/8 w - - 0 1",
        "3k4/8/8/3K1N2/8/8/8/8 w - - 0 1",
        "3k4/8/8/3KP3/8/8/8/8 w - - 0 1",
    }) |fen| {
        try std.testing.expect(!(try parseFen(fen, true)).hasDirectCheck());
    }
}

pub inline fn hasCheck(noalias self: *const Board) bool {
    if (self.pinnedFor(self.stm.flipped()) & self.occupancyFor(self.stm) != 0) {
        return true;
    }
    return self.hasDirectCheck();
}

test hasCheck {
    root.init();
    inline for (.{
        "3k4/8/8/8/8/8/K2N4/3R4 w - - 0 1",
        "3k4/8/3K4/8/8/8/8/3R4 w - - 0 1",
    }) |fen| {
        try std.testing.expect((try parseFen(fen, true)).hasCheck());
    }
}

test discoveredCheck {
    root.init();

    inline for (.{
        .{
            .fen = "3k4/8/8/8/8/8/K2N4/3R4 w - - 0 1",
            .move = Move.quiet(.d2, .f3),
        },
        .{
            .fen = "7k/8/8/8/8/8/KR6/B7 w - - 0 1",
            .move = Move.quiet(.b2, .b3),
        },
    }) |case| {
        try std.testing.expect((try parseFen(case.fen, true)).discoveredCheck(case.move));
    }

    inline for (.{
        .{
            .fen = "3k4/8/8/8/1K1N4/8/8/8 w - - 0 1",
            .move = Move.quiet(.d4, .c6),
        },
        .{
            .fen = "3k4/8/8/8/8/8/K2N4/3R4 w - - 0 1",
            .move = Move.quiet(.a2, .a3),
        },
    }) |case| {
        try std.testing.expect(!(try parseFen(case.fen, true)).discoveredCheck(case.move));
    }
}

test givesCheck {
    root.init();

    inline for (.{
        .{
            .fen = "3k4/8/8/8/1K1N4/8/8/8 w - - 0 1",
            .move = Move.quiet(.d4, .c6),
        },
        .{
            .fen = "3k4/8/8/8/3K4/8/3B4/8 w - - 0 1",
            .move = Move.quiet(.d2, .g5),
        },
        .{
            .fen = "3k4/8/8/8/4K3/8/5R2/8 w - - 0 1",
            .move = Move.quiet(.f2, .d2),
        },
        .{
            .fen = "3k4/8/4P3/3K4/8/8/8/8 w - - 0 1",
            .move = Move.quiet(.e6, .e7),
        },
    }) |case| {
        const board = try parseFen(case.fen, true);
        try std.testing.expect(board.isDirectCheck(case.move));
        try std.testing.expect(board.givesCheck(case.move));
    }

    inline for (.{
        .{
            .fen = "3k4/8/8/8/1K1N4/8/8/8 w - - 0 1",
            .move = Move.quiet(.d4, .f5),
        },
        .{
            .fen = "3k4/8/8/8/3K4/8/3B4/8 w - - 0 1",
            .move = Move.quiet(.d2, .e3),
        },
        .{
            .fen = "3k4/8/8/8/4K3/8/5R2/8 w - - 0 1",
            .move = Move.quiet(.f2, .f3),
        },
        .{
            .fen = "3k4/8/8/3KP3/8/8/8/8 w - - 0 1",
            .move = Move.quiet(.e5, .e6),
        },
    }) |case| {
        const board = try parseFen(case.fen, true);
        try std.testing.expect(!board.isDirectCheck(case.move));
        try std.testing.expect(!board.givesCheck(case.move));
    }

    inline for (.{
        .{
            .fen = "3k4/8/8/8/8/8/K2N4/3R4 w - - 0 1",
            .move = Move.quiet(.d2, .f3),
        },
        .{
            .fen = "7k/8/8/8/8/8/KR6/B7 w - - 0 1",
            .move = Move.quiet(.b2, .b3),
        },
    }) |case| {
        const board = try parseFen(case.fen, true);
        try std.testing.expect(board.discoveredCheck(case.move));
        try std.testing.expect(board.givesCheck(case.move));
    }

    inline for (.{
        .{
            .fen = "3k4/8/8/8/1K1N4/8/8/8 w - - 0 1",
            .move = Move.quiet(.d4, .c6),
        },
        .{
            .fen = "3k4/8/8/8/8/8/K2N4/3R4 w - - 0 1",
            .move = Move.quiet(.a2, .a3),
        },
    }) |case| {
        const board = try parseFen(case.fen, true);
        try std.testing.expect(!board.discoveredCheck(case.move));
    }
}

pub fn makeMoveSimple(noalias self: *Board, move: Move) void {
    switch (self.stm) {
        inline else => |stm| {
            makeMove(self, stm, move, NullEvalState{});
        },
    }
}

pub fn makeMove(noalias self: *Board, comptime stm: Colour, move: Move, eval_state: anytype) void {
    self.plies += 1;
    var updated_halfmove = self.halfmove + 1;
    var updated_castling_rights = self.castling_rights;
    self.updateEPHash();
    self.ep_target = null;

    switch (move.tp()) {
        .default => {
            @branchHint(.likely);
            const from = move.from();
            const to = move.to();
            const pt = self.pieceOn(from).?;

            updated_castling_rights.updateSquare(from, stm);
            if (self.pieceOn(move.to())) |cap| {
                updated_halfmove = 0;
                updated_castling_rights.updateSquare(to, stm.flipped());
                self.movePieceCapture(stm, pt, from, to, cap, to, eval_state);
            } else {
                self.movePiece(stm, pt, from, to, eval_state);
            }

            if (pt == .pawn) {
                updated_halfmove = 0;
                const pawn_d_rank = if (stm == .white) 1 else -1;
                if (to.toInt() ^ from.toInt() == 16) {
                    const target = from.move(pawn_d_rank, 0);
                    if (Bitboard.pawnAttacks(target, stm) & self.pawnsFor(stm.flipped()) != 0) {
                        self.ep_target = target;
                        self.updateEPHash();
                    }
                }
            }
            if (pt == .king) {
                @branchHint(.unpredictable);
                updated_castling_rights.kingMoved(stm);
            }
        },
        .ep => {
            @branchHint(.unlikely);
            const from = move.from();
            const to = move.to();
            const target = move.getEnPassantPawnSquare(stm);
            updated_halfmove = 0;
            self.movePieceCapture(stm, .pawn, from, to, .pawn, target, eval_state);
        },
        .castling => {
            @branchHint(.unlikely);
            const king_from = move.from();
            const king_to = self.castlingKingDestFor(move, stm);
            const rook_from = move.to();
            const rook_to = self.castlingRookDestFor(move, stm);
            updated_castling_rights.kingMoved(stm);
            self.movePieceCastling(stm, king_from, king_to, rook_from, rook_to, eval_state);
        },
        .promotion => {
            @branchHint(.unlikely);
            const from = move.from();
            const to = move.to();
            updated_halfmove = 0;
            if (self.pieceOn(move.to())) |cap| {
                updated_castling_rights.updateSquare(to, stm.flipped());
                self.movePiecePromoCapture(stm, move.promoType(), from, to, cap, to, eval_state);
            } else {
                self.movePiecePromo(stm, move.promoType(), from, to, eval_state);
            }
        },
    }
    if (updated_castling_rights.rawCastlingAvailability() != self.castling_rights.rawCastlingAvailability()) {
        self.hash ^= root.zobrist.castling(self.castling_rights.rawCastlingAvailability()) ^ root.zobrist.castling(updated_castling_rights.rawCastlingAvailability());
    }
    self.halfmove = updated_halfmove;
    self.castling_rights = updated_castling_rights;
    self.stm = stm.flipped();
    self.fullmove += stm.toInt();

    self.updateMasks(stm.flipped());
    self.updateTurnHash();
}

pub inline fn parseMoveStr(self: *const Board, str: []const u8) !Move {
    switch (self.stm) {
        inline else => |stm| {
            var rec: movegen.MoveListReceiver = .{};
            movegen.generateAllNoisies(stm, self, &rec);
            movegen.generateAllQuiets(stm, self, &rec);

            for (rec.vals.slice()) |move| {
                if (std.mem.eql(u8, move.toString(self).slice(), str)) {
                    return move;
                }
            }
        },
    }
    return error.NoSuchMove;
}

pub inline fn makeMoveFromStr(self: *Board, str: []const u8) !void {
    const move = try self.parseMoveStr(str);
    switch (self.stm) {
        inline else => |stm| self.makeMove(stm, move, NullEvalState{}),
    }
}

pub fn parseSANMove(self: *const Board, san_move_inp: []const u8) ?Move {
    if (san_move_inp[0] == 'O') {
        switch (self.stm) {
            inline else => |stm| {
                var ml = movegen.MoveListReceiver{};
                root.movegen.generateKingQuiets(stm, self, &ml);
                const queenside = san_move_inp.len >= "O-O-O".len and std.mem.eql(u8, san_move_inp[0..5], "O-O-O");
                for (ml.vals.slice()) |move| {
                    if (move.tp() != .castling) {
                        continue;
                    }
                    if ((self.castlingKingDestFor(move, stm).getFile() == .c) == queenside) {
                        return move;
                    }
                }
            },
        }
        return null;
    }
    var san_move = san_move_inp;
    switch (san_move[san_move.len - 1]) {
        '+', '#' => san_move.len -= 1,
        else => {},
    }
    const promo_type = switch (san_move[san_move.len - 1]) {
        '1'...'8' => null,
        else => |p| blk: {
            san_move.len -= 2;
            break :blk PieceType.fromAsciiLetter(p);
        },
    };

    const destination = Square.fromRankFile(
        Rank.parse(san_move[san_move.len - 1]) catch unreachable,
        File.parse(san_move[san_move.len - 2]) catch unreachable,
    );

    const tp: PieceType = switch (san_move[0]) {
        'a'...'h' => .pawn,
        'N' => .knight,
        'B' => .bishop,
        'R' => .rook,
        'Q' => .queen,
        'K' => .king,
        else => unreachable,
    };

    var is_capture: bool = false;
    var allowed_start_mask: u64 = std.math.maxInt(u64);
    for (san_move[0 .. san_move.len - 2]) |c| switch (c) {
        '1'...'8' => allowed_start_mask &= @as(u64, 0b11111111) << @intCast(8 * (c - '1')),
        'a'...'h' => allowed_start_mask &= @as(u64, std.math.maxInt(u64) / std.math.maxInt(u8)) << @intCast(c - 'a'),
        'x' => is_capture = true,
        else => {},
    };

    switch (self.stm) {
        inline else => |stm| {
            var ml = movegen.MoveListReceiver{};
            root.movegen.generateAllQuietsWithMask(stm, self, &ml, destination.toBitboard());
            root.movegen.generateAllNoisiesWithMask(stm, self, &ml, destination.toBitboard());
            var valid_count: usize = 0;

            for (ml.vals.slice()) |move| {
                if (move.to() != destination) {
                    continue;
                }
                if (move.from().toBitboard() & allowed_start_mask == 0) {
                    continue;
                }
                if (self.pieceOn(move.from()) != tp) {
                    continue;
                }
                const move_promotype = if (move.tp() == .promotion) move.promoType() else null;
                if (promo_type != move_promotype) {
                    continue;
                }
                if (!std.debug.runtime_safety) {
                    return move;
                }
                ml.vals.slice()[valid_count] = move;
                valid_count += 1;
            }
            if (valid_count == 1) {
                if (promo_type != null) {}
                return ml.vals.slice()[0];
            }
            // std.debug.print("valid: {} {s} {} {} '{s}'\n", .{ valid_count, self.toFen().slice(), allowed_start_mask, destination, san_move });
        },
    }
    return null;
}

pub fn pickMoveDatagen(self: *Board, rng: std.Random) ?Move {
    const hce = @import("hce.zig");
    switch (self.stm) {
        inline else => |stm| {
            var ml = root.ScoredMoveReceiver{};
            root.movegen.generateAllQuiets(stm, self, &ml);
            root.movegen.generateAllNoisies(stm, self, &ml);

            for (ml.vals.slice()) |*m| {
                m.score = switch (m.move.tp()) {
                    .default => blk: {
                        const pt = self.pieceOn(m.move.from()).?;
                        const pst_score: i32 = hce.readPieceSquareTable(stm, pt, m.move.to()).midgame();
                        const material = hce.readPieceValue(pt).midgame();
                        var piece_score: i32 = switch (pt) {
                            .pawn => 500,
                            .knight => 1000,
                            .bishop => 1000,
                            .rook => 500,
                            .queen => 100,
                            .king => 0,
                        };
                        const diag_sliders = self.bishopsFor(stm) | self.queensFor(stm);

                        if (Bitboard.bishopAttacks(m.move.from()) & diag_sliders != 0) {
                            piece_score += 1000;
                        }
                        break :blk pst_score - material + piece_score;
                    },
                    .castling => 10000,
                    .ep => 10000,
                    .promotion => 10000,
                } + rng.uintLessThanBiased(u16, 30000);
            }
            std.sort.pdq(root.ScoredMove, ml.vals.slice(), void{}, root.ScoredMove.desc);
            for (ml.vals.slice()) |m| {
                if (root.SEE.scoreMove(self, m.move, -200, .pruning)) {
                    return m.move;
                }
            }
            return null;
        },
    }
}

pub fn hasLegalMove(self: *const Board) bool {
    switch (self.stm) {
        inline else => |stm| {
            var ml = root.movegen.CountReceiver{};
            root.movegen.generateAllNoisies(stm, self, &ml);
            if (ml.count > 0) return true;
            root.movegen.generateAllQuiets(stm, self, &ml);
            return ml.count > 0;
        },
    }
}

pub fn isCastlingMoveLegal(self: *const Board, comptime stm: Colour, move: Move) bool {
    const rook_from = move.to();
    if (self.pinnedFor(stm) & rook_from.toBitboard() != 0) {
        return false;
    }
    const rook_to = self.castlingRookDestFor(move, stm);
    const king_from = move.from();
    const king_to = self.castlingKingDestFor(move, stm);
    const king_rook_bbs = rook_from.toBitboard() | king_from.toBitboard();

    const all_pieces = rook_from.toBitboard() | rook_to.toBitboard() | king_from.toBitboard() | king_to.toBitboard();
    const start = @ctz(all_pieces);
    const end = 63 - @clz(all_pieces);
    const need_to_be_empty = Bitboard.queenRayBetweenInclusive(start, end);

    const occ_without_king_rook = self.occupancy() & ~king_rook_bbs;
    if (occ_without_king_rook & need_to_be_empty != 0) {
        return false;
    }
    const need_to_be_unattacked = Bitboard.queenRayBetween(king_from, king_to);
    return need_to_be_unattacked & self.threats[stm.flipped().toInt()] == 0;
}

pub fn isLegal(self: *const Board, comptime stm: Colour, move: Move) bool {
    const from = move.from();
    const to = move.to();
    if (from == to or move.isNull()) {
        return false;
    }

    const tp = move.tp();
    const from_bb = from.toBitboard();
    const to_bb = to.toBitboard();

    if (tp == .castling) {
        if (self.checkers != 0) {
            return false;
        }

        const raw: u16 = self.castling_rights.rawCastlingAvailability();
        const extra: u16 = move.extra();
        if (raw & (@as(u8, 1) << @intCast(extra)) == 0) {
            return false;
        }

        const from_is_king = self.kingFor(stm) & from_bb != 0;
        const to_is_rook = self.rooksFor(stm) & to_bb != 0;

        if (!from_is_king or !to_is_rook) {
            return false;
        }

        if (extra & 1 != stm.toInt()) {
            return false;
        }
        const is_kingside = extra & 2 == 0;
        if (is_kingside != (to.getFile().toInt() > from.getFile().toInt())) {
            return false;
        }

        return self.isCastlingMoveLegal(stm, move);
    }

    if ((self.occupancyFor(stm) & (from_bb | to_bb)) != from_bb) {
        return false;
    }

    const pt = self.pieceOn(from).?;

    if (self.checkers & self.checkers -% 1 != 0) {
        return pt == .king and
            tp == .default and move.extra() == 0 and
            Bitboard.kingMoves(from) & to_bb != 0 and
            self.threatsFor(stm.flipped()) & to_bb == 0 and
            movegen.attackersFor(stm.flipped(), self, to, self.occupancy() ^ from_bb) == 0;
    }

    if (pt == .king) {
        return Bitboard.kingMoves(from) & to_bb != 0 and
            tp == .default and move.extra() == 0 and
            self.threatsFor(stm.flipped()) & to_bb == 0 and
            movegen.attackersFor(stm.flipped(), self, to, self.occupancy() ^ from_bb) == 0;
    }

    if (tp == .ep) {
        if (move.extra() != 0 or pt != .pawn or to != self.ep_target or Bitboard.pawnAttacks(from, stm) & to_bb == 0)
            return false;

        const pawn_d_rank = if (stm == .white) 1 else -1;
        const captured = to.move(-pawn_d_rank, 0);
        const occ_change = from_bb ^ to_bb ^ captured.toBitboard();
        return movegen.slidingAttackersFor(
            stm.flipped(),
            self,
            Square.fromBitboard(self.kingFor(stm)),
            self.occupancy() ^ occ_change,
        ) == 0;
    }

    if (self.checkers != 0) {
        if (Bitboard.checkMask(Square.fromBitboard(self.kingFor(stm)), Square.fromBitboard(self.checkers)) & to_bb == 0) {
            return false;
        }
    }

    if (self.pinnedFor(stm) & from_bb != 0) {
        if (Bitboard.extendingRayBb(from, to) & self.kingFor(stm) == 0) {
            return false;
        }
    }

    if (pt == .pawn) {
        const d_rank = if (stm == .white) 1 else -1;
        const promo_rank: Rank = if (stm == .white) .eighth else .first;
        const promo_mask = @as(u64, 0b11111111) << @as(comptime_int, comptime promo_rank.toInt()) * 8;
        const double_push_rank: Rank = if (stm == .white) .fourth else .fifth;
        const double_push_mask = @as(u64, 0b11111111) << @as(comptime_int, comptime double_push_rank.toInt()) * 8;

        if ((to_bb & promo_mask != 0) != (tp == .promotion)) return false;
        if (tp == .default and move.extra() != 0) return false;

        var allowed: u64 = 0;
        allowed |= Bitboard.move(from_bb, d_rank, 0) & ~self.occupancy();
        allowed |= Bitboard.move(allowed, d_rank, 0) & ~self.occupancy() & double_push_mask;

        allowed |= Bitboard.move(from_bb, d_rank, 1) & self.occupancyFor(stm.flipped());
        allowed |= Bitboard.move(from_bb, d_rank, -1) & self.occupancyFor(stm.flipped());

        return allowed & to_bb != 0;
    } else if (tp == .promotion) {
        return false;
    }

    if (tp != .default or move.extra() != 0) {
        return false;
    }

    return to_bb & switch (pt) {
        .pawn => unreachable,
        .knight => Bitboard.knightMoves(from),
        .bishop => attacks.bishopAttacks(from, self.occupancy()),
        .rook => attacks.rookAttacks(from, self.occupancy()),
        .queen => attacks.bishopAttacks(from, self.occupancy()) | attacks.rookAttacks(from, self.occupancy()),
        .king => unreachable,
    } != 0;
}

pub inline fn roughHashAfter(self: *const Board, move: Move, comptime include_halfmove: bool) u64 {
    var res: u64 = self.hash;

    var hmc = if (include_halfmove) self.halfmove + 1 else void{};
    if (!move.isNull()) {
        if (self.colouredPieceOn(move.to())) |cpt| {
            @branchHint(.unpredictable);
            res ^= root.zobrist.piece(cpt.toColour(), cpt.toPieceType(), move.to());
            if (include_halfmove) {
                hmc = 0;
            }
        }

        const cpt = self.colouredPieceOn(move.from()).?;
        const pt = cpt.toPieceType();
        const col = cpt.toColour();

        res ^= root.zobrist.piece(col, pt, move.from());
        res ^= root.zobrist.piece(col, pt, move.to());

        if (include_halfmove) {
            hmc *= @intFromBool(pt != .pawn);
        }
    } else {
        if (include_halfmove) {
            hmc = 0;
        }
    }
    res ^= root.zobrist.turn();
    if (include_halfmove) {
        res ^= root.zobrist.halfmove(hmc);
    }

    return res;
}

pub const NullEvalState = struct {
    pub inline fn init(board: *const Board) NullEvalState {
        _ = board;
        return .{};
    }

    pub inline fn initInPlace(self: @This(), board: *const Board) void {
        _ = self;
        _ = board;
    }

    pub inline fn update(self: @This(), _: anytype, _: anytype, _: anytype) void {
        _ = self;
    }

    pub inline fn add(self: @This(), comptime col: Colour, pt: PieceType, square: Square) void {
        _ = self;
        _ = col;
        _ = pt;
        _ = square;
    }

    pub inline fn sub(self: @This(), comptime col: Colour, pt: PieceType, square: Square) void {
        _ = self;
        _ = col;
        _ = pt;
        _ = square;
    }

    pub inline fn addSub(self: @This(), comptime add_col: Colour, add_pt: PieceType, add_square: Square, comptime sub_col: Colour, sub_pt: PieceType, sub_square: Square) void {
        _ = self;
        _ = add_col;
        _ = add_pt;
        _ = add_square;
        _ = sub_col;
        _ = sub_pt;
        _ = sub_square;
    }

    pub inline fn addSubSub(self: @This(), comptime add_col: Colour, add_pt: PieceType, add_square: Square, comptime sub1_col: Colour, sub1_pt: PieceType, sub1_square: Square, comptime sub2_col: Colour, sub2_pt: PieceType, sub2_square: Square) void {
        _ = self;
        _ = add_col;
        _ = add_pt;
        _ = add_square;
        _ = sub1_col;
        _ = sub1_pt;
        _ = sub1_square;
        _ = sub2_col;
        _ = sub2_pt;
        _ = sub2_square;
    }

    pub inline fn addAddSubSub(self: @This(), comptime add1_col: Colour, add1_pt: PieceType, add1_square: Square, comptime add2_col: Colour, add2_pt: PieceType, add2_square: Square, comptime sub1_col: Colour, sub1_pt: PieceType, sub1_square: Square, comptime sub2_col: Colour, sub2_pt: PieceType, sub2_square: Square) void {
        _ = self;
        _ = add1_col;
        _ = add1_pt;
        _ = add1_square;
        _ = add2_col;
        _ = add2_pt;
        _ = add2_square;
        _ = sub1_col;
        _ = sub1_pt;
        _ = sub1_square;
        _ = sub2_col;
        _ = sub2_pt;
        _ = sub2_square;
    }
};

// const HashPair = struct {
//     zobrist: u64 = 0,
//     crc: u128 = 0,
//     b: *const Board = .{},

//     fn init(board: *const Board) HashPair {
//         var hasher = std.hash.Fnv1a_128.init();

//         hasher.update(std.mem.asBytes(board.whitePtr()));
//         hasher.update(std.mem.asBytes(board.blackPtr()));
//         hasher.update(std.mem.asBytes(board.pieceBBs()));
//         hasher.update(std.mem.asBytes(&board.ep_target));
//         hasher.update(std.mem.asBytes(&board.mailbox));
//         hasher.update(std.mem.asBytes(&board.stm));
//         hasher.update(std.mem.asBytes(&board.castling_rights));
//         var b = board.*;
//         b.resetHash();
//         return .{
//             .zobrist = b.hash,
//             .crc = hasher.final(),
//             .b = b,
//         };
//     }
// };

const plausible_moves = computePlausibleMoves();

fn computePlausibleMoves() BoundedArray(Move, 8192) {
    @setEvalBranchQuota(1_000_000);
    var result: BoundedArray(Move, 8192) = .{};

    for (0..64) |from_int| {
        const from_rank = from_int / 8;
        const from_file = from_int % 8;
        const from = Square.fromInt(@intCast(from_int));

        for (0..64) |to_int| {
            if (from_int == to_int) continue;
            const to_rank = to_int / 8;
            const to_file = to_int % 8;
            const to = Square.fromInt(@intCast(to_int));

            const rank_diff = if (to_rank >= from_rank) to_rank - from_rank else from_rank - to_rank;
            const file_diff = if (to_file >= from_file) to_file - from_file else from_file - to_file;

            const is_queen = (rank_diff == 0 or file_diff == 0 or rank_diff == file_diff) and rank_diff <= 7 and file_diff <= 7;
            const is_knight = (rank_diff == 1 and file_diff == 2) or (rank_diff == 2 and file_diff == 1);

            if (is_queen or is_knight) {
                result.appendAssumeCapacity(Move.quiet(from, to));
            }

            const is_white_promo = from_rank == 6 and to_rank == 7;
            const is_black_promo = from_rank == 1 and to_rank == 0;
            const is_pawn_push = file_diff == 0 and rank_diff == 1;
            const is_pawn_capture = file_diff == 1 and rank_diff == 1;

            if ((is_white_promo or is_black_promo) and (is_pawn_push or is_pawn_capture)) {
                result.appendAssumeCapacity(Move.promo(from, to, .knight));
                result.appendAssumeCapacity(Move.promo(from, to, .bishop));
                result.appendAssumeCapacity(Move.promo(from, to, .rook));
                result.appendAssumeCapacity(Move.promo(from, to, .queen));
            }

            const is_white_ep = from_rank == 4 and to_rank == 5;
            const is_black_ep = from_rank == 3 and to_rank == 2;
            if ((is_white_ep or is_black_ep) and is_pawn_capture) {
                result.appendAssumeCapacity(Move.enPassant(from, to));
            }

            if ((from_rank == 0 and to_rank == 0) or (from_rank == 7 and to_rank == 7)) {
                const col_offset: u16 = if (from_rank == 7) 1 else 0;
                const ks = Move.castlingKingside(@enumFromInt(col_offset), from, to);
                const qs = Move.castlingQueenside(@enumFromInt(col_offset), from, to);
                result.appendAssumeCapacity(ks);
                if (@intFromEnum(ks) != @intFromEnum(qs)) {
                    result.appendAssumeCapacity(qs);
                }
            }
        }
    }

    return result;
}

fn perft_impl(
    self: *const Board,
    comptime is_root: bool,
    comptime stm: Colour,
    comptime quiet: bool,
    comptime verify: bool,
    depth: i32,
) u64 {
    if (depth == 0) return 1;
    var movelist = movegen.MoveListReceiver{};
    movegen.generateAllNoisies(stm, self, &movelist);
    movegen.generateAllQuiets(stm, self, &movelist);
    var res: u64 = 0;

    if (verify) {
        var is_legal_count: usize = 0;
        for (plausible_moves.slice()) |m| {
            if (self.isLegal(stm, m)) is_legal_count += 1;
        }
        if (is_legal_count != movelist.vals.len) {
            std.debug.print("mismatch at {s}: movegen={} legal={}\n", .{
                self.toFen().slice(),
                movelist.vals.len,
                is_legal_count,
            });
            for (plausible_moves.slice()) |m| {
                if (!self.isLegal(stm, m)) continue;
                var found = false;
                for (movelist.vals.slice()) |gen_move| {
                    if (gen_move == m) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    std.debug.print("  extra: {s} (tp={} extra={})\n", .{
                        m.toString(self).slice(),
                        @intFromEnum(m.tp()),
                        m.extra(),
                    });
                }
            }
            for (movelist.vals.slice()) |gen_move| {
                var found = false;
                for (plausible_moves.slice()) |m| {
                    if (gen_move == m) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    std.debug.print("  missing: {s} (tp={} extra={})\n", .{
                        gen_move.toString(self).slice(),
                        @intFromEnum(gen_move.tp()),
                        gen_move.extra(),
                    });
                }
            }
            std.debug.panic("legal movegen count ({}) does not match isLegal count ({})", .{
                movelist.vals.len,
                is_legal_count,
            });
        }
    }

    if (depth == 1) {
        res += movelist.vals.len;
    } else {
        for (movelist.vals.slice()) |move| {
            var cp = self.*;
            cp.makeMove(stm, move, NullEvalState{});
            if (is_root and !quiet) {
                std.debug.print("{s}: ", .{move.toString(self).slice()});
            }
            const count = cp.perft_impl(
                false,
                stm.flipped(),
                quiet,
                verify,
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
            false,
            depth,
        ),
    };
}

pub fn perftVerify(
    self: Board,
    comptime quiet: bool,
    depth: i32,
) u64 {
    return switch (self.stm) {
        inline else => |stm_comptime| self.perft_impl(
            true,
            stm_comptime,
            quiet,
            true,
            depth,
        ),
    };
}

test "basic makemove" {
    var board = startpos();
    board.makeMove(.white, Move.quiet(.e2, .e4), Board.NullEvalState{});
    try std.testing.expectEqual(@as(u8, ColouredPieceType.white_pawn.toInt()), board.mailbox[Square.e4.toInt()]);
    try std.testing.expectEqual(board.pawnsFor(.white) & Square.e4.toBitboard(), Square.e4.toBitboard());
    try std.testing.expectEqual(board.pawnsFor(.white) & Square.e2.toBitboard(), 0);
}
