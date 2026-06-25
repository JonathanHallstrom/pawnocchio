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
const evaluation = root.evaluation;

const Bitboard = root.Bitboard;
const Board = root.Board;
const PieceType = root.PieceType;

const PIECE_VALUES = [_]i16{
    100,
    300,
    300,
    500,
    900,
    0,
};

const COLOURED_PIECE_VALUES = [_]i16{
    100, -100,
    300, -300,
    300, -300,
    500, -500,
    900, -900,
    0,   0,
    0,
};

fn value(f: root.PSQTFeature) i16 {
    return COLOURED_PIECE_VALUES[f.colouredPiece().toInt()];
}

fn valueBB(pt: PieceType, bb: u64) i16 {
    return PIECE_VALUES[pt.toInt()] * @popCount(bb);
}

const Frame = struct {
    state: i16,

    pub fn init(board: *const Board) Frame {
        var state: i16 = 0;

        for (PieceType.all) |pt| {
            state += valueBB(pt, board.pieceFor(.white, pt));
            state -= valueBB(pt, board.pieceFor(.black, pt));
        }

        return .{
            .state = state,
        };
    }

    pub fn initInPlace(noalias self: *Frame, board: *const Board) void {
        self.* = init(board);
    }

    pub fn update(self: *Frame, other: *const Frame) void {
        self.* = other.*;
    }

    pub fn add(self: *Frame, a: root.PSQTFeature) void {
        self.state += value(a);
    }

    pub fn sub(self: *Frame, s: root.PSQTFeature) void {
        self.state -= value(s);
    }

    pub fn eval(self: Frame, board: *const Board) i16 {
        var res = self.state;

        if (board.stm == .black) {
            res = -res;
        }
        res += @as(i16, @intCast(board.hash & 14)) - 7;
        return res;
    }
};

pub const Context = struct {
    frames: [root.SEARCH_MAX_PLY]Frame = undefined,

    pub fn initForThread(_: *Context, _: usize) void {}

    pub fn initRoot(self: *Context, board: *const Board) void {
        self.frames[0].initInPlace(board);
    }

    pub fn prepareChild(self: *Context, child_ply: usize, child_board: *const Board) void {
        _ = child_board;
        self.frames[child_ply].update(&self.frames[child_ply - 1]);
    }

    pub fn handle(self: *Context, ply: usize) evaluation.Handle(*Frame) {
        return evaluation.wrapHandle(&self.frames[ply]);
    }
};

pub fn evalPosition(board: *const Board) i16 {
    const ctx = evaluation.globalCtx.lock();
    defer evaluation.globalCtx.release();
    ctx.initRoot(board);
    return ctx.handle(0).eval(board);
}
