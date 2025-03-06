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
previous_move: Move,
ply: u8,
sent_killer: Move = Move.null_move,
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

    pub fn increment(self: Stage) Stage {
        return switch (self) {
            .tt => .generate_noisy,
            .generate_noisy => .good_noisy,
            .good_noisy => .killer,
            .killer => .bad_noisy,
            .bad_noisy => .generate_quiet,
            .generate_quiet => .quiet,
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

fn completedStage(self: *Self) ?ScoredMove {
    self.stage = self.stage.increment();
    return self.next();
}

fn iterImpl(self: *Self, comptime do_peek: bool) ?ScoredMove {
    switch (self.board.turn) { // gotta work around that horrible design decision....  (requiring `comptime turn: Side` all over the damn place....)
        inline else => |turn| switch (self.stage) {
            .tt => {
                if (!self.board.isLegal(self.tt_move)) {
                    return self.completedStage();
                }
                if (!do_peek)
                    self.stage = self.stage.increment();
                return ScoredMove{
                    .move = self.tt_move,
                    .flag = .tt,
                };
            },
            .generate_noisy => {
                var noisies: [256]Move = undefined;
                const num_moves = movegen.getMovesWithOutInfo(turn, true, false, self.board.*, &noisies, self.masks);
                for (noisies[0..num_moves]) |move| {
                    if (move == self.tt_move) continue;
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
                var best = self.good_noisies[self.num_good_noisies - 1];
                for (self.good_noisies[0 .. self.num_good_noisies - 1], 0..) |cur, i| {
                    if (cur.score > best.score) {
                        self.good_noisies[i] = best;
                        self.good_noisies[self.num_good_noisies - 1] = cur;
                        best = cur;
                    }
                }
                if (!do_peek)
                    self.num_good_noisies -= 1;

                return best;
            },
            .killer => {
                const killer_move = move_ordering.killers[self.ply];
                if (killer_move == self.tt_move or !self.board.isLegal(killer_move)) {
                    return self.completedStage();
                }
                if (!do_peek)
                    self.stage = self.stage.increment();
                self.sent_killer = killer_move;
                return ScoredMove{
                    .move = killer_move,
                    .flag = .killer,
                };
            },
            .bad_noisy => {
                if (self.num_bad_noisies == 0) {
                    return self.completedStage();
                }

                var best = self.bad_noisies[self.num_bad_noisies - 1];
                for (self.bad_noisies[0 .. self.num_bad_noisies - 1], 0..) |cur, i| {
                    if (cur.score > best.score) {
                        self.bad_noisies[i] = best;
                        self.bad_noisies[self.num_bad_noisies - 1] = cur;
                        best = cur;
                    }
                }
                if (!do_peek)
                    self.num_bad_noisies -= 1;

                return best;
            },
            .generate_quiet => {
                const num_generated = movegen.getMovesWithOutInfo(turn, false, true, self.board.*, &self.quiets, self.masks);

                for (self.quiets[0..num_generated]) |uninitialized_scored_quiet| {
                    if (uninitialized_scored_quiet.move == self.tt_move) continue;
                    if (uninitialized_scored_quiet.move == self.sent_killer) continue;

                    self.quiets[self.num_quiets] = uninitialized_scored_quiet;
                    self.quiets[self.num_quiets].score = move_ordering.getHistory(turn, self.board, uninitialized_scored_quiet.move, self.previous_move);
                    self.quiets[self.num_quiets].flag = .none;
                    self.num_quiets += 1;
                }
                return self.completedStage();
            },
            .quiet => {
                if (self.num_quiets == 0) {
                    return self.completedStage();
                }
                var best = self.quiets[self.num_quiets - 1];
                for (self.quiets[0 .. self.num_quiets - 1], 0..) |cur, i| {
                    if (cur.score > best.score) {
                        self.quiets[i] = best;
                        self.quiets[self.num_quiets - 1] = cur;
                        best = cur;
                    }
                }
                if (!do_peek)
                    self.num_quiets -= 1;
                return best;
            },
            .done => return null,
        },
    }
}

pub fn next(self: *Self) ?ScoredMove {
    return self.iterImpl(false);
}

pub fn peek(self: *Self) ?ScoredMove {
    return self.iterImpl(true);
}

const Self = @This();

pub fn init(board: *const Board, tt_move: Move, previous_move: Move, ply: u8) Self {
    switch (board.turn) {
        inline else => |turn| {
            return .{
                .board = board,
                .tt_move = tt_move,
                .previous_move = previous_move,
                .ply = ply,
                .masks = movegen.getMasks(turn, board.*),
            };
        },
    }
}

test "basic mp functionality" {
    const board = Board.init();
    move_ordering.reset();
    var mp = Self.init(&board, Move.null_move, Move.null_move, 0);
    var count: usize = 0;
    while (mp.next()) |scored_move| {
        _ = scored_move;
        count += 1;
    }
    try std.testing.expectEqual(20, count);
}

test "TT move first in mp" {
    const board = Board.init();
    move_ordering.reset();
    assert(board.isPseudoLegal(Move.initQuiet(.e2, .e4)));
    var mp = Self.init(&board, Move.initQuiet(.e2, .e4), Move.null_move, 0);
    var count: usize = 1;
    const first = mp.next().?;
    try std.testing.expectEqual(ScoredMove.MoveFlag.tt, first.flag);
    try std.testing.expectEqual(Move.initQuiet(.e2, .e4), first.move);
    while (mp.next()) |scored_move| {
        _ = scored_move;
        count += 1;
    }
    try std.testing.expectEqual(20, count);
}

test "captures first in mp" {
    const board = try Board.parseFen("r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQ1RK1 b kq - 5 4");
    move_ordering.reset();
    var mp = Self.init(&board, Move.null_move, Move.null_move, 0);
    var quiets = false;
    var count: usize = 0;
    while (mp.next()) |scored_move| {
        if (count == 0) {
            try std.testing.expect(scored_move.move.isCapture());
        }
        count += 1;
        quiets = quiets or scored_move.move.isQuiet();
        if (quiets) {
            try std.testing.expect(scored_move.move.isQuiet());
        }
    }
    try std.testing.expectEqual(29, count);
}
