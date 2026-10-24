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

pub const KINGSIDE_KING_FILE = File.g;
pub const QUEENSIDE_KING_FILE = File.c;
pub const KINGSIDE_ROOK_FILE = File.f;
pub const QUEENSIDE_ROOK_FILE = File.d;

pub const Side = enum {
    king,
    queen,

    pub fn toAsciiLetter(self: Side) u8 {
        return switch (self) {
            .king => 'k',
            .queen => 'q',
        };
    }
};

pub fn init() CastlingRights {
    return .{
        .raw = 0,
    };
}
pub fn initFromParts(
    raw_availability: u8,
    white_kingside_rook_file: File,
    black_kingside_rook_file: File,
    white_queenside_rook_file: File,
    black_queenside_rook_file: File,
) CastlingRights {
    var res: CastlingRights = .{ .raw = raw_availability & 0b1111 };
    res.setRookFile(.white, .king, white_kingside_rook_file);
    res.setRookFile(.black, .king, black_kingside_rook_file);
    res.setRookFile(.white, .queen, white_queenside_rook_file);
    res.setRookFile(.black, .queen, black_queenside_rook_file);
    return res;
}

pub fn rawCastlingAvailability(self: CastlingRights) u8 {
    return @intCast(self.raw & 0b1111);
}

fn sideIndex(col: Colour, side: Side) u2 {
    var id: u2 = 0;
    if (col == .black) id += 1;
    if (side == .queen) id += 2;
    return id;
}

fn availability(col: Colour, side: Side) u16 {
    return @as(u16, 1) << sideIndex(col, side);
}

fn rookFileShift(col: Colour, side: Side) u4 {
    return 4 + 3 * @as(u4, sideIndex(col, side));
}

pub fn getRookFile(self: CastlingRights, col: Colour, side: Side) File {
    return File.fromInt(@intCast(self.raw >> rookFileShift(col, side) & 0b111));
}

pub fn setRookFile(self: *CastlingRights, col: Colour, side: Side, file: File) void {
    const shift = rookFileShift(col, side);
    self.raw = (self.raw & ~(@as(u16, 0b111) << shift)) | @as(u16, file.toInt()) << shift;
}

pub fn getRookSquare(self: CastlingRights, col: Colour, side: Side) Square {
    return Square.fromRankFile(startingRankFor(col), self.getRookFile(col, side));
}

pub fn isAvailable(self: CastlingRights, col: Colour, side: Side) bool {
    return self.raw & availability(col, side) != 0;
}

pub fn setAvailable(self: *CastlingRights, col: Colour, side: Side, available: bool) void {
    const bit = availability(col, side);
    self.raw = (self.raw & ~bit) | @intFromBool(available) * bit;
}

pub inline fn startingRankFor(col: Colour) Rank {
    return if (col == .white) .first else .eighth;
}

pub inline fn kingMoved(self: *CastlingRights, col: Colour) void {
    self.raw &= ~(availability(col, .king) | availability(col, .queen));
}

pub inline fn updateSquare(
    self: *CastlingRights,
    sq: Square,
    col: Colour,
) void {
    const queenside_rook_sq = self.getRookSquare(col, .queen);
    const kingside_rook_sq = self.getRookSquare(col, .king);

    var kingside_rook_mask: u16 = @intFromBool(sq == kingside_rook_sq);
    kingside_rook_mask <<= sideIndex(col, .king);

    var queenside_rook_mask: u16 = @intFromBool(sq == queenside_rook_sq);
    queenside_rook_mask <<= sideIndex(col, .queen);

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
