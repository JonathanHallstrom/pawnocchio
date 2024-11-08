const std = @import("std");
const assert = std.debug.assert;

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

pub const Turn = enum { Black, White };

pub const BitBoard = enum(u64) {
    _,

    const Self = @This();

    fn data(self: Self) u64 {
        return @intFromEnum(self);
    }

    pub fn init(value: u64) BitBoard {
        return @enumFromInt(value);
    }

    pub fn fromSquare(square: []const u8) !BitBoard {
        if (square.len != 2) return error.InvalidSquare;
        const col = std.ascii.toLower(square[0]);
        const row = std.ascii.toLower(square[1]);
        if (square.len != 2) return error.InvalidSquare;
        if (!('a' <= col and col <= 'h')) return error.InvalidColumn;
        if (!('1' <= row and row <= '8')) return error.InvalidRow;
        return BitBoard.init(@as(u64, 1) << @intCast(8 * (row - '1') + col - 'a'));
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
        self.* = BitBoard.init(self.data() | getSquare(row, col));
    }

    pub fn get(self: Self, row: Row, col: Col) bool {
        return self.data() & getSquare(row, col) != 0;
    }

    // gives bitboard of all the values that are in either `self` or `other`
    pub fn combine(self: Self, other: BitBoard) BitBoard {
        return BitBoard.init(self.data() | other.data());
    }

    // gives bitboard of all the values that are in both `self` and `other`
    pub fn collision(self: Self, other: BitBoard) BitBoard {
        return BitBoard.init(self.data() & other.data());
    }

    // adds in all the set squares from `other` to `self`
    pub fn add(self: *Self, other: BitBoard) void {
        self.* = self.combine(other);
    }

    fn getSquare(row: Row, col: Col) u64 {
        return @as(u64, 1) << (8 * row.toInt() + col.toInt());
    }

    pub fn flip(self: Self) BitBoard {
        return BitBoard.init(@byteSwap(self.data()));
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

    const Side = struct {
        pawns: BitBoard = BitBoard.initEmpty(),
        knights: BitBoard = BitBoard.initEmpty(),
        bishops: BitBoard = BitBoard.initEmpty(),
        rooks: BitBoard = BitBoard.initEmpty(),
        queens: BitBoard = BitBoard.initEmpty(),
        king: BitBoard = BitBoard.initEmpty(),

        fn addPieceFen(self: *Side, which: u8, row: Row, col: Col) !void {
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
    };

    white: Side = .{},
    black: Side = .{},
    last_pawn_move: BitBoard = BitBoard.initEmpty(),

    // if u can castle queenside as white `C1` will be set
    castling_squares: BitBoard = BitBoard.initEmpty(),
    turn: Turn = .White,
    halfmove_clock: u8 = 0,
    fullmove_clock: u64 = 1,

    const queenside_white_castle = BitBoard.fromSquareUnchecked("C1");
    const kingside_white_castle = BitBoard.fromSquareUnchecked("G1");
    const queenside_black_castle = BitBoard.fromSquareUnchecked("C8");
    const kingside_black_castle = BitBoard.fromSquareUnchecked("G8");

    comptime {
        assert(queenside_white_castle == queenside_black_castle.flip());
        assert(kingside_white_castle == kingside_black_castle.flip());
    }

    const Self = @This();

    pub fn fromFen(fen: []const u8) !Self {
        var iter = std.mem.tokenizeAny(u8, fen, " /");
        var rows: [8][]const u8 = undefined;
        for (0..8) |i| {
            rows[7 - i] = iter.next() orelse return error.NotEnoughRows;
        }

        var res: Self = .{};
        for (0..8) |r| {
            // why not support it?
            // if (rows[r].len == 0) return error.emptyRow;

            var c: usize = 0;
            for (rows[r]) |ch| {
                if (std.ascii.isLower(ch)) {
                    try res.white.addPieceFen(ch, try Row.init(r), try Col.init(c));
                    c += 1;
                } else if (std.ascii.isUpper(ch)) {
                    try res.black.addPieceFen(ch, try Row.init(r), try Col.init(c));
                    c += 1;
                } else switch (ch) {
                    '1'...'8' => |n| c += n - '0',
                    else => return error.InvalidCharacter,
                }
            }
        }

        const turn_str = iter.next() orelse return error.MissingTurn;
        assert(turn_str.len > 0); // tokenize should only return non-empty strings
        if (turn_str.len > 1) return error.TurnStringTooBig;
        if (std.ascii.toLower(turn_str[0]) == 'w') {
            res.turn = .White;
        } else if (std.ascii.toLower(turn_str[0]) == 'b') {
            res.turn = .Black;
        } else {
            return error.InvalidTurn;
        }

        const castling_string = iter.next() orelse return error.MissingCastling;
        if (castling_string.len > 4) return error.CastlingStringTooBig;
        for (castling_string) |castle_ch| {
            res.castling_squares.add(switch (castle_ch) {
                'Q' => queenside_white_castle,
                'q' => queenside_black_castle,
                'K' => kingside_white_castle,
                'k' => kingside_black_castle,
                else => return error.InvalidCharacter,
            });
        }

        const en_passant_target_square_string = iter.next() orelse return error.MissingEnPassantTarget;
        if (std.mem.eql(u8, en_passant_target_square_string, "-")) {
            res.castling_squares = BitBoard.initEmpty();
        } else {
            res.castling_squares = try BitBoard.fromSquare(en_passant_target_square_string);
        }

        const halfmove_clock_string = iter.next() orelse return error.MissingHalfMoveClock;
        res.halfmove_clock = try std.fmt.parseInt(u8, halfmove_clock_string, 10);
        const fullmove_clock_str = iter.next() orelse return error.MissingFullMoveClock;
        const fullmove = try std.fmt.parseInt(u64, fullmove_clock_str, 10);
        if (fullmove == 0) return error.InvalidFullMove;
        res.fullmove_clock = fullmove;

        return res;
    }

    pub fn toString(self: Self) [8][8]u8 {
        var res: [8][8]u8 = .{.{' '} ** 8} ** 8;
        for (0..8) |r| {
            for (0..8) |c| {
                if (self.white.pawns.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'P';
                }
                if (self.black.pawns.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'p';
                }

                if (self.white.knights.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'N';
                }
                if (self.black.knights.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'n';
                }

                if (self.white.bishops.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'B';
                }
                if (self.black.bishops.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'b';
                }

                if (self.white.rooks.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'R';
                }
                if (self.black.rooks.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'r';
                }

                if (self.white.queens.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'Q';
                }
                if (self.black.queens.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'q';
                }

                if (self.white.king.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'K';
                }
                if (self.black.king.get(Row.init(r) catch unreachable, Col.init(c) catch unreachable)) {
                    res[7 - r][c] = 'k';
                }
            }
        }
        return res;
    }
};
