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

const Move = root.Move;
const Colour = root.Colour;
const PieceType = root.PieceType;
const Board = root.Board;
const tunable_constants = root.tunable_constants;

pub const TypedMove = struct {
    move: Move,
    tp: PieceType,

    pub fn init() TypedMove {
        return .{ .move = Move.init(), .tp = .pawn };
    }

    pub fn fromBoard(board: *const Board, move_: Move) TypedMove {
        if (move_.isNull()) {
            return .{
                .move = move_,
                .tp = .pawn,
            };
        }
        return .{
            .move = move_,
            .tp = (&board.mailbox)[move_.from().toInt()].?.toPieceType(),
        };
    }
};

pub const MAX_HISTORY: i16 = 1 << 14;
const SHIFT = @ctz(MAX_HISTORY);

pub fn bonus(depth: i32) i16 {
    return @intCast(@min(
        depth * tunable_constants.history_bonus_mult + tunable_constants.history_bonus_offs,
        tunable_constants.history_bonus_max,
    ));
}

pub fn penalty(depth: i32) i16 {
    return @intCast(@min(
        depth * tunable_constants.history_penalty_mult + tunable_constants.history_penalty_offs,
        tunable_constants.history_penalty_max,
    ));
}

pub const QuietHistory = struct {
    vals: [2 * 64 * 64]i16,

    pub fn reset(self: *QuietHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    fn entry(self: anytype, col: Colour, move: TypedMove) root.inheritConstness(@TypeOf(self), *i16) {
        const col_offs: usize = col.toInt();
        const from_offs: usize = move.move.from().toInt();
        const to_offs = move.move.to().toInt();
        return &(&self.vals)[col_offs * 64 * 64 + from_offs * 64 + to_offs];
    }

    pub fn update(self: *QuietHistory, col: Colour, move: TypedMove, adjustment: i16) void {
        gravityUpdate(self.entry(col, move), adjustment);
    }

    pub fn read(self: *const QuietHistory, col: Colour, move: TypedMove) i16 {
        return self.entry(col, move).*;
    }
};

pub const ContHistory = struct {
    vals: [2 * 6 * 64 * 6 * 64]i16,

    pub fn reset(self: *ContHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    fn entry(self: anytype, col: Colour, move: TypedMove, prev: TypedMove) root.inheritConstness(@TypeOf(self), *i16) {
        const col_offs: usize = col.toInt();
        const move_offs: usize = @as(usize, move.tp.toInt()) * 64 + move.move.to().toInt();
        const prev_offs: usize = @as(usize, prev.tp.toInt()) * 64 + prev.move.to().toInt();
        return &(&self.vals)[col_offs * 6 * 64 * 6 * 64 + prev_offs * 6 * 64 + move_offs];
    }

    pub fn update(self: *ContHistory, col: Colour, move: TypedMove, prev: TypedMove, adjustment: i16) void {
        gravityUpdate(self.entry(col, move, prev), adjustment);
    }

    pub fn read(self: *const ContHistory, col: Colour, move: TypedMove, prev: TypedMove) i16 {
        return self.entry(col, move, prev).*;
    }
};

pub const HistoryTable = struct {
    quiet: QuietHistory,
    countermove: ContHistory,

    pub fn reset(self: *HistoryTable) void {
        self.quiet.reset();
        self.countermove.reset();
    }

    pub fn read(self: *const HistoryTable, board: *const Board, move: Move, prev: TypedMove) i32 {
        const typed = TypedMove.fromBoard(board, move);
        var res: i32 = 0;
        res += self.quiet.read(board.stm, typed);
        res += self.countermove.read(board.stm, typed, prev);

        return res;
    }

    pub fn update(self: *HistoryTable, board: *const Board, move: Move, prev: TypedMove, adjustment: i16) void {
        const typed = TypedMove.fromBoard(board, move);
        self.quiet.update(board.stm, typed, adjustment);
        self.countermove.update(board.stm, typed, prev, adjustment);
    }
};

fn gravityUpdate(entry: *i16, adjustment: anytype) void {
    const clamped: i16 = @intCast(std.math.clamp(adjustment, -MAX_HISTORY, MAX_HISTORY));
    const magnitude: i32 = @abs(clamped);
    entry.* += @intCast(clamped - ((magnitude * entry.*) >> SHIFT));
}
