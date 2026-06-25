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

const Rank = root.Rank;
const File = root.File;
const Square = root.Square;
const Colour = root.Colour;
const Move = root.Move;

raw: u16,

const CastlingRights = @This();

pub const WHITE_KINGSIDE_CASTLE: u8 = 1;
pub const BLACK_KINGSIDE_CASTLE: u8 = 2;
pub const WHITE_QUEENSIDE_CASTLE: u8 = 4;
pub const BLACK_QUEENSIDE_CASTLE: u8 = 8;

pub const KINGSIDE_KING_FILE = File.g;
pub const QUEENSIDE_KING_FILE = File.c;
pub const KINGSIDE_ROOK_FILE = File.f;
pub const QUEENSIDE_ROOK_FILE = File.d;

const KINGSIDE_MASK: u16 = 0b0011;
const QUEENSIDE_MASK: u16 = 0b1100;
const BOTH_MASK: u16 = 0b0101;

pub fn init() CastlingRights {
    return .{
        .raw = 0,
    };
}
pub fn initFromParts(
    castling_rights: u8,
    white_kingside_rook_file: File,
    black_kingside_rook_file: File,
    white_queenside_rook_file: File,
    black_queenside_rook_file: File,
) CastlingRights {
    return .{
        .raw = (castling_rights & 0b1111) |
            @as(u16, white_kingside_rook_file.toInt()) << 4 |
            @as(u16, black_kingside_rook_file.toInt()) << 7 |
            @as(u16, white_queenside_rook_file.toInt()) << 10 |
            @as(u16, black_queenside_rook_file.toInt()) << 13,
    };
}

pub fn rawCastlingAvailability(self: CastlingRights) u8 {
    return @intCast(self.raw & 0b1111);
}

pub fn getWhiteKingsideRookFile(self: CastlingRights) File {
    return File.fromInt(@intCast(self.raw >> 4 & 0b111));
}
pub fn getBlackKingsideRookFile(self: CastlingRights) File {
    return File.fromInt(@intCast(self.raw >> 7 & 0b111));
}
pub fn getWhiteQueensideRookFile(self: CastlingRights) File {
    return File.fromInt(@intCast(self.raw >> 10 & 0b111));
}
pub fn getBlackQueensideRookFile(self: CastlingRights) File {
    return File.fromInt(@intCast(self.raw >> 13 & 0b111));
}

pub fn kingsideCastlingFor(self: CastlingRights, col: Colour) bool {
    if (col == .white) {
        return self.raw & WHITE_KINGSIDE_CASTLE != 0;
    } else {
        return self.raw & BLACK_KINGSIDE_CASTLE != 0;
    }
}
pub fn queensideCastlingFor(self: CastlingRights, col: Colour) bool {
    if (col == .white) {
        return self.raw & WHITE_QUEENSIDE_CASTLE != 0;
    } else {
        return self.raw & BLACK_QUEENSIDE_CASTLE != 0;
    }
}

pub fn kingsideRookFileFor(self: CastlingRights, col: Colour) File {
    if (col == .white) {
        return self.getWhiteKingsideRookFile();
    } else {
        return self.getBlackKingsideRookFile();
    }
}
pub fn queensideRookFileFor(self: CastlingRights, col: Colour) File {
    if (col == .white) {
        return self.getWhiteQueensideRookFile();
    } else {
        return self.getBlackQueensideRookFile();
    }
}

pub inline fn startingRankFor(col: Colour) Rank {
    return if (col == .white) .first else .eighth;
}

pub inline fn kingMoved(self: *CastlingRights, col: Colour) void {
    self.raw &= ~(@as(u16, BOTH_MASK) << @intCast(col.toInt()));
}

pub inline fn updateSquare(
    self: *CastlingRights,
    sq: Square,
    col: Colour,
) void {
    const queenside_rook_sq = Square.fromRankFile(startingRankFor(col), self.queensideRookFileFor(col));
    const kingside_rook_sq = Square.fromRankFile(startingRankFor(col), self.kingsideRookFileFor(col));

    var kingside_rook_mask: u16 = @intFromBool(sq == kingside_rook_sq);
    kingside_rook_mask <<= @intCast(col.toInt());

    var queenside_rook_mask: u16 = @intFromBool(sq == queenside_rook_sq);
    queenside_rook_mask <<= @intCast(col.toInt() + 2);

    self.raw &= ~(kingside_rook_mask | queenside_rook_mask);
}

pub inline fn startingRankSquare(col: Colour, f: File) Square {
    var res = Square.fromRankFile(startingRankFor(.black), f);
    if (col == .white) {
        @branchHint(.unpredictable);
        res = Square.fromRankFile(startingRankFor(.white), f);
    }
    return res;
}

pub inline fn kingsideKingDestFor(col: Colour) Square {
    return startingRankSquare(col, KINGSIDE_KING_FILE);
}

pub inline fn queensideKingDestFor(col: Colour) Square {
    return startingRankSquare(col, QUEENSIDE_KING_FILE);
}

pub inline fn castlingKingDestFor(move: Move, col: Colour) Square {
    return Square.fromRankFile(
        startingRankFor(col),
        if (move.isMoveLeft()) QUEENSIDE_KING_FILE else KINGSIDE_KING_FILE,
    );
}

pub inline fn kingsideRookDestFor(col: Colour) Square {
    return startingRankSquare(col, KINGSIDE_ROOK_FILE);
}

pub inline fn queensideRookDestFor(col: Colour) Square {
    return startingRankSquare(col, QUEENSIDE_ROOK_FILE);
}

pub inline fn castlingRookDestFor(move: Move, col: Colour) Square {
    return Square.fromRankFile(
        startingRankFor(col),
        if (move.isMoveLeft()) QUEENSIDE_ROOK_FILE else KINGSIDE_ROOK_FILE,
    );
}
