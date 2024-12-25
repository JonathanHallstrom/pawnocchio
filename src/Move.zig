const std = @import("std");
const assert = std.debug.assert;
const Move = @This();
const PieceType = @import("piece_type.zig").PieceType;

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

    en_passant = 10,
    castle_left = 12,
    castle_right = 14,

    fn isPromotion(self: MoveFlag) bool {
        return @intFromEnum(self) -% 2 <= @intFromEnum(MoveFlag.promote_queen_capture) -% 2;
    }

    fn isCapture(self: MoveFlag) bool {
        return @intFromEnum(self) & 1 != 0;
    }

    fn isCastlingMove(self: MoveFlag) bool {
        return self == .castle_left or self == .castle_right;
    }

    fn isValid(int: u4) bool {
        return int <= 10 or int % 2 == 0;
    }
};

const Self = @This();

fn initWithFlag(from: u6, to: u6, flag: MoveFlag) Self {
    return .{ .raw = @as(u16, from) << 6 | to | @as(u16, @intFromEnum(flag)) << 12 };
}

pub fn initQuiet(from: u6, to: u6) Move {
    return initWithFlag(from, to, .quiet);
}

pub fn initCapture(from: u6, to: u6) Move {
    return initWithFlag(from, to, .capture);
}

pub fn initCastling(from: u6, to: u6) Move {
    return initWithFlag(from, to, if (from > to) .castle_left else .castle_right);
}

pub fn initEnPassant(from: u6, to: u6) Move {
    return initWithFlag(from, to, .en_passant);
}

pub fn initPromotion(from: u6, to: u6, promoted_type: PieceType) Move {
    comptime var lookup: [8]MoveFlag = undefined;
    lookup[@intFromEnum(PieceType.knight)] = .promote_knight;
    lookup[@intFromEnum(PieceType.bishop)] = .promote_bishop;
    lookup[@intFromEnum(PieceType.rook)] = .promote_rook;
    lookup[@intFromEnum(PieceType.queen)] = .promote_queen;
    return initWithFlag(from, to, lookup[@intFromEnum(promoted_type)]);
}

pub fn initPromotionCapture(from: u6, to: u6, promoted_type: PieceType) Move {
    comptime var lookup: [8]MoveFlag = undefined;
    lookup[@intFromEnum(PieceType.knight)] = .promote_knight_capture;
    lookup[@intFromEnum(PieceType.bishop)] = .promote_bishop_capture;
    lookup[@intFromEnum(PieceType.rook)] = .promote_rook_capture;
    lookup[@intFromEnum(PieceType.queen)] = .promote_queen_capture;
    return initWithFlag(from, to, lookup[@intFromEnum(promoted_type)]);
}

fn getFlag(self: Self) MoveFlag {
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

pub fn getTo(self: Self) u6 {
    return @intCast(self.raw & 63);
}

pub fn getFrom(self: Self) u6 {
    return @intCast(self.raw >> 6 & 63);
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

comptime {
    @setEvalBranchQuota(61 << 10);
    assert(initCapture(0, 0).isCapture());
    assert(initQuiet(0, 0).isQuiet());
    assert(initCastling(0, 0).isCastlingMove());
    assert(initEnPassant(0, 0).isEnPassant());
    for ([_]PieceType{ .knight, .bishop, .rook, .queen }) |pt| {
        assert(initPromotion(0, 0, pt).isPromotion());
        assert(initPromotion(0, 0, pt).getPromotedPieceType() == pt);
        assert(initPromotionCapture(0, 0, pt).isPromotion());
        assert(initPromotionCapture(0, 0, pt).getPromotedPieceType() == pt);
        assert(initPromotionCapture(0, 0, pt).isCapture());
    }

    for (0..64) |from| {
        for (0..64) |to| {
            assert(initQuiet(from, to).getFrom() == from);
            assert(initQuiet(from, to).getTo() == to);
            assert(initCapture(from, to).getFrom() == from);
            assert(initCapture(from, to).getTo() == to);
        }
    }
}
