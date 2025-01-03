const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const PieceType = @import("piece_type.zig").PieceType;
const Move = @import("Move.zig");
const Board = @import("Board.zig");

pub const checkmate_score: i16 = 16000;
const piece_values: [PieceType.all.len]i16 = .{
    100,
    300,
    300,
    500,
    900,
    0,
};

pub fn mateIn(plies: u8) i16 {
    return -checkmate_score + plies;
}

pub fn isMateScore(score: i16) bool {
    return @abs(score) >= checkmate_score - 255;
}

pub fn evaluate(board: Board) i16 {
    var res: i16 = 0;
    for (PieceType.all) |pt| {
        const p: usize = @intFromEnum(pt);
        res += piece_values[p] * @popCount(board.white.raw[p]);
        res -= piece_values[p] * @popCount(board.black.raw[p]);
    }
    return if (board.turn == .white) res else -res;
}
