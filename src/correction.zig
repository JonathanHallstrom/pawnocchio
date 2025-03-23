const std = @import("std");
const Board = @import("Board.zig");
const Side = @import("side.zig").Side;
const eval = @import("eval.zig");
const tunable_constants = @import("tuning.zig").tunable_constants;

// heavily based on https://github.com/Ciekce/Stormphrax/blob/main/src/correction.h

pub fn update(board: *const Board, corrected_static_eval: i16, score: i16, depth: u8) void {
    const err: i32 = (@as(i32, score) - corrected_static_eval) * 256;
    const weight: i32 = @min(@as(i32, depth), 15) + 1;

    updatePawnCorrhist(board, err, weight);
    updateNonPawnCorrhist(board, err, weight);
}

pub fn correct(board: *const Board, static_eval: i16) i16 {
    const pawn_correction: i32 = pawnCorrhistEntry(board).*;
    const non_pawn_correction: i32 = whiteNonPawnCorrhistEntry(board).* + blackNonCorrhistEntry(board).*;
    const total_correction = pawn_correction * tunable_constants.pawn_corrhist_weight + non_pawn_correction * tunable_constants.nonpawn_corrhist_weight >> 12;
    // std.debug.print("{s} {} {} {}\n", .{ board.toFen().slice(), static_eval, non_pawn_correction >> 8, pawn_correction >> 8 });
    return eval.clampScore(static_eval + total_correction);
}

pub fn reset() void {
    @memset(&pawn_corrhist, 0);
    @memset(std.mem.asBytes(&non_pawn_corrhist), 0);
}

fn updatePawnCorrhist(board: *const Board, err: i32, weight: i32) void {
    const entry = pawnCorrhistEntry(board);
    const lerped = (entry.* * (256 - weight) + err * weight) >> 8;
    const clamped = std.math.clamp(lerped, -max_history, max_history);
    entry.* = @intCast(clamped);
}

fn updateNonPawnCorrhist(board: *const Board, err: i32, weight: i32) void {
    const entry = nonPawnCorrhistEntry(board);
    const lerped = (entry.* * (256 - weight) + err * weight) >> 8;
    const clamped = std.math.clamp(lerped, -max_history, max_history);
    entry.* = @intCast(clamped);
}

fn pawnCorrhistEntry(board: *const Board) *i16 {
    return &pawn_corrhist[board.pawn_zobrist % corrhist_size];
}

fn whiteNonPawnCorrhistEntry(board: *const Board) *i16 {
    return &non_pawn_corrhist[Side.white.toInt()][board.non_pawn_zobrist[Side.white.toInt()] % corrhist_size];
}

fn blackNonCorrhistEntry(board: *const Board) *i16 {
    return &non_pawn_corrhist[Side.black.toInt()][board.non_pawn_zobrist[Side.black.toInt()] % corrhist_size];
}

fn nonPawnCorrhistEntry(board: *const Board) *i16 {
    return &non_pawn_corrhist[board.turn.toInt()][board.non_pawn_zobrist[board.turn.toInt()] % corrhist_size];
}

const corrhist_size = 16384;

var pawn_corrhist = std.mem.zeroes([corrhist_size]i16);
var non_pawn_corrhist = std.mem.zeroes([2][corrhist_size]i16);
const max_history = 256 * 32;
