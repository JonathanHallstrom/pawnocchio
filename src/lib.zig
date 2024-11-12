const std = @import("std");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

pub const Row = enum(u8) {
    _,

    pub fn init(int: anytype) !Row {
        if (int >= 8) return error.OutOfRange;
        return @enumFromInt(int);
    }

    pub fn toInt(self: @This()) u6 {
        const res: u8 = @intFromEnum(self);
        assert(res < 8);
        return @intCast(res);
    }
};

pub const Col = enum(u8) {
    _,

    pub fn init(int: anytype) !Col {
        if (int >= 8) return error.OutOfRange;
        return @enumFromInt(int);
    }

    pub fn toInt(self: @This()) u6 {
        const res: u8 = @intFromEnum(self);
        assert(res < 8);
        return @intCast(res);
    }
};

pub const Side = enum { black, white };

pub const BitBoard = enum(u64) {
    _,

    const Self = @This();

    pub fn toInt(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn init(value: u64) BitBoard {
        return @enumFromInt(value);
    }

    pub fn fromSquare(square: []const u8) !BitBoard {
        if (square.len != 2) return error.InvalidSquare;
        const col = std.ascii.toLower(square[0]);
        const row = std.ascii.toLower(square[1]);
        return init(getSquare(try Row.init(row - '1'), try Col.init(col - 'a')));
    }

    pub fn fromSquareUnchecked(square: []const u8) BitBoard {
        return fromSquare(square) catch unreachable;
    }

    pub fn initEmpty() BitBoard {
        return init(0);
    }

    pub fn set(self: *Self, row: Row, col: Col) !void {
        if (self.get(row, col)) return error.AlreadySet;
        self.setUnchecked(row, col);
    }

    pub fn setUnchecked(self: *Self, row: Row, col: Col) void {
        self.* = init(self.toInt() | getSquare(row, col));
    }

    pub fn get(self: Self, row: Row, col: Col) bool {
        return self.toInt() & getSquare(row, col) != 0;
    }

    // gives bitboard of all the values that are in either `self` or `other`
    pub fn getCombination(self: Self, other: BitBoard) BitBoard {
        return init(self.toInt() | other.toInt());
    }

    // gives bitboard of all the values that are in both `self` and `other`
    pub fn getOverlap(self: Self, other: BitBoard) BitBoard {
        return init(self.toInt() & other.toInt());
    }

    pub fn overlaps(self: Self, other: BitBoard) bool {
        return self.getOverlap(other).toInt() != 0;
    }

    // adds in all the set squares from `other` to `self`
    pub fn add(self: *Self, other: BitBoard) void {
        self.* = self.getCombination(other);
    }

    pub fn complement(self: Self) BitBoard {
        return init(~self.toInt());
    }

    fn getSquare(row: Row, col: Col) u64 {
        return @as(u64, 1) << (8 * row.toInt() + col.toInt());
    }

    pub fn flipped(self: Self) BitBoard {
        return init(@byteSwap(self.toInt()));
    }

    pub fn iterator(self: Self) PieceIterator {
        return PieceIterator.init(self);
    }

    fn getColMask(self: Self) u64 {
        const idx = @ctz(self.toInt());
        const masks = comptime blk: {
            const first_col = 1 << 0 | 1 << 8 | 1 << 16 | 1 << 24 | 1 << 32 | 1 << 40 | 1 << 48 | 1 << 56;
            var res: [8]u64 = undefined;
            for (0..8) |i| res[i] = first_col << i;
            break :blk res;
        };
        return masks[idx % 8];
    }

    fn getRowMask(self: Self) u64 {
        const idx = @ctz(self.toInt()) & 63;
        return 255 * (@as(u64, 1) << @intCast(idx & ~@as(u64, 7)));
    }

    pub fn forward(self: Self, steps: u6) BitBoard {
        // not needed, will just go to zero if we go above the board
        // return init(self.toInt() << 8 * steps & self.getColMask());
        return init(self.toInt() << 8 * steps);
    }

    pub fn forwardUnchecked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() << 8 * steps);
    }

    pub fn backward(self: Self, steps: u6) BitBoard {
        // not needed, will just go to zero if we go below the board
        // return init(self.toInt() >> 8 * steps & self.getColMask());
        return init(self.toInt() >> 8 * steps);
    }

    pub fn backwardUnchecked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() >> 8 * steps);
    }

    pub fn left(self: Self, steps: u6) BitBoard {
        return init(self.toInt() >> steps & self.getRowMask());
    }

    pub fn leftUnchecked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() >> steps);
    }

    pub fn right(self: Self, steps: u6) BitBoard {
        return init(self.toInt() << steps & self.getRowMask());
    }

    pub fn rightUnchecked(self: Self, steps: u6) BitBoard {
        return init(self.toInt() << steps);
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

        assert(fromSquareUnchecked("D8").forward(1) == initEmpty());
        assert(fromSquareUnchecked("D1").backward(1) == initEmpty());
        assert(fromSquareUnchecked("A4").left(1) == initEmpty());
        assert(fromSquareUnchecked("H4").right(1) == initEmpty());
    }

    pub fn allForward(self: Self) BitBoard {
        var res = self;
        res.add(res.forward(1));
        res.add(res.forward(2));
        res.add(res.forward(4));
        return res;
    }

    pub fn allBackward(self: Self) BitBoard {
        var res = self;
        res.add(res.backward(1));
        res.add(res.backward(2));
        res.add(res.backward(4));
        return res;
    }

    pub fn allLeft(self: Self) BitBoard {
        const mask = self.getRowMask();
        var res = self;
        res.add(res.leftUnchecked(1));
        res.add(res.leftUnchecked(2));
        res.add(res.leftUnchecked(4));
        return init(res.toInt() & mask);
    }

    pub fn allRight(self: Self) BitBoard {
        const mask = self.getRowMask();
        var res = self;
        res.add(res.rightUnchecked(1));
        res.add(res.rightUnchecked(2));
        res.add(res.rightUnchecked(4));
        return init(res.toInt() & mask);
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

pub const PieceType = enum {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king,

    pub fn format(self: anytype, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = actual_fmt;
        _ = options;
        return try writer.print("{s}", .{@tagName(self)});
    }
};

pub const Piece = struct {
    tp: PieceType,
    pos: u6,

    pub fn init(tp: PieceType, b: BitBoard) Piece {
        assert(@popCount(b.toInt()) == 1);
        return .{
            .tp = tp,
            .pos = @intCast(@ctz(b.toInt())),
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

    pub fn format(self: anytype, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = actual_fmt;
        _ = options;
        const row = @as(u8, self.pos / 8) + '1';
        const col = @as(u8, self.pos % 8) + 'A';
        return try writer.print("({s} on {c}{c})", .{ @tagName(self.tp), col, row });
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
            .pos = flipPos(self.pos),
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

    pub fn format(self: anytype, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
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

    const PieceSet = struct {
        pawns: BitBoard = BitBoard.initEmpty(),
        knights: BitBoard = BitBoard.initEmpty(),
        bishops: BitBoard = BitBoard.initEmpty(),
        rooks: BitBoard = BitBoard.initEmpty(),
        queens: BitBoard = BitBoard.initEmpty(),
        king: BitBoard = BitBoard.initEmpty(),

        fn addPieceFen(self: *PieceSet, which: u8, row: Row, col: Col) !void {
            const board: *BitBoard = switch (std.ascii.toLower(which)) {
                'p' => &self.pawns,
                'n' => &self.knights,
                'b' => &self.bishops,
                'r' => &self.rooks,
                'q' => &self.queens,
                'k' => &self.king,
                else => return error.InvalidCharacter,
            };
            try board.set(row, col);
        }

        fn flipped(self: PieceSet) PieceSet {
            return .{
                .pawns = self.pawns.flipped(),
                .knights = self.knights.flipped(),
                .bishops = self.bishops.flipped(),
                .rooks = self.rooks.flipped(),
                .queens = self.queens.flipped(),
                .king = self.king.flipped(),
            };
        }

        fn all(self: PieceSet) BitBoard {
            var res = self.pawns;
            res.add(self.knights);
            res.add(self.bishops);
            res.add(self.rooks);
            res.add(self.queens);
            res.add(self.king);
            return res;
        }

        fn whichType(self: PieceSet, needle: BitBoard) PieceType {
            inline for (.{
                "pawns",
                "knights",
                "bishops",
                "rooks",
                "queens",
                "king",
            }, .{
                .pawn,
                .knight,
                .bishop,
                .rook,
                .queen,
                .king,
            }) |s, e| {
                if (@field(self, s).overlaps(needle)) {
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
            const should_overlap = if (res.turn == .white) res.black.pawns.forward(1) else res.white.pawns.backward(1);
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
                if (self.white.pawns.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'P';
                if (self.black.pawns.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'p';

                if (self.white.knights.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'N';
                if (self.black.knights.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'n';

                if (self.white.bishops.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'B';
                if (self.black.bishops.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'b';

                if (self.white.rooks.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'R';
                if (self.black.rooks.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'r';

                if (self.white.queens.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'Q';
                if (self.black.queens.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'q';

                if (self.white.king.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'K';
                if (self.black.king.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable))
                    res[7 - r][c] = 'k';
            }
        }
        return res;
    }

    pub fn getQuietPawnMoves(self: Self, move_buffer: []Move) usize {
        const should_flip = self.turn == .black;
        const own_pieces = if (should_flip) self.black.all().flipped() else self.white.all();
        const opponents_pieces = if (should_flip) self.white.all().flipped() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const pawns = if (should_flip) self.black.pawns.flipped() else self.white.pawns;

        var move_count: usize = 0;
        var iter = pawns.iterator();
        const third_row = BitBoard.fromSquareUnchecked("A3");
        const eigth_row = BitBoard.fromSquareUnchecked("A8").allRight();
        while (iter.next()) |pawn| {
            const forward_one = pawn.forward(1);
            if (!forward_one.overlaps(all_pieces) and forward_one != BitBoard.initEmpty()) {
                if (forward_one.overlaps(eigth_row)) {
                    for ([_]PieceType{ .knight, .bishop, .rook, .queen }) |piece_type| {
                        move_buffer[move_count] = Move.initQuiet(
                            Piece.pawnFromBitBoard(pawn),
                            Piece.init(piece_type, forward_one),
                        );
                        move_count += 1;
                    }
                } else {
                    move_buffer[move_count] = Move.initQuiet(
                        Piece.pawnFromBitBoard(pawn),
                        Piece.pawnFromBitBoard(forward_one),
                    );
                    move_count += 1;
                }
            }
            if (pawn.toInt() < third_row.toInt()) {
                const forward_two = pawn.forward(2);
                if (!forward_two.overlaps(all_pieces) and forward_two != BitBoard.initEmpty()) {
                    move_buffer[move_count] = Move.init(Piece.pawnFromBitBoard(pawn), Piece.pawnFromBitBoard(forward_two), null);
                    move_count += 1;
                }
            }
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
        const opponent_side = if (should_flip) self.white.flipped() else self.black;

        const opponents_pieces = opponent_side.all();
        const pawns = if (should_flip) self.black.pawns.flipped() else self.white.pawns;

        var move_count: usize = 0;
        var iter = pawns.iterator();
        const en_passant_target = if (should_flip) self.en_passant_target.flipped() else self.en_passant_target;
        while (iter.next()) |pawn| {
            const forward_one = pawn.forward(1);
            const forward_left = forward_one.left(1);
            const forward_right = forward_one.right(1);
            if (forward_left.overlaps(opponents_pieces)) {
                move_buffer[move_count] = Move.initCapture(
                    Piece.pawnFromBitBoard(pawn),
                    Piece.pawnFromBitBoard(forward_left),
                    Piece.init(
                        opponent_side.whichType(forward_left.getOverlap(opponents_pieces)),
                        forward_left,
                    ),
                );
                move_count += 1;
            }
            if (forward_right.overlaps(opponents_pieces)) {
                move_buffer[move_count] = Move.init(
                    Piece.pawnFromBitBoard(pawn),
                    Piece.pawnFromBitBoard(forward_right),
                    Piece.init(
                        opponent_side.whichType(forward_right.getOverlap(opponents_pieces)),
                        forward_right,
                    ),
                );
                move_count += 1;
            }

            // TODO: this can be done in O(1) before the loop using by moving en_passant_target to the left and right and checking collisions
            if (forward_left.overlaps(en_passant_target)) {
                move_buffer[move_count] = Move.init(
                    Piece.pawnFromBitBoard(pawn),
                    Piece.pawnFromBitBoard(forward_left),
                    Piece.pawnFromBitBoard(en_passant_target.backward(1)),
                );
                move_count += 1;
            }
            if (forward_right.overlaps(en_passant_target)) {
                move_buffer[move_count] = Move.init(
                    Piece.pawnFromBitBoard(pawn),
                    Piece.pawnFromBitBoard(forward_right),
                    Piece.pawnFromBitBoard(en_passant_target.backward(1)),
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
        const own_pieces = if (should_flip) self.black.all().flipped() else self.white.all();
        const opponents_pieces = if (should_flip) self.white.all().flipped() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const knights = if (should_flip) self.black.knights.flipped() else self.white.knights;

        var move_count: usize = 0;

        // 00000000
        // 00000000
        // 00111100
        // 00111100
        // 00111100
        // 00111100
        // 00000000
        // 00000000
        const far_from_edges = BitBoard.init(0b00111100 * (1 << 16) * ((1 << 0) + (1 << 8) + (1 << 16) + (1 << 24)));
        var iter = knights.iterator();
        while (iter.next()) |knight| {
            const row_offsets = [8]comptime_int{ 2, 2, -2, -2, 1, 1, -1, -1 };
            const col_offsets = [8]comptime_int{ 1, -1, 1, -1, 2, -2, 2, -2 };
            const is_far = knight.overlaps(far_from_edges);
            inline for (row_offsets, col_offsets) |dr, dc| {
                var moved = knight;
                if (is_far) {
                    moved = if (dr < 0) moved.backwardUnchecked(-dr) else moved.forwardUnchecked(dr);
                    moved = if (dc < 0) moved.leftUnchecked(-dc) else moved.rightUnchecked(dc);
                    if (!moved.overlaps(all_pieces)) {
                        move_buffer[move_count] = Move.initQuiet(
                            Piece.knightFromBitBoard(knight),
                            Piece.knightFromBitBoard(moved),
                        );
                        move_count += 1;
                    }
                } else {
                    moved = if (dr < 0) moved.backward(-dr) else moved.forward(dr);
                    moved = if (dc < 0) moved.left(-dc) else moved.right(dc);
                    if (!moved.overlaps(all_pieces) and moved != BitBoard.initEmpty()) {
                        move_buffer[move_count] = Move.initQuiet(
                            Piece.knightFromBitBoard(knight),
                            Piece.knightFromBitBoard(moved),
                        );
                        move_count += 1;
                    }
                }
            }
        }
        if (should_flip) {
            for (move_buffer[0..move_count]) |*move| {
                move.* = move.flipped();
            }
        }
        return move_count;
    }
};

const testing = std.testing;

test "quiet pawn moves" {
    var buf: [100]Move = undefined;

    // starting position
    try testing.expectEqual(16, Board.fromFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").getQuietPawnMoves(&buf));

    // https://lichess.org/editor/8/8/p7/P1P5/2K2kP1/5P2/2P4P/8_w_-_-_0_1?color=white
    try testing.expectEqual(5, Board.fromFenUnchecked("8/8/p7/P1P5/2K2kP1/5P2/2P4P/8 w - - 0 1").getQuietPawnMoves(&buf));

    // https://lichess.org/editor/8/8/p7/P7/2K2k2/2P5/8/8_w_-_-_0_1?color=white
    try testing.expectEqual(0, Board.fromFenUnchecked("8/8/p7/P7/2K2k2/2P5/8/8 w - - 0 1").getQuietPawnMoves(&buf));

    // https://lichess.org/editor/8/P7/8/8/2K2k2/8/8/8_w_-_-_0_1?color=white
    try testing.expectEqual(4, Board.fromFenUnchecked("8/P7/8/8/2K2k2/8/8/8 w - - 0 1").getQuietPawnMoves(&buf));
}

test "quiet knight moves" {
    var buf: [100]Move = undefined;

    // starting position
    try testing.expectEqual(4, Board.fromFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").getQuietKnightMoves(&buf));

    // https://lichess.org/editor/8/6k1/8/8/8/3N4/1K6/8_w_-_-_0_1?color=white
    try testing.expectEqual(7, Board.fromFenUnchecked("8/6k1/8/8/8/3N4/1K6/8 w - - 0 1").getQuietKnightMoves(&buf));

    // https://lichess.org/editor/8/6k1/8/5p2/8/3NN3/1K6/8_w_-_-_0_1?color=white
    try testing.expectEqual(14, Board.fromFenUnchecked("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1").getQuietKnightMoves(&buf));

    // https://lichess.org/editor/K7/6k1/8/8/8/8/8/NN6_w_-_-_0_1?color=white
    try testing.expectEqual(5, Board.fromFenUnchecked("K7/6k1/8/8/8/8/8/NN6 w - - 0 1").getQuietKnightMoves(&buf));

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
}

test "fen parsing" {
    try testing.expectError(error.NotEnoughRows, Board.fromFen(""));
    try testing.expectError(error.EnPassantTargetDoesntExist, Board.fromFen("8/k7/8/4P3/8/8/K7/8 w - d6 0 1"));
    try testing.expect(!std.meta.isError(Board.fromFen("8/k7/8/3pP3/8/8/K7/8 w - d6 0 1")));
}
