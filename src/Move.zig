const std = @import("std");
const assert = std.debug.assert;
const Move = @This();
const PieceType = @import("piece_type.zig").PieceType;
const Square = @import("square.zig").Square;

raw: u16,

const MoveFlag = enum(u4) {
    quiet = 0,
    capture = 1,

    promote_knight = 2,
    promote_knight_capture = 3,

    promote_bishop = 4,
    promote_bishop_capture = 5,

    promote_rook = 6,
    promote_rook_capture = 7,

    promote_queen = 8,
    promote_queen_capture = 9,

    en_passant = 11,
    castle_queenside = 12,
    castle_kingside = 14,

    fn isPromotion(self: MoveFlag) bool {
        return @intFromEnum(self) -% 2 <= @intFromEnum(MoveFlag.promote_queen_capture) -% 2;
    }

    fn isCapture(self: MoveFlag) bool {
        return @intFromEnum(self) & 1 != 0;
    }

    fn isCastlingMove(self: MoveFlag) bool {
        return self == .castle_queenside or self == .castle_kingside;
    }

    fn isValid(int: u4) bool {
        inline for (std.meta.fields(MoveFlag)) |field| {
            if (field.value == int) return true;
        }
        return false;
    }
};

const Self = @This();

pub fn isSameAsStr(self: Move, str: []const u8) bool {
    var print_buf: [32]u8 = undefined;
    const move_str = std.fmt.bufPrint(&print_buf, "{}", .{self}) catch unreachable;
    return std.ascii.eqlIgnoreCase(move_str, str);
}

pub fn initWithFlag(from: Square, to: Square, flag: MoveFlag) Self {
    return .{ .raw = @as(u16, from.toInt()) << 6 | to.toInt() | @as(u16, @intFromEnum(flag)) << 12 };
}

pub fn initQuiet(from: Square, to: Square) Move {
    return initWithFlag(from, to, .quiet);
}

pub fn initCapture(from: Square, to: Square) Move {
    return initWithFlag(from, to, .capture);
}

pub fn initCastling(from: Square, to: Square) Move {
    return initWithFlag(from, to, if (from.toInt() > to.toInt()) .castle_queenside else .castle_kingside);
}

pub fn initCastlingQueenside(from: Square, to: Square) Move {
    return initWithFlag(from, to, .castle_queenside);
}

pub fn initCastlingKingside(from: Square, to: Square) Move {
    return initWithFlag(from, to, .castle_kingside);
}

pub fn initEnPassant(from: Square, to: Square) Move {
    return initWithFlag(from, to, .en_passant);
}

pub fn initPromotion(from: Square, to: Square, promoted_type: PieceType) Move {
    comptime var lookup: [8]MoveFlag = undefined;
    lookup[@intFromEnum(PieceType.knight)] = .promote_knight;
    lookup[@intFromEnum(PieceType.bishop)] = .promote_bishop;
    lookup[@intFromEnum(PieceType.rook)] = .promote_rook;
    lookup[@intFromEnum(PieceType.queen)] = .promote_queen;
    return initWithFlag(from, to, lookup[@intFromEnum(promoted_type)]);
}

pub fn initPromotionCapture(from: Square, to: Square, promoted_type: PieceType) Move {
    comptime var lookup: [8]MoveFlag = undefined;
    lookup[@intFromEnum(PieceType.knight)] = .promote_knight_capture;
    lookup[@intFromEnum(PieceType.bishop)] = .promote_bishop_capture;
    lookup[@intFromEnum(PieceType.rook)] = .promote_rook_capture;
    lookup[@intFromEnum(PieceType.queen)] = .promote_queen_capture;
    return initWithFlag(from, to, lookup[@intFromEnum(promoted_type)]);
}

pub fn getFlag(self: Self) MoveFlag {
    const int: u4 = @intCast(self.raw >> 12);
    assert(MoveFlag.isValid(int));
    return @enumFromInt(int);
}

pub fn isQuiet(self: Self) bool {
    return !self.isCapture();
}

pub fn isCapture(self: Self) bool {
    return self.getFlag().isCapture();
}

pub fn isEnPassant(self: Self) bool {
    return self.getFlag() == .en_passant;
}
pub fn isCastlingMove(self: Self) bool {
    return self.getFlag().isCastlingMove();
}

pub fn isPromotion(self: Self) bool {
    return self.getFlag().isPromotion();
}

pub fn getTo(self: Self) Square {
    return Square.fromInt(@intCast(self.raw & 63));
}

pub fn getFrom(self: Self) Square {
    return Square.fromInt(@intCast(self.raw >> 6 & 63));
}

pub fn getPromotedPieceType(self: Self) ?PieceType {
    comptime var options: [16]?PieceType = .{null} ** 16;
    options[@intFromEnum(MoveFlag.promote_knight)] = .knight;
    options[@intFromEnum(MoveFlag.promote_knight_capture)] = .knight;
    options[@intFromEnum(MoveFlag.promote_bishop)] = .bishop;
    options[@intFromEnum(MoveFlag.promote_bishop_capture)] = .bishop;
    options[@intFromEnum(MoveFlag.promote_rook)] = .rook;
    options[@intFromEnum(MoveFlag.promote_rook_capture)] = .rook;
    options[@intFromEnum(MoveFlag.promote_queen)] = .queen;
    options[@intFromEnum(MoveFlag.promote_queen_capture)] = .queen;

    return options[@intFromEnum(self.getFlag())];
}

pub fn format(self: Move, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = actual_fmt;
    _ = options;
    if (self.isPromotion()) {
        return try writer.print("{s}{s}{c}", .{ @tagName(self.getFrom()), @tagName(self.getTo()), self.getPromotedPieceType().?.toLetter() });
    } else if (self.isCastlingMove()) {
        if (self.getFrom().getFile() != .e) {}
        return try writer.print("{s}{s}", .{ @tagName(self.getFrom()), @tagName(self.getTo()) });
    } else {
        return try writer.print("{s}{s}", .{ @tagName(self.getFrom()), @tagName(self.getTo()) });
    }
}

comptime {
    @setEvalBranchQuota(1 << 30);
    assert(initCapture(.a1, .a2).isCapture());
    assert(initQuiet(.a1, .a2).isQuiet());
    assert(initCastling(.a1, .a2).isCastlingMove());
    assert(initEnPassant(.a1, .a2).isEnPassant());
    assert(initEnPassant(.a1, .a2).isCapture());
    for ([_]PieceType{ .knight, .bishop, .rook, .queen }) |pt| {
        assert(initPromotion(.a1, .a2, pt).isPromotion());
        assert(initPromotion(.a1, .a2, pt).getPromotedPieceType() == pt);
        assert(initPromotionCapture(.a1, .a2, pt).isPromotion());
        assert(initPromotionCapture(.a1, .a2, pt).getPromotedPieceType() == pt);
        assert(initPromotionCapture(.a1, .a2, pt).isCapture());
    }

    for (0..64) |from| {
        for (0..64) |to| {
            assert(initQuiet(Square.fromInt(from), Square.fromInt(to)).getFrom().toInt() == from);
            assert(initQuiet(Square.fromInt(from), Square.fromInt(to)).getTo().toInt() == to);
            assert(initCapture(Square.fromInt(from), Square.fromInt(to)).getFrom().toInt() == from);
            assert(initCapture(Square.fromInt(from), Square.fromInt(to)).getTo().toInt() == to);
        }
    }
}
