const PieceType = @import("piece_type.zig").PieceType;
const Self = @This();
const Square = @import("square.zig").Square;

raw: [6]u64 = .{0} ** 6,
all: u64 = 0,

pub fn addPiece(self: *Self, tp: PieceType, square: Square) void {
    self.addPieceBB(tp, square.toBitboard());
}

pub fn addPieceBB(self: *Self, tp: PieceType, bitboard: u64) void {
    self.raw[@intFromEnum(tp)] |= bitboard;
    self.all |= bitboard;
}

pub fn getBoard(self: Self, which: PieceType) u64 {
    return self.raw[@intFromEnum(which)];
}

pub fn getBoardPtr(self: *Self, which: PieceType) *u64 {
    return &self.raw[@intFromEnum(which)];
}
