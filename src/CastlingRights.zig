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

raw: u16,

const CastlingRights = @This();

pub const white_kingside_castle: u8 = 1;
pub const black_kingside_castle: u8 = 2;
pub const white_queenside_castle: u8 = 4;
pub const black_queenside_castle: u8 = 8;

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
        return self.raw & white_kingside_castle != 0;
    } else {
        return self.raw & black_kingside_castle != 0;
    }
}
pub fn queensideCastlingFor(self: CastlingRights, col: Colour) bool {
    if (col == .white) {
        return self.raw & white_queenside_castle != 0;
    } else {
        return self.raw & black_queenside_castle != 0;
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

pub inline fn startingRankFor(_: CastlingRights, col: Colour) Rank {
    return if (col == .white) .first else .eighth;
}

pub inline fn kingMoved(self: *CastlingRights, col: Colour) void {
    self.raw &= ~(@as(u16, 0b101) << @intCast(col.toInt()));
}

pub inline fn updateSquare(
    self: *CastlingRights,
    sq: Square,
    col: Colour,
) void {
    const queenside_rook_sq = Square.fromRankFile(self.startingRankFor(col), self.queensideRookFileFor(col));
    const kingside_rook_sq = Square.fromRankFile(self.startingRankFor(col), self.kingsideRookFileFor(col));

    var kingside_rook_mask: u16 = @intFromBool(sq == kingside_rook_sq);
    kingside_rook_mask <<= @intCast(col.toInt());

    var queenside_rook_mask: u16 = @intFromBool(sq == queenside_rook_sq);
    queenside_rook_mask <<= @intCast(col.toInt() + 2);

    self.raw &= ~(kingside_rook_mask | queenside_rook_mask);
}
