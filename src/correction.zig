const std = @import("std");
const Board = @import("Board.zig");
const eval = @import("eval.zig");

// heavily based on https://github.com/Ciekce/Stormphrax/blob/main/src/correction.h

pub fn update(board: *const Board, corrected_static_eval: i16, score: i16, depth: u8) void {
    const err: i32 = (@as(i32, score) - corrected_static_eval) * 256;
    const weight: i32 = @min(@as(i32, depth), 15) + 1;

    updatePawnCorrhist(board, err, weight);
    updateMajorCorrhist(board, err, weight);
}

pub fn correct(board: *const Board, static_eval: i16) i16 {
    const pawn_correction: i32 = pawn_corrhist[board.pawn_zobrist % pawn_corrhist.len];
    const major_correction: i32 = pawn_corrhist[board.major_zobrist % pawn_corrhist.len];
    const total_correction = pawn_correction + major_correction >> 8;
    return eval.clampScore(static_eval + total_correction);
}

pub fn reset() void {
    @memset(&pawn_corrhist, 0);
    @memset(&major_corrhist, 0);
}

fn updatePawnCorrhist(board: *const Board, err: i32, weight: i32) void {
    const entry = &pawn_corrhist[@intCast(board.pawn_zobrist % pawn_corrhist.len)];
    const lerped = (entry.* * (256 - weight) + err * weight) >> 8;
    const clamped = std.math.clamp(lerped, -max_history, max_history);
    entry.* = @intCast(clamped);
}

fn updateMajorCorrhist(board: *const Board, err: i32, weight: i32) void {
    const entry = &major_corrhist[board.major_zobrist % pawn_corrhist.len];
    const lerped = (entry.* * (256 - weight) + err * weight) >> 8;
    const clamped = std.math.clamp(lerped, -max_history, max_history);
    entry.* = @intCast(clamped);
}

var pawn_corrhist = std.mem.zeroes([16384]i16);
var major_corrhist = std.mem.zeroes([16384]i16);
const max_history = 256 * 32;
