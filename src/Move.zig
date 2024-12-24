const std = @import("std");

const Move = @This();
const PieceType = @import("piece_type.zig").PieceType;
const BitBoard = @import("BitBoard.zig");

raw: u16,

const promote_knight_flag: u16 = 0b0001;
const promote_rook_flag: u16 = 0b0010;
const promote_queen_flag: u16 = 0b0011;
const capture_flag: u16 = 0b0100;
const en_passant_flag: u16 = 0b1000;
const castle_left_flag: u16 = 0b1001;
const castle_right_flag: u16 = 0b1010;

const Self = @This();

pub fn initQuiet(from: u6, to: u6) Move {
    return @as(u16, from) << 6 | to;
}

pub fn initCapture(from: u6, to: u6) Move {
    return initQuiet(from, to) | capture_flag << 12;
}

pub fn initCastling(from: u6, to: u6) Move {
    return initQuiet(from, to) | (0b1000 | 0b0001 << @intFromBool(from < to)) << 12;
}

pub fn initEnPassant(from: u6, to: u6) Move {
    return initQuiet(from, to) | en_passant_flag << 12;
}

pub fn initPromotion(from: u6, to: u6, promoted_type: PieceType) Move {
    return initQuiet(from, to) | switch (promoted_type) {
        .knight => promote_knight_flag,
        .rook => promote_rook_flag,
        .queen => promote_queen_flag,
        else => unreachable,
    } << 12;
}

pub fn initPromotionCapture(from: u6, to: u6, promoted_type: PieceType) Move {
    return initPromotion(from, to, promoted_type) | capture_flag;
}

fn getFlag(self: Self) u16 {
    return self >> 12;
}

pub fn isQuiet(self: Self) bool {
    return !self.isCapture();
}

pub fn isCapture(self: Self) bool {
    return self.getFlag() & capture_flag != 0;
}

pub fn isCastlingMove(self: Self) bool {
    return self.getFlag() > en_passant_flag;
}

pub fn isPromotion(self: Self) bool {
    return self.getFlag() & 0b11 != 0;
}
