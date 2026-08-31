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

const Allocator = std.mem.Allocator;

const root = @import("root.zig");

const PieceType = root.PieceType;
const Square = root.Square;
const Bitboard = root.Bitboard;
const attacks = root.attacks;
const Board = root.Board;
const LeanBoard = root.LeanBoard;
const Move = root.Move;
const Colour = root.Colour;
const Rank = root.Rank;
const File = root.File;
const WDL = root.WDL;
const dataformat = root.dataformat;
const CastlingRights = root.CastlingRights;

pub const Error = error{
    TooManyPieces,
    MissingKing,
    PawnsOnFirstLastRank,
    KingOnWrongRankAndCanCastle,
    InvalidEpSquare,
    InvalidPieceCode,
};

fn LittleEndian(comptime T: type) type {
    return packed struct(T) {
        val: T,

        const Self = @This();

        pub fn fromNative(x: T) Self {
            return .{ .val = std.mem.nativeToLittle(T, x) };
        }

        pub fn toNative(self: Self) T {
            return std.mem.littleToNative(T, self.val);
        }
    };
}

pub const MarlinPackedBoard = extern struct {
    occupancy: LittleEndian(u64),
    pieces: [16]u8,
    stm_ep_square: u8,
    halfmove_clock: u8,
    fullmove_number: LittleEndian(u16),
    eval: LittleEndian(i16),
    wdl: u8,
    extra: u8,

    const unmoved_rook = 6;

    pub fn toBoard(self: MarlinPackedBoard) Error!Board {
        return self.toImpl(Board);
    }

    pub fn toLeanBoard(self: MarlinPackedBoard) Error!LeanBoard {
        return self.toImpl(LeanBoard);
    }

    fn toImpl(self: MarlinPackedBoard, comptime T: type) Error!T {
        var res: T = .{};

        const occ = self.occupancy.toNative();
        if (@popCount(occ) > 32) {
            return error.TooManyPieces;
        }
        var iter = Bitboard.iterator(occ);
        var castling_rooks: u64 = 0;
        var i: usize = 0;
        while (iter.next()) |sq| : (i += 1) {
            const code = (self.pieces[i / 2] >> if (i % 2 == 0) 0 else 4) & 0b1111;
            const is_black = code & 8 != 0;
            const col: Colour = if (is_black) .black else .white;
            const pt: PieceType = switch (code & 0b111) {
                0 => .pawn,
                1 => .knight,
                2 => .bishop,
                3 => .rook,
                4 => .queen,
                5 => .king,
                6 => blk: {
                    castling_rooks |= sq.toBitboard();
                    break :blk .rook;
                },
                else => return error.InvalidPieceCode,
            };
            res.addPiece(col, pt, sq);
        }
        if (@popCount(res.kingFor(.white)) != 1 or @popCount(res.kingFor(.black)) != 1) {
            return error.MissingKing;
        }
        const first = 0xff00000000000000;
        const last = 0x00000000000000ff;
        const first_last = first | last;
        if (first_last & res.pawns() != 0) {
            return error.PawnsOnFirstLastRank;
        }

        var white_queenside_file: ?File = null;
        var white_kingside_file: ?File = null;
        const white_castling_rooks = castling_rooks & 0b1111_1111;
        var black_queenside_file: ?File = null;
        var black_kingside_file: ?File = null;
        const black_castling_rooks = castling_rooks >> 56;

        iter = Bitboard.iterator(white_castling_rooks);
        var rights_flag: u8 = 0;
        while (iter.next()) |sq| {
            const king = Square.fromBitboard(res.kingFor(.white));

            if (king.getFile().toInt() < sq.getFile().toInt()) {
                white_kingside_file = sq.getFile();
                rights_flag |= CastlingRights.WHITE_KINGSIDE_CASTLE;
            } else {
                white_queenside_file = sq.getFile();
                rights_flag |= CastlingRights.WHITE_QUEENSIDE_CASTLE;
            }
        }
        iter = Bitboard.iterator(black_castling_rooks);
        while (iter.next()) |sq| {
            const king = Square.fromBitboard(res.kingFor(.black));

            if (king.getFile().toInt() < sq.getFile().toInt()) {
                black_kingside_file = sq.getFile();
                rights_flag |= CastlingRights.BLACK_KINGSIDE_CASTLE;
            } else {
                black_queenside_file = sq.getFile();
                rights_flag |= CastlingRights.BLACK_QUEENSIDE_CASTLE;
            }
        }

        res.castling_rights = .initFromParts(
            rights_flag,
            white_kingside_file orelse .a,
            black_kingside_file orelse .a,
            white_queenside_file orelse .h,
            black_queenside_file orelse .h,
        );
        if (res.kingFor(.white) & first_last == 0 and rights_flag & (CastlingRights.WHITE_KINGSIDE_CASTLE | CastlingRights.WHITE_QUEENSIDE_CASTLE) != 0) {
            return error.KingOnWrongRankAndCanCastle;
        }
        if (res.kingFor(.black) & first_last == 0 and rights_flag & (CastlingRights.BLACK_KINGSIDE_CASTLE | CastlingRights.BLACK_QUEENSIDE_CASTLE) != 0) {
            return error.KingOnWrongRankAndCanCastle;
        }

        const ep_target = self.stm_ep_square & 0b0111_1111;
        res.ep_target = if (ep_target < 64) Square.fromInt(ep_target) else null;
        res.stm = if (self.stm_ep_square & 0b1000_0000 == 0) .white else .black;
        if (res.ep_target) |ep_sq| {
            const proper_rank: Rank = if (res.stm == .white) .sixth else .third;
            if (ep_sq.getRank() != proper_rank) {
                return error.InvalidEpSquare;
            }
            const d_rank: i8 = if (res.stm == .white) 1 else -1;
            const pushed_pawn = ep_sq.move(-d_rank, 0);
            if (res.pieceFor(res.stm.flipped(), .pawn) & pushed_pawn.toBitboard() == 0 or
                res.occupancy() & ep_sq.toBitboard() != 0)
            {
                return error.InvalidEpSquare;
            }
        }
        res.halfmove = self.halfmove_clock;
        res.fullmove = self.fullmove_number.toNative();
        res.recomputeAll();

        return res;
    }

    pub fn from(board: anytype, loss_draw_win: u8, score: i16) MarlinPackedBoard {
        const occ = board.occupancy();
        var pieces: [16]u8 = .{0} ** 16;
        {
            var i: usize = 0;
            var iter = Bitboard.iterator(occ);
            while (iter.next()) |sq| : (i += 1) {
                const cpt = board.colouredPieceOn(sq).?;
                const piece_type = cpt.toPieceType();
                const side: Colour = cpt.toColour();
                const starting_rank: Rank = if (side == .white) .first else .eighth;

                var piece_code: u4 = @intCast(piece_type.toInt());

                // if yoinking and not doing FRC u can skip this
                if (piece_type == .rook and sq.getRank() == starting_rank) {
                    const can_kingside_castle = board.castling_rights.kingsideCastlingFor(side);
                    const can_queenside_castle = board.castling_rights.queensideCastlingFor(side);
                    const kingside_file = board.castling_rights.kingsideRookFileFor(side);
                    const queenside_file = board.castling_rights.queensideRookFileFor(side);
                    if ((sq.getFile() == kingside_file and can_kingside_castle) or
                        (sq.getFile() == queenside_file and can_queenside_castle))
                    {
                        piece_code = unmoved_rook;
                    }
                }

                const val: u8 = piece_code | @as(u4, if (side == .black) 1 << 3 else 0);
                pieces[i / 2] |= val << if (i % 2 == 0) 0 else 4;
            }
        }
        return MarlinPackedBoard{
            .occupancy = LittleEndian(u64).fromNative(board.occupancy()),
            .pieces = pieces,
            .stm_ep_square = @as(u8, if (board.stm == .black) 1 << 7 else 0) | @as(u8, if (board.ep_target) |ep_target| ep_target.toInt() else 64),
            .halfmove_clock = board.halfmove,
            .fullmove_number = LittleEndian(u16).fromNative(@intCast(board.fullmove)),
            .eval = LittleEndian(i16).fromNative(score),
            .wdl = loss_draw_win,
            .extra = 164,
        };
    }
};

pub const ViriMove = extern struct {
    const promo_flag_bits: u16 = 0b1100_0000_0000_0000;
    const ep_flag_bits: u16 = 0b0100_0000_0000_0000;
    const castle_flag_bits: u16 = 0b1000_0000_0000_0000;

    const Self = @This();

    data: LittleEndian(u16),

    const MoveFlags = enum(u16) {
        Promotion = promo_flag_bits,
        EnPassant = ep_flag_bits,
        Castle = castle_flag_bits,
    };

    pub fn raw(self: Self) u16 {
        return self.data.toNative();
    }

    pub fn newWithPromo(from_: Square, to_: Square, promotion: PieceType) Self {
        const promotion_int = promotion.toInt() - 1;
        return .{ .data = .fromNative(@as(u16, from_.toInt()) | @as(u16, to_.toInt()) << 6 | @as(u16, promotion_int) << 12 | promo_flag_bits) };
    }

    pub fn newWithFlags(from_: Square, to_: Square, flags: MoveFlags) Self {
        return .{ .data = .fromNative(@as(u16, from_.toInt()) | @as(u16, to_.toInt()) << 6 | @intFromEnum(flags)) };
    }

    pub fn new(from_: Square, to_: Square) Self {
        return .{ .data = .fromNative(@as(u16, from_.toInt()) | @as(u16, to_.toInt()) << 6) };
    }

    pub fn isPromo(self: Self) bool {
        return self.raw() & promo_flag_bits == promo_flag_bits;
    }

    pub fn isEp(self: Self) bool {
        return self.raw() & ep_flag_bits == ep_flag_bits;
    }

    pub fn isCastle(self: Self) bool {
        return self.raw() & castle_flag_bits == castle_flag_bits;
    }

    pub fn from(self: Self) Square {
        return @enumFromInt(self.raw() & 0b111111);
    }

    pub fn to(self: Self) Square {
        return @enumFromInt(self.raw() >> 6 & 0b111111);
    }

    pub fn fromMove(move: Move) Self {
        if (move.tp() == .castling) return newWithFlags(move.from(), move.to(), .Castle);
        if (move.tp() == .ep) return newWithFlags(move.from(), move.to(), .EnPassant);
        if (move.tp() == .promotion) return newWithPromo(move.from(), move.to(), move.promoType());
        return new(move.from(), move.to());
    }

    pub fn toMove(self: Self, board: anytype) Move {
        if (self.isPromo()) {
            const promo_type = PieceType.fromInt(@intCast(1 + ((self.raw() & ~promo_flag_bits) >> 12)));
            return Move.promo(self.from(), self.to(), promo_type);
        }
        if (self.isCastle()) {
            if (self.from().toInt() < self.to().toInt()) {
                return Move.castlingKingside(board.stm, self.from(), self.to());
            } else {
                return Move.castlingQueenside(board.stm, self.from(), self.to());
            }
        }
        if (self.isEp()) {
            return Move.enPassant(self.from(), self.to());
        }
        const is_capture = board.pieceOn(self.to()) != null;
        if (is_capture) {
            return Move.capture(self.from(), self.to());
        } else {
            return Move.quiet(self.from(), self.to());
        }
    }
};

pub const MoveEvalPair = extern struct {
    move: ViriMove,
    eval: LittleEndian(i16),
};

pub const ScoredPlyReader = struct {
    reader: *std.Io.Reader,

    pub const GameView = struct {
        reader: *std.Io.Reader,
        board: LeanBoard,
        outcome: WDL,

        pub fn iter(self: @This()) Iter {
            return .{
                .reader = self.reader,
                .board = self.board,
            };
        }
    };

    pub const Iter = struct {
        reader: *std.Io.Reader,
        board: LeanBoard,
        pending: ?Move = null,
        exhausted: bool = false,

        pub fn next(self: *Iter) !?dataformat.ScoredPly {
            return self.nextHandle(root.evaluation.noHandle());
        }

        pub fn nextHandle(self: *Iter, eval_state: anytype) !?dataformat.ScoredPly {
            if (self.exhausted) {
                return null;
            }

            if (self.pending) |move| {
                if (self.board.halfmove == std.math.maxInt(u8)) {
                    return error.HalfmoveOverflow;
                }
                if (self.board.pieceOn(move.from()) == null) {
                    return error.MoveNotLegal;
                }
                switch (self.board.stm) {
                    inline else => |stm| Board.makeMoveCommon(&self.board, stm, move, eval_state),
                }
                if (self.board.kingFor(.white) == 0 or
                    self.board.kingFor(.black) == 0 or
                    self.board.pawns() & 0xff000000000000ff != 0)
                {
                    return error.MoveNotLegal;
                }
            }

            const pair_bytes = self.reader.takeArray(@sizeOf(MoveEvalPair)) catch |e| switch (e) {
                error.EndOfStream => return null,
                else => return e,
            };
            const move_eval_pair = std.mem.bytesToValue(MoveEvalPair, pair_bytes);

            if (move_eval_pair.move.raw() == 0) {
                self.exhausted = true;
                return null;
            }

            const move = move_eval_pair.move.toMove(&self.board);
            const eval = move_eval_pair.eval.toNative();
            self.pending = move;

            return .{
                .board = &self.board,
                .move = move,
                ._eval = eval,
            };
        }
    };

    pub fn next(self: *ScoredPlyReader) !?GameView {
        const header_bytes = self.reader.takeArray(@sizeOf(MarlinPackedBoard)) catch |e| switch (e) {
            error.EndOfStream => return null,
            else => return e,
        };
        const initial_position = std.mem.bytesToValue(MarlinPackedBoard, header_bytes);
        if (initial_position.wdl > 2) {
            return error.InvalidWdl;
        }

        const board = try initial_position.toLeanBoard();
        return .{
            .reader = self.reader,
            .board = board,
            .outcome = @enumFromInt(initial_position.wdl),
        };
    }

    pub fn deinit(self: *ScoredPlyReader) void {
        _ = self;
    }
};

pub fn scoredPlyReader(reader: *std.Io.Reader, allocator: std.mem.Allocator) ScoredPlyReader {
    _ = allocator;
    return .{
        .reader = reader,
    };
}

pub const GameRecord = struct {
    initial_position: MarlinPackedBoard,
    moves: std.array_list.Managed(MoveEvalPair),

    pub fn serializeInto(self: GameRecord, writer: *std.Io.Writer) !void {
        try writer.writeAll(std.mem.asBytes(&self.initial_position));
        for (self.moves.items) |move_eval_pair| {
            if (move_eval_pair.move.raw() == 0) {
                @panic("NULL MOVE IN GAME");
            }
            try writer.writeAll(std.mem.asBytes(&move_eval_pair));
        }
        try writer.writeAll(&(.{0} ** @sizeOf(MoveEvalPair)));
    }

    pub fn bytesRequiredToSerialize(self: GameRecord) usize {
        return @sizeOf(MarlinPackedBoard) + @sizeOf(MoveEvalPair) * (1 + self.moves.items.len);
    }

    /// WDL has to be from whites perspective
    /// if white won its .win
    /// if black won its .loss
    pub fn setOutCome(self: *GameRecord, wdl: WDL) void {
        self.initial_position.wdl = wdl.toInt();
    }

    pub fn reset(self: *GameRecord, board: anytype) void {
        self.initial_position = .from(board, 1, 0);
        self.moves.clearRetainingCapacity();
    }

    pub fn from(board: anytype, allocator: Allocator) GameRecord {
        return GameRecord{
            .initial_position = .from(board, 1, 0),
            .moves = .init(allocator),
        };
    }

    pub fn deinit(self: GameRecord) void {
        self.moves.deinit();
    }

    /// score has to be from whites perspective
    pub fn addMove(self: *GameRecord, move: Move, score: i16) !void {
        try self.moves.append(MoveEvalPair{
            .eval = LittleEndian(i16).fromNative(score),
            .move = ViriMove.fromMove(move),
        });
    }
};

comptime {
    std.debug.assert(@sizeOf(MarlinPackedBoard) == 32);
    std.debug.assert(@bitSizeOf(MarlinPackedBoard) == 32 * 8);
}
