const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;

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

const ScoreMovePair = struct {
    move: Move,
    score: i16,

    fn cmp(_: void, lhs: ScoreMovePair, rhs: ScoreMovePair) bool {
        return lhs.score > rhs.score;
    }
};

pub fn order(board: *const Board, tt_move: Move, moves: []Move) void {
    var quiets = std.BoundedArray(ScoreMovePair, 256).init(0) catch unreachable;
    var captures = std.BoundedArray(ScoreMovePair, 256).init(0) catch unreachable;
    var has_tt_move = false;
    for (moves) |move| {
        if (tt_move != Move.null_move and move == tt_move) {
            has_tt_move = true;
            continue;
        }
        if (move.isCapture()) {
            captures.appendAssumeCapacity(.{ .move = move, .score = mvvLvaValue(board, move) });
        } else {
            quiets.appendAssumeCapacity(.{ .move = move, .score = getHistory(board, move) });
        }
    }
    sort(ScoreMovePair, captures.slice(), void{}, ScoreMovePair.cmp);
    sort(ScoreMovePair, quiets.slice(), void{}, ScoreMovePair.cmp);
    moves[0] = tt_move;
    for (0..captures.len) |i| {
        moves[@intFromBool(has_tt_move) + i] = captures.slice()[i].move;
    }
    for (0..quiets.len) |i| {
        moves[captures.len + @intFromBool(has_tt_move) + i] = quiets.slice()[i].move;
    }
}

pub fn reset() void {
    @memset(std.mem.asBytes(&history), 0);
}

pub fn historyEntry(board: *const Board, move: Move) *i16 {
    return &history[if (board.turn == .white) 0 else 1][move.getFrom().toInt()][move.getTo().toInt()];
}

pub fn getHistory(board: *const Board, move: Move) i16 {
    return historyEntry(board, move).*;
}

pub fn getBonus(depth: u8) i16 {
    // TODO: tuning
    return @min(@as(i16, depth) * 300 - 300, 2300);
}

pub fn updateHistory(board: *const Board, move: Move, bonus: anytype) void {
    const clamped_bonus: i16 = @intCast(std.math.clamp(bonus, -max_history, max_history));
    const entry = historyEntry(board, move);
    entry.* = @intCast(clamped_bonus - @divTrunc(@as(i32, @abs(clamped_bonus)) * entry.*, max_history));
}

const max_history = 1 << 14;
var history = std.mem.zeroes([2][64][64]i16);
