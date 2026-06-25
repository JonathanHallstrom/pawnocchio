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
const Board = root.Board;
const Move = root.Move;

pub const FileFormat = enum {
    pgn,
    viriformat,
};

pub const ScoredMove = struct {
    move: Move,
    score: ?i16,

    pub fn whiteEval(self: ScoredMove) ?i16 {
        return self.score;
    }

    pub fn stmEval(self: ScoredMove, stm: root.Colour) ?i16 {
        const ev = self.score orelse return null;
        return if (stm == .white) ev else -ev;
    }
};

pub const ScoredPly = struct {
    board: *Board,
    move: Move,
    _eval: ?i16,

    pub fn whiteEval(self: ScoredPly) ?i16 {
        return self._eval;
    }

    pub fn stmEval(self: ScoredPly) ?i16 {
        const ev = self._eval orelse return null;
        return if (self.board.stm == .white) ev else -ev;
    }
};
