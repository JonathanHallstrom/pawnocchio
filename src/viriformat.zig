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
const Move = root.Move;
const Colour = root.Colour;
const Rank = root.Rank;
const File = root.File;
const WDL = root.WDL;
const CastlingRights = root.CastlingRights;

fn LittleEndian(comptime T: type) type {
    return packed struct {
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

    pub fn toBoard(self: MarlinPackedBoard) !Board {
        var res: Board = .{};

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
                else => undefined,
            };
            switch (col) {
                inline else => |ccol| res.addPiece(ccol, pt, sq, Board.NullEvalState{}),
            }
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
                rights_flag |= CastlingRights.white_kingside_castle;
            } else {
                white_queenside_file = sq.getFile();
                rights_flag |= CastlingRights.white_queenside_castle;
            }
        }
        iter = Bitboard.iterator(black_castling_rooks);
        while (iter.next()) |sq| {
            const king = Square.fromBitboard(res.kingFor(.black));

            if (king.getFile().toInt() < sq.getFile().toInt()) {
                black_kingside_file = sq.getFile();
                rights_flag |= CastlingRights.black_kingside_castle;
            } else {
                black_queenside_file = sq.getFile();
                rights_flag |= CastlingRights.black_queenside_castle;
            }
        }

        res.castling_rights = .initFromParts(
            rights_flag,
            white_kingside_file orelse .a,
            black_kingside_file orelse .a,
            white_queenside_file orelse .h,
            black_queenside_file orelse .h,
        );
        if (res.kingFor(.white) & first == 0 and rights_flag & (CastlingRights.white_kingside_castle | CastlingRights.white_queenside_castle) != 0) {
            return error.KingOnWrongRankAndCanCastle;
        }
        if (res.kingFor(.white) & last == 0 and rights_flag & (CastlingRights.black_kingside_castle | CastlingRights.black_queenside_castle) != 0) {
            return error.KingOnWrongRankAndCanCastle;
        }

        const ep_target = self.stm_ep_square & 0b0111_1111;
        res.ep_target = if (ep_target < 64) Square.fromInt(ep_target) else null;
        if (ep_target < 64 and (ep_target < 16 or ep_target > 48)) {
            return error.InvalidEpSquare;
        }
        res.stm = if (self.stm_ep_square & 0b1000_0000 == 0) .white else .black;
        res.halfmove = self.halfmove_clock;
        res.fullmove = self.fullmove_number.toNative();
        res.updateMasks(res.stm);
        res.resetHash();

        return res;
    }

    pub fn from(board: Board, loss_draw_win: u8, score: i16) MarlinPackedBoard {
        const occ = board.white | board.black;
        var pieces: [16]u8 = .{0} ** 16;
        {
            var i: usize = 0;
            var iter = Bitboard.iterator(occ);
            while (iter.next()) |sq| : (i += 1) {
                const piece_type = board.pieceOn(sq).?;
                const side: Colour = if (Bitboard.contains(board.white, sq)) .white else .black;
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
            .occupancy = LittleEndian(u64).fromNative(board.white | board.black),
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

pub const ViriMove = struct {
    const promo_flag_bits: u16 = 0b1100_0000_0000_0000;
    const ep_flag_bits: u16 = 0b0100_0000_0000_0000;
    const castle_flag_bits: u16 = 0b1000_0000_0000_0000;

    const Self = @This();

    data: u16,

    const MoveFlags = enum(u16) {
        Promotion = promo_flag_bits,
        EnPassant = ep_flag_bits,
        Castle = castle_flag_bits,
    };

    pub fn newWithPromo(from_: Square, to_: Square, promotion: PieceType) Self {
        const promotion_int = promotion.toInt() - 1;
        return .{ .data = @as(u16, from_.toInt()) | @as(u16, to_.toInt()) << 6 | @as(u16, promotion_int) << 12 | promo_flag_bits };
    }

    pub fn newWithFlags(from_: Square, to_: Square, flags: MoveFlags) Self {
        return .{ .data = @as(u16, from_.toInt()) | @as(u16, to_.toInt()) << 6 | @intFromEnum(flags) };
    }

    pub fn new(from_: Square, to_: Square) Self {
        return .{ .data = @as(u16, from_.toInt()) | @as(u16, to_.toInt()) << 6 };
    }

    pub fn isPromo(self: Self) bool {
        return self.data & promo_flag_bits == promo_flag_bits;
    }

    pub fn isEp(self: Self) bool {
        return self.data & ep_flag_bits == ep_flag_bits;
    }

    pub fn isCastle(self: Self) bool {
        return self.data & castle_flag_bits == castle_flag_bits;
    }

    pub fn from(self: Self) Square {
        return @enumFromInt(self.data & 0b111111);
    }

    pub fn to(self: Self) Square {
        return @enumFromInt(self.data >> 6 & 0b111111);
    }

    pub fn fromMove(move: Move) Self {
        if (move.tp() == .castling) return newWithFlags(move.from(), move.to(), .Castle);
        if (move.tp() == .ep) return newWithFlags(move.from(), move.to(), .EnPassant);
        if (move.tp() == .promotion) return newWithPromo(move.from(), move.to(), move.promoType());
        return new(move.from(), move.to());
    }

    // pub fn toMove(self: Self, board: *const Board) Move {
    //     var moves = root.movegen.MoveListReceiver{};
    //     root.movegen.generateAll(board, &moves);
    //
    //     var correct: Move = .init();
    //     for (moves.vals.slice()) |move| {
    //         if (ViriMove.fromMove(move).data == self.data) {
    //             correct = move;
    //         }
    //     }
    //     const res = self.toMoveImpl(board);
    //
    //     if (res != correct) {
    //         std.debug.print("{s} {s} {s}\n", .{ board.toFen().slice(), res.toString(board).slice(), correct.toString(board).slice() });
    //     }
    //     return res;
    // }
    pub fn toMove(self: Self, board: *const Board) Move {
        if (self.isPromo()) {
            const promo_type = PieceType.fromInt(@intCast(1 + ((self.data & ~promo_flag_bits) >> 12)));
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

pub const MoveEvalPair = struct {
    move: ViriMove,
    eval: LittleEndian(i16),
};

pub const Game = struct {
    initial_position: MarlinPackedBoard,
    moves: std.array_list.Managed(MoveEvalPair),

    pub fn serializeInto(self: Game, writer: *std.Io.Writer) !void {
        // std.debug.print("{any}\n", .{std.mem.asBytes(&self.initial_position)});
        try writer.writeAll(std.mem.asBytes(&self.initial_position));
        for (self.moves.items) |move_eval_pair| {
            // std.debug.print("{} {}\n", .{ Square.fromInt(@intCast(move_eval_pair.move.data % (1 << 6))), Square.fromInt(@intCast((move_eval_pair.move.data >> 6) % (1 << 6))) });
            if (move_eval_pair.move.data == 0) {
                @panic("NULL MOVE IN GAME");
                // break;
            }
            try writer.writeAll(std.mem.asBytes(&std.mem.nativeToLittle(u16, move_eval_pair.move.data)));
            try writer.writeAll(std.mem.asBytes(&move_eval_pair.eval.val));
        }
        try writer.writeAll(&(.{0} ** @sizeOf(MoveEvalPair)));
    }

    pub fn bytesRequiredToSerialize(self: Game) usize {
        return @sizeOf(MarlinPackedBoard) + @sizeOf(MoveEvalPair) * (1 + self.moves.items.len);
    }

    /// WDL has to be from whites perspective
    /// if white won its .win
    /// if black won its .loss
    pub fn setOutCome(self: *Game, wdl: WDL) void {
        self.initial_position.wdl = wdl.toInt();
    }

    pub fn reset(self: *Game, board: Board) void {
        self.initial_position = .from(board, 1, 0);
        self.moves.clearRetainingCapacity();
    }

    pub fn from(board: Board, allocator: Allocator) Game {
        return Game{
            .initial_position = .from(board, 1, 0),
            .moves = .init(allocator),
        };
    }

    fn deinit(self: Game) void {
        self.moves.deinit();
    }

    /// score has to be from whites perspective
    pub fn addMove(self: *Game, move: Move, score: i16) !void {
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

fn viriformatTest(fen: []const u8, move: Move, expected: u32) !void {
    var game = Game.from(try Board.parseFen(fen, true), std.testing.allocator);
    defer game.deinit();
    try game.addMove(move, 0);
    var buf: [40]u8 = undefined;
    var fbs = std.Io.Writer.fixed(&buf);
    try game.serializeInto(&fbs);
    try std.testing.expectEqual(expected, std.mem.readInt(u32, fbs.buffered()[32..][0..4], .little));
}

test "viriformat moves" {
    root.init();
    try viriformatTest("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Move.quiet(.e2, .e4), 0x070c);
    try viriformatTest("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1", Move.castlingKingside(.white, .e1, .h1), 0x81c4);
    try viriformatTest("8/6P1/8/8/1k6/4K3/8/8 w - - 0 1", Move.promo(.g7, .g8, .queen), 0xffb6);
    try viriformatTest("rnbqkbnr/2pppppp/p7/Pp6/8/8/1PPPPPPP/RNBQKBNR w KQkq b6 0 1", Move.enPassant(.a5, .b6), 0x4a60);
}

test "all edge cases i could think of in one position" {
    root.init();
    var game = Game.from(try Board.parseFen("4k3/P4p2/8/6P1/8/8/8/R3K2R w Q - 0 1", false), std.testing.allocator);
    defer game.deinit();
    try game.addMove(Move.castlingQueenside(.white, .e1, .a1), 0);
    try game.addMove(Move.quiet(.f7, .f5), 0);
    try game.addMove(Move.enPassant(.g5, .f6), 0);
    try game.addMove(Move.quiet(.e8, .f8), 0);
    try game.addMove(Move.promo(.a7, .a8, .queen), 0);

    var buf: [64]u8 = undefined;
    var fbs = std.Io.Writer.fixed(&buf);
    try game.serializeInto(&fbs);

    // var file = try std.fs.cwd().createFile("tmp.bin", .{});
    // defer file.close();
    // try file.writeAll(fbs.getWritten());

    try std.testing.expectEqualSlices(u8, &.{ 145, 0, 0, 0, 64, 0, 33, 16, 86, 3, 128, 13, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 1, 0, 0, 0, 1, 164, 4, 128, 0, 0, 117, 9, 0, 0, 102, 75, 0, 0, 124, 15, 0, 0, 48, 254, 0, 0, 0, 0, 0, 0 }, fbs.buffered());
}

test {
    const board_original = Board.startpos();

    const marlin_board = MarlinPackedBoard.from(board_original, 1, 0);

    const round_trip = marlin_board.toBoard();

    try std.testing.expectEqualDeep(board_original, round_trip);
}
