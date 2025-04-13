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
const evaluation = root.evaluation;
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
const CORRHIST_SIZE = 16384;
const MAX_CORRHIST = 256 * 32;
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

    inline fn reset(self: *QuietHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(self: anytype, col: Colour, move: TypedMove) root.inheritConstness(@TypeOf(self), *i16) {
        const col_offs: usize = col.toInt();
        const from_offs: usize = move.move.from().toInt();
        const to_offs = move.move.to().toInt();
        return &(&self.vals)[col_offs * 64 * 64 + from_offs * 64 + to_offs];
    }

    inline fn update(self: *QuietHistory, col: Colour, move: TypedMove, adjustment: i16) void {
        gravityUpdate(self.entry(col, move), adjustment);
    }

    inline fn read(self: *const QuietHistory, col: Colour, move: TypedMove) i16 {
        return self.entry(col, move).*;
    }
};

pub const ContHistory = struct {
    vals: [2 * 6 * 64 * 6 * 64]i16,

    inline fn reset(self: *ContHistory) void {
        @memset(std.mem.asBytes(&self.vals), 0);
    }

    inline fn entry(self: anytype, col: Colour, move: TypedMove, prev: TypedMove) root.inheritConstness(@TypeOf(self), *i16) {
        const col_offs: usize = col.toInt();
        const move_offs: usize = @as(usize, move.tp.toInt()) * 64 + move.move.to().toInt();
        const prev_offs: usize = @as(usize, prev.tp.toInt()) * 64 + prev.move.to().toInt();
        return &(&self.vals)[col_offs * 6 * 64 * 6 * 64 + prev_offs * 6 * 64 + move_offs];
    }

    inline fn update(self: *ContHistory, col: Colour, move: TypedMove, prev: TypedMove, adjustment: i16) void {
        gravityUpdate(self.entry(col, move, prev), adjustment);
    }

    inline fn read(self: *const ContHistory, col: Colour, move: TypedMove, prev: TypedMove) i16 {
        return self.entry(col, move, prev).*;
    }
};

pub const HistoryTable = struct {
    quiet: QuietHistory,
    countermove: ContHistory,
    pawn_corrhist: [16384][2]CorrhistEntry,
    major_corrhist: [16384][2]CorrhistEntry,
    nonpawn_corrhist: [16384][2][2]CorrhistEntry,
    countermove_corrhist: [6 * 64][2]CorrhistEntry,

    pub fn reset(self: *HistoryTable) void {
        self.quiet.reset();
        self.countermove.reset();
        @memset(std.mem.asBytes(&self.pawn_corrhist), 0);
        @memset(std.mem.asBytes(&self.major_corrhist), 0);
        @memset(std.mem.asBytes(&self.nonpawn_corrhist), 0);
        @memset(std.mem.asBytes(&self.countermove_corrhist), 0);
    }

    pub fn readQuiet(self: *const HistoryTable, board: *const Board, move: Move, prev: TypedMove) i32 {
        const typed = TypedMove.fromBoard(board, move);
        var res: i32 = 0;
        res += self.quiet.read(board.stm, typed);
        res += self.countermove.read(board.stm, typed, prev);

        return res;
    }

    pub fn updateQuiet(self: *HistoryTable, board: *const Board, move: Move, prev: TypedMove, adjustment: i16) void {
        const typed = TypedMove.fromBoard(board, move);
        self.quiet.update(board.stm, typed, adjustment);
        self.countermove.update(board.stm, typed, prev, adjustment);
    }

    pub fn updateCorrection(self: *HistoryTable, board: *const Board, prev: TypedMove, corrected_static_eval: i32, score: i32, depth: i32) void {
        const err = (score - corrected_static_eval) * 256;
        const weight = @min(depth, 15) + 1;

        self.pawn_corrhist[board.pawn_hash % CORRHIST_SIZE][board.stm.toInt()].update(err, weight);
        self.major_corrhist[board.major_hash % CORRHIST_SIZE][board.stm.toInt()].update(err, weight);
        self.nonpawn_corrhist[board.nonpawn_hash[0] % CORRHIST_SIZE][board.stm.toInt()][0].update(err, weight);
        self.nonpawn_corrhist[board.nonpawn_hash[1] % CORRHIST_SIZE][board.stm.toInt()][1].update(err, weight);
        self.countermove_corrhist[@as(usize, prev.tp.toInt()) * 64 + prev.move.to().toInt()][board.stm.toInt()].update(err, weight);
    }

    pub fn correct(self: *const HistoryTable, board: *const Board, prev: TypedMove, static_eval: i16) i16 {
        const pawn_correction: i32 = (&self.pawn_corrhist)[board.pawn_hash % CORRHIST_SIZE][board.stm.toInt()].val;

        const major_correction: i32 = (&self.major_corrhist)[board.major_hash % CORRHIST_SIZE][board.stm.toInt()].val;

        const white_nonpawn_correction: i32 = (&self.nonpawn_corrhist)[board.nonpawn_hash[0] % CORRHIST_SIZE][board.stm.toInt()][0].val;
        const black_nonpawn_correction: i32 = (&self.nonpawn_corrhist)[board.nonpawn_hash[1] % CORRHIST_SIZE][board.stm.toInt()][1].val;
        const nonpawn_correction = white_nonpawn_correction + black_nonpawn_correction >> 1;

        const countermove_correction: i32 = (&self.countermove_corrhist)[@as(usize, prev.tp.toInt()) * 64 + prev.move.to().toInt()][board.stm.toInt()].val;

        const correction = (pawn_correction + nonpawn_correction + countermove_correction + major_correction) >> 8;
        return evaluation.clampScore(static_eval + correction);
    }
};

fn gravityUpdate(entry: *i16, adjustment: anytype) void {
    const clamped: i16 = @intCast(std.math.clamp(adjustment, -MAX_HISTORY, MAX_HISTORY));
    const magnitude: i32 = @abs(clamped);
    entry.* += @intCast(clamped - ((magnitude * entry.*) >> SHIFT));
}

const CorrhistEntry = struct {
    val: i16 = 0,

    fn update(self: *CorrhistEntry, err: i32, weight: i32) void {
        const val = self.val;
        const lerped = (val * (256 - weight) + err * weight) >> 8;
        const clamped = std.math.clamp(lerped, -MAX_CORRHIST, MAX_CORRHIST);
        self.val = @intCast(clamped);
    }
};
