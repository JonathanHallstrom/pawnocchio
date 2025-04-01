// Pawnocchio, UCI chess engine
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

const use_hce = true;
const impl = if (use_hce) @import("hce.zig") else @compileError("TODO: nnue");

pub const State = impl.State;
pub const evaluate: fn (*const Board, State) i16 = impl.evaluate;

pub const checkmate_score: i16 = 16000;
pub const win_score: i16 = checkmate_score - root.Searcher.MAX_PLY;

pub fn clampScore(score: anytype) i16 {
    return @intCast(std.math.clamp(score, -(win_score - 1), win_score - 1));
}

pub fn scoreToTt(score: i16, ply: u8) i16 {
    if (score < -win_score) {
        return score - ply;
    }
    if (score > win_score) {
        return score + ply;
    }
    return score;
}

pub fn scoreFromTt(score: i16, ply: u8) i16 {
    if (score < -win_score) {
        return score + ply;
    }
    if (score > win_score) {
        return score - ply;
    }
    return score;
}

pub fn matedIn(plies: u8) i16 {
    return -checkmate_score + plies;
}

pub fn isMateScore(score: i16) bool {
    return @abs(score) >= win_score;
}

pub fn formatScore(score: i16) std.BoundedArray(u8, 15) {
    var print_buf: [8]u8 = undefined;
    var res: std.BoundedArray(u8, 15) = .{};
    if (isMateScore(score)) {
        const plies_to_mate = if (score > 0) checkmate_score - score else checkmate_score + score;
        const moves_to_mate = @divTrunc(plies_to_mate + 1, 2);
        if (score < 0)
            res.appendAssumeCapacity('-');
        res.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{moves_to_mate}) catch unreachable);
    } else {
        res.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{score}) catch unreachable);
    }
    return res;
}
