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

pub const Side = enum(u8) {
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

    pub inline fn toSquare(self: Self) [2]u8 {
        assert(@popCount(self.toInt()) == 1);
        const pos = @ctz(self.toInt());
        const row = pos / 8;
        const col = pos % 8;
        return .{ 'a' + col, '1' + row };
    }

    pub fn fromLoc(loc: u6) BitBoard {
        return init(@as(u64, 1) << loc);
    }

    pub fn toLoc(self: Self) u6 {
        return @intCast(@ctz(self.toInt()));
    }

    pub inline fn initEmpty() BitBoard {
        return init(0);
    }

    pub inline fn isEmpty(self: Self) bool {
        return self == initEmpty();
    }

    pub inline fn isNonEmpty(self: Self) bool {
        return self != initEmpty();
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

    // removes all the set squares in `other` from `self`
    pub inline fn remove(self: *Self, other: BitBoard) void {
        self.* = self.getOverlap(other.complement());
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
        res = if (dr < 0) res.backwardMasked(@intCast(@abs(dr))) else res.forwardMasked(@intCast(dr));
        res = if (dc < 0) res.leftMasked(@intCast(@abs(dc))) else res.rightMasked(@intCast(dc));
        return res;
    }

    pub inline fn moveUnchecked(self: Self, dr: anytype, dc: anytype) BitBoard {
        var res = self;
        res = if (dr < 0) res.backwardUnchecked(@intCast(@abs(dr))) else res.forwardUnchecked(@intCast(dr));
        res = if (dc < 0) res.leftUnchecked(@intCast(@abs(dc))) else res.rightUnchecked(@intCast(dc));
        return res;
    }

    fn getFirstOverLappingInDir(self: Self, overlap: BitBoard, dr: anytype, dc: anytype) BitBoard {
        assert(@popCount(self.toInt()) <= 1);
        var moved = self.move(dr, dc).allDirection(dr, dc).getOverlap(overlap).allDirection(dr, dc);
        moved.remove(moved.move(dr, dc));
        return moved;
    }

    fn getFirstOverLappingInDirUnchecked(self: Self, overlap: BitBoard, dr: anytype, dc: anytype) BitBoard {
        var moved = self.move(dr, dc).allDirection(dr, dc).getOverlap(overlap).allDirection(dr, dc);
        moved.remove(moved.move(dr, dc));
        return moved;
    }

    fn getFirstOverLappingInDirMasked(self: Self, overlap: BitBoard, dr: anytype, dc: anytype) BitBoard {
        var cleaned = self;
        cleaned.remove(self.move(-dr, -dc).allDirection(-dr, -dc));
        var moved = cleaned.move(dr, dc).allDirection(dr, dc).getOverlap(overlap).allDirection(dr, dc);
        moved.remove(moved.move(dr, dc));
        return moved;
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
        res.add(res.forwardMasked(1));
        res.add(res.forwardMasked(2));
        res.add(res.forwardMasked(4));
        return res;
    }

    pub fn allBackward(self: Self) BitBoard {
        var res = self;
        res.add(res.backwardMasked(1));
        res.add(res.backwardMasked(2));
        res.add(res.backwardMasked(4));
        return res;
    }

    pub fn allLeft(self: Self) BitBoard {
        var res = self;
        res.add(res.leftMasked(1));
        res.add(res.leftMasked(2));
        res.add(res.leftMasked(4));
        return res;
    }

    pub fn allRight(self: Self) BitBoard {
        var res = self;
        res.add(res.rightMasked(1));
        res.add(res.rightMasked(2));
        res.add(res.rightMasked(4));
        return res;
    }

    pub fn allDirection(self: Self, dr: anytype, dc: anytype) BitBoard {
        var res = self;
        res.add(res.move(dr * 1, dc * 1));
        res.add(res.move(dr * 2, dc * 2));
        res.add(res.move(dr * 4, dc * 4));
        return res;
    }

    pub fn prettyPrint(self: Self) void {
        for (0..8) |i| {
            std.debug.print("{b:0>8}\n", .{self.toInt() >> @intCast(8 * i) & 255});
        }
    }

    comptime {
        @setEvalBranchQuota(1 << 30);
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

        pub fn numRemaining(self: PieceIterator) u8 {
            return @popCount(self.data);
        }

        pub fn init(b: BitBoard) PieceIterator {
            return .{ .data = b.toInt() };
        }

        pub fn next(self: *PieceIterator) ?BitBoard {
            const res = self.data & -%self.data;
            self.data ^= res;
            return if (res == 0) null else BitBoard.init(res);
        }

        pub fn peek(self: *const PieceIterator) ?BitBoard {
            return if (self.data == 0) null else BitBoard.init(self.data & -%self.data);
        }
    };
};

pub const PieceType = enum(u3) {
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

    pub fn fromLetter(letter: u8) PieceType {
        return switch (letter) {
            'p' => .pawn,
            'n' => .knight,
            'b' => .bishop,
            'r' => .rook,
            'q' => .queen,
            'k' => .king,
            else => unreachable,
        };
    }
    pub fn toLetter(self: PieceType) u8 {
        return switch (self) {
            .pawn => 'p',
            .knight => 'n',
            .bishop => 'b',
            .rook => 'r',
            .queen => 'q',
            .king => 'k',
        };
    }

    pub const all = [_]PieceType{
        .pawn,
        .knight,
        .bishop,
        .rook,
        .queen,
        .king,
    };
};

const SmallPiece = struct {
    _pt: PieceType,
    _loc: u7,

    pub fn initInvalid() SmallPiece {
        return .{
            ._pt = .pawn,
            ._loc = 127,
        };
    }

    pub fn init(pt: PieceType, b: BitBoard) SmallPiece {
        assert(@popCount(b.toInt()) == 1);
        return .{
            ._pt = pt,
            ._loc = @intCast(b.toLoc()),
        };
    }
    pub fn initLoc(tp: PieceType, loc: u6) SmallPiece {
        return .{
            ._pt = tp,
            ._loc = loc,
        };
    }

    pub fn pawnFromBitBoard(b: BitBoard) SmallPiece {
        return init(.pawn, b);
    }

    pub fn knightFromBitBoard(b: BitBoard) SmallPiece {
        return init(.knight, b);
    }

    pub fn bishopFromBitBoard(b: BitBoard) SmallPiece {
        return init(.bishop, b);
    }

    pub fn rookFromBitBoard(b: BitBoard) SmallPiece {
        return init(.rook, b);
    }

    pub fn queenFromBitBoard(b: BitBoard) SmallPiece {
        return init(.queen, b);
    }

    pub fn kingFromBitBoard(b: BitBoard) SmallPiece {
        return init(.king, b);
    }

    pub fn format(self: SmallPiece, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = actual_fmt;
        _ = options;
        const pos = self.getBoard().toLoc();
        const row = @as(u8, pos / 8) + '1';
        const col = @as(u8, pos % 8) + 'A';
        return try writer.print("({s} on {c}{c})", .{ @tagName(self.getType()), col, row });
    }

    pub fn getType(self: SmallPiece) PieceType {
        return self._pt;
    }

    pub fn getBoard(self: SmallPiece) BitBoard {
        return BitBoard.init(@as(u64, 1) << @intCast(self._loc));
    }

    pub fn getLoc(self: SmallPiece) u6 {
        return @intCast(self._loc);
    }

    fn flipPos(x: anytype) @TypeOf(x) {
        return x ^ 56;
    }
    comptime {
        for (0..64) |i| {
            assert(@byteSwap(@as(u64, 1) << i) == @as(u64, 1) << flipPos(i));
        }
    }

    pub fn flipped(self: SmallPiece) SmallPiece {
        return .{
            ._pt = self._pt,
            ._loc = flipPos(self._loc),
        };
    }

    pub fn prettyPos(self: SmallPiece) [2]u8 {
        const pos = self.getBoard().toLoc();
        const row = @as(u8, pos / 8) + '1';
        const col = @as(u8, pos % 8) + 'a';
        return .{ col, row };
    }
};

const BigPiece = struct {
    _pt: PieceType,
    _board: BitBoard,

    pub fn initInvalid() BigPiece {
        return undefined;
    }

    pub fn init(tp: PieceType, b: BitBoard) BigPiece {
        assert(@popCount(b.toInt()) == 1);
        return .{
            ._pt = tp,
            ._board = b,
        };
    }

    pub fn pawnFromBitBoard(b: BitBoard) BigPiece {
        return init(.pawn, b);
    }

    pub fn knightFromBitBoard(b: BitBoard) BigPiece {
        return init(.knight, b);
    }

    pub fn bishopFromBitBoard(b: BitBoard) BigPiece {
        return init(.bishop, b);
    }

    pub fn rookFromBitBoard(b: BitBoard) BigPiece {
        return init(.rook, b);
    }

    pub fn queenFromBitBoard(b: BitBoard) BigPiece {
        return init(.queen, b);
    }

    pub fn kingFromBitBoard(b: BitBoard) BigPiece {
        return init(.king, b);
    }

    pub fn format(self: BigPiece, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = actual_fmt;
        _ = options;
        const pos = self.getBoard().toLoc();
        const row = @as(u8, pos / 8) + '1';
        const col = @as(u8, pos % 8) + 'A';
        return try writer.print("({s} on {c}{c})", .{ @tagName(self.getType()), col, row });
    }

    pub fn getType(self: BigPiece) PieceType {
        return self._pt;
    }

    pub fn getBoard(self: BigPiece) BitBoard {
        return self._board;
    }

    pub fn getLoc(self: BigPiece) u6 {
        return @ctz(self._board);
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

    pub fn flipped(self: BigPiece) BigPiece {
        return init(self.getType(), self.getBoard().flipped());
    }

    pub fn prettyPos(self: BigPiece) [2]u8 {
        const pos = @ctz(self.getBoard().toInt());
        const row = @as(u8, pos / 8) + '1';
        const col = @as(u8, pos % 8) + 'A';
        return .{ col, row };
    }
};

pub const Piece = SmallPiece;

comptime {
    assert(@sizeOf(PieceType) == 1);
}

pub const Move = struct {
    _from: Piece,
    _to: Piece,
    _captured: Piece,
    _might_cause_self_check: bool,
    _is_capture: bool,

    pub fn init(from_: Piece, to_: Piece, captured_: ?Piece, might_self_check: bool) Move {
        return .{
            ._from = from_,
            ._to = to_,
            ._captured = captured_ orelse Piece.initInvalid(),
            ._is_capture = captured_ != null,
            ._might_cause_self_check = might_self_check,
        };
    }

    pub fn from(self: Move) Piece {
        return self._from;
    }

    pub fn to(self: Move) Piece {
        return self._to;
    }

    pub fn captured(self: Move) ?Piece {
        return if (self.isCapture()) self._captured else null;
    }

    pub fn isQuiet(self: Move) bool {
        return !self.isCapture();
    }

    pub fn isCapture(self: Move) bool {
        return self._is_capture;
    }

    pub fn mightSelfCheck(self: Move) bool {
        return self._might_cause_self_check;
    }

    pub fn isEnPassantTarget(self: Move) bool {
        if (self.from().getType() != .pawn) return false;
        const forward = self.from().getBoard().forwardMasked(2);
        const backward = self.from().getBoard().backwardMasked(2);
        return forward.getCombination(backward).overlaps(self.to().getBoard());
    }

    pub fn getEnPassantTarget(self: Move) BitBoard {
        assert(self.isEnPassantTarget());
        const f = self.from().getBoard();
        const t = self.to().getBoard();
        return f.forwardMasked(1).getCombination(f.backwardMasked(1)).getOverlap(t.forwardMasked(1).getCombination(t.backwardMasked(1)));
    }

    pub fn isCastlingMove(self: Move) bool {
        const left = self.from().getBoard().left(2);
        const right = self.from().getBoard().right(2);
        return self.from().getType() == .king and left.getCombination(right).overlaps(self.to().getBoard());
    }

    pub fn getCastlingRookMove(self: Move) Move {
        assert(self.isCastlingMove());
        const f = self.from().getBoard();
        const t = self.to().getBoard();
        if (f.leftUnchecked(2) == t) {
            return initQuiet(Piece.rookFromBitBoard(t.leftUnchecked(2)), Piece.rookFromBitBoard(t.rightUnchecked(1)), self.mightSelfCheck());
        } else {
            return initQuiet(Piece.rookFromBitBoard(t.rightUnchecked(1)), Piece.rookFromBitBoard(t.leftUnchecked(1)), self.mightSelfCheck());
        }
    }

    pub fn initQuiet(from_: Piece, to_: Piece, might_self_check: bool) Move {
        return init(from_, to_, null, might_self_check);
    }

    pub fn initCapture(from_: Piece, to_: Piece, captured_: Piece, might_self_check: bool) Move {
        return init(from_, to_, captured_, might_self_check);
    }

    pub fn format(self: Move, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = actual_fmt;
        _ = options;
        if (self.captured()) |cap| {
            return try writer.print("(move {} to {} capturing {})", .{ self.from(), self.to(), cap });
        } else if (self.isCastlingMove()) {
            return try writer.print("(move {} to {} (castled))", .{ self.from(), self.to() });
        } else {
            return try writer.print("(move {} to {})", .{ self.from(), self.to() });
        }
    }

    pub fn flipped(self: Move) Move {
        return .{
            ._from = self._from.flipped(),
            ._to = self._to.flipped(),
            ._captured = self._captured.flipped(),
            ._is_capture = self._is_capture,
            ._might_cause_self_check = self._might_cause_self_check,
        };
    }

    pub fn pretty(self: Move) std.BoundedArray(u8, 8) {
        var res = std.BoundedArray(u8, 8).init(0) catch unreachable;
        if (self.from().getType() != self.to().getType()) {
            res.appendSliceAssumeCapacity(&self.from().prettyPos());
            res.appendSliceAssumeCapacity(&self.to().prettyPos());
            res.appendAssumeCapacity(self.to().getType().toLetter());
        } else {
            res.appendSliceAssumeCapacity(&self.from().prettyPos());
            res.appendSliceAssumeCapacity(&self.to().prettyPos());
        }
        return res;
    }

    pub fn eql(self: Move, other: Move) bool {
        return std.meta.eql(self.from(), other.from()) and
            std.meta.eql(self.to(), other.to());
    }
};

pub const MoveInverse = struct {
    move: Move,
    halfmove: u8,
    castling: u4,
    en_passant: ?u6,
};

pub const GameResult = enum {
    tie,
    white,
    black,

    pub fn from(turn: Side) GameResult {
        return switch (turn) {
            .white => .white,
            .black => .black,
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

    pub const PieceSet = packed struct {
        pawn: BitBoard = BitBoard.initEmpty(),
        knight: BitBoard = BitBoard.initEmpty(),
        bishop: BitBoard = BitBoard.initEmpty(),
        rook: BitBoard = BitBoard.initEmpty(),
        queen: BitBoard = BitBoard.initEmpty(),
        king: BitBoard = BitBoard.initEmpty(),

        // kinda ugly but makes for much better assembly than the naive implementation
        // https://godbolt.org/z/se5zaWv5r
        pub fn getBoard(self: *const PieceSet, pt: PieceType) BitBoard {
            const base: [*]const BitBoard = @ptrCast(self);
            const offset: usize = switch (pt) {
                inline else => |tp| @offsetOf(PieceSet, @tagName(tp)),
            };
            return base[offset / @sizeOf(BitBoard)];
        }

        pub fn getBoardPtr(self: *PieceSet, pt: PieceType) *BitBoard {
            const base: [*]BitBoard = @ptrCast(self);
            const offset: usize = switch (pt) {
                inline else => |tp| @offsetOf(PieceSet, @tagName(tp)),
            };
            return &base[offset / @sizeOf(BitBoard)];
        }

        pub fn addPieceFen(self: *PieceSet, which: u8, row: Row, col: Col) !void {
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

        pub fn flipped(self: PieceSet) PieceSet {
            return .{
                .pawn = self.pawn.flipped(),
                .knight = self.knight.flipped(),
                .bishop = self.bishop.flipped(),
                .rook = self.rook.flipped(),
                .queen = self.queen.flipped(),
                .king = self.king.flipped(),
            };
        }

        pub fn all(self: PieceSet) BitBoard {
            var res = self.pawn;
            res.add(self.knight);
            res.add(self.bishop);
            res.add(self.rook);
            res.add(self.queen);
            res.add(self.king);
            return res;
        }

        pub fn whichTypeUnchecked(self: PieceSet, needle: BitBoard) PieceType {
            return self.whichType(needle).?;
        }

        pub fn whichType(self: PieceSet, needle: BitBoard) ?PieceType {
            inline for (PieceType.all) |e| {
                if (@field(self, @tagName(e)).overlaps(needle)) {
                    return e;
                }
            }
            return null;
        }
    };

    white: PieceSet = .{},
    black: PieceSet = .{},

    turn: Side = .white,
    // if u can castle queenside as white `C1` will be set
    castling_squares: u4 = 0,
    en_passant_target: ?u6 = null,

    halfmove_clock: u8 = 0,
    fullmove_clock: u64 = 1,
    zobrist: u64 = 0,

    const white_king_start = BitBoard.fromSquareUnchecked("E1");
    const black_king_start = BitBoard.fromSquareUnchecked("E8");
    const queenside_white_castle: u4 = 1;
    const kingside_white_castle: u4 = 2;
    const queenside_black_castle: u4 = 4;
    const kingside_black_castle: u4 = 8;

    const Self = @This();

    pub fn parseFenUnchecked(fen: []const u8) Self {
        return parseFen(fen) catch unreachable;
    }

    pub fn init() Board {
        return parseFenUnchecked("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    }

    pub fn parseFen(fen: []const u8) !Self {
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
                res.castling_squares |= switch (castle_ch) {
                    'Q' => queenside_white_castle,
                    'q' => queenside_black_castle,
                    'K' => kingside_white_castle,
                    'k' => kingside_black_castle,
                    else => return error.InvalidCharacter,
                };
            }
        }

        const en_passant_target_square_string = iter.next() orelse return error.MissingEnPassantTarget;
        if (std.mem.eql(u8, en_passant_target_square_string, "-")) {
            res.en_passant_target = null;
        } else {
            const correct_row: u8 = if (res.turn == .white) '6' else '3';
            if (en_passant_target_square_string.len != 2 or
                en_passant_target_square_string[1] != correct_row)
                return error.InvalidEnPassantTarget;
            const board = try BitBoard.fromSquare(en_passant_target_square_string);
            const should_overlap = if (res.turn == .white) res.black.pawn.forwardMasked(1) else res.white.pawn.backwardMasked(1);
            if (!board.overlaps(should_overlap)) return error.EnPassantTargetDoesntExist;
            res.en_passant_target = board.toLoc();
        }

        const halfmove_clock_string = iter.next() orelse "0";
        res.halfmove_clock = try std.fmt.parseInt(u8, halfmove_clock_string, 10);
        const fullmove_clock_str = iter.next() orelse "1";
        const fullmove = try std.fmt.parseInt(u64, fullmove_clock_str, 10);
        if (fullmove == 0)
            return error.InvalidFullMove;
        res.fullmove_clock = fullmove;
        res.resetZobrist();

        return res;
    }

    pub fn resetZobrist(self: *Self) void {
        self.zobrist = 0;
        for (PieceType.all) |pt| {
            var iter = self.white.getBoard(pt).iterator();
            while (iter.next()) |b| {
                self.zobristPiece(Piece.init(pt, b), .white);
            }
            iter = self.black.getBoard(pt).iterator();
            while (iter.next()) |b| {
                self.zobristPiece(Piece.init(pt, b), .black);
            }
        }
        if (self.en_passant_target) |ep|
            self.zobristEnPassant(ep);
        self.zobristCastling(self.castling_squares);
        if (self.turn == .black)
            self.zobristTurn();
    }

    fn zobristPiece(self: *Self, piece: Piece, turn: Side) void {
        self.zobrist ^= @import("zobrist.zig").get(piece, turn);
    }

    fn zobristTurn(self: *Self) void {
        self.zobrist ^= @import("zobrist.zig").getTurn();
    }

    fn zobristEnPassant(self: *Self, ep: u6) void {
        self.zobrist ^= @import("zobrist.zig").getEnPassant(ep);
    }

    fn zobristCastling(self: *Self, rights: u4) void {
        self.zobrist ^= @import("zobrist.zig").getCastling(rights);
    }

    pub fn toFen(self: Self) std.BoundedArray(u8, 127) {
        var res = std.BoundedArray(u8, 127).init(0) catch unreachable;
        _ = &res;

        var count: u8 = 0;
        inline for (0..8) |ir| {
            inline for (0..8) |c| {
                const r = 7 - ir;
                const letter_opt: ?u8 = if (self.white.whichType(BitBoard.init(1 << r * 8 + c))) |piece_type|
                    std.ascii.toUpper(piece_type.toLetter())
                else if (self.black.whichType(BitBoard.init(1 << r * 8 + c))) |piece_type|
                    std.ascii.toLower(piece_type.toLetter())
                else
                    null;

                if (letter_opt) |letter| {
                    if (count != 0) {
                        res.appendAssumeCapacity(count + '0');
                        count = 0;
                    }
                    res.appendAssumeCapacity(letter);
                } else {
                    count += 1;
                }
            }
            if (count != 0) {
                res.appendAssumeCapacity(count + '0');
                count = 0;
            }
            if (ir != 7)
                res.appendAssumeCapacity('/');
        }
        res.appendAssumeCapacity(' ');
        res.appendAssumeCapacity(std.ascii.toLower(@tagName(self.turn)[0]));
        res.appendAssumeCapacity(' ');
        if (self.castling_squares == 0) {
            res.appendAssumeCapacity('-');
        } else {
            if (self.castling_squares & kingside_white_castle != 0) res.appendAssumeCapacity('K');
            if (self.castling_squares & queenside_white_castle != 0) res.appendAssumeCapacity('Q');
            if (self.castling_squares & kingside_black_castle != 0) res.appendAssumeCapacity('k');
            if (self.castling_squares & queenside_black_castle != 0) res.appendAssumeCapacity('q');
        }
        res.appendAssumeCapacity(' ');
        if (self.en_passant_target == null) {
            res.appendAssumeCapacity('-');
        } else {
            res.appendSliceAssumeCapacity(&BitBoard.fromLoc(self.en_passant_target.?).toSquare());
        }
        res.appendAssumeCapacity(' ');
        var clock_buf: [32]u8 = undefined;
        res.appendSliceAssumeCapacity(std.fmt.bufPrint(&clock_buf, "{d} {d}", .{ self.halfmove_clock, self.fullmove_clock }) catch unreachable);

        return res;
    }

    pub fn isInCheck(self: Self, comptime turn_mode: TurnMode) bool {
        const is_white_turn = switch (turn_mode) {
            .auto => self.turn == .white,
            .flip => self.turn == .black,
            .white => true,
            .black => false,
        };

        const own_side = if (is_white_turn) self.white else self.black;

        return self.areSquaresAttacked(own_side.king, turn_mode);
    }

    pub fn isInCheckMate(self: Self, comptime turn_mode: TurnMode) bool {
        var tmp_buf: [400]Move = undefined;
        if (self.isInCheck(turn_mode)) {
            if (self.getAllMoves(&tmp_buf, self.getSelfCheckSquares()) == 0) {
                return true;
            }
        }
        return false;
    }

    pub fn isTieByInsufficientMaterial(self: Self) bool {
        if (self.white.pawn
            .getCombination(self.black.pawn)
            .getCombination(self.white.rook)
            .getCombination(self.black.rook)
            .getCombination(self.white.queen)
            .getCombination(self.black.queen)
            .isNonEmpty())
            return false;
        return @popCount(self.white.knight
            .getCombination(self.black.knight)
            .getCombination(self.white.bishop)
            .getCombination(self.black.bishop)
            .toInt()) < 2;
    }

    pub fn isFiftyMoveTie(self: Self) bool {
        return self.halfmove_clock >= 50;
    }

    pub fn gameOver(self: Self) ?GameResult {
        if (self.isFiftyMoveTie()) return .tie;
        if (self.isTieByInsufficientMaterial()) return .tie;
        var tmp_buf: [400]Move = undefined;
        if (self.getAllMoves(&tmp_buf, self.getSelfCheckSquares()) == 0) {
            if (self.isInCheck(.auto)) {
                return GameResult.from(self.turn.flipped());
            } else {
                return .tie;
            }
        }

        return null;
    }

    pub fn toString(self: Self) [17][33]u8 {
        const row: [33]u8 = ("+" ++ "---+" ** 8).*;
        var res: [17][33]u8 = .{row} ++ (.{("|" ++ "   |" ** 8).*} ++ .{row}) ** 8;
        for (0..8) |r| {
            for (0..8) |c| {
                const square = BitBoard.init(@as(u64, 1) << @intCast(8 * r + c));
                if (self.white.whichType(square)) |s| {
                    res[2 * (7 - r) + 1][4 * c + 2] = std.ascii.toUpper(s.toLetter());
                }
                if (self.black.whichType(square)) |s| {
                    res[2 * (7 - r) + 1][4 * c + 2] = std.ascii.toLower(s.toLetter());
                }
            }
        }
        return res;
    }

    // move has to be valid
    pub fn compressMove(self: Self, move: Move) u16 {
        _ = self;
        const from_sq: u16 = move.from().getLoc();
        const to_sq: u16 = move.to().getLoc();
        var other_flags: u16 = 0;
        if (move.from().getType() != move.to().getType()) {
            other_flags = switch (move.to().getType()) {
                .knight => 0b1000,
                .bishop => 0b1001,
                .rook => 0b1010,
                .queen => 0b1011,
                else => unreachable,
            };
        }
        if (move.captured()) |cap| {
            if (cap.getLoc() != move.to().getLoc()) {
                other_flags = 0b0100;
            }
        }

        return from_sq | to_sq << 6 | other_flags << 12;
    }
    pub fn decompressMove(self: Self, compressed_move: u16) Move {
        const moved_side = if (self.turn == .white) self.white else self.black;
        const from_sq: u6 = @intCast(compressed_move & 0b111111);
        const from_bb = BitBoard.init(@as(u64, 1) << from_sq);
        const to_sq: u6 = @intCast(compressed_move >> 6 & 0b111111);
        const to_bb = BitBoard.init(@as(u64, 1) << to_sq);
        const other_flags: u4 = @intCast(compressed_move >> 12);
        const from = Piece.init(moved_side.whichTypeUnchecked(from_bb), from_bb);
        var to = Piece.init(moved_side.whichTypeUnchecked(from_bb), to_bb);
        if (other_flags & 0b1000 != 0) {
            to = Piece.init(switch (other_flags) {
                0b1000 => .knight,
                0b1001 => .bishop,
                0b1010 => .rook,
                0b1011 => .queen,
                else => unreachable,
            }, to_bb);
        }
        var captured: ?Piece = null;
        if (moved_side.whichType(to_bb)) |captured_type| {
            captured = Piece.init(captured_type, to_bb);
        } else if (other_flags == 0b0100) {
            captured = Piece.pawnFromBitBoard(if (self.turn == .white) to_bb.backwardUnchecked(1) else to_bb.forwardUnchecked(1));
        }

        return Move.init(from, to, captured, true);
    }

    pub fn playMove(self: *Self, move: Move) MoveInverse {
        const res = MoveInverse{
            .move = move,
            .halfmove = self.halfmove_clock,
            .castling = self.castling_squares,
            .en_passant = self.en_passant_target,
        };
        self.zobristTurn();
        self.halfmove_clock += 1;
        self.fullmove_clock += @intFromBool(self.turn == .black);
        const turn = self.turn;
        self.turn = self.turn.flipped();
        const moved_side = if (turn == .white) &self.white else &self.black;

        self.zobristPiece(move.from(), turn);
        self.zobristPiece(move.to(), turn);

        const from_board = moved_side.getBoardPtr(move.from().getType());
        assert(from_board.overlaps(move.from().getBoard()));
        from_board.remove(move.from().getBoard());

        const to_board = moved_side.getBoardPtr(move.to().getType());
        assert(!to_board.overlaps(move.to().getBoard()));
        to_board.add(move.to().getBoard());

        if (move.from().getType() == .pawn) {
            self.halfmove_clock = 0;
            if (move.isEnPassantTarget()) {
                if (self.en_passant_target) |ep| self.zobristEnPassant(ep);
                self.en_passant_target = move.getEnPassantTarget().toLoc();
                if (self.en_passant_target) |ep| self.zobristEnPassant(ep);
            } else {
                if (self.en_passant_target) |ep| self.zobristEnPassant(ep);
                self.en_passant_target = null;
            }
        } else {
            if (self.en_passant_target) |ep| self.zobristEnPassant(ep);
            self.en_passant_target = null;
            if (move.from().getType() == .king) {
                self.zobristCastling(self.castling_squares);
                if (turn == .white) {
                    self.castling_squares &= ~@as(u4, kingside_white_castle | queenside_white_castle);
                }
                if (turn == .black) {
                    self.castling_squares &= ~@as(u4, kingside_black_castle | queenside_black_castle);
                }
                self.zobristCastling(self.castling_squares);
            } else if (move.from().getType() == .rook) {
                self.zobristCastling(self.castling_squares);
                if (turn == .white and move.from().getBoard() == BitBoard.fromSquareUnchecked("A1")) {
                    self.castling_squares &= ~@as(u4, queenside_white_castle);
                }
                if (turn == .white and move.from().getBoard() == BitBoard.fromSquareUnchecked("H1")) {
                    self.castling_squares &= ~@as(u4, kingside_white_castle);
                }
                if (turn == .black and move.from().getBoard() == BitBoard.fromSquareUnchecked("A8")) {
                    self.castling_squares &= ~@as(u4, queenside_black_castle);
                }
                if (turn == .black and move.from().getBoard() == BitBoard.fromSquareUnchecked("H8")) {
                    self.castling_squares &= ~@as(u4, kingside_black_castle);
                }
                self.zobristCastling(self.castling_squares);
            }
        }

        if (move.isCastlingMove()) {
            self.zobristCastling(self.castling_squares);
            if (move.from().getBoard().leftUnchecked(2) == move.to().getBoard()) {
                moved_side.rook.remove(move.to().getBoard().leftUnchecked(2));
                moved_side.rook.add(move.to().getBoard().rightUnchecked(1));
                self.zobristPiece(Piece.rookFromBitBoard(move.to().getBoard().leftUnchecked(2)), turn);
                self.zobristPiece(Piece.rookFromBitBoard(move.to().getBoard().rightUnchecked(1)), turn);
            } else {
                moved_side.rook.remove(move.to().getBoard().rightUnchecked(1));
                moved_side.rook.add(move.to().getBoard().leftUnchecked(1));
                self.zobristPiece(Piece.rookFromBitBoard(move.to().getBoard().rightUnchecked(1)), turn);
                self.zobristPiece(Piece.rookFromBitBoard(move.to().getBoard().leftUnchecked(1)), turn);
            }
            self.zobristCastling(self.castling_squares);
        }
        if (move.captured()) |cap| {
            self.zobristPiece(cap, turn.flipped());
            self.halfmove_clock = 0;
            const capture_side = if (turn == .white) &self.black else &self.white;
            const capture_board = capture_side.getBoardPtr(cap.getType());
            capture_board.remove(cap.getBoard());
        }
        return res;
    }

    pub fn playMoveFromSquare(self: *Self, square: []const u8, move_buf: []Move) !MoveInverse {
        const num_moves = self.getAllMoves(move_buf, self.getSelfCheckSquares());
        const moves = move_buf[0..num_moves];

        for (moves) |move| {
            if (std.ascii.eqlIgnoreCase(
                std.mem.trim(u8, move.pretty().slice(), &std.ascii.whitespace),
                std.mem.trim(u8, square, &std.ascii.whitespace),
            )) {
                return self.playMove(move);
            }
        }
        return error.NoSuchMove;
    }

    pub fn playMovePossibleSelfCheck(self: *Self, move: Move) ?MoveInverse {
        const inverse = self.playMove(move);
        if (move._might_cause_self_check and self.isInCheck(.flip)) {
            self.undoMove(inverse);
            return null;
        }
        return inverse;
    }

    pub fn undoMove(self: *Self, inv: MoveInverse) void {
        const move = inv.move;
        const moved_side = if (self.turn == .black) &self.white else &self.black;
        self.zobristTurn();
        const turn = self.turn.flipped();

        self.zobristPiece(move.from(), turn);
        self.zobristPiece(move.to(), turn);

        const from_board = moved_side.getBoardPtr(move.from().getType());
        assert(!from_board.overlaps(move.from().getBoard()));
        from_board.add(move.from().getBoard());

        const to_board = moved_side.getBoardPtr(move.to().getType());
        assert(to_board.overlaps(move.to().getBoard()));
        to_board.remove(move.to().getBoard());

        if (move.isEnPassantTarget()) {
            if (self.en_passant_target) |ep| self.zobristEnPassant(ep);
            self.en_passant_target = move.getEnPassantTarget().toLoc();
            if (self.en_passant_target) |ep| self.zobristEnPassant(ep);
        } else if (move.isCastlingMove()) {
            self.zobristCastling(self.castling_squares);
            if (move.from().getBoard().leftUnchecked(2) == move.to().getBoard()) {
                moved_side.rook.add(move.to().getBoard().leftUnchecked(2));
                moved_side.rook.remove(move.to().getBoard().rightUnchecked(1));
                self.zobristPiece(Piece.rookFromBitBoard(move.to().getBoard().leftUnchecked(2)), turn);
                self.zobristPiece(Piece.rookFromBitBoard(move.to().getBoard().rightUnchecked(1)), turn);
            } else {
                moved_side.rook.add(move.to().getBoard().rightUnchecked(1));
                moved_side.rook.remove(move.to().getBoard().leftUnchecked(1));
                self.zobristPiece(Piece.rookFromBitBoard(move.to().getBoard().rightUnchecked(1)), turn);
                self.zobristPiece(Piece.rookFromBitBoard(move.to().getBoard().leftUnchecked(1)), turn);
            }
            self.zobristCastling(self.castling_squares);
        }
        if (move.captured()) |cap| {
            const capture_side = if (self.turn == .black) &self.black else &self.white;
            const capture_board = capture_side.getBoardPtr(cap.getType());
            self.zobristPiece(cap, turn.flipped());
            capture_board.add(cap.getBoard());
        }
        self.turn = turn;
        self.zobristCastling(self.castling_squares);
        self.castling_squares = inv.castling;
        self.zobristCastling(self.castling_squares);
        if (self.en_passant_target) |ep| self.zobristEnPassant(ep);
        self.en_passant_target = inv.en_passant;
        if (self.en_passant_target) |ep| self.zobristEnPassant(ep);
        self.halfmove_clock = inv.halfmove;
        self.fullmove_clock -= @intFromBool(self.turn == .black);
    }

    pub const TurnMode = enum {
        auto,
        flip,
        white,
        black,
        pub fn from(side: Side) TurnMode {
            return switch (side) {
                .black => .black,
                .white => .white,
            };
        }
    };

    // careful with lined up pieces!
    // remember the castling bug
    fn areSquaresAttacked(self: Self, squares: BitBoard, comptime turn_mode: TurnMode) bool {
        const is_white_turn = switch (turn_mode) {
            .auto => self.turn == .white,
            .flip => self.turn == .black,
            .white => true,
            .black => false,
        };

        const own_pieces = if (is_white_turn) self.white.all() else self.black.all();
        const opponent_side = if (is_white_turn) self.black else self.white;
        const opponents_pieces = opponent_side.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);

        var bishop_mask = BitBoard.initEmpty();
        for (bishop_drs, bishop_dcs) |dr, dc| bishop_mask.add(squares.getFirstOverLappingInDirMasked(all_pieces, dr, dc));
        if (bishop_mask.overlaps(opponent_side.bishop.getCombination(opponent_side.queen))) {
            // std.debug.print("bishop\n", .{});
            return true;
        }

        var rook_mask = BitBoard.initEmpty();
        for (rook_drs, rook_dcs) |dr, dc| rook_mask.add(squares.getFirstOverLappingInDirMasked(all_pieces, dr, dc));
        if (rook_mask.overlaps(opponent_side.rook.getCombination(opponent_side.queen))) {
            // std.debug.print("rook\n", .{});
            return true;
        }
        const pawn_dr: i8 = if (is_white_turn) 1 else -1;
        var pawn_mask = BitBoard.initEmpty();
        pawn_mask.add(squares.move(pawn_dr, 1));
        pawn_mask.add(squares.move(pawn_dr, -1));
        if (pawn_mask.overlaps(opponent_side.pawn)) {
            return true;
        }
        var knight_mask = BitBoard.initEmpty();
        for (knight_drs, knight_dcs) |dr, dc| knight_mask.add(squares.move(dr, dc));
        if (knight_mask.overlaps(opponent_side.knight)) {
            // std.debug.print("knight\n", .{});
            return true;
        }

        var king_mask = squares;
        king_mask.add(squares.leftMasked(1));
        king_mask.add(squares.rightMasked(1));
        king_mask.add(king_mask.forwardMasked(1));
        king_mask.add(king_mask.backwardMasked(1));
        if (king_mask.overlaps(opponent_side.king)) {
            // std.debug.print("king\n", .{});
            return true;
        }
        return false;
    }

    pub fn doesMoveCauseSelfCheck(self: Self, move: Move) bool {
        if (!move.mightSelfCheck()) return false;
        var board = self;
        if (board.playMovePossibleSelfCheck(move)) |_| {
            return false;
        }
        return true;
    }

    const knight_drs = [_]i8{ 2, 2, -2, -2, 1, 1, -1, -1 };
    const knight_dcs = [_]i8{ 1, -1, 1, -1, 2, -2, 2, -2 };

    const bishop_drs = [_]i8{ 1, 1, -1, -1 };
    const bishop_dcs = [_]i8{ 1, -1, 1, -1 };

    const rook_drs = [_]i8{ 1, -1, 0, 0 };
    const rook_dcs = [_]i8{ 0, 0, 1, -1 };

    pub fn getQuietPawnMovesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares_inp: BitBoard) usize {
        const should_flip = self.turn == .black;
        const pawns = if (should_flip) self.black.pawn.flipped() else self.white.pawn;
        if (pawns.isEmpty()) return 0;
        const possible_self_check_squares = if (should_flip) possible_self_check_squares_inp.flipped() else possible_self_check_squares_inp;

        const own_pieces = if (should_flip) self.black.all().flipped() else self.white.all();
        const opponents_pieces = if (should_flip) self.white.all().flipped() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);

        var move_count: usize = 0;
        const allowed_squares = all_pieces.complement();

        const seventh_row = BitBoard.fromSquareUnchecked("A7").allRight();

        const pawns_that_can_move = pawns.forwardMasked(1).getOverlap(allowed_squares).backwardMasked(1);

        var promotion_pawns = pawns_that_can_move.getOverlap(seventh_row).iterator();
        while (promotion_pawns.next()) |pawn_to_promote| {
            for ([_]PieceType{ .knight, .bishop, .rook, .queen }) |piece_type| {
                move_buffer[move_count] = Move.initQuiet(
                    Piece.pawnFromBitBoard(pawn_to_promote),
                    Piece.init(
                        piece_type,
                        pawn_to_promote.forward(1),
                    ),
                    possible_self_check_squares.overlaps(pawn_to_promote),
                );
                move_count += 1;
            }
        }

        const second_row = BitBoard.fromSquareUnchecked("A2").allRight();
        var double_move_pawns = pawns_that_can_move.getOverlap(second_row).forwardMasked(2).getOverlap(allowed_squares).backwardMasked(2).iterator();
        while (double_move_pawns.next()) |pawn| {
            move_buffer[move_count] = Move.initQuiet(
                Piece.pawnFromBitBoard(pawn),
                Piece.pawnFromBitBoard(pawn.forward(2)),
                possible_self_check_squares.overlaps(pawn),
            );
            move_count += 1;
        }

        var last_pawns = pawns_that_can_move.getOverlap(seventh_row.complement()).iterator();
        while (last_pawns.next()) |pawn| {
            move_buffer[move_count] = Move.initQuiet(
                Piece.pawnFromBitBoard(pawn),
                Piece.pawnFromBitBoard(pawn.forward(1)),
                possible_self_check_squares.overlaps(pawn),
            );
            move_count += 1;
        }

        if (should_flip) {
            for (move_buffer[0..move_count]) |*move| {
                move.* = move.flipped();
            }
        }
        return move_count;
    }

    pub fn getPawnCapturesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares_inp: BitBoard) usize {
        const should_flip = self.turn == .black;
        const pawns = if (should_flip) self.black.pawn.flipped() else self.white.pawn;
        if (pawns.isEmpty()) return 0;
        const possible_self_check_squares = if (should_flip) possible_self_check_squares_inp.flipped() else possible_self_check_squares_inp;
        const opponent_side = if (should_flip) self.white.flipped() else self.black;

        var move_count: usize = 0;
        const en_passant_board = BitBoard.init(if (self.en_passant_target) |tg| @as(u64, 1) << tg else 0);
        const en_passant_target = if (should_flip) en_passant_board.flipped() else en_passant_board;
        const en_passant_pawn = en_passant_target.backward(1);
        for ([_]BitBoard{ en_passant_pawn.left(1), en_passant_pawn.right(1) }) |capturing_pawn| {
            if (pawns.overlaps(capturing_pawn)) {
                move_buffer[move_count] = Move.initCapture(
                    Piece.pawnFromBitBoard(capturing_pawn),
                    Piece.pawnFromBitBoard(en_passant_target),
                    Piece.pawnFromBitBoard(en_passant_pawn),
                    true,
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
                const to = from.forwardUnchecked(1).leftUnchecked(1);
                const might_self_check = possible_self_check_squares.overlaps(from);
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
                        might_self_check,
                    );
                    move_count += 1;
                }
            }
            while (promote_captures_right.next()) |from| {
                const to = from.forwardUnchecked(1).rightUnchecked(1);
                const might_self_check = possible_self_check_squares.overlaps(from);
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
                        might_self_check,
                    );
                    move_count += 1;
                }
            }

            var captures_left = forward_left_captures.getOverlap(seventh_row.complement()).iterator();
            var captures_right = forward_right_captures.getOverlap(seventh_row.complement()).iterator();
            while (captures_left.next()) |from| {
                const to = from.forwardUnchecked(1).leftUnchecked(1);

                move_buffer[move_count] = Move.initCapture(
                    Piece.pawnFromBitBoard(from),
                    Piece.pawnFromBitBoard(to),
                    Piece.init(TargetPieceType, to),
                    possible_self_check_squares.overlaps(from),
                );
                move_count += 1;
            }
            while (captures_right.next()) |from| {
                const to = from.forwardUnchecked(1).rightUnchecked(1);
                move_buffer[move_count] = Move.initCapture(
                    Piece.pawnFromBitBoard(from),
                    Piece.pawnFromBitBoard(to),
                    Piece.init(TargetPieceType, to),
                    possible_self_check_squares.overlaps(from),
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

    pub fn getAllPawnMovesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        const first_move_count = self.getQuietPawnMovesUnchecked(move_buffer, possible_self_check_squares);
        const second_move_count = self.getPawnCapturesUnchecked(move_buffer[first_move_count..], possible_self_check_squares);
        return first_move_count + second_move_count;
    }

    pub fn getQuietKnightMovesUnchecked(self: Self, move_buffer: []Move, _: BitBoard) usize {
        const should_flip = self.turn == .black;
        const knights = if (should_flip) self.black.knight else self.white.knight;
        if (knights.isEmpty()) return 0;

        const own_pieces = if (should_flip) self.black.all() else self.white.all();
        const opponents_pieces = if (should_flip) self.white.all() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const allowed_squares = all_pieces.complement();

        var move_count: usize = 0;
        const row_offsets = [8]comptime_int{ 2, 2, -2, -2, 1, 1, -1, -1 };
        const col_offsets = [8]comptime_int{ 1, -1, 1, -1, 2, -2, 2, -2 };
        inline for (row_offsets, col_offsets) |dr, dc| {
            var iter = knights.move(dr, dc).getOverlap(allowed_squares).move(-dr, -dc).iterator();
            while (iter.next()) |knight| {
                const moved = knight.move(dr, dc);
                move_buffer[move_count] = Move.initQuiet(
                    Piece.knightFromBitBoard(knight),
                    Piece.knightFromBitBoard(moved),
                    true,
                );
                move_count += 1;
            }
        }
        return move_count;
    }

    pub fn getKnightCapturesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        const is_black_turn = self.turn == .black;
        const knights = if (is_black_turn) self.black.knight else self.white.knight;
        if (knights.isEmpty()) return 0;

        const opponent_side = if (is_black_turn) self.white else self.black;

        const opponents_pieces = if (is_black_turn) self.white.all() else self.black.all();

        var move_count: usize = 0;

        inline for (knight_drs, knight_dcs) |dr, dc| {
            var iter = knights.move(dr, dc).getOverlap(opponents_pieces).move(-dr, -dc).iterator();
            while (iter.next()) |knight| {
                const moved = knight.move(dr, dc);
                move_buffer[move_count] = Move.initCapture(
                    Piece.knightFromBitBoard(knight),
                    Piece.knightFromBitBoard(moved),
                    Piece.init(opponent_side.whichTypeUnchecked(moved), moved),
                    knight.overlaps(possible_self_check_squares),
                );
                move_count += 1;
            }
        }
        return move_count;
    }

    pub fn getAllKnightMovesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        const is_white_turn = self.turn == .white;
        const own_side = if (is_white_turn) self.white else self.black;
        const knights = own_side.knight;
        if (knights.isEmpty()) return 0;
        const opponent_side = if (is_white_turn) self.black else self.white;
        const own_pieces = own_side.all();
        const opponents_pieces = opponent_side.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const empty_squares = all_pieces.complement();

        var move_count: usize = 0;
        inline for (knight_drs, knight_dcs) |dr, dc| {
            var quiet = knights.move(dr, dc).getOverlap(empty_squares).move(-dr, -dc).iterator();
            while (quiet.next()) |knight| {
                const moved = knight.move(dr, dc);
                move_buffer[move_count] = Move.initQuiet(
                    Piece.knightFromBitBoard(knight),
                    Piece.knightFromBitBoard(moved),
                    knight.overlaps(possible_self_check_squares),
                );
                move_count += 1;
            }
            var captures = knights.move(dr, dc).getOverlap(opponents_pieces).move(-dr, -dc).iterator();
            while (captures.next()) |knight| {
                const moved = knight.move(dr, dc);
                move_buffer[move_count] = Move.initCapture(
                    Piece.knightFromBitBoard(knight),
                    Piece.knightFromBitBoard(moved),
                    Piece.init(opponent_side.whichTypeUnchecked(moved), moved),
                    knight.overlaps(possible_self_check_squares),
                );
                move_count += 1;
            }
        }
        return move_count;
    }

    fn getStraightLineMoves(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard, comptime captures_only: bool, comptime drs: anytype, comptime dcs: anytype, comptime piece_type: PieceType) usize {
        const is_black_turn = self.turn == .black;
        const pieces_of_interest = if (is_black_turn) self.black.getBoard(piece_type) else self.white.getBoard(piece_type);
        if (pieces_of_interest.isEmpty()) return 0;

        const own_pieces = if (is_black_turn) self.black.all() else self.white.all();
        const opponent_side = if (is_black_turn) self.white else self.black;
        const opponents_pieces = opponent_side.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const allowed_squares = all_pieces.complement();

        var move_count: usize = 0;

        var iter = pieces_of_interest.iterator();
        while (iter.next()) |curr| {
            for (drs, dcs) |dr, dc| {
                var moved = if (captures_only) curr.getFirstOverLappingInDir(all_pieces, dr, dc) else curr.move(dr, dc);
                const might_self_check = possible_self_check_squares.overlaps(curr);
                if (!captures_only) {
                    while (moved.overlaps(allowed_squares)) : (moved = moved.move(dr, dc)) {
                        move_buffer[move_count] = Move.initQuiet(
                            Piece.init(piece_type, curr),
                            Piece.init(piece_type, moved),
                            might_self_check,
                        );
                        move_count += 1;
                    }
                }
                if (moved.overlaps(opponents_pieces)) {
                    move_buffer[move_count] = Move.initCapture(
                        Piece.init(piece_type, curr),
                        Piece.init(piece_type, moved),
                        Piece.init(opponent_side.whichTypeUnchecked(moved), moved),
                        might_self_check,
                    );
                    move_count += 1;
                }
            }
        }
        return move_count;
    }

    pub fn getAllBishopMovesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        return getStraightLineMoves(self, move_buffer, possible_self_check_squares, false, bishop_drs, bishop_dcs, .bishop);
    }

    pub fn getBishopCapturesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        return getStraightLineMoves(self, move_buffer, possible_self_check_squares, true, bishop_drs, bishop_dcs, .bishop);
    }

    pub fn getAllRookMovesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        return getStraightLineMoves(self, move_buffer, possible_self_check_squares, false, rook_drs, rook_dcs, .rook);
    }

    pub fn getRookCapturesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        return getStraightLineMoves(self, move_buffer, possible_self_check_squares, true, rook_drs, rook_dcs, .rook);
    }

    pub fn getAllQueenMovesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        return getStraightLineMoves(self, move_buffer, possible_self_check_squares, false, bishop_drs ++ rook_drs, bishop_dcs ++ rook_dcs, .queen);
    }

    pub fn getQueenCapturesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        return getStraightLineMoves(self, move_buffer, possible_self_check_squares, true, bishop_drs ++ rook_drs, bishop_dcs ++ rook_dcs, .queen);
    }

    pub fn getQuietKingMovesUnchecked(self: Self, move_buffer: []Move, _: BitBoard) usize {
        const is_black_turn = self.turn == .black;
        const king = if (is_black_turn) self.black.king else self.white.king;
        assert(!king.isEmpty());

        const own_side = if (is_black_turn) self.black else self.white;
        const own_pieces = own_side.all();
        const opponents_pieces = if (is_black_turn) self.white.all() else self.black.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const empty_squares = all_pieces.complement();

        var move_count: usize = 0;

        var possible_places_to_move = king;
        possible_places_to_move.add(king.leftMasked(1));
        possible_places_to_move.add(king.rightMasked(1));
        possible_places_to_move.add(possible_places_to_move.forwardMasked(1));
        possible_places_to_move.add(possible_places_to_move.backwardMasked(1));
        var iter = possible_places_to_move.getOverlap(empty_squares).iterator();
        while (iter.next()) |moved| {
            move_buffer[move_count] = Move.initQuiet(
                Piece.kingFromBitBoard(king),
                Piece.kingFromBitBoard(moved),
                true,
            );
            move_count += 1;
        }

        // castling
        const starting_square = if (self.turn == .white) BitBoard.fromSquareUnchecked("E1") else BitBoard.fromSquareUnchecked("E8");
        if (king.overlaps(starting_square)) {
            const rook = own_side.rook;

            var left_rook = rook;
            left_rook.remove(rook.rightMasked(1).allRight());

            var right_rook = rook;
            right_rook.remove(rook.leftMasked(1).allLeft());

            const left_side_king = king.leftUnchecked(1).allLeft();
            const right_side_king = king.rightUnchecked(1).allRight();

            // queenside
            if ((is_black_turn and (self.castling_squares & queenside_black_castle != 0) or
                !is_black_turn and (self.castling_squares & queenside_white_castle != 0)) and
                left_side_king.getOverlap(all_pieces) == left_side_king.getOverlap(left_rook) and
                !left_side_king.getOverlap(left_rook).isEmpty() and
                !self.areSquaresAttacked(king.getCombination(king.leftUnchecked(1)).getCombination(king.leftUnchecked(2)), .auto))
            {
                move_buffer[move_count] = Move.initQuiet(
                    Piece.kingFromBitBoard(king),
                    Piece.kingFromBitBoard(king.leftUnchecked(2)),
                    true,
                );
                move_count += 1;
            }

            // kingside
            if ((is_black_turn and (self.castling_squares & kingside_black_castle != 0) or
                !is_black_turn and (self.castling_squares & kingside_white_castle != 0)) and
                right_side_king.getOverlap(all_pieces) == right_side_king.getOverlap(right_rook) and
                right_side_king.overlaps(right_rook) and
                !self.areSquaresAttacked(king.getCombination(king.rightUnchecked(1)), .auto))
            {
                move_buffer[move_count] = Move.initQuiet(
                    Piece.kingFromBitBoard(king),
                    Piece.kingFromBitBoard(king.rightUnchecked(2)),
                    true,
                );
                move_count += 1;
            }
        }
        return move_count;
    }

    pub fn getKingCapturesUnchecked(self: Self, move_buffer: []Move, _: BitBoard) usize {
        const should_flip = self.turn == .black;
        const king = if (should_flip) self.black.king else self.white.king;
        assert(!king.isEmpty());

        const opponent_side = if (should_flip) &self.white else &self.black;
        const opponents_pieces = opponent_side.all();

        var move_count: usize = 0;

        var possible_places_to_move = king;
        possible_places_to_move.add(king.leftMasked(1));
        possible_places_to_move.add(king.rightMasked(1));
        possible_places_to_move.add(possible_places_to_move.forwardMasked(1));
        possible_places_to_move.add(possible_places_to_move.backwardMasked(1));
        possible_places_to_move.remove(king);
        var iter = possible_places_to_move.getOverlap(opponents_pieces).iterator();
        while (iter.next()) |moved| {
            move_buffer[move_count] = Move.initCapture(
                Piece.kingFromBitBoard(king),
                Piece.kingFromBitBoard(moved),
                Piece.init(opponent_side.whichTypeUnchecked(moved), moved),
                true,
            );
            move_count += 1;
        }
        return move_count;
    }

    pub fn getAllKingMovesUnchecked(self: Self, move_buffer: []Move, _: BitBoard) usize {
        const is_black_turn = self.turn == .black;
        const king = if (is_black_turn) self.black.king else self.white.king;
        assert(!king.isEmpty());

        const own_side = if (is_black_turn) self.black else self.white;
        const own_pieces = own_side.all();
        const opponent_side = if (is_black_turn) self.white else self.black;
        const opponents_pieces = opponent_side.all();
        const all_pieces = own_pieces.getCombination(opponents_pieces);
        const empty_squares = all_pieces.complement();

        var move_count: usize = 0;

        var possible_places_to_move = king;
        possible_places_to_move.add(king.leftMasked(1));
        possible_places_to_move.add(king.rightMasked(1));
        possible_places_to_move.add(possible_places_to_move.forwardMasked(1));
        possible_places_to_move.add(possible_places_to_move.backwardMasked(1));

        for (knight_drs, knight_dcs) |dr, dc| {
            const dangers = possible_places_to_move.move(dr, dc).getOverlap(opponent_side.knight);
            possible_places_to_move.remove(dangers.move(-dr, -dc));
        }
        possible_places_to_move.remove(king);

        var captures = possible_places_to_move.getOverlap(opponents_pieces).iterator();
        while (captures.next()) |moved| {
            move_buffer[move_count] = Move.initCapture(
                Piece.kingFromBitBoard(king),
                Piece.kingFromBitBoard(moved),
                Piece.init(opponent_side.whichTypeUnchecked(moved), moved),
                true,
            );
            move_count += 1;
        }
        var quiet = possible_places_to_move.getOverlap(empty_squares).iterator();
        while (quiet.next()) |moved| {
            move_buffer[move_count] = Move.initQuiet(
                Piece.kingFromBitBoard(king),
                Piece.kingFromBitBoard(moved),
                true,
            );
            move_count += 1;
        }

        // castling
        const starting_square = if (self.turn == .white) BitBoard.fromSquareUnchecked("E1") else BitBoard.fromSquareUnchecked("E8");
        if (king.overlaps(starting_square)) {
            const rook = own_side.rook;

            var left_rook = rook;
            left_rook.remove(rook.rightMasked(1).allRight());

            var right_rook = rook;
            right_rook.remove(rook.leftMasked(1).allLeft());

            const left_side_king = king.leftUnchecked(1).allLeft();
            const right_side_king = king.rightUnchecked(1).allRight();

            // queenside
            if (self.castling_squares & queenside_white_castle << 2 * @as(u2, @intFromBool(is_black_turn)) != 0 and
                left_side_king.getOverlap(all_pieces) == left_side_king.getOverlap(left_rook) and
                !left_side_king.getOverlap(left_rook).isEmpty() and
                !self.areSquaresAttacked(king.getCombination(king.leftUnchecked(1)).getCombination(king.leftUnchecked(2)), .auto))
            {
                move_buffer[move_count] = Move.initQuiet(
                    Piece.kingFromBitBoard(king),
                    Piece.kingFromBitBoard(king.leftUnchecked(2)),
                    true,
                );
                move_count += 1;
            }

            // kingside
            if (self.castling_squares & kingside_white_castle << 2 * @as(u2, @intFromBool(is_black_turn)) != 0 and
                right_side_king.getOverlap(all_pieces) == right_side_king.getOverlap(right_rook) and
                right_side_king.overlaps(right_rook) and
                !self.areSquaresAttacked(king.getCombination(king.rightUnchecked(1)), .auto))
            {
                move_buffer[move_count] = Move.initQuiet(
                    Piece.kingFromBitBoard(king),
                    Piece.kingFromBitBoard(king.rightUnchecked(2)),
                    true,
                );
                move_count += 1;
            }
        }
        return move_count;
    }

    pub fn getAllKingMoves(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        const unfiltered_count = self.getAllKingMovesUnchecked(move_buffer, possible_self_check_squares);
        return self.filterMoves(move_buffer[0..unfiltered_count]);
    }

    pub fn getAllMovesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        var res: usize = 0;
        res += self.getAllPawnMovesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getAllKnightMovesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getAllBishopMovesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getAllRookMovesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getAllQueenMovesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getAllKingMovesUnchecked(move_buffer[res..], possible_self_check_squares);
        return res;
    }

    pub fn filterMoves(self: Self, move_buffer: []Move) usize {
        var filtered_count: usize = 0;
        var board = self;
        for (move_buffer) |move| {
            if (!board.doesMoveCauseSelfCheck(move)) {
                move_buffer[filtered_count] = move;
                filtered_count += 1;
            }
        }
        return filtered_count;
    }

    pub var in_check_cnt: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
    pub var total: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

    pub fn getSelfCheckSquares(self: Self) BitBoard {
        const own_side = if (self.turn == .white) self.white else self.black;
        const opponent_side = if (self.turn == .white) self.black else self.white;
        var own_pieces = own_side.pawn;
        own_pieces.add(own_side.knight);
        own_pieces.add(own_side.bishop);
        own_pieces.add(own_side.rook);
        own_pieces.add(own_side.queen);
        const all_pieces = opponent_side.all().getCombination(own_pieces);

        var is_in_check = false;
        var self_check_squares = own_side.king;
        for (rook_drs, rook_dcs) |dr, dc| {
            var dir = own_side.king.move(dr, dc).allDirection(dr, dc);
            const first = dir.getOverlap(all_pieces);
            const second = first.move(dr, dc).allDirection(dr, dc).getOverlap(all_pieces);
            const enemy_piece = second.getOverlap(opponent_side.rook.getCombination(opponent_side.queen));
            const enemy_back = enemy_piece.allDirection(-dr, -dc);
            const pinned = enemy_back.getOverlap(own_pieces);
            dir.remove(enemy_piece.move(dr, dc).allDirection(dr, dc));

            is_in_check = is_in_check or first.overlaps(opponent_side.rook.getCombination(opponent_side.queen));
            self_check_squares.add(pinned);
        }
        for (bishop_drs, bishop_dcs) |dr, dc| {
            var dir = own_side.king.move(dr, dc).allDirection(dr, dc);
            const first = dir.getOverlap(all_pieces);
            const second = first.move(dr, dc).allDirection(dr, dc).getOverlap(all_pieces);
            const enemy_piece = second.getOverlap(opponent_side.bishop.getCombination(opponent_side.queen));
            const enemy_back = enemy_piece.allDirection(-dr, -dc);
            const pinned = enemy_back.getOverlap(own_pieces);
            dir.remove(enemy_piece.move(dr, dc).allDirection(dr, dc));

            is_in_check = is_in_check or first.overlaps(opponent_side.bishop.getCombination(opponent_side.queen));
            is_in_check = is_in_check or (own_side.king.move(dr, dc).overlaps(opponent_side.pawn) and (dr == 1) == (self.turn == .white));
            self_check_squares.add(pinned);
        }
        for (knight_drs, knight_dcs) |dr, dc| {
            is_in_check = is_in_check or own_side.king.move(dr, dc).overlaps(opponent_side.knight);
        }
        if (is_in_check) self_check_squares = BitBoard.initEmpty().complement();

        if (std.debug.runtime_safety) {
            _ = total.fetchAdd(1, .acq_rel);
            if (is_in_check)
                _ = in_check_cnt.fetchAdd(1, .acq_rel);
        }

        return self_check_squares;
    }

    pub fn getAllMoves(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        const unfiltered_count = self.getAllMovesUnchecked(move_buffer, possible_self_check_squares);
        return self.filterMoves(move_buffer[0..unfiltered_count]);
    }

    pub fn getAllCapturesUnchecked(self: Self, move_buffer: []Move, possible_self_check_squares: BitBoard) usize {
        var res: usize = 0;
        res += self.getPawnCapturesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getKnightCapturesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getBishopCapturesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getRookCapturesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getQueenCapturesUnchecked(move_buffer[res..], possible_self_check_squares);
        res += self.getKingCapturesUnchecked(move_buffer[res..], possible_self_check_squares);
        return res;
    }

    pub fn perftZobrist(self: *Self, move_buf: []Move, depth_remaining: usize, zobrist_list: anytype) !void {
        if (depth_remaining == 0) return;
        const num_moves = self.getAllMovesUnchecked(move_buf, self.getSelfCheckSquares());
        const moves = move_buf[0..num_moves];
        for (moves) |move| {
            try testing.expect(move.eql(self.decompressMove(self.compressMove(move))));
            if (self.playMovePossibleSelfCheck(move)) |inv| {
                defer self.undoMove(inv);
                var hash = std.hash.CityHash64.hash(&std.mem.toBytes(self.white));
                hash +%= std.hash.CityHash64.hash(&std.mem.toBytes(self.black));
                hash +%= std.hash.CityHash64.hash(&std.mem.toBytes(self.castling_squares));
                hash +%= std.hash.CityHash64.hash(&std.mem.toBytes(self.en_passant_target));
                try zobrist_list.append(.{ .zobrist = self.zobrist, .other_hash = hash });
                try perftZobrist(self, move_buf[num_moves..], depth_remaining - 1, zobrist_list);
            }
        }
    }

    pub fn perftSingleThreaded(self: *Self, move_buf: []Move, depth_remaining: usize) u64 {
        if (depth_remaining == 0) return 0;
        const num_moves = self.getAllMovesUnchecked(move_buf, self.getSelfCheckSquares());
        const moves = move_buf[0..num_moves];
        var res: u64 = 0;
        if (depth_remaining == 1) {
            for (moves) |move| {
                if (!self.doesMoveCauseSelfCheck(move))
                    res += 1;
            }
        } else {
            for (moves) |move| {
                if (self.playMovePossibleSelfCheck(move)) |inv| {
                    defer self.undoMove(inv);
                    res += perftSingleThreaded(self, move_buf[num_moves..], depth_remaining - 1);
                }
            }
        }
        return res;
    }

    pub fn perftSingleThreadedNonBulk(self: *Self, move_buf: []Move, depth_remaining: usize) u64 {
        if (depth_remaining == 0) return 1;
        const num_moves = self.getAllMovesUnchecked(move_buf, self.getSelfCheckSquares());
        const moves = move_buf[0..num_moves];
        var res: u64 = 0;
        for (moves) |move| {
            if (self.playMovePossibleSelfCheck(move)) |inv| {
                defer self.undoMove(inv);
                res += perftSingleThreadedNonBulk(self, move_buf[num_moves..], depth_remaining - 1);
            }
        }
        return res;
    }

    fn perftMultiThreadedWorkerFn(res_: *std.atomic.Value(u64), board_: Self, move_buf_: []Move, depth_remaining_: usize) void {
        var board = board_;
        _ = res_.fetchAdd(board.perftSingleThreaded(move_buf_, depth_remaining_), .acquire);
    }

    pub fn perftMultiThreaded(inp: Self, move_buf: []Move, depth_remaining: usize, allocator: std.mem.Allocator) !u64 {
        var self = inp;
        if (depth_remaining < 3) return self.perftSingleThreaded(move_buf, depth_remaining);
        if (depth_remaining == 0) return 0;

        const num_moves1 = self.getAllMovesUnchecked(move_buf, self.getSelfCheckSquares());
        const moves1 = move_buf[0..num_moves1];
        var res = std.atomic.Value(u64).init(0);

        const thread_count = 400;
        assert(thread_count > num_moves1);
        var threads: std.Thread.Pool = undefined;
        try threads.init(.{
            .n_jobs = null,
            .allocator = allocator,
        });
        defer threads.deinit();
        var wg = std.Thread.WaitGroup{};
        var move_buf1 = move_buf[num_moves1..];
        const amount_per_thread = move_buf1.len / num_moves1;

        for (moves1) |move1| {
            var board1 = self;
            const cur_move_buf1 = move_buf1[0..amount_per_thread];
            move_buf1 = move_buf1[amount_per_thread..];

            if (board1.playMovePossibleSelfCheck(move1)) |_| {
                const num_moves2 = board1.getAllMovesUnchecked(cur_move_buf1, board1.getSelfCheckSquares());
                const moves2 = cur_move_buf1[0..num_moves2];
                var move_buf2 = cur_move_buf1[num_moves2..];
                const amount_per_move = move_buf2.len / num_moves2;

                for (moves2) |move2| {
                    var board2 = board1;
                    const cur_move_buf2 = move_buf2[0..amount_per_move];
                    move_buf2 = move_buf2[amount_per_move..];

                    if (board2.playMovePossibleSelfCheck(move2)) |_| {
                        threads.spawnWg(&wg, perftMultiThreadedWorkerFn, .{ &res, board2, cur_move_buf2, depth_remaining - 2 });
                    }
                }
            }
        }
        threads.waitAndWork(&wg);

        return res.load(.seq_cst);
    }
};

const testing = std.testing;

fn expectNumCaptures(moves: []Move, count: usize) !void {
    var actual_count: usize = 0;
    for (moves) |move| actual_count += @intFromBool(move.isCapture());
    if (count != actual_count) {
        std.log.err("Expected {} captures, found {}. Captures found:\n", .{ count, actual_count });
        for (moves) |move| {
            if (move.isCapture()) {
                std.log.err("{}\n", .{move});
            }
        }
        return error.WrongNumberCaptures;
    }
}

fn expectNumCastling(moves: []Move, count: usize) !void {
    var actual_count: usize = 0;
    for (moves) |move| actual_count += @intFromBool(move.isCastlingMove());
    if (count != actual_count) {
        std.log.err("Expected {} castling moves, found {}. Castling moves found:\n", .{ count, actual_count });
        for (moves) |move| {
            if (move.isCastlingMove()) {
                std.log.err("{}\n", .{move});
            }
        }
        return error.WrongNumberCastling;
    }
}

fn expectMovesInvertible(board: Board, moves: []Move) !void {
    const hash_before = board.zobrist;
    for (moves) |move| {
        var tmp = board;
        const inv = tmp.playMove(move);
        tmp.undoMove(inv);
        try std.testing.expectEqual(board.fullmove_clock, tmp.fullmove_clock);
        try std.testing.expectEqual(board.halfmove_clock, tmp.halfmove_clock);
        try std.testing.expectEqual(board.turn, tmp.turn);
        try std.testing.expectEqual(board.castling_squares, tmp.castling_squares);
        try std.testing.expectEqual(board.white, tmp.white);
        try std.testing.expectEqual(board.black, tmp.black);
        try std.testing.expectEqualDeep(board, tmp);
        try testing.expectEqual(tmp.zobrist, hash_before);
        tmp.resetZobrist();
        try testing.expectEqual(tmp.zobrist, hash_before);
    }
}

fn expectCapturesImplyAttacked(board: Board, moves: []Move) !void {
    for (moves) |move| {
        if (move.isCapture()) {
            try std.testing.expect(board.areSquaresAttacked(move.to().getBoard(), .flip));
        }
    }
}

fn expectMovesCompressible(board: Board, moves: []Move) !void {
    for (moves) |move| {
        try std.testing.expect(move.eql(board.decompressMove(board.compressMove(move))));
    }
}

fn testCase(fen: []const u8, func: anytype, expected_moves: usize, expected_captures: usize, expected_castling: usize) !void {
    var buf: [400]Move = undefined;
    const board = try Board.parseFen(fen);
    try testing.expectEqualSlices(u8, fen, board.toFen().slice());
    const num_moves = func(board, &buf, board.getSelfCheckSquares());
    testing.expectEqual(expected_moves, num_moves) catch |e| {
        for (buf[0..num_moves]) |move| {
            std.debug.print("{}\n", .{move});
        }
        return e;
    };
    const moves = buf[0..num_moves];
    try expectNumCaptures(moves, expected_captures);
    try expectNumCastling(moves, expected_castling);
    try expectMovesInvertible(board, moves);
    try expectCapturesImplyAttacked(board, moves);
    try expectMovesCompressible(board, moves);
}

fn expectZobristResetInvertible(board: Board) !void {
    var tmp = board;
    const before = board.zobrist;
    tmp.resetZobrist();
    try testing.expectEqual(before, tmp.zobrist);
}

test "failing" {}

test "fen parsing" {
    try testing.expectError(error.NotEnoughRows, Board.parseFen(""));
    try testing.expectError(error.EnPassantTargetDoesntExist, Board.parseFen("8/k7/8/4P3/8/8/K7/8 w - d6 0 1"));
    try testing.expect(!std.meta.isError(Board.parseFen("8/k7/8/3pP3/8/8/K7/8 w - d6 0 1")));
}

test "quiet pawn moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getQuietPawnMovesUnchecked, 16, 0, 0);
    try testCase("8/8/p7/P1P5/2K2kP1/5P2/2P4P/8 w - - 0 1", Board.getQuietPawnMovesUnchecked, 5, 0, 0);
    try testCase("8/8/p7/P7/2K2k2/2P5/8/8 w - - 0 1", Board.getQuietPawnMovesUnchecked, 0, 0, 0);
    try testCase("8/P7/8/8/2K2k2/8/8/8 w - - 0 1", Board.getQuietPawnMovesUnchecked, 4, 0, 0);
}

test "pawn captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getPawnCapturesUnchecked, 0, 0, 0);
    try testCase("8/8/p7/P1P5/2K2kP1/5P2/2P4P/8 w - - 0 1", Board.getPawnCapturesUnchecked, 0, 0, 0);
    try testCase("8/8/p7/P7/2K2k2/2P5/8/8 w - - 0 1", Board.getPawnCapturesUnchecked, 0, 0, 0);
    try testCase("8/8/p1q5/1P1P4/2K2k2/2P5/8/8 w - - 0 1", Board.getPawnCapturesUnchecked, 3, 3, 0);
    try testCase("8/k7/8/3pP3/8/8/K7/8 w - d6 0 1", Board.getPawnCapturesUnchecked, 1, 1, 0);
    try testCase("8/k7/8/8/3pP3/8/K7/8 b - e3 0 1", Board.getPawnCapturesUnchecked, 1, 1, 0);
    try testCase("1p6/P7/8/8/2K2k2/8/8/8 w - - 0 1", Board.getPawnCapturesUnchecked, 4, 4, 0);
    try testCase("p1p5/1P6/8/8/2K2k2/8/8/8 w - - 0 1", Board.getPawnCapturesUnchecked, 8, 8, 0);
}

test "quiet knight moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getQuietKnightMovesUnchecked, 4, 0, 0);
    try testCase("8/6k1/8/8/8/3N4/1K6/8 w - - 0 1", Board.getQuietKnightMovesUnchecked, 7, 0, 0);
    try testCase("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1", Board.getQuietKnightMovesUnchecked, 14, 0, 0);
    try testCase("K7/6k1/8/8/8/8/8/NN6 w - - 0 1", Board.getQuietKnightMovesUnchecked, 5, 0, 0);
    try testCase("K7/6k1/8/8/8/ppp5/2pp4/NN6 w - - 0 1", Board.getQuietKnightMovesUnchecked, 0, 0, 0);
    try testCase("K7/6k1/8/8/8/ppp5/3p4/NN6 w - - 0 1", Board.getQuietKnightMovesUnchecked, 1, 0, 0);
}

test "knight captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getKnightCapturesUnchecked, 0, 0, 0);
    try testCase("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1", Board.getKnightCapturesUnchecked, 1, 1, 0);
    try testCase("K7/6k1/8/8/8/8/8/NN6 w - - 0 1", Board.getKnightCapturesUnchecked, 0, 0, 0);
    try testCase("K7/6k1/8/8/8/ppp5/2pp4/NN6 w - - 0 1", Board.getKnightCapturesUnchecked, 5, 5, 0);
    try testCase("K7/6k1/8/8/8/ppp5/3p4/NN6 w - - 0 1", Board.getKnightCapturesUnchecked, 4, 4, 0);
    try testCase("K1k5/8/8/8/8/8/6p1/N7 w - - 0 1", Board.getKnightCapturesUnchecked, 0, 0, 0);
    try testCase("K1k4N/8/8/8/8/8/6p1/8 w - - 0 1", Board.getKnightCapturesUnchecked, 0, 0, 0);
}

test "all knight moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllKnightMovesUnchecked, 4, 0, 0);
    try testCase("8/6k1/8/5p2/8/3NN3/1K6/8 w - - 0 1", Board.getAllKnightMovesUnchecked, 15, 1, 0);
    try testCase("K7/6k1/8/8/8/8/8/NN6 w - - 0 1", Board.getAllKnightMovesUnchecked, 5, 0, 0);
    try testCase("K7/6k1/8/8/8/ppp5/2pp4/NN6 w - - 0 1", Board.getAllKnightMovesUnchecked, 5, 5, 0);
    try testCase("K7/6k1/8/8/8/ppp5/3p4/NN6 w - - 0 1", Board.getAllKnightMovesUnchecked, 5, 4, 0);
    try testCase("K1k5/8/8/8/8/8/6p1/N7 w - - 0 1", Board.getAllKnightMovesUnchecked, 2, 0, 0);
    try testCase("K1k4N/8/8/8/8/8/6p1/8 w - - 0 1", Board.getAllKnightMovesUnchecked, 2, 0, 0);
}

test "bishop captures" {
    try testCase("k7/8/8/5p2/8/3B4/8/K7 w - - 0 1", Board.getBishopCapturesUnchecked, 1, 1, 0);
    try testCase("7r/2k3p1/8/b7/8/2B5/8/1K6 w - - 0 1", Board.getBishopCapturesUnchecked, 2, 2, 0);
    try testCase("7r/2k3p1/8/b7/8/2B5/8/1K6 b - - 0 1", Board.getBishopCapturesUnchecked, 1, 1, 0);
}

test "all bishop moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllBishopMovesUnchecked, 0, 0, 0);
    try testCase("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3", Board.getAllBishopMovesUnchecked, 5, 0, 0);
    try testCase("k7/8/8/8/8/3B4/8/K7 w - - 0 1", Board.getAllBishopMovesUnchecked, 11, 0, 0);
    try testCase("k7/8/8/5p2/8/3B4/8/K7 w - - 0 1", Board.getAllBishopMovesUnchecked, 9, 1, 0);
    try testCase("7r/2k3p1/8/b7/8/2B5/8/1K6 b - - 0 1", Board.getAllBishopMovesUnchecked, 3, 1, 0);
}

test "rook captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getRookCapturesUnchecked, 0, 0, 0);
    try testCase("k7/8/8/3R1p2/8/8/8/K7 w - - 0 1", Board.getRookCapturesUnchecked, 1, 1, 0);
    try testCase("k7/8/8/3RRp2/8/8/8/K7 w - - 0 1", Board.getRookCapturesUnchecked, 1, 1, 0);
    try testCase("7k/8/8/8/3rrP2/8/8/7K b - - 0 1", Board.getRookCapturesUnchecked, 1, 1, 0);
}

test "all rook moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllRookMovesUnchecked, 0, 0, 0);
    try testCase("k7/8/8/3R1p2/8/8/8/K7 w - - 0 1", Board.getAllRookMovesUnchecked, 12, 1, 0);
    try testCase("k7/8/8/3RRp2/8/8/8/K7 w - - 0 1", Board.getAllRookMovesUnchecked, 18, 1, 0);
    try testCase("7k/8/8/8/3rrP2/8/8/7K b - - 0 1", Board.getAllRookMovesUnchecked, 18, 1, 0);
}

test "queen captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getQueenCapturesUnchecked, 0, 0, 0);
    try testCase("8/k7/8/3Q1p2/8/8/8/K7 w - - 0 1", Board.getQueenCapturesUnchecked, 1, 1, 0);
    try testCase("8/k7/8/3QQp2/8/8/8/K7 w - - 0 1", Board.getQueenCapturesUnchecked, 1, 1, 0);
    try testCase("7k/8/8/8/3qqP2/8/7K/8 b - - 0 1", Board.getQueenCapturesUnchecked, 1, 1, 0);
}

test "all queen moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllQueenMovesUnchecked, 0, 0, 0);
    try testCase("7k/8/8/3q4/8/8/7K/8 b - - 0 1", Board.getAllQueenMovesUnchecked, 27, 0, 0);
    try testCase("7k/8/8/3q2P1/8/8/7K/8 b - - 0 1", Board.getAllQueenMovesUnchecked, 26, 1, 0);
}

test "quiet king moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getQuietKingMovesUnchecked, 0, 0, 0);
    try testCase("8/1k6/8/8/8/8/PPP5/1K6 w - - 0 1", Board.getQuietKingMovesUnchecked, 2, 0, 0);
    try testCase("k7/8/8/3K4/8/8/8/8 w - - 0 1", Board.getQuietKingMovesUnchecked, 8, 0, 0);
    try testCase("K7/8/8/3k4/8/8/8/8 b - - 0 1", Board.getQuietKingMovesUnchecked, 8, 0, 0);
}

test "king captures" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getKingCapturesUnchecked, 0, 0, 0);
    try testCase("8/1k6/8/8/8/8/1p6/1K6 w - - 0 1", Board.getKingCapturesUnchecked, 1, 1, 0);
    try testCase("8/1k6/8/8/8/2pKp3/2p1p3/8 w - - 0 1", Board.getKingCapturesUnchecked, 4, 4, 0);
    try testCase("8/1k6/8/8/2p5/2pKp3/2p1p3/8 w - - 0 1", Board.getKingCapturesUnchecked, 5, 5, 0);
    try testCase("K7/8/8/2Pk4/8/8/8/8 b - - 0 1", Board.getKingCapturesUnchecked, 1, 1, 0);
}

test "all king moves" {
    try testCase("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Board.getAllKingMovesUnchecked, 0, 0, 0);
    try testCase("8/1k6/8/8/8/8/1p6/1K6 w - - 0 1", Board.getAllKingMovesUnchecked, 5, 1, 0);
    try testCase("8/1k6/8/8/8/2pKp3/2p1p3/8 w - - 0 1", Board.getAllKingMovesUnchecked, 8, 4, 0);
    try testCase("8/1k6/8/8/2p5/2pKp3/2p1p3/8 w - - 0 1", Board.getAllKingMovesUnchecked, 8, 5, 0);
    try testCase("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1", Board.getAllKingMovesUnchecked, 6, 0, 1);
    try testCase("r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4", Board.getAllKingMovesUnchecked, 3, 0, 1);
    try testCase("3k4/8/8/8/8/8/3PPPPP/3QK2R w - - 0 1", Board.getAllKingMovesUnchecked, 1, 0, 0);
    try testCase("3k4/8/8/8/8/8/3PPPPP/3QK2R w K - 0 1", Board.getAllKingMovesUnchecked, 2, 0, 1);
    try testCase("3k4/8/8/8/8/8/8/R3K2R w KQ - 0 1", Board.getAllKingMovesUnchecked, 7, 0, 2);
    try testCase("rnN2k1r/pp2bppp/2p5/8/2B5/8/PPP1NnPP/RNBqK2R w KQ - 0 9", Board.getAllKingMoves, 1, 1, 0);
    try testCase("5k2/8/8/8/8/8/5n2/3qK2R w K - 0 9", Board.getAllMoves, 1, 1, 0);
}

test "en passant on d6" {
    var board = Board.init();
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E2")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("A7")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("A6")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E4")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E5")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("D7")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("D5")), true));
    var buf: [400]Move = undefined;
    const pawn_captures = board.getPawnCapturesUnchecked(&buf, board.getSelfCheckSquares());
    try testing.expectEqual(1, pawn_captures);
    try expectMovesInvertible(board, buf[0..pawn_captures]);
    try expectCapturesImplyAttacked(board, buf[0..pawn_captures]);
}

test "en passant on a6" {
    var board = Board.init();
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("B2")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("B4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("H7")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("H6")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("B4")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("B5")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("A7")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("A5")), true));
    var buf: [400]Move = undefined;
    const pawn_captures = board.getPawnCapturesUnchecked(&buf, board.getSelfCheckSquares());
    try testing.expectEqual(1, pawn_captures);
    try expectMovesInvertible(board, buf[0..pawn_captures]);
    try expectCapturesImplyAttacked(board, buf[0..pawn_captures]);
}

test "en passant on h6" {
    var board = Board.init();
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("G2")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("G4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("A7")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("A6")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("G4")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("G5")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("H7")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("H5")), true));
    var buf: [400]Move = undefined;
    const pawn_captures = board.getPawnCapturesUnchecked(&buf, board.getSelfCheckSquares());
    try testing.expectEqual(1, pawn_captures);
    try expectMovesInvertible(board, buf[0..pawn_captures]);
    try expectCapturesImplyAttacked(board, buf[0..pawn_captures]);
}

test "en passant on d3" {
    var board = Board.init();
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("G2")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("G3")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E7")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E5")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("G3")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("G4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E5")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("E4")), true));
    _ = board.playMove(Move.initQuiet(Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("D2")), Piece.pawnFromBitBoard(BitBoard.fromSquareUnchecked("D4")), true));
    var buf: [400]Move = undefined;
    const pawn_moves = board.getAllPawnMovesUnchecked(&buf, board.getSelfCheckSquares());
    try testing.expectEqual(16, pawn_moves);
    try expectMovesInvertible(board, buf[0..pawn_moves]);
    try expectCapturesImplyAttacked(board, buf[0..pawn_moves]);
}

test "cant castle when in between square is attacked by knight" {
    try testCase("r3k2r/p1ppqpb1/bnN1pnp1/3P4/1p2P3/2N2Q1p/PPPBBPPP/R3K2R b KQkq - 1 1", Board.getAllMoves, 41, 8, 1);
}

test "castling blocked by bishop" {
    try testCase("5k2/8/b7/8/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 7, 0, 0);
    try testCase("5k2/8/1b6/8/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 8, 0, 0);
    try testCase("5k2/8/8/b7/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 4, 0, 0);
    try testCase("5k2/8/8/3b4/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 10, 0, 1);
    try testCase("5k2/8/8/3b4/8/8/7P/4K2R w K - 0 9", Board.getAllMoves, 10, 0, 1);
}

test "fools mate" {
    var board = Board.init();
    var buf: [1024]Move = undefined;
    _ = try board.playMoveFromSquare("f2f3", &buf);
    _ = try board.playMoveFromSquare("e7e6", &buf);
    _ = try board.playMoveFromSquare("g2g4", &buf);
    _ = try board.playMoveFromSquare("d8h4", &buf);

    try testing.expectEqual(.black, board.gameOver());
}

comptime {
    // @compileLog(@sizeOf(Board));
    // @compileLog(@sizeOf(Board) + 50 * @sizeOf(usize) + 1);

    std.testing.refAllDeclsRecursive(@This());
}
