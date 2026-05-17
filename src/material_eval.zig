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

pub fn evalPosition(board: *const Board) i16 {
    return evaluate(board, undefined, undefined);
}

pub inline fn evaluate(board: *const Board, _: anytype, _: anytype) i16 {
    var res: i16 = 0;
    for (PieceType.all, [_]i16{ 100, 300, 300, 500, 900, 0 }) |pt, value| {
        res += value * @popCount(board.pieceFor(.white, pt));
        res -= value * @popCount(board.pieceFor(.black, pt));
    }
    res = if (board.stm == .white) res else -res;
    res += @intCast(board.hash & 63);
    return res;
}
