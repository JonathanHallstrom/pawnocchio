const std = @import("std");
const assert = std.debug.assert;

pub const Row = enum(u8) {
    _,

    pub inline fn init(int: anytype) !Row {
        if (int >= 8) return error.OutOfRange;
        return @enumFromInt(int);
    }

    pub inline fn toInt(self: @This()) u6 {
        const res: u8 = @intFromEnum(self);
        assert(res < 8);
        return @intCast(res);
    }
};

pub const Col = enum(u8) {
    _,

    pub inline fn init(int: anytype) !Col {
        if (int >= 8) return error.OutOfRange;
        return @enumFromInt(int);
    }

    pub inline fn toInt(self: @This()) u6 {
        const res: u8 = @intFromEnum(self);
        assert(res < 8);
        return @intCast(res);
    }
};

pub const Side = enum {
    black,
    white,

    pub fn flipped(self: Side) Side {
        return if (self == .white) .black else .white;
    }
};

pub const BitBoard = enum(u64) {
    _,

    const Self = @This();

    pub inline fn toInt(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub inline fn init(value: u64) BitBoard {
        return @enumFromInt(value);
    }

    pub inline fn fromSquare(square: []const u8) !BitBoard {
        if (square.len != 2) return error.InvalidSquare;
        const col = std.ascii.toLower(square[0]);
        const row = std.ascii.toLower(square[1]);
        return init(getSquare(try Row.init(row -% '1'), try Col.init(col -% 'a')));
    }

    pub inline fn fromSquareUnchecked(square: []const u8) BitBoard {
        return fromSquare(square) catch unreachable;
    }

    pub inline fn initEmpty() BitBoard {
        return init(0);
    }

    pub inline fn isEmpty(self: Self) bool {
        return self == initEmpty();
    }

    pub inline fn set(self: *Self, row: Row, col: Col) !void {
        if (self.get(row, col)) return error.AlreadySet;
        self.setUnchecked(row, col);
    }

    pub inline fn setUnchecked(self: *Self, row: Row, col: Col) void {
        self.* = init(self.toInt() | getSquare(row, col));
    }

    pub inline fn get(self: Self, row: Row, col: Col) bool {
        return self.toInt() & getSquare(row, col) != 0;
    }

    // gives bitboard of all the values that are in either `self` or `other`
    pub inline fn getCombination(self: Self, other: BitBoard) BitBoard {
        return init(self.toInt() | other.toInt());
    }

    // gives bitboard of all the values that are in both `self` and `other`
    pub inline fn getOverlap(self: Self, other: BitBoard) BitBoard {
        return init(self.toInt() & other.toInt());
    }

    // gives bitboard of all the values that are in both `self` and `other`
    pub inline fn getOverlapNonEmpty(self: Self, other: BitBoard) ?BitBoard {
        const res = self.toInt() & other.toInt();
        return if (res != 0) init(res) else null;
    }

    pub inline fn overlaps(self: Self, other: BitBoard) bool {
        return self.getOverlap(other).toInt() != 0;
    }

    // adds in all the set squares from `other` to `self`
    pub inline fn add(self: *Self, other: BitBoard) void {
        self.* = self.getCombination(other);
    }

    pub inline fn complement(self: Self) BitBoard {
        return init(~self.toInt());
    }

    inline fn getSquare(row: Row, col: Col) u64 {
        return @as(u64, 1) << (8 * row.toInt() + col.toInt());
    }

    pub inline fn flipped(self: Self) BitBoard {
        return init(@byteSwap(self.toInt()));
    }

    pub inline fn iterator(self: Self) PieceIterator {
        return PieceIterator.init(self);
    }

    pub inline fn forward(self: Self, steps: u6) BitBoard {
        assert(@popCount(self.toInt()) <= 1);
        return self.forwardMasked(steps);
    }

    pub inline fn forwardMasked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() << 8 * steps);
    }

    pub inline fn forwardUnchecked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() << 8 * steps);
    }

    pub inline fn backward(self: Self, steps: u6) BitBoard {
        assert(@popCount(self.toInt()) <= 1);
        return self.backwardMasked(steps);
    }

    pub inline fn backwardMasked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() >> 8 * steps);
    }

    pub inline fn backwardUnchecked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() >> 8 * steps);
    }

    pub inline fn left(self: Self, steps: u6) BitBoard {
        assert(@popCount(self.toInt()) <= 1);
        return self.leftMasked(steps);
    }

    pub inline fn leftMasked(self: Self, steps: u6) BitBoard {
        const mask = @as(u64, @as(u8, 255) >> @intCast(steps)) * (std.math.maxInt(u64) / 255);
        return init(self.toInt() >> steps & mask);
    }

    pub inline fn leftUnchecked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() >> steps);
    }

    pub inline fn right(self: Self, steps: u6) BitBoard {
        assert(@popCount(self.toInt()) <= 1);
        return self.rightMasked(steps);
    }

    pub inline fn rightMasked(self: Self, steps: u6) BitBoard {
        const mask = @as(u64, @as(u8, 255) << @intCast(steps)) * (std.math.maxInt(u64) / 255);
        return init(self.toInt() << steps & mask);
    }

    pub inline fn rightUnchecked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() << steps);
    }

    pub inline fn move(self: Self, dr: anytype, dc: anytype) BitBoard {
        assert(-7 <= dr and dr <= 7);
        assert(-7 <= dc and dc <= 7);
        var res = self;
        res = if (dr < 0) res.backwardMasked(@abs(dr)) else res.forwardMasked(dr);
        res = if (dc < 0) res.leftMasked(@abs(dc)) else res.rightMasked(dc);
        return res;
    }

    pub inline fn moveUnchecked(self: Self, dr: anytype, dc: anytype) BitBoard {
        var res = self;
        res = if (dr < 0) res.backwardUnchecked(@abs(dr)) else res.forwardUnchecked(dr);
        res = if (dc < 0) res.leftUnchecked(@abs(dc)) else res.rightUnchecked(dc);
        return res;
    }

    comptime {
        assert(fromSquareUnchecked("A1").forward(1) == fromSquareUnchecked("A2"));
        assert(fromSquareUnchecked("B1").forward(4) == fromSquareUnchecked("B5"));

        assert(fromSquareUnchecked("A2").backward(1) == fromSquareUnchecked("A1"));
        assert(fromSquareUnchecked("B5").backward(4) == fromSquareUnchecked("B1"));

        assert(fromSquareUnchecked("B1").left(1) == fromSquareUnchecked("A1"));
        assert(fromSquareUnchecked("H1").left(4) == fromSquareUnchecked("D1"));

        assert(fromSquareUnchecked("A1").right(1) == fromSquareUnchecked("B1"));
        assert(fromSquareUnchecked("D1").right(4) == fromSquareUnchecked("H1"));

        assert(fromSquareUnchecked("D8").forward(1).isEmpty());
        assert(fromSquareUnchecked("D1").backward(1).isEmpty());
        assert(fromSquareUnchecked("A4").left(1).isEmpty());
        assert(fromSquareUnchecked("H4").right(1).isEmpty());
    }

    pub fn allForward(self: Self) BitBoard {
        var res = self;
        res.add(res.forwardUnchecked(1));
        res.add(res.forwardUnchecked(2));
        res.add(res.forwardUnchecked(4));
        return res;
    }

    pub fn allBackward(self: Self) BitBoard {
        var res = self;
        res.add(res.backwardUnchecked(1));
        res.add(res.backwardUnchecked(2));
        res.add(res.backwardUnchecked(4));
        return res;
    }

    pub fn allLeft(self: Self) BitBoard {
        var res = self;
        res.add(res.leftUnchecked(1).getOverlap(BitBoard.init(0b01111111 * (std.math.maxInt(u64) / 255))));
        res.add(res.leftUnchecked(2).getOverlap(BitBoard.init(0b00111111 * (std.math.maxInt(u64) / 255))));
        res.add(res.leftUnchecked(4).getOverlap(BitBoard.init(0b00001111 * (std.math.maxInt(u64) / 255))));
        return init(res.toInt());
    }

    pub fn allRight(self: Self) BitBoard {
        var res = self;
        res.add(res.rightUnchecked(1).getOverlap(BitBoard.init(0b11111110 * (std.math.maxInt(u64) / 255))));
        res.add(res.rightUnchecked(2).getOverlap(BitBoard.init(0b11111100 * (std.math.maxInt(u64) / 255))));
        res.add(res.rightUnchecked(4).getOverlap(BitBoard.init(0b11110000 * (std.math.maxInt(u64) / 255))));
        return init(res.toInt());
    }

    pub fn prettyPrint(self: Self) void {
        for (0..8) |i| {
            std.debug.print("{b:0>8}\n", .{self.toInt() >> @intCast(8 * i) & 255});
        }
    }

    comptime {
        assert(BitBoard.fromSquareUnchecked("A8").allForward() == BitBoard.fromSquareUnchecked("A8"));
        assert(BitBoard.fromSquareUnchecked("A1").allForward() == blk: {
            var res = BitBoard.initEmpty();
            for (.{ "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8" }) |sqr| {
                res.add(BitBoard.fromSquareUnchecked(sqr));
            }
            break :blk res;
        });

        assert(BitBoard.fromSquareUnchecked("A1").allBackward() == BitBoard.fromSquareUnchecked("A1"));
        assert(BitBoard.fromSquareUnchecked("A8").allBackward() == blk: {
            var res = BitBoard.initEmpty();
            for (.{ "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8" }) |sqr| {
                res.add(BitBoard.fromSquareUnchecked(sqr));
            }
            break :blk res;
        });

        assert(BitBoard.fromSquareUnchecked("A1").allLeft() == BitBoard.fromSquareUnchecked("A1"));
        assert(BitBoard.fromSquareUnchecked("H1").allLeft() == blk: {
            var res = BitBoard.initEmpty();
            for (.{ "A1", "B1", "C1", "D1", "E1", "F1", "G1", "H1" }) |sqr| {
                res.add(BitBoard.fromSquareUnchecked(sqr));
            }
            break :blk res;
        });

        assert(BitBoard.fromSquareUnchecked("H1").allRight() == BitBoard.fromSquareUnchecked("H1"));
        assert(BitBoard.fromSquareUnchecked("A1").allRight() == blk: {
            var res = BitBoard.initEmpty();
            for (.{ "A1", "B1", "C1", "D1", "E1", "F1", "G1", "H1" }) |sqr| {
                res.add(BitBoard.fromSquareUnchecked(sqr));
            }
            break :blk res;
        });
    }

    pub const PieceIterator = struct {
        data: u64,

        pub fn init(b: BitBoard) PieceIterator {
            return .{ .data = b.toInt() };
        }

        pub fn next(self: *PieceIterator) ?BitBoard {
            const res = self.data & -%self.data;
            self.data ^= res;
            return if (res == 0) null else BitBoard.init(res);
        }

        pub fn peek(self: *const PieceIterator) ?BitBoard {
            return if (self.data == 0) null else BitBoard.init(self.data & -self.data);
        }
    };
};

pub const PieceType = enum(u8) {
    pawn = 0,
    knight = 1,
    bishop = 2,
    rook = 3,
    queen = 4,
    king = 5,

    pub fn format(self: PieceType, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = actual_fmt;
        _ = options;
        return try writer.print("{s}", .{@tagName(self)});
    }
};

pub const Piece = struct {
    tp: PieceType,
    board: BitBoard,

    pub fn init(tp: PieceType, b: BitBoard) Piece {
        assert(@popCount(b.toInt()) == 1);
        return .{
            .tp = tp,
            .board = b,
        };
    }

    pub fn pawnFromBitBoard(b: BitBoard) Piece {
        return init(.pawn, b);
    }

    pub fn knightFromBitBoard(b: BitBoard) Piece {
        return init(.knight, b);
    }

    pub fn bishopFromBitBoard(b: BitBoard) Piece {
        return init(.bishop, b);
    }

    pub fn rookFromBitBoard(b: BitBoard) Piece {
        return init(.rook, b);
    }

    pub fn queenFromBitBoard(b: BitBoard) Piece {
        return init(.queen, b);
    }

    pub fn kingFromBitBoard(b: BitBoard) Piece {
        return init(.king, b);
    }

    pub fn format(self: Piece, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = actual_fmt;
        _ = options;
        const pos = @ctz(self.board.toInt());
        const row = @as(u8, pos / 8) + '1';
        const col = @as(u8, pos % 8) + 'A';
        return try writer.print("({s} on {c}{c})", .{ @tagName(self.tp), col, row });
    }

    pub fn getType(self: Piece) PieceType {
        return self.tp;
    }

    pub fn getBoard(self: Piece) BitBoard {
        return self.board;
    }

    fn flipPos(pos: u6) u6 {
        const row = pos / 8;
        const col = pos % 8;
        const new_row = 7 - row;
        return 8 * new_row + col;
    }
    comptime {
        for (0..64) |i| {
            assert(@byteSwap(@as(u64, 1) << i) == @as(u64, 1) << flipPos(i));
        }
    }

    pub fn flipped(self: Piece) Piece {
        return .{
            .tp = self.tp,
            .board = self.board.flipped(),
        };
    }
};

comptime {
    assert(@sizeOf(PieceType) == 1);
}

pub const Move = struct {
    from: Piece,
    to: Piece,
    captured: ?Piece,

    pub fn init(from: Piece, to: Piece, captured: ?Piece) Move {
        return .{
            .from = from,
            .to = to,
            .captured = captured,
        };
    }

    pub fn initQuiet(from: Piece, to: Piece) Move {
        return .{
            .from = from,
            .to = to,
            .captured = null,
        };
    }

    pub fn initCapture(from: Piece, to: Piece, captured: Piece) Move {
        return .{
            .from = from,
            .to = to,
            .captured = captured,
        };
    }

    pub fn format(self: Move, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = actual_fmt;
        _ = options;
        if (self.captured) |cap| {
            return try writer.print("(move {} to {} capturing {})", .{ self.from, self.to, cap });
        } else {
            return try writer.print("(move {} to {})", .{ self.from, self.to });
        }
    }

    pub fn flipped(self: Move) Move {
        return .{
            .from = self.from.flipped(),
            .to = self.to.flipped(),
            .captured = if (self.captured) |c| c.flipped() else null,
        };
    }
};

pub const Board = struct {
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

    const PieceSet = packed struct {
        pawn: BitBoard = BitBoard.initEmpty(),
        knight: BitBoard = BitBoard.initEmpty(),
        bishop: BitBoard = BitBoard.initEmpty(),
        rook: BitBoard = BitBoard.initEmpty(),
        queen: BitBoard = BitBoard.initEmpty(),
        king: BitBoard = BitBoard.initEmpty(),

        // kinda ugly but makes for much better assembly than the naive implementation
        // https://godbolt.org/z/se5zaWv5r
        fn getBoard(self: *const PieceSet, pt: PieceType) BitBoard {
            const base: [*]const BitBoard = @ptrCast(self);
            const offset: usize = switch (pt) {
                inline else => |tp| @offsetOf(PieceSet, @tagName(tp)),
            };
            return base[offset / @sizeOf(BitBoard)];
        }

        fn getBoardPtr(self: *PieceSet, pt: PieceType) *BitBoard {
            const base: [*]BitBoard = @ptrCast(self);
            const offset: usize = switch (pt) {
                inline else => |tp| @offsetOf(PieceSet, @tagName(tp)),
            };
            return &base[offset / @sizeOf(BitBoard)];
        }

        fn addPieceFen(self: *PieceSet, which: u8, row: Row, col: Col) !void {
            const board: *BitBoard = switch (std.ascii.toLower(which)) {
                'p' => &self.pawn,
                'n' => &self.knight,
                'b' => &self.bishop,
                'r' => &self.rook,
                'q' => &self.queen,
                'k' => &self.king,
                else => return error.InvalidCharacter,
            };
            try board.set(row, col);
        }

        fn flipped(self: PieceSet) PieceSet {
            return .{
                .pawn = self.pawn.flipped(),
                .knight = self.knight.flipped(),
                .bishop = self.bishop.flipped(),
                .rook = self.rook.flipped(),
                .queen = self.queen.flipped(),
                .king = self.king.flipped(),
            };
        }

        fn all(self: PieceSet) BitBoard {
            var res = self.pawn;
            res.add(self.knight);
            res.add(self.bishop);
            res.add(self.rook);
            res.add(self.queen);
            res.add(self.king);
            return res;
        }

        fn whichType(self: PieceSet, needle: BitBoard) PieceType {
            inline for (.{
                .pawn,
                .knight,
                .bishop,
                .rook,
                .queen,
                .king,
            }) |e| {
                if (@field(self, @tagName(e)).overlaps(needle)) {
                    return e;
                }
            }
            unreachable;
        }
    };

    white: PieceSet = .{},
    black: PieceSet = .{},

    turn: Side = .white,
    // if u can castle queenside as white `C1` will be set
    castling_squares: BitBoard = BitBoard.initEmpty(),
    en_passant_target: BitBoard = BitBoard.initEmpty(),

    halfmove_clock: u8 = 0,
    fullmove_clock: u64 = 1,

    const queenside_white_castle = BitBoard.fromSquareUnchecked("C1");
    const kingside_white_castle = BitBoard.fromSquareUnchecked("G1");
    const queenside_black_castle = BitBoard.fromSquareUnchecked("C8");
    const kingside_black_castle = BitBoard.fromSquareUnchecked("G8");

    comptime {
        assert(queenside_white_castle == queenside_black_castle.flipped());
        assert(kingside_white_castle == kingside_black_castle.flipped());
    }

    const Self = @This();

    pub fn fromFenUnchecked(fen: []const u8) Self {
        return fromFen(fen) catch unreachable;
    }

    pub fn fromFen(fen: []const u8) !Self {
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
                    try res.black.addPieceFen(ch, try Row.init(r), try Col.init(c));
                    c += 1;
                } else if (std.ascii.isUpper(ch)) {
                    try res.white.addPieceFen(ch, try Row.init(r), try Col.init(c));
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
        if (castling_string.len > 4) return error.CastlingStringTooBig;
        if (!std.mem.eql(u8, "-", castling_string)) {
            for (castling_string) |castle_ch| {
                res.castling_squares.add(switch (castle_ch) {
                    'Q' => queenside_white_castle,
                    'q' => queenside_black_castle,
                    'K' => kingside_white_castle,
                    'k' => kingside_black_castle,
                    else => return error.InvalidCharacter,
                });
            }
        }

        const en_passant_target_square_string = iter.next() orelse return error.MissingEnPassantTarget;
        if (std.mem.eql(u8, en_passant_target_square_string, "-")) {
            res.en_passant_target = BitBoard.initEmpty();
        } else {
            const correct_row: u8 = if (res.turn == .white) '6' else '3';
            if (en_passant_target_square_string.len != 2 or
                en_passant_target_square_string[1] != correct_row)
                return error.InvalidEnPassantTarget;
            const board = try BitBoard.fromSquare(en_passant_target_square_string);
            const should_overlap = if (res.turn == .white) res.black.pawn.forward(1) else res.white.pawn.backward(1);
            if (!board.overlaps(should_overlap)) return error.EnPassantTargetDoesntExist;
            res.en_passant_target = board;
        }

        const halfmove_clock_string = iter.next() orelse return error.MissingHalfMoveClock;
        res.halfmove_clock = try std.fmt.parseInt(u8, halfmove_clock_string, 10);
        const fullmove_clock_str = iter.next() orelse return error.MissingFullMoveClock;
        const fullmove = try std.fmt.parseInt(u64, fullmove_clock_str, 10);
        if (fullmove == 0)
            return error.InvalidFullMove;
        res.fullmove_clock = fullmove;

        return res;
    }

    pub fn flipped(self: Self) Board {
        return Board{
            .white = self.white.flipped(),
            .black = self.black.flipped(),
            .en_passant_target = self.en_passant_target.flipped(),
            .castling_squares = self.castling_squares.flipped(),
            .turn = self.turn,
            .halfmove_clock = self.halfmove_clock,
            .fullmove_clock = self.fullmove_clock,
        };
    }

    pub fn toString(self: Self) [8][8]u8 {
        var res: [8][8]u8 = .{.{' '} ** 8} ** 8;
        for (0..8) |r| {
            for (0..8) |c| {
                if (self.white.pawn.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'P';
                if (self.black.pawn.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'p';

                if (self.white.knight.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'N';
                if (self.black.knight.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'n';

                if (self.white.bishop.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'B';
                if (self.black.bishop.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'b';

                if (self.white.rook.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'R';
                if (self.black.rook.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'r';

                if (self.white.queen.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'Q';
                if (self.black.queen.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'q';

                if (self.white.king.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'K';
                if (self.black.king.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'k';
            }
        }
        return res;
    }

    pub fn playMove(self: *Self, move: Move) !void {
        const moved_side = if (self.turn == .white) &self.white else &self.black;
        const from_board = moved_side.getBoardPtr(move.from.getType());
        assert(from_board.overlaps(move.from.getBoard()));
        from_board.* = from_board.getOverlap(move.from.getBoard().complement());
        const to_board = moved_side.getBoardPtr(move.to.getType());
        assert(!to_board.overlaps(move.to.getBoard()));
        to_board.* = to_board.getCombination(move.to.getBoard());
        if (move.captured) |cap| {
            const capture_side = if (self.turn == .white) &self.black else &self.white;
            const capture_board = capture_side.getBoardPtr(cap.getType());
            capture_board.* = capture_board.getOverlap(cap.getBoard().complement());
        }
        self.turn = self.turn.flipped();
    }

    pub fn undoMove(self: *Self, move: Move) !void {
        const moved_side = if (self.turn == .black) &self.white else &self.black;
        const from_board = moved_side.getBoardPtr(move.from.getType());
        assert(!from_board.overlaps(move.from.getBoard()));
        from_board.* = from_board.getCombination(move.from.getBoard());
        const to_board = moved_side.getBoardPtr(move.to.getType());
        assert(to_board.overlaps(move.to.getBoard()));
        to_board.* = to_board.getOverlap(move.to.getBoard().complement());
        if (move.captured) |cap| {
            const capture_side = if (self.turn == .black) &self.black else &self.white;
            const capture_board = capture_side.getBoardPtr(cap.getType());
            capture_board.* = capture_board.getCombination(cap.getBoard());
        }
        self.turn = self.turn.flipped();
    }

    pub fn getQuietPawnMoves(self: Self, move_buffer: []Move) usize {
        const should_flip = self.turn == .black;
        const pawns = if (should_flip) self.black.pawn.flipped() else self.white.pawn;
        if (pawns.isEmpty()) return 0;

        const own_pieces = if (should_flip) self.black.all().flipped() else self.white.all();
        const opponents_pieces = if (should_flip) self.white.all().flipped() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);

        var move_count: usize = 0;
        const allowed_squares = all_pieces.complement();

        const seventh_row = BitBoard.fromSquareUnchecked("A7").allRight();

        const pawns_that_can_move = pawns.forwardUnchecked(1).getOverlap(allowed_squares).backwardUnchecked(1);

        var promotion_pawns = pawns_that_can_move.getOverlap(seventh_row).iterator();
        while (promotion_pawns.next()) |pawn_to_promote| {
            for ([_]PieceType{ .knight, .bishop, .rook, .queen }) |piece_type| {
                move_buffer[move_count] = Move.initQuiet(Piece.pawnFromBitBoard(pawn_to_promote), Piece.init(piece_type, pawn_to_promote.forward(1)));
                move_count += 1;
            }
        }

        const second_row = BitBoard.fromSquareUnchecked("A2").allRight();
        var double_move_pawns = pawns_that_can_move.getOverlap(second_row).forwardUnchecked(2).getOverlap(allowed_squares).backwardUnchecked(2).iterator();
        while (double_move_pawns.next()) |pawn| {
            move_buffer[move_count] = Move.initQuiet(Piece.pawnFromBitBoard(pawn), Piece.pawnFromBitBoard(pawn.forward(2)));
            move_count += 1;
        }

        var last_pawns = pawns_that_can_move.getOverlap(seventh_row.complement()).iterator();
        while (last_pawns.next()) |pawn| {
            move_buffer[move_count] = Move.initQuiet(Piece.pawnFromBitBoard(pawn), Piece.pawnFromBitBoard(pawn.forward(1)));
            move_count += 1;
        }

        if (should_flip) {
            for (move_buffer[0..move_count]) |*move| {
                move.* = move.flipped();
            }
        }
        return move_count;
    }

    pub fn getPawnCaptures(self: Self, move_buffer: []Move) usize {
        const should_flip = self.turn == .black;
        const pawns = if (should_flip) self.black.pawn.flipped() else self.white.pawn;
        if (pawns.isEmpty()) return 0;
        const opponent_side = if (should_flip) self.white.flipped() else self.black;

        var move_count: usize = 0;
        const en_passant_target = if (should_flip) self.en_passant_target.flipped() else self.en_passant_target;
        const en_passant_pawn = en_passant_target.backward(1);
        for ([_]BitBoard{ en_passant_pawn.left(1), en_passant_pawn.right(1) }) |capturing_pawn| {
            if (pawns.overlaps(capturing_pawn)) {
                move_buffer[move_count] = Move.initCapture(
                    Piece.pawnFromBitBoard(capturing_pawn),
                    Piece.pawnFromBitBoard(en_passant_target),
                    Piece.pawnFromBitBoard(en_passant_pawn),
                );
                move_count += 1;
            }
        }
        for ([_]PieceType{
            .pawn,
            .knight,
            .bishop,
            .rook,
            .queen,
        }) |TargetPieceType| {
            const opponents_pieces = opponent_side.getBoard(TargetPieceType);

            const can_be_left_captures = BitBoard.fromSquareUnchecked("B7").allRight().allBackward();
            const can_be_right_captures = BitBoard.fromSquareUnchecked("G7").allLeft().allBackward();
            const forward_left_captures = pawns.getOverlap(can_be_left_captures).forwardUnchecked(1).leftUnchecked(1).getOverlap(opponents_pieces).rightUnchecked(1).backwardUnchecked(1);
            const forward_right_captures = pawns.getOverlap(can_be_right_captures).forwardUnchecked(1).rightUnchecked(1).getOverlap(opponents_pieces).leftUnchecked(1).backwardUnchecked(1);

            const seventh_row = BitBoard.fromSquareUnchecked("A7").allRight();
            var promote_captures_left = forward_left_captures.getOverlap(seventh_row).iterator();
            var promote_captures_right = forward_right_captures.getOverlap(seventh_row).iterator();
            while (promote_captures_left.next()) |from| {
                const to = from.forward(1).left(1);
                for ([_]PieceType{
                    .knight,
                    .bishop,
                    .rook,
                    .queen,
                }) |PromotionType| {
                    move_buffer[move_count] = Move.initCapture(
                        Piece.pawnFromBitBoard(from),
                        Piece.init(PromotionType, to),
                        Piece.init(TargetPieceType, to),
                    );
                    move_count += 1;
                }
            }
            while (promote_captures_right.next()) |from| {
                const to = from.forward(1).right(1);
                for ([_]PieceType{
                    .knight,
                    .bishop,
                    .rook,
                    .queen,
                }) |PromotionType| {
                    move_buffer[move_count] = Move.initCapture(
                        Piece.pawnFromBitBoard(from),
                        Piece.init(PromotionType, to),
                        Piece.init(TargetPieceType, to),
                    );
                    move_count += 1;
                }
            }

            var captures_left = forward_left_captures.getOverlap(seventh_row.complement()).iterator();
            var captures_right = forward_right_captures.getOverlap(seventh_row.complement()).iterator();
            while (captures_left.next()) |from| {
                const to = from.forward(1).left(1);
                move_buffer[move_count] = Move.initCapture(
                    Piece.pawnFromBitBoard(from),
                    Piece.pawnFromBitBoard(to),
                    Piece.init(TargetPieceType, to),
                );
                move_count += 1;
            }
            while (captures_right.next()) |from| {
                const to = from.forward(1).right(1);
                move_buffer[move_count] = Move.initCapture(
                    Piece.pawnFromBitBoard(from),
                    Piece.pawnFromBitBoard(to),
                    Piece.init(TargetPieceType, to),
                );
                move_count += 1;
            }
        }

        if (should_flip) {
            for (move_buffer[0..move_count]) |*move| {
                move.* = move.flipped();
            }
        }
        return move_count;
    }

    pub fn getQuietKnightMoves(self: Self, move_buffer: []Move) usize {
        const should_flip = self.turn == .black;
        const knights = if (should_flip) self.black.knight else self.white.knight;
        if (knights.isEmpty()) return 0;

        const own_pieces = if (should_flip) self.black.all() else self.white.all();
        const opponents_pieces = if (should_flip) self.white.all() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);

        var move_count: usize = 0;

        var iter = knights.iterator();
        while (iter.next()) |knight| {
            const row_offsets = [8]comptime_int{ 2, 2, -2, -2, 1, 1, -1, -1 };
            const col_offsets = [8]comptime_int{ 1, -1, 1, -1, 2, -2, 2, -2 };
            inline for (row_offsets, col_offsets) |dr, dc| {
                var moved = knight;
                moved = if (dr < 0) moved.backward(-dr) else moved.forward(dr);
                moved = if (dc < 0) moved.left(-dc) else moved.right(dc);
                if (!moved.overlaps(all_pieces) and !moved.isEmpty()) {
                    move_buffer[move_count] = Move.initQuiet(
                        Piece.knightFromBitBoard(knight),
                        Piece.knightFromBitBoard(moved),
                    );
                    move_count += 1;
                }
            }
        }
        return move_count;
    }

    pub fn getKnightCaptures(self: Self, move_buffer: []Move) usize {
        const is_black_turn = self.turn == .black;
        const knights = if (is_black_turn) self.black.knight else self.white.knight;
        if (knights.isEmpty()) return 0;

        const opponent_side = if (is_black_turn) self.white else self.black;

        const opponents_pieces = if (is_black_turn) self.white.all() else self.black.all();

        var move_count: usize = 0;

        var iter = knights.iterator();
        while (iter.next()) |knight| {
            const row_offsets = [8]comptime_int{ 2, 2, -2, -2, 1, 1, -1, -1 };
            const col_offsets = [8]comptime_int{ 1, -1, 1, -1, 2, -2, 2, -2 };
            inline for (row_offsets, col_offsets) |dr, dc| {
                const moved = knight.move(dr, dc);
                if (moved.overlaps(opponents_pieces)) {
                    move_buffer[move_count] = Move.initCapture(
                        Piece.knightFromBitBoard(knight),
                        Piece.knightFromBitBoard(moved),
                        Piece.init(opponent_side.whichType(moved), moved),
                    );
                    move_count += 1;
                }
            }
        }
        return move_count;
    }

    pub fn getAllKnightMoves(self: Self, move_buffer: []Move) usize {
        const is_white_turn = self.turn == .white;
        const own_side = if (is_white_turn) self.white else self.black;
        const knights = own_side.knight;
        if (knights.isEmpty()) return 0;
        const opponent_side = if (is_white_turn) self.black else self.white;
        const own_pieces = own_side.all();
        const opponents_pieces = opponent_side.all();
        const allowed_squares = own_pieces.complement();

        var move_count: usize = 0;

        var iter = knights.iterator();
        while (iter.next()) |knight| {
            const row_offsets = [8]comptime_int{ 2, 2, -2, -2, 1, 1, -1, -1 };
            const col_offsets = [8]comptime_int{ 1, -1, 1, -1, 2, -2, 2, -2 };
            inline for (row_offsets, col_offsets) |dr, dc| {
                const moved = knight.move(dr, dc);
                if (moved.overlaps(allowed_squares)) {
                    move_buffer[move_count] = Move.init(
                        Piece.knightFromBitBoard(knight),
                        Piece.knightFromBitBoard(moved),
                        if (moved.overlaps(opponents_pieces)) Piece.init(opponent_side.whichType(moved), moved) else null,
                    );
                    move_count += 1;
                }
            }
        }
        return move_count;
    }

    pub fn getBishopCaptures(self: Self, move_buffer: []Move) usize {
        const should_flip = self.turn == .black;
        const bishops = if (should_flip) self.black.bishop else self.white.bishop;
        if (bishops.isEmpty()) return 0;

        const own_pieces = if (should_flip) self.black.all() else self.white.all();
        const opponent_side = if (should_flip) self.white else self.black;
        const opponents_pieces = if (should_flip) self.white.all() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const allowed_squares = all_pieces.complement();

        var move_count: usize = 0;

        var iter = bishops.iterator();

        while (iter.next()) |bishop| {
            var bishop_parity = BitBoard.init((255 / 3 << 8 | 255 / 3 << 1) * (1 << 0 | 1 << 16 | 1 << 32 | 1 << 48));
            if (!bishop.overlaps(bishop_parity)) bishop_parity = bishop_parity.complement();

            inline for ([_]comptime_int{ 1, 1, -1, -1 }, [_]comptime_int{ 1, -1, 1, -1 }) |dr, dc| {
                var moved = bishop.move(dr, dc);
                while (moved.overlaps(allowed_squares)) : (moved = moved.moveUnchecked(dr, dc).getOverlap(bishop_parity)) {}
                if (moved.overlaps(opponents_pieces)) {
                    move_buffer[move_count] = Move.initCapture(
                        Piece.bishopFromBitBoard(bishop),
                        Piece.bishopFromBitBoard(moved),
                        Piece.init(opponent_side.whichType(moved), moved),
                    );
                    move_count += 1;
                }
            }
        }
        return move_count;
    }

    pub fn getAllBishopMoves(self: Self, move_buffer: []Move) usize {
        const should_flip = self.turn == .black;
        const bishops = if (should_flip) self.black.bishop else self.white.bishop;
        if (bishops.isEmpty()) return 0;

        const own_pieces = if (should_flip) self.black.all() else self.white.all();
        const opponent_side = if (should_flip) self.white else self.black;
        const opponents_pieces = if (should_flip) self.white.all() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const allowed_squares = all_pieces.complement();

        var move_count: usize = 0;

        var iter = bishops.iterator();
        while (iter.next()) |bishop| {
            var bishop_parity = BitBoard.init((255 / 3 << 8 | 255 / 3 << 1) * (1 << 0 | 1 << 16 | 1 << 32 | 1 << 48));
            if (!bishop.overlaps(bishop_parity)) bishop_parity = bishop_parity.complement();

            inline for ([_]comptime_int{ 1, 1, -1, -1 }, [_]comptime_int{ 1, -1, 1, -1 }) |dr, dc| {
                var moved = bishop.move(dr, dc);
                while (moved.overlaps(allowed_squares)) : (moved = moved.moveUnchecked(dr, dc).getOverlap(bishop_parity)) {
                    move_buffer[move_count] = Move.initQuiet(
                        Piece.bishopFromBitBoard(bishop),
                        Piece.bishopFromBitBoard(moved),
                    );
                    move_count += 1;
                }
                if (moved.overlaps(opponents_pieces)) {
                    move_buffer[move_count] = Move.initCapture(
                        Piece.bishopFromBitBoard(bishop),
                        Piece.bishopFromBitBoard(moved),
                        Piece.init(opponent_side.whichType(moved), moved),
                    );
                    move_count += 1;
                }
            }
        }
        return move_count;
    }

    pub fn getAllRookMoves(self: Self, move_buffer: []Move) usize {
        const should_flip = self.turn == .black;
        const rooks = if (should_flip) self.black.rook else self.white.rook;
        if (rooks.isEmpty()) return 0;

        const own_pieces = if (should_flip) self.black.all() else self.white.all();
        const opponent_side = if (should_flip) self.white else self.black;
        const opponents_pieces = if (should_flip) self.white.all() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const allowed_squares = all_pieces.complement();

        var move_count: usize = 0;

        var iter = rooks.iterator();
        while (iter.next()) |bishop| {
            inline for ([_]comptime_int{ 1, -1, 0, 0 }, [_]comptime_int{ 0, 0, 1, -1 }) |dr, dc| {
                var moved = bishop.move(dr, dc);
                while (moved.overlaps(allowed_squares)) : (moved = moved.move(dr, dc)) {
                    move_buffer[move_count] = Move.initQuiet(
                        Piece.rookFromBitBoard(bishop),
                        Piece.rookFromBitBoard(moved),
                    );
                    move_count += 1;
                }
                if (moved.overlaps(opponents_pieces)) {
                    move_buffer[move_count] = Move.initCapture(
                        Piece.rookFromBitBoard(bishop),
                        Piece.rookFromBitBoard(moved),
                        Piece.init(opponent_side.whichType(moved), moved),
                    );
                    move_count += 1;
                }
            }
        }
        return move_count;
    }
};

const testing = std.testing;

fn expectNumCaptures(moves: []Move, count: usize) !void {
    var actual_count: usize = 0;
    for (moves) |move| actual_count += @intFromBool(move.captured != null);
    if (count != actual_count) {
        std.log.err("Expected {} captures, found {}. Captures found:\n", .{ count, actual_count });
        for (moves) |move| {
            if (move.captured != null) {
                std.log.err("{}\n", .{move});
            }
        }
        return error.WrongNumberCaptures;
    }
}

test "fen parsing" {
    try testing.expectError(error.NotEnoughRows, Board.fromFen(""));
    try testing.expectError(error.EnPassantTargetDoesntExist, Board.fromFen("8/k7/8/4P3/8/8/K7/8 w - d6 0 1"));
    try testing.expect(!std.meta.isError(Board.fromFen("8/k7/8/3pP3/8/8/K7/8 w - d6 0 1")));
}

test "quiet pawn moves" {
    var buf: [100]Move = undefined;

    // starting position
    try testing.expectEqual(16, Board.fromFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").getQuietPawnMoves(&buf));
    try expectNumCaptures(buf[0..16], 0);

    // https://lichess.org/editor/8/8/p7/P1P5/2K2kP1/5P2/2P4P/8_w_-_-_0_1?color=white
    try testing.expectEqual(5, Board.fromFenUnchecked("8/8/p7/P1P5/2K2kP1/5P2/2P4P/8 w - - 0 1").getQuietPawnMoves(&buf));
    try expectNumCaptures(buf[0..5], 0);

    // https://lichess.org/editor/8/8/p7/P7/2K2k2/2P5/8/8_w_-_-_0_1?color=white
    try testing.expectEqual(0, Board.fromFenUnchecked("8/8/p7/P7/2K2k2/2P5/8/8 w - - 0 1").getQuietPawnMoves(&buf));

    // https://lichess.org/editor/8/P7/8/8/2K2k2/8/8/8_w_-_-_0_1?color=white
    try testing.expectEqual(4, Board.fromFenUnchecked("8/P7/8/8/2K2k2/8/8/8 w - - 0 1").getQuietPawnMoves(&buf));
    try expectNumCaptures(buf[0..4], 0);
}

test "pawn captures" {
    var buf: [100]Move = undefined;

    // starting position
    try testing.expectEqual(0, Board.fromFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").getPawnCaptures(&buf));

    // https://lichess.org/editor/8/8/p7/P1P5/2K2kP1/5P2/2P4P/8_w_-_-_0_1?color=white
    try testing.expectEqual(0, Board.fromFenUnchecked("8/8/p7/P1P5/2K2kP1/5P2/2P4P/8 w - - 0 1").getPawnCaptures(&buf));

    // https://lichess.org/editor/8/8/p7/P7/2K2k2/2P5/8/8_w_-_-_0_1?color=white
    try testing.expectEqual(0, Board.fromFenUnchecked("8/8/p7/P7/2K2k2/2P5/8/8 w - - 0 1").getPawnCaptures(&buf));

    // https://lichess.org/editor/8/8/p1q5/1P1P4/2K2k2/2P5/8/8_w_-_-_0_1?color=white
    try testing.expectEqual(3, Board.fromFenUnchecked("8/8/p1q5/1P1P4/2K2k2/2P5/8/8 w - - 0 1").getPawnCaptures(&buf));
    try expectNumCaptures(buf[0..3], 3);

    // https://lichess.org/editor/8/k7/8/3pP3/8/8/K7/8_w_-_d6_0_1?color=white
    try testing.expectEqual(1, Board.fromFenUnchecked("8/k7/8/3pP3/8/8/K7/8 w - d6 0 1").getPawnCaptures(&buf));
    try testing.expectEqualSlices(
        Move,
        &.{Move.init(
            Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E5")),
            Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("D6")),
            Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("D5")),
        )},
        buf[0..1],
    );
    // https://lichess.org/editor/8/k7/8/8/3pP3/8/K7/8_b_-_e3_0_1?color=white
    try testing.expectEqual(1, Board.fromFenUnchecked("8/k7/8/8/3pP3/8/K7/8 b - e3 0 1").getPawnCaptures(&buf));
    try testing.expectEqualSlices(
        Move,
        &.{Move.init(
            Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("D4")),
            Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E3")),
            Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E4")),
        )},
        buf[0..1],
    );

    // https://lichess.org/editor/1p6/P7/8/8/2K2k2/8/8/8_w_-_-_0_1?color=white
    try testing.expectEqual(4, Board.fromFenUnchecked("1p6/P7/8/8/2K2k2/8/8/8 w - - 0 1").getPawnCaptures(&buf));
    try expectNumCaptures(buf[0..4], 4);

    // https://lichess.org/editor/p1p5/1P6/8/8/2K2k2/8/8/8_w_-_-_0_1?color=white
    try testing.expectEqual(8, Board.fromFenUnchecked("p1p5/1P6/8/8/2K2k2/8/8/8 w - - 0 1").getPawnCaptures(&buf));
    try expectNumCaptures(buf[0..8], 8);
}

test "quiet knight moves" {
    var buf: [100]Move = undefined;

    // starting position
    try testing.expectEqual(4, Board.fromFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").getQuietKnightMoves(&buf));
    try expectNumCaptures(buf[0..4], 0);

    // https://lichess.org/editor/8/6k1/8/8/8/3N4/1K6/8_w_-_-_0_1?color=white
    try testing.expectEqual(7, Board.fromFenUnchecked("8/6k1/8/8/8/3N4/1K6/8 w - - 0 1").getQuietKnightMoves(&buf));
    try expectNumCaptures(buf[0..7], 0);

    // https://lichess.org/editor/8/6k1/8/5p2/8/3NN3/1K6/8_w_-_-_0_1?color=white
    try testing.expectEqual(14, Board.fromFenUnchecked("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1").getQuietKnightMoves(&buf));
    try expectNumCaptures(buf[0..14], 0);

    // https://lichess.org/editor/K7/6k1/8/8/8/8/8/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(5, Board.fromFenUnchecked("K7/6k1/8/8/8/8/8/NN6 w - - 0 1").getQuietKnightMoves(&buf));
    try expectNumCaptures(buf[0..5], 0);

    // https://lichess.org/editor/K7/6k1/8/8/8/ppp5/2pp4/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(0, Board.fromFenUnchecked("K7/6k1/8/8/8/ppp5/2pp4/NN6 w - - 0 1").getQuietKnightMoves(&buf));

    // https://lichess.org/editor/K7/6k1/8/8/8/ppp5/3p4/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(1, Board.fromFenUnchecked("K7/6k1/8/8/8/ppp5/3p4/NN6 w - - 0 1").getQuietKnightMoves(&buf));
    try testing.expectEqualSlices(
        Move,
        &.{Move.initQuiet(
            Piece.knightFromBitBoard(BitBoard.fromSquareUnchecked("A1")),
            Piece.knightFromBitBoard(BitBoard.fromSquareUnchecked("C2")),
        )},
        buf[0..1],
    );
}

test "knight captures" {
    var buf: [100]Move = undefined;

    // starting position
    try testing.expectEqual(0, Board.fromFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").getKnightCaptures(&buf));

    // https://lichess.org/editor/8/6k1/8/5p2/8/3NN3/1K6/8_w_-_-_0_1?color=white
    try testing.expectEqual(1, Board.fromFenUnchecked("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1").getKnightCaptures(&buf));
    try expectNumCaptures(buf[0..1], 1);

    // https://lichess.org/editor/K7/6k1/8/8/8/8/8/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(0, Board.fromFenUnchecked("K7/6k1/8/8/8/8/8/NN6 w - - 0 1").getKnightCaptures(&buf));

    // https://lichess.org/editor/K7/6k1/8/8/8/ppp5/2pp4/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(5, Board.fromFenUnchecked("K7/6k1/8/8/8/ppp5/2pp4/NN6 w - - 0 1").getKnightCaptures(&buf));
    try expectNumCaptures(buf[0..5], 5);

    // https://lichess.org/editor/K7/6k1/8/8/8/ppp5/3p4/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(4, Board.fromFenUnchecked("K7/6k1/8/8/8/ppp5/3p4/NN6 w - - 0 1").getKnightCaptures(&buf));
    try expectNumCaptures(buf[0..4], 4);

    // https://lichess.org/editor/K1k5/8/8/8/8/8/6p1/N7_w_-_-_0_1?color=white
    try testing.expectEqual(0, Board.fromFenUnchecked("K1k5/8/8/8/8/8/6p1/N7 w - - 0 1").getKnightCaptures(&buf));

    // https://lichess.org/editor/K1k4N/8/8/8/8/8/6p1/8_w_-_-_0_1?color=white
    try testing.expectEqual(0, Board.fromFenUnchecked("K1k4N/8/8/8/8/8/6p1/8 w - - 0 1").getKnightCaptures(&buf));
}

test "all knight moves" {
    var buf: [100]Move = undefined;

    // starting position
    try testing.expectEqual(4, Board.fromFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").getAllKnightMoves(&buf));
    try expectNumCaptures(buf[0..4], 0);

    // https://lichess.org/editor/8/6k1/8/5p2/8/3NN3/1K6/8_w_-_-_0_1?color=white
    try testing.expectEqual(15, Board.fromFenUnchecked("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1").getAllKnightMoves(&buf));
    try expectNumCaptures(buf[0..15], 1);

    // https://lichess.org/editor/K7/6k1/8/8/8/8/8/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(5, Board.fromFenUnchecked("K7/6k1/8/8/8/8/8/NN6 w - - 0 1").getAllKnightMoves(&buf));
    try expectNumCaptures(buf[0..5], 0);

    // https://lichess.org/editor/K7/6k1/8/8/8/ppp5/2pp4/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(5, Board.fromFenUnchecked("K7/6k1/8/8/8/ppp5/2pp4/NN6 w - - 0 1").getAllKnightMoves(&buf));
    try expectNumCaptures(buf[0..5], 5);

    // https://lichess.org/editor/K7/6k1/8/8/8/ppp5/3p4/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(5, Board.fromFenUnchecked("K7/6k1/8/8/8/ppp5/3p4/NN6 w - - 0 1").getAllKnightMoves(&buf));
    try expectNumCaptures(buf[0..5], 4);

    // https://lichess.org/editor/K1k5/8/8/8/8/8/6p1/N7_w_-_-_0_1?color=white
    try testing.expectEqual(2, Board.fromFenUnchecked("K1k5/8/8/8/8/8/6p1/N7 w - - 0 1").getAllKnightMoves(&buf));
    try expectNumCaptures(buf[0..2], 0);

    // https://lichess.org/editor/K1k4N/8/8/8/8/8/6p1/8_w_-_-_0_1?color=white
    try testing.expectEqual(2, Board.fromFenUnchecked("K1k4N/8/8/8/8/8/6p1/8 w - - 0 1").getAllKnightMoves(&buf));
    try expectNumCaptures(buf[0..2], 0);
}

test "bishop captures" {
    var buf: [100]Move = undefined;

    // https://lichess.org/editor/k7/8/8/5p2/8/3B4/8/K7_w_-_-_0_1?color=white
    try testing.expectEqual(1, Board.fromFenUnchecked("k7/8/8/5p2/8/3B4/8/K7 w - - 0 1").getBishopCaptures(&buf));

    // https://lichess.org/editor/7r/2k3p1/8/b7/8/2B5/8/1K6_w_-_-_0_1?color=white
    try testing.expectEqual(2, Board.fromFenUnchecked("7r/2k3p1/8/b7/8/2B5/8/1K6 w - - 0 1").getBishopCaptures(&buf));

    // https://lichess.org/editor/7r/2k3p1/8/b7/8/2B5/8/1K6_b_-_-_0_1?color=black
    try testing.expectEqual(1, Board.fromFenUnchecked("7r/2k3p1/8/b7/8/2B5/8/1K6 b - - 0 1").getBishopCaptures(&buf));
}

test "all bishop moves" {
    var buf: [100]Move = undefined;

    // starting position
    try testing.expectEqual(0, Board.fromFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").getAllBishopMoves(&buf));

    // https://lichess.org/editor?fen=r1bqkbnr%2Fpppp1ppp%2F2n5%2F4p3%2F4P3%2F5N2%2FPPPP1PPP%2FRNBQKB1R+w+KQkq+-+2+3&variant=fromPosition&color=white
    try testing.expectEqual(5, Board.fromFenUnchecked("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3").getAllBishopMoves(&buf));
    try expectNumCaptures(buf[0..5], 0);

    // https://lichess.org/editor/k7/8/8/8/8/3B4/8/K7_w_-_-_0_1?color=white
    try testing.expectEqual(11, Board.fromFenUnchecked("k7/8/8/8/8/3B4/8/K7 w - - 0 1").getAllBishopMoves(&buf));
    try expectNumCaptures(buf[0..11], 0);

    // https://lichess.org/editor/k7/8/8/5p2/8/3B4/8/K7_w_-_-_0_1?color=white
    try testing.expectEqual(9, Board.fromFenUnchecked("k7/8/8/5p2/8/3B4/8/K7 w - - 0 1").getAllBishopMoves(&buf));
    try expectNumCaptures(buf[0..9], 1);

    // https://lichess.org/editor/7r/2k3p1/8/b7/8/2B5/8/1K6_b_-_-_0_1?color=black
    try testing.expectEqual(3, Board.fromFenUnchecked("7r/2k3p1/8/b7/8/2B5/8/1K6 b - - 0 1").getAllBishopMoves(&buf));
    try expectNumCaptures(buf[0..3], 1);
}

test "all rook moves" {
    var buf: [100]Move = undefined;

    // starting position
    try testing.expectEqual(0, Board.fromFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").getAllRookMoves(&buf));

    // https://lichess.org/editor/k7/8/8/3R1p2/8/8/8/K7_w_-_-_0_1?color=white
    try testing.expectEqual(12, Board.fromFenUnchecked("k7/8/8/3R1p2/8/8/8/K7 w - - 0 1").getAllRookMoves(&buf));
    try expectNumCaptures(buf[0..12], 1);

    // https://lichess.org/editor/k7/8/8/3RRp2/8/8/8/K7_w_-_-_0_1?color=white
    try testing.expectEqual(18, Board.fromFenUnchecked("k7/8/8/3RRp2/8/8/8/K7 w - - 0 1").getAllRookMoves(&buf));
    try expectNumCaptures(buf[0..18], 1);

    // https://lichess.org/editor/7k/8/8/8/3rrP2/8/8/7K_b_-_-_0_1?color=black
    try testing.expectEqual(18, Board.fromFenUnchecked("7k/8/8/8/3rrP2/8/8/7K b - - 0 1").getAllRookMoves(&buf));
    try expectNumCaptures(buf[0..18], 1);
}
