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

test {
    std.testing.refAllDecls(@This());
}

pub const Bitboard = @import("Bitboard.zig");
pub const Board = @import("Board.zig");
pub const Move = @import("move.zig").Move;
pub const movegen = @import("movegen.zig");
pub const attacks = @import("attacks.zig");
pub const zobrist = @import("zobrist.zig");
pub const PerftEPDParser = @import("PerftEPDParser.zig");
pub const evaluation = @import("evaluation.zig");
pub const Searcher = @import("Searcher.zig");
pub const engine = @import("engine.zig");
pub const Limits = @import("Limits.zig");
pub const MovePicker = @import("MovePicker.zig");
pub const CastlingRights = @import("CastlingRights.zig");
pub const history = @import("history.zig");
pub const tuning = @import("tuning.zig");
pub const tunable_constants = tuning.tunable_constants;
pub const SEE = @import("SEE.zig");
pub const refreshCache = @import("refresh_cache.zig").refreshCache;
pub const viriformat = @import("viriformat.zig");
pub const wdl = @import("wdl.zig");

pub const is_0_14_0 = @import("builtin").zig_version.minor >= 14;

const assert = std.debug.assert;

pub const Colour = enum(u1) {
    white = 0,
    black = 1,

    pub fn fromInt(i: u8) Colour {
        return @enumFromInt(@as(u1, @intCast(i)));
    }

    pub fn toInt(self: Colour) u8 {
        return @intFromBool(self == .black);
    }

    pub fn flipped(self: Colour) Colour {
        return fromInt(self.toInt() ^ 1);
    }
};

pub fn init() void {
    const globals = struct {
        fn initImpl() void {
            stdout = std.io.getStdOut();
            attacks.init();
            evaluation.init();
            engine.reset();
            engine.setTTSize(16) catch std.debug.panic("Fatal: couldn't allocate default TT size\n", .{});
            engine.setThreadCount(1) catch std.debug.panic("Fatal: couldn't allocate default thread count\n", .{});
        }
        var init_once = std.once(initImpl);
    };
    globals.init_once.call();
}

pub fn deinit() void {
    const globals = struct {
        fn deinitImpl() void {
            stdout = std.io.getStdOut();
            attacks.init();
        }
        var deinit_once = std.once(deinitImpl);
    };
    globals.deinit_once.call();
}

pub const Square = enum(u8) {
    // zig fmt: off
    a1, b1, c1, d1, e1, f1, g1, h1,
    a2, b2, c2, d2, e2, f2, g2, h2,
    a3, b3, c3, d3, e3, f3, g3, h3,
    a4, b4, c4, d4, e4, f4, g4, h4,
    a5, b5, c5, d5, e5, f5, g5, h5,
    a6, b6, c6, d6, e6, f6, g6, h6,
    a7, b7, c7, d7, e7, f7, g7, h7,
    a8, b8, c8, d8, e8, f8, g8, h8,
    // zig fmt: on

    pub fn fromInt(int: u8) Square {
        return @enumFromInt(int);
    }

    pub fn toInt(self: Square) u6 {
        return @intCast(@intFromEnum(self));
    }

    pub fn getFile(self: Square) File {
        return File.fromInt(@intCast(self.toInt() % 8));
    }

    pub fn getRank(self: Square) Rank {
        return Rank.fromInt(@intCast(self.toInt() / 8));
    }

    pub fn fromBitboard(bitboard: u64) Square {
        assert(@popCount(bitboard) == 1);
        return fromInt(@intCast(@ctz(bitboard)));
    }

    pub fn toBitboard(self: Square) u64 {
        return @as(u64, 1) << self.toInt();
    }

    pub fn fromRankFile(rank: anytype, file: anytype) Square {
        return Square.a1.move(rank, file);
    }

    pub fn move(self: Square, d_rank: anytype, d_file: anytype) Square {
        const actual_d_rank = if (std.meta.hasFn(@TypeOf(d_rank), "toInt")) d_rank.toInt() else d_rank;
        const actual_d_file = if (std.meta.hasFn(@TypeOf(d_file), "toInt")) d_file.toInt() else d_file;
        return fromInt(@intCast(self.toInt() + @as(i8, @intCast(actual_d_rank)) * 8 + @as(i8, @intCast(actual_d_file))));
    }

    pub fn parse(square: []const u8) !Square {
        const rank = square[1] -% '1';
        if (rank > 7) return error.InvalidRank;
        const file = std.ascii.toLower(square[0]) -% 'a';
        if (file > 7) return error.InvalidFile;
        return @enumFromInt(rank * 8 + file);
    }

    pub fn flipRank(self: Square) Square {
        return fromInt(self.toInt() ^ 0b111000);
    }

    pub fn flipFile(self: Square) Square {
        return fromInt(self.toInt() ^ 0b000111);
    }
};

pub const File = enum {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,

    pub fn fromInt(int: u3) File {
        return @enumFromInt(int);
    }

    pub fn toInt(self: File) u3 {
        return @intFromEnum(self);
    }

    pub fn parse(file: u8) !File {
        const idx = std.ascii.toLower(file) -% 'a';
        if (idx >= 8) return error.InvalidFile;
        return @enumFromInt(idx);
    }

    pub fn cmp(_: void, lhs: File, rhs: File) bool {
        return @intFromEnum(lhs) < @intFromEnum(rhs);
    }

    pub fn toAsciiLetter(self: File) u8 {
        return @as(u8, 'a') + self.toInt();
    }
};

pub const Rank = enum {
    first,
    second,
    third,
    fourth,
    fifth,
    sixth,
    seventh,
    eighth,

    pub fn fromInt(int: u3) Rank {
        return @enumFromInt(int);
    }

    pub fn toInt(self: Rank) u3 {
        return @intFromEnum(self);
    }

    pub fn parse(rank: u8) !Rank {
        const idx = rank -% '1';
        if (idx >= 8) return error.InvalidRank;
        return @enumFromInt(idx);
    }

    pub fn cmp(_: void, lhs: Rank, rhs: Rank) bool {
        return @intFromEnum(lhs) < @intFromEnum(rhs);
    }
};

pub const PieceType = enum {
    pawn,
    knight,
    bishop,
    rook,
    queen,
    king,

    pub const all = [_]PieceType{
        .pawn,
        .knight,
        .bishop,
        .rook,
        .queen,
        .king,
    };

    pub fn fromInt(i: u8) PieceType {
        return @enumFromInt(i);
    }

    pub fn toInt(self: PieceType) u8 {
        return @intFromEnum(self);
    }

    pub fn toAsciiLetter(self: PieceType) u8 {
        return switch (self) {
            .pawn => 'p',
            .knight => 'n',
            .bishop => 'b',
            .rook => 'r',
            .queen => 'q',
            .king => 'k',
        };
    }

    pub fn fromAsciiLetter(char: u8) ?PieceType {
        return switch (std.ascii.toLower(char)) {
            'p' => .pawn,
            'n' => .knight,
            'b' => .bishop,
            'r' => .rook,
            'q' => .queen,
            'k' => .king,
            else => null,
        };
    }
};

pub const NullableColouredPieceType = struct {
    data: u8 = null_bit,
    const null_bit = 128;

    pub inline fn isNull(self: NullableColouredPieceType) bool {
        return self.data & null_bit != 0;
    }

    pub inline fn from(ocpt: ?ColouredPieceType) NullableColouredPieceType {
        return if (ocpt) |cpt| fromColouredPieceType(cpt) else .{};
    }

    pub inline fn opt(self: NullableColouredPieceType) ?ColouredPieceType {
        return if (self.isNull()) null else self.toColouredPieceType();
    }

    pub inline fn fromColouredPieceType(cpt: ColouredPieceType) NullableColouredPieceType {
        return .{ .data = @intCast(cpt.toInt()) };
    }

    pub inline fn toColouredPieceType(self: NullableColouredPieceType) ColouredPieceType {
        return @enumFromInt(self.data);
    }
};

pub const ColouredPieceType = enum(u4) {
    white_pawn = 0,
    black_pawn = 1,

    white_knight = 2,
    black_knight = 3,

    white_bishop = 4,
    black_bishop = 5,

    white_rook = 6,
    black_rook = 7,

    white_queen = 8,
    black_queen = 9,

    white_king = 10,
    black_king = 11,

    pub inline fn nullable(self: ColouredPieceType) NullableColouredPieceType {
        return NullableColouredPieceType.fromColouredPieceType(self);
    }

    pub inline fn fromInt(i: u8) ColouredPieceType {
        return @enumFromInt(i);
    }

    pub inline fn toInt(self: ColouredPieceType) u8 {
        return @intFromEnum(self);
    }

    pub inline fn fromPieceType(pt: PieceType, col: Colour) ColouredPieceType {
        return fromInt(pt.toInt() << 1 | col.toInt());
    }

    pub inline fn toPieceType(self: ColouredPieceType) PieceType {
        return PieceType.fromInt(self.toInt() >> 1);
    }

    pub inline fn isWhite(self: ColouredPieceType) bool {
        return self.toColour() == .white;
    }

    pub inline fn isBlack(self: ColouredPieceType) bool {
        return self.toColour() == .black;
    }

    pub inline fn toColour(self: ColouredPieceType) Colour {
        return Colour.fromInt(self.toInt() & 1);
    }

    pub inline fn fromAsciiLetter(char: u8) ?ColouredPieceType {
        return fromPieceType(PieceType.fromAsciiLetter(char) orelse return null, if (std.ascii.isUpper(char)) .white else .black);
    }

    pub inline fn toAsciiLetter(self: ColouredPieceType) u8 {
        const pt_char = self.toPieceType().toAsciiLetter();
        return if (self.toColour() == .white) std.ascii.toUpper(pt_char) else std.ascii.toLower(pt_char);
    }
};

pub const ScoredMove = struct {
    move: Move,
    score: i32,

    pub fn desc(_: void, lhs: ScoredMove, rhs: ScoredMove) bool {
        return lhs.score > rhs.score;
    }
};

pub const ScoredMoveReceiver = struct {
    vals: std.BoundedArray(ScoredMove, 256) = .{},

    pub fn receive(self: *@This(), move: Move) void {
        self.vals.appendAssumeCapacity(.{ .move = move, .score = 0 });
    }
};

pub const FilteringScoredMoveReceiver = struct {
    vals: std.BoundedArray(ScoredMove, 256) = .{},
    filter: Move,

    pub fn receive(self: *@This(), move: Move) void {
        if (move == self.filter) return;
        self.vals.appendAssumeCapacity(.{ .move = move, .score = 0 });
    }
};

pub const ScoreType = enum(u2) {
    none = 0,
    lower = 1,
    upper = 2,
    exact = 3,
};

pub const TTFlags = packed struct {
    score_type: ScoreType = .none,
    is_pv: bool = false,
    age: u5 = 0,
};

comptime {
    assert(@sizeOf(TTFlags) == 1);
}

pub const TTEntry = struct {
    hash: u16 = 0,
    score: i16 = 0,
    flags: TTFlags = .{},
    move: Move = Move.init(),
    depth: u8 = 0,
    raw_static_eval: i16 = 0,

    pub fn compress(h: u64) u16 {
        return @intCast(h >> 48);
    }

    pub fn hashEql(self: TTEntry, other_hash: u64) bool {
        return self.hash == compress(other_hash);
    }
};

var stdout: std.fs.File = undefined;
var write_mutex: std.Thread.Mutex = .{};
pub fn write(comptime fmt: []const u8, args: anytype) void {
    write_mutex.lock();
    defer write_mutex.unlock();
    var buf: [4096]u8 = undefined;
    const to_print = std.fmt.bufPrint(&buf, fmt, args) catch "";

    stdout.writer().writeAll(to_print) catch |e| {
        std.debug.panic("writing to stdout failed! Error: {}\n", .{e});
    };
}

pub fn isConstPointer(comptime T: type) bool {
    if (is_0_14_0) {
        if (@typeInfo(T) == .pointer) {
            return @typeInfo(T).pointer.is_const;
        }
    } else {
        if (@typeInfo(T) == .Pointer) {
            return @typeInfo(T).Pointer.is_const;
        }
    }
    return false;
}

pub fn inheritConstness(comptime Base: type, comptime Pointer: type) type {
    comptime var ptr_attrs: std.builtin.Type.Pointer = undefined;
    if (is_0_14_0) {
        ptr_attrs = @typeInfo(Pointer).pointer;
    } else {
        ptr_attrs = @typeInfo(Pointer).Pointer;
    }
    if (isConstPointer(Base)) {
        ptr_attrs.is_const = true;
    }
    if (is_0_14_0) {
        return @Type(.{ .pointer = ptr_attrs });
    } else {
        return @Type(.{ .Pointer = ptr_attrs });
    }
}
