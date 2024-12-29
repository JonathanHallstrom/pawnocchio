const std = @import("std");
const assert = std.debug.assert;
const Bitboard = @import("Bitboard.zig");

pub const Square = enum(u6) {
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

    pub fn fromInt(int: u6) Square {
        return @enumFromInt(int);
    }

    pub fn toInt(self: Square) u6 {
        return @intFromEnum(self);
    }

    pub fn getFile(self: Square) File {
        return File.fromInt(self.toInt() % 8);
    }

    pub fn fromBitboard(bitboard: u64) Square {
        assert(@popCount(bitboard) == 1);
        return fromInt(@intCast(@ctz(bitboard)));
    }

    pub fn toBitboard(self: Square) u64 {
        return Bitboard.fromSquare(self);
    }

    pub fn parse(square: []const u8) !Square {
        const rank = square[1] -% '1';
        if (rank > 7) return error.InvalidRank;
        const file = std.ascii.toLower(square[0]) -% 'a';
        if (file > 7) return error.InvalidFile;
        return @enumFromInt(rank * 8 + file);
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
};

comptime {
    for (0..64) |i| {
        assert(Square.parse(&.{ i % 8 + 'a', i / 8 + '1' }) catch unreachable == @as(Square, @enumFromInt(i)));
    }
}
