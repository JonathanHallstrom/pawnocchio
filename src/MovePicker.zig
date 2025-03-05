const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const SEE = @import("see.zig");

board: *const Board,
tt_move: Move,
prev_move: Move,
ply: u8,
quiets: [256]ScoredMove = undefined,
num_quiets: u8 = 0,
good_noisies: [256]ScoredMove = undefined,
num_good_noisies: u8 = 0,
bad_noisies: [256]ScoredMove = undefined,
num_bad_noisies: u8 = 0,
stage: Stage = .tt,

const Stage = enum {
    tt,
    good_noisy,
    killer,
    bad_noisy,
    quiet,
};

const ScoredMove = struct {
    move: Move,
    score: i16 = 0,
    flags: u8 = 0,

    pub fn init(move: Move) ScoredMove {
        return .{
            .move = move,
        };
    }

    const good_capture_flag = 1;
    const bad_capture_flag = 2;
    const tt_move_flag = 3;
    const killer_flag = 4;

    pub fn isGoodCapture(self: ScoredMove) bool {
        return self.flags == good_capture_flag;
    }

    pub fn isBadCapture(self: ScoredMove) bool {
        return self.flags == bad_capture_flag;
    }

    pub fn isTTMove(self: ScoredMove) bool {
        return self.flags == tt_move_flag;
    }

    pub fn isKiller(self: ScoredMove) bool {
        return self.flags == killer_flag;
    }

    fn cmp(self: ScoredMove, other: ScoredMove) bool {
        return self.score > other.score;
    }
};

const Self = @This();

pub fn init(board: *const Board, tt_move: Move, previous_move: Move, ply: u8) Self {
    return .{
        .board = board,
        .tt_move = tt_move,
        .previous_move = previous_move,
        .ply = ply,
    };
}
