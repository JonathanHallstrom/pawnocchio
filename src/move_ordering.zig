const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;

pub fn historyEntry(board: *const Board, move: Move) *i16 {
    const from_idx: usize = move.getFrom().toInt();
    const tp = board.mailbox[from_idx].?;
    return &history[@intFromBool(board.turn == .black)][tp.toInt()][from_idx];
}

pub fn readHistory(board: *const Board, move: Move) i16 {
    return historyEntry(board, move).*;
}

pub fn updateHistory(board: *const Board, move: Move, bonus: i32) void {
    const clamped = std.math.clamp(bonus, -MAX_HISTORY, MAX_HISTORY);
    const entry = historyEntry(board, move);

    // entry.* += @intCast(clamped - @divTrunc(clamped * entry.*, MAX_HISTORY));
    entry.* = @intCast(std.math.clamp(entry.* + clamped, -MAX_HISTORY, MAX_HISTORY));
}

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
    @call(.always_inline, std.sort.pdq, .{ T, items, context, lessThanFn });
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
            quiets.appendAssumeCapacity(.{ .move = move, .score = readHistory(board, move) });
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

var history: [2][PieceType.all.len][64]i16 = .{.{.{0} ** 64} ** PieceType.all.len} ** 2;
const MAX_HISTORY: i16 = 1 << 14;
