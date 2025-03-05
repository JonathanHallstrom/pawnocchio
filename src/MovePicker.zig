const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const move_ordering = @import("move_ordering.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const SEE = @import("see.zig");

const assert = std.debug.assert;

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
generate_quiets: bool = true,
masks: movegen.Masks = undefined,

const Stage = enum {
    tt,
    generate_noisy,
    good_noisy,
    killer,
    bad_noisy,
    generate_quiet,
    quiet,
    done,

    pub fn increment(self: *Stage) Stage {
        return switch (self.*) {
            .tt => .good_noisy,
            .good_noisy => .killer,
            .killer => .bad_noisy,
            .bad_noisy => .quiet,
            .quiet => .done,
            .done => unreachable,
        };
    }
};

const ScoredMove = struct {
    move: Move,
    score: i16 = 0,
    flag: MoveFlag = .none,

    pub fn init(move: Move) ScoredMove {
        return .{
            .move = move,
        };
    }

    const MoveFlag = enum {
        none,
        tt,
        killer,
        good_noisy,
        bad_noisy,
    };

    pub fn isGoodNoisy(self: ScoredMove) bool {
        return self.flag == .bad_noisy;
    }

    pub fn isBadCapture(self: ScoredMove) bool {
        return self.flag == .bad_capture;
    }

    pub fn isTTMove(self: ScoredMove) bool {
        return self.flag == .tt;
    }

    pub fn isKiller(self: ScoredMove) bool {
        return self.flag == .killer;
    }

    fn cmp(self: ScoredMove, other: ScoredMove) bool {
        return self.score > other.score;
    }
};

fn completedStage(self: Self) ?ScoredMove {
    self.stage = self.stage.increment();
    return self.next();
}

pub fn next(self: *Self) ?ScoredMove {
    switch (self.board.turn) { // gotta work around that horrible design decision....  (requiring `comptime turn: Side` all over the damn place....)
        inline else => |turn| switch (self.stage) {
            .tt => {
                if (!self.board.isPseudoLegal(self.tt_move)) {
                    return self.completedStage();
                }
                self.stage = self.stage.increment();
                return ScoredMove{
                    .move = self.tt_move,
                    .flag = .tt,
                };
            },
            .generate_noisy => {
                var noisies: [256]Move = undefined;
                assert(self.masks == null);
                self.masks = movegen.getMasks(turn, self.board.*);
                const num_moves = movegen.getMovesWithOutInfo(turn, true, false, self.board.*, &noisies, self.masks);
                for (noisies[0..num_moves]) |move| {
                    const is_good = SEE.scoreMove(self.board, move, 0);
                    if (is_good) {
                        self.good_noisies[self.num_good_noisies] = ScoredMove.init(move);
                        self.good_noisies[self.num_good_noisies].flag = .good_noisy;
                        self.good_noisies[self.num_good_noisies].score = move_ordering.mvvLvaValue(self.board, move);
                        self.num_good_noisies += 1;
                    } else {
                        self.bad_noisies[self.num_bad_noisies] = ScoredMove.init(move);
                        self.bad_noisies[self.num_bad_noisies].flag = .bad_noisy;
                        self.bad_noisies[self.num_bad_noisies].score = move_ordering.mvvLvaValue(self.board, move);
                        self.num_bad_noisies += 1;
                    }
                }
                return self.completedStage();
            },
            .good_noisy => {
                if (self.num_good_noisies == 0) {
                    return self.completedStage();
                }
                var best = self.good_noisies[0];
                for (self.good_noisies[1..self.num_good_noisies]) |cur| {
                    if (cur.score > best.score) {
                        best = cur;
                    }
                }
                self.num_good_noisies -= 1;
                return best;
            },
            .killer => {
                const killer_move = move_ordering.killers[self.ply];
                if (!self.board.isPseudoLegal(killer_move)) {
                    return self.completedStage();
                }
                self.stage = self.stage.increment();
                return ScoredMove{
                    .move = killer_move,
                    .flag = .killer,
                };
            },
            .bad_noisy => {
                if (self.num_bad_noisies == 0) {
                    return self.completedStage();
                }
                var best = self.bad_noisies[0];
                for (self.bad_noisies[1..self.num_bad_noisies]) |cur| {
                    if (cur.score > best.score) {
                        best = cur;
                    }
                }
                self.num_bad_noisies -= 1;
                return best;
            },
            .generate_quiet => {
                self.num_quiets = movegen.getMovesWithOutInfo(turn, false, true, self.board.*, self.quiets, self.masks);
                for (self.quiets[0..self.num_quiets]) |*uninitialized_scored_quiet| {
                    uninitialized_scored_quiet.score = move_ordering.getHistory(turn, self.board, self.prev_move);
                    uninitialized_scored_quiet.flag = .none;
                }
                return self.completedStage();
            },
            .quiet => {
                if (self.num_quiets == 0) {
                    return self.completedStage();
                }
                var best = self.quiets[0];
                for (self.quiets[1..self.num_quiets]) |cur| {
                    if (cur.score > best.score) {
                        best = cur;
                    }
                }
                self.num_quiets -= 1;
                return best;
            },
            .done => return null,
        },
    }
}

const Self = @This();

pub fn init(board: *const Board, tt_move: Move, previous_move: Move, ply: u8) Self {
    return .{
        .board = board,
        .tt_move = tt_move,
        .previous_move = previous_move,
        .ply = ply,
    };
}
