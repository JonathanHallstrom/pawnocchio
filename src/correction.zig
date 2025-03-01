const std = @import("std");
const Board = @import("Board.zig");
const eval = @import("eval.zig");

pub fn update(board: *const Board, corrected_static_eval: i16, score: i16) void {
    const bonus: i32 = @as(i32, score) - corrected_static_eval >> 4;
    updatePawnCorrhist(board, bonus);
}

fn updatePawnCorrhist(board: *const Board, bonus: anytype) void {
    const entry = &pawn_corrhist[board.pawn_zobrist % pawn_corrhist.len];
    const clamped_bonus: i16 = @intCast(std.math.clamp(bonus - @as(i32, entry.*), -max_history, max_history));
    const magnitude: i32 = @abs(clamped_bonus);
    entry.* += @intCast(clamped_bonus - @divTrunc(magnitude * clamped_bonus, max_history));
}

pub fn correct(board: *const Board, static_eval: i16) i16 {
    const correction: i32 = pawn_corrhist[board.pawn_zobrist % pawn_corrhist.len];
    return eval.clampScore(static_eval + correction);
}

pub fn reset() void {
    @memset(&pawn_corrhist, 0);
}

var pawn_corrhist = std.mem.zeroes([8192]i16);

const max_history = 1 << 14;
