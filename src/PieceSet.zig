const PieceType = @import("piece_type.zig").PieceType;
const Self = @This();
const Square = @import("square.zig").Square;

raw: [6]u64 = .{0} ** 6,
all: u64 = 0,

pub fn addPiece(self: *Self, tp: PieceType, square: Square) void {
    self.addPieceBB(tp, square.toBitBoard());
}

pub fn addPieceBB(self: *Self, tp: PieceType, bitboard: u64) void {
    self.raw[@intFromEnum(tp)] |= bitboard;
    self.all |= bitboard;
}

pub fn removePiece(self: *Self, tp: PieceType, square: Square) void {
    self.removePieceBB(tp, square.toBitBoard());
}

pub fn removePieceBB(self: *Self, tp: PieceType, bitboard: u64) void {
    self.raw[@intFromEnum(tp)] &= ~bitboard;
    self.all &= ~bitboard;
}

pub fn movePiece(self: *Self, tp: PieceType, from: u6, to: u6) void {
    self.movePieceBB(tp, 1 << from, 1 << to);
}

pub fn movePieceBB(self: *Self, tp: PieceType, from_bb: u64, to_bb: u64) void {
    self.raw[@intFromEnum(tp)] ^= from_bb | to_bb;
    self.all ^= from_bb | to_bb;
}

pub fn getBoard(self: Self, which: PieceType) u64 {
    return self.raw[@intFromEnum(which)];
}
