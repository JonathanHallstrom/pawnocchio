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

/// debugging purposes only
const std = @import("std");

const root = @import("root.zig");

const Board = root.Board;
const PieceType = root.PieceType;
pub const State = Board.NullEvalState;

pub fn evaluate(board: *const Board, _: State) i16 {
    var res: i16 = 0;
    const value = [6]i16{ 100, 300, 300, 500, 900, 0 };
    for (PieceType.all) |pt| {
        res += value[pt.toInt()] * @popCount(board.pieceFor(.white, pt));
        res -= value[pt.toInt()] * @popCount(board.pieceFor(.black, pt));
    }
    return if (board.stm == .white) res else -res;
}
