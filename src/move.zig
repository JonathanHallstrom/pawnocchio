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

const root = @import("root.zig");

const Square = root.Square;
const PieceType = root.PieceType;
const Colour = root.Colour;
const Board = root.Board;

// 6 bits from 6 bits to 4 bits flag
// start out with simplest possible flag, just the promotion piece

pub const MoveType = enum(u2) {
    default = 0,
    ep = 1,
    castling = 2,
    promotion = 3,
};

pub const Move = enum(u16) {
    _,

    pub const default_flag: u16 = 0b0000;
    pub const ep_flag: u16 = 0b0100;
    pub const castling_flag: u16 = 0b1000;
    pub const promotion_flag: u16 = 0b1100;

    fn initFromParts(from_: u16, to_: u16, flag_: u16) Move {
        return @enumFromInt(from_ | to_ << 6 | flag_ << 12);
    }

    fn toInt(self: Move) u16 {
        return @intFromEnum(self);
    }

    pub fn from(self: Move) Square {
        return Square.fromInt(@intCast(self.toInt() & 0b111111));
    }

    pub fn to(self: Move) Square {
        return Square.fromInt(@intCast(self.toInt() >> 6 & 0b111111));
    }

    pub fn flag(self: Move) u8 {
        return @intCast(self.toInt() >> 12);
    }

    pub fn tp(self: Move) MoveType {
        return @enumFromInt(self.toInt() >> 14);
    }

    pub fn extra(self: Move) u8 {
        return @intCast((self.toInt() >> 12) & 0b11);
    }

    pub fn init() Move {
        return @enumFromInt(0);
    }

    pub inline fn isNull(self: Move) bool {
        return self == init();
    }

    pub fn quiet(from_: Square, to_: Square) Move {
        return initFromParts(from_.toInt(), to_.toInt(), 0);
    }

    pub fn capture(from_: Square, to_: Square) Move {
        return initFromParts(from_.toInt(), to_.toInt(), 0);
    }

    pub fn enPassant(from_: Square, to_: Square) Move {
        return initFromParts(from_.toInt(), to_.toInt(), ep_flag);
    }

    pub fn promo(from_: Square, to_: Square, tp_: PieceType) Move {
        std.debug.assert(tp_.toInt() < castling_flag);
        return initFromParts(from_.toInt(), to_.toInt(), promotion_flag | tp_.toInt() - 1);
    }

    pub fn castlingKingside(col: Colour, from_: Square, to_: Square) Move {
        return initFromParts(from_.toInt(), to_.toInt(), castling_flag | col.toInt());
    }

    pub fn castlingQueenside(col: Colour, from_: Square, to_: Square) Move {
        return initFromParts(from_.toInt(), to_.toInt(), castling_flag | 2 + col.toInt());
    }

    pub fn promoType(self: Move) PieceType {
        return PieceType.fromInt(@intCast(1 + self.extra()));
    }

    pub fn getEnPassantPawnSquare(self: Move, comptime col: Colour) Square {
        return self.to().move(if (col == .white) -1 else 1, 0);
    }

    pub fn toString(self: Move, board: *const Board) std.BoundedArray(u8, 5) {
        switch (board.stm) {
            inline else => |stm| {
                var buf: [5]u8 = undefined;
                var bw = std.io.fixedBufferStream(&buf);
                if (board.isCastling(self)) {
                    if (board.frc) {
                        bw.writer().print("{s}{s}", .{
                            @tagName(self.from()),
                            @tagName(self.to()),
                        }) catch unreachable;
                    } else {
                        bw.writer().print("{s}{s}", .{
                            @tagName(self.from()),
                            @tagName(board.castlingKingDestFor(self, stm)),
                        }) catch unreachable;
                    }
                } else if (board.isPromo(self)) {
                    bw.writer().print("{s}{s}{c}", .{
                        @tagName(self.from()),
                        @tagName(self.to()),
                        self.promoType().toAsciiLetter(),
                    }) catch unreachable;
                } else {
                    bw.writer().print("{s}{s}", .{
                        @tagName(self.from()),
                        @tagName(self.to()),
                    }) catch unreachable;
                }

                var res: std.BoundedArray(u8, 5) = .{};
                if (self.isNull()) {
                    res.appendSliceAssumeCapacity("0000");
                } else {
                    res.appendSliceAssumeCapacity(bw.getWritten());
                }
                return res;
            },
        }
    }
};

test "promo to string" {
    const board = try Board.parseFen("8/3n3P/5k2/6p1/6P1/2r5/8/7K w - - 3 0", true);
    try std.testing.expectEqualSlices(u8, "h7h8q", Move.promo(.h7, .h8, .queen).toString(&board).slice());
}
