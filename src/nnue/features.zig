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

const root = @import("../root.zig");

pub const FeatureKind = enum {
    psqt,
};

pub const PSQTFeature = packed struct {
    c: root.ColouredPieceType,
    s: root.Square,

    pub fn col(self: PSQTFeature) root.Colour {
        return self.c.toColour();
    }

    pub fn piece(self: PSQTFeature) root.PieceType {
        return self.c.toPieceType();
    }

    pub fn colouredPiece(self: PSQTFeature) root.ColouredPieceType {
        return self.c;
    }

    pub fn square(self: PSQTFeature) root.Square {
        return self.s;
    }

    pub fn initColoured(c: root.ColouredPieceType, s: root.Square) PSQTFeature {
        return .{
            .c = c,
            .s = s,
        };
    }

    pub fn init(c: root.Colour, p: root.PieceType, s: root.Square) PSQTFeature {
        return .{
            .c = .fromPieceType(p, c),
            .s = s,
        };
    }
};
