const std = @import("std");

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
        return switch (std.ascii.toLower(letter)) {
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

    pub fn toInt(self: PieceType) u3 {
        return @intFromEnum(self);
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
