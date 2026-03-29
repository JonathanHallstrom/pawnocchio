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
const build_options = @import("build_options");
const EvalMode = @import("eval_mode.zig").EvalMode;

const root = @import("root.zig");

const Board = root.Board;
pub const EVAL_MODE: EvalMode = std.meta.stringToEnum(EvalMode, build_options.eval).?;
pub const eval_mode: EvalMode = EVAL_MODE;
const impl = switch (EVAL_MODE) {
    .hce => @import("hce.zig"),
    .material => @import("material_eval.zig"),
    .nnue => root.nnue,
};

pub const Context = switch (EVAL_MODE) {
    .nnue => struct {
        weights: *const root.nnue.Weights,
        refresh_cache: *root.refreshCache(root.nnue.HORIZONTAL_MIRRORING, root.nnue.INPUT_BUCKET_COUNT),
    },
    inline else => struct {},
};

pub const State = impl.State;

pub inline fn evaluate(comptime stm: root.Colour, board: *const Board, state: *State, ctx: Context) i16 {
    return impl.evaluate(stm, board, state, ctx);
}

pub fn evalPosition(board: *const Board) i16 {
    return impl.evalPosition(board);
}

pub fn evalFen(fen: []const u8) !i16 {
    return evalPosition(&try Board.parseFen(fen, true));
}

pub const INF_SCORE: i16 = 32767;
pub const CHECKMATE_SCORE: i16 = 32000;
pub const HIGHEST_NON_MATE_SCORE = CHECKMATE_SCORE - root.SEARCH_MAX_PLY - 1;
pub const TB_WIN_SCORE: i16 = 30000;
pub const HIGHEST_NON_TB_SCORE = TB_WIN_SCORE - root.SEARCH_MAX_PLY - 1;
pub const WIN_SCORE: i16 = 29000;

pub fn clampScore(score: anytype) i16 {
    return @intCast(std.math.clamp(score, -(WIN_SCORE - 1), WIN_SCORE - 1));
}

pub fn scoreToTt(score: i16, ply: u8) i16 {
    if (score < -WIN_SCORE) {
        return score - ply;
    }
    if (score > WIN_SCORE) {
        return score + ply;
    }
    return score;
}

pub fn scoreFromTt(score: i16, ply: u8) i16 {
    if (score < -WIN_SCORE) {
        return score + ply;
    }
    if (score > WIN_SCORE) {
        return score - ply;
    }
    return score;
}

pub fn checkTTBound(score: i16, alpha: i32, beta: i32, tp: root.ScoreType) bool {
    return switch (tp) {
        .none => false,
        .lower => score >= beta,
        .upper => score <= alpha,
        .exact => true,
    };
}

pub fn matedIn(plies: u16) i16 {
    return -CHECKMATE_SCORE + @as(i16, @intCast(plies));
}

pub fn tbWin(plies: u8) i16 {
    return TB_WIN_SCORE - plies;
}

pub fn tbLoss(plies: u8) i16 {
    return -TB_WIN_SCORE + plies;
}

pub fn isMateScore(score: i32) bool {
    return @abs(score) > HIGHEST_NON_MATE_SCORE;
}

pub fn isTBScore(score: i32) bool {
    return @abs(score) > HIGHEST_NON_TB_SCORE;
}

pub fn formatScore(score: i16) root.BoundedArray(u8, 15) {
    var print_buf: [15]u8 = undefined;
    var res: root.BoundedArray(u8, 15) = .{};
    if (isMateScore(score)) {
        const plies_to_mate = if (score > 0) CHECKMATE_SCORE - score else CHECKMATE_SCORE + score;
        const moves_to_mate = @divTrunc(plies_to_mate + 1, 2);
        res.appendSliceAssumeCapacity("mate ");
        if (score < 0)
            res.appendAssumeCapacity('-');
        res.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{moves_to_mate}) catch unreachable);
    } else {
        res.appendSliceAssumeCapacity("cp ");
        res.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{score}) catch unreachable);
    }
    return res;
}
