const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const SEE = @import("see.zig");
const tunable_constants = @import("tuning.zig").tunable_constants;

fn mvvLvaValue(board: *const Board, move: Move) u8 {
    if (!move.isCapture()) return 0;
    const captured_type: PieceType = if (move.isEnPassant()) .pawn else board.mailbox[move.getTo().toInt()].?;
    const moved_type = board.mailbox[move.getFrom().toInt()].?;
    return @intCast(@as(i16, 1 + @intFromEnum(captured_type)) * 8 - @intFromEnum(moved_type));
}

fn mvvLvaCompare(board: *const Board, lhs: Move, rhs: Move) bool {
    if (lhs.isCapture() != rhs.isCapture()) return @intFromBool(lhs.isCapture()) > @intFromBool(rhs.isCapture());
    return mvvLvaValue(board, lhs) > mvvLvaValue(board, rhs);
}

const MoveOrderContext = struct {
    board: *const Board,
    tt_move: Move,
};

fn compare(ctx: MoveOrderContext, lhs: Move, rhs: Move) bool {
    if ((lhs == ctx.tt_move) != (rhs == ctx.tt_move)) {
        return @intFromBool(lhs == ctx.tt_move) > @intFromBool(rhs == ctx.tt_move);
    }
    if (lhs.isCapture() != rhs.isCapture()) return @intFromBool(lhs.isCapture()) > @intFromBool(rhs.isCapture());
    return mvvLvaValue(ctx.board, lhs) > mvvLvaValue(ctx.board, rhs);
}

inline fn sort(
    comptime T: type,
    items: []T,
    context: anytype,
    comptime lessThanFn: fn (context: @TypeOf(context), lhs: T, rhs: T) bool,
) void {
    @call(.always_inline, std.mem.sort, .{ T, items, context, lessThanFn });
}

pub fn mvvLva(board: *const Board, moves: []Move) void {
    std.sort.pdq(Move, moves, board, mvvLvaCompare);
}

pub const ScoredMove = struct {
    move: Move align(4),
    score: i16,

    fn cmp(_: void, lhs: ScoredMove, rhs: ScoredMove) bool {
        return lhs.score > rhs.score;
    }
};

pub fn order(comptime turn: Side, board: *const Board, tt_move: Move, previous_move: Move, ply: u8, moves: []Move) void {
    var quiets = std.BoundedArray(ScoredMove, 256).init(0) catch unreachable;
    var good_noisies = std.BoundedArray(ScoredMove, 256).init(0) catch unreachable;
    var bad_noisies = std.BoundedArray(ScoredMove, 256).init(0) catch unreachable;
    var has_tt_move = false;
    var has_killer_move = false;
    for (moves) |move| {
        if (move == tt_move) {
            has_tt_move = true;
            continue;
        }
        if (move == killers[ply]) {
            has_killer_move = true;
            continue;
        }
        if (move.isCapture()) {
            if (SEE.scoreMove(board, move, 0)) {
                good_noisies.appendAssumeCapacity(.{ .move = move, .score = mvvLvaValue(board, move) });
            } else {
                bad_noisies.appendAssumeCapacity(.{ .move = move, .score = mvvLvaValue(board, move) });
            }
        } else {
            quiets.appendAssumeCapacity(.{ .move = move, .score = getHistory(turn, board, move, previous_move) });
        }
    }
    sort(ScoredMove, good_noisies.slice(), void{}, ScoredMove.cmp);
    sort(ScoredMove, bad_noisies.slice(), void{}, ScoredMove.cmp);
    sort(ScoredMove, quiets.slice(), void{}, ScoredMove.cmp);
    var idx: usize = 0;
    if (has_tt_move) {
        moves[idx] = tt_move;
        idx += 1;
    }
    for (good_noisies.slice()) |score_move_pair| {
        moves[idx] = score_move_pair.move;
        idx += 1;
    }
    if (has_killer_move) {
        moves[idx] = killers[ply];
        idx += 1;
    }
    for (quiets.slice()) |score_move_pair| {
        moves[idx] = score_move_pair.move;
        idx += 1;
    }
    for (bad_noisies.slice()) |score_move_pair| {
        moves[idx] = score_move_pair.move;
        idx += 1;
    }
}

pub const MovePicker = struct {
    const ScoredMoveArray = std.BoundedArray(ScoredMove, 256);

    moves: ScoredMoveArray = .{},
    masks: movegen.Masks = undefined,
    tt_move: MoveSpan = .{},
    good_noisies: MoveSpan = .{},
    killer: MoveSpan = .{},
    bad_noisies: MoveSpan = .{},
    quiets: MoveSpan = .{},
    stage: Stage = .tt,
    num_seen: u8 = 0,

    const MoveSpan = struct {
        begin: u8 = 0,
        end: u8 = 0,

        fn init(slice: anytype, len: anytype) MoveSpan {
            return .{
                .begin = @intCast(slice.len - len),
                .end = @intCast(slice.len),
            };
        }

        fn dropFirst(self: *MoveSpan) void {
            self.begin += 1;
        }

        fn numMoves(self: MoveSpan) usize {
            return self.end - self.begin;
        }
    };

    pub const Stage = enum(u4) {
        tt = 0,
        good_noisy = 1,
        killer = 2,
        quiet = 3,
        bad_noisy = 4,

        pub fn increment(self: *Stage) bool {
            if (self.* == .bad_noisy) return false;
            self.* = @enumFromInt(@intFromEnum(self.*) + 1);
            return true;
        }
    };

    pub fn moveCount(self: *const MovePicker) usize {
        return self.moves.len;
    }

    pub fn skipQuiets(self: *MovePicker) void {
        self.quiets = &.{};
        self.killer = &.{};
    }

    pub fn next(noalias self: *MovePicker) ?ScoredMove {
        var move_span = self.currentStageMoves();
        while (move_span.numMoves() == 0) {
            if (!self.stage.increment())
                return null;
            move_span = self.currentStageMoves();
        }
        const moves = self.moves.slice()[move_span.begin..move_span.end];
        var res_ptr: *ScoredMove = &moves[0];
        var res = res_ptr.*;
        for (moves) |*candidate_ptr| {
            if (candidate_ptr.score < res.score) {
                res_ptr = candidate_ptr;
                res = res_ptr.*;
            }
        }
        std.mem.swap(ScoredMove, res_ptr, &moves[0]);
        move_span.dropFirst();
        self.num_seen += 1;
        // std.debug.print("{} {} {any}\n", .{
        //     res.move.getFrom(),
        //     res.move.getTo(),
        //     res.move.getFlag(),
        // });
        return res;
    }

    pub fn init(
        comptime turn: Side,
        board: *const Board,
        tt_move: Move,
        previous_move: Move,
        ply: u8,
    ) MovePicker {
        return initImpl(false, turn, board, tt_move, previous_move, ply);
    }

    pub fn initQsearch(
        comptime turn: Side,
        board: *const Board,
        tt_move: Move,
    ) MovePicker {
        return initImpl(true, turn, board, tt_move, Move.null_move, 0);
    }

    fn initImpl(
        comptime qsearch: bool,
        comptime turn: Side,
        board: *const Board,
        tt_move: Move,
        previous_move: Move,
        ply: u8,
    ) MovePicker {
        var self: MovePicker = .{};

        var temp_buf: [256]Move = undefined;
        const move_count, self.masks = if (qsearch) movegen.getCapturesOrEvasionsWithInfo(turn, board.*, &temp_buf) else movegen.getMovesWithInfo(turn, false, board.*, &temp_buf);

        var quiets = std.BoundedArray(ScoredMove, 256).init(0) catch unreachable;
        var good_noisies = std.BoundedArray(ScoredMove, 256).init(0) catch unreachable;
        var bad_noisies = std.BoundedArray(ScoredMove, 256).init(0) catch unreachable;
        var has_tt_move = false;
        var has_killer_move = false;
        for (temp_buf[0..move_count]) |move| {
            if (move == tt_move) {
                has_tt_move = true;
                continue;
            }
            if (move == killers[ply]) {
                has_killer_move = true;
                continue;
            }
            if (move.isCapture()) {
                if (SEE.scoreMove(board, move, 0)) {
                    good_noisies.appendAssumeCapacity(.{ .move = move, .score = mvvLvaValue(board, move) });
                } else {
                    bad_noisies.appendAssumeCapacity(.{ .move = move, .score = mvvLvaValue(board, move) });
                }
            } else {
                quiets.appendAssumeCapacity(.{ .move = move, .score = getHistory(turn, board, move, previous_move) });
            }
        }

        if (has_tt_move) {
            self.moves.appendAssumeCapacity(.{ .move = tt_move, .score = 0 });
            self.tt_move = MoveSpan.init(self.moves.slice(), 1);
        }
        self.moves.appendSliceAssumeCapacity(good_noisies.slice());
        self.good_noisies = MoveSpan.init(self.moves.slice(), good_noisies.len);
        if (has_killer_move) {
            self.moves.appendAssumeCapacity(.{ .move = killers[ply], .score = 0 });
            self.killer = MoveSpan.init(self.moves.slice(), 1);
        }
        self.moves.appendSliceAssumeCapacity(quiets.slice());
        self.quiets = MoveSpan.init(self.moves.slice(), quiets.len);
        self.moves.appendSliceAssumeCapacity(bad_noisies.slice());
        self.bad_noisies = MoveSpan.init(self.moves.slice(), bad_noisies.len);

        return self;
    }

    fn currentStageMoves(self: *MovePicker) *MoveSpan {
        return switch (self.stage) {
            .tt => &self.tt_move,
            .good_noisy => &self.good_noisies,
            .killer => &self.killer,
            .quiet => &self.quiets,
            .bad_noisy => &self.bad_noisies,
        };
    }
};

pub fn reset() void {
    @memset(std.mem.asBytes(&history), 0);
    @memset(std.mem.asBytes(&cont_hist), 0);
    @memset(std.mem.asBytes(&killers), 0);
}

fn historyEntry(board: *const Board, move: Move) *i16 {
    const from = move.getFrom().toInt();
    const to = move.getTo().toInt();
    const moved_type = board.mailbox[from].?.toInt();
    return &history[if (board.turn == .white) 0 else 1][moved_type][from][to];
}

fn contHistEntry(comptime turn: Side, board: *const Board, move: Move, previous_move: Move) *i16 {
    const from = move.getFrom().toInt();
    const to = move.getTo().toInt();
    const moved_type = board.mailbox[from].?.toInt();
    const prev_to = if (previous_move.isCastlingMove()) previous_move.getCastlingKingDest(turn.flipped()).toInt() else previous_move.getTo().toInt();
    const prev_moved_type = board.mailbox[prev_to].?.toInt();
    return &cont_hist[if (board.turn == .white) 0 else 1][moved_type][to][prev_moved_type][prev_to];
}

pub fn getHistory(comptime turn: Side, board: *const Board, move: Move, previous_move: Move) i16 {
    if (previous_move == Move.null_move) {
        return historyEntry(board, move).*;
    } else {
        return @intCast(@as(i32, historyEntry(board, move).*) + contHistEntry(turn, board, move, previous_move).* >> 1);
    }
}

pub fn getBonus(depth: u8) i16 {
    return @intCast(@min(@as(i32, depth) * tunable_constants.history_bonus_mult - tunable_constants.history_bonus_offs, tunable_constants.history_bonus_max));
}

pub fn getMalus(depth: u8) i16 {
    return @intCast(-@min(@as(i32, depth) * tunable_constants.history_malus_mult - tunable_constants.history_malus_offs, tunable_constants.history_malus_max));
}

pub fn updateHistory(comptime turn: Side, board: *const Board, move: Move, previous_move: Move, bonus: anytype) void {
    const clamped_bonus: i16 = @intCast(std.math.clamp(bonus, -max_history, max_history));
    const magnitude: i32 = @abs(clamped_bonus); // i32 to avoid overflows

    const hist_entry = historyEntry(board, move);
    hist_entry.* += @intCast(clamped_bonus - @divTrunc(magnitude * hist_entry.*, max_history));

    if (previous_move != Move.null_move) {
        const cont_hist_entry = contHistEntry(turn, board, move, previous_move);
        cont_hist_entry.* += @intCast(clamped_bonus - @divTrunc(magnitude * cont_hist_entry.*, max_history));
    }
}

pub fn recordKiller(move: Move, ply: u8) void {
    killers[ply] = move;
}

pub fn clearIrrelevantKillers(ply: u8) void {
    if (ply < 255)
        killers[ply + 1] = Move.null_move;
}

const max_history = 1 << 14;
var killers = std.mem.zeroes([256]Move);
var history = std.mem.zeroes([2][6][64][64]i16);
var cont_hist = std.mem.zeroes([2][6][64][6][64]i16);
