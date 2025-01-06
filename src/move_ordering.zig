const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const search = @import("search.zig");

pub fn historyEntry(board: *const Board, move: Move) *i16 {
    // const mb: [*]const ?PieceType = &board.mailbox;
    const from_idx: usize = move.getFrom().toInt();
    var ptr: [*]i16 = @ptrCast(&history);
    ptr = ptr[64 * @as(usize, board.mailbox[from_idx].?.toInt()) ..];
    ptr = ptr[from_idx..];
    return @ptrCast(ptr);
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

inline fn sort(
    comptime T: type,
    items: []T,
    context: anytype,
    comptime lessThanFn: fn (context: @TypeOf(context), lhs: T, rhs: T) bool,
) void {
    @call(.always_inline, std.sort.pdq, .{ T, items, context, lessThanFn });
}

fn compare(ctx: MoveOrderContext, lhs: Move, rhs: Move) bool {
    var l: i32 = @intFromBool(lhs == ctx.tt_move);
    var r: i32 = @intFromBool(rhs == ctx.tt_move);
    if (l != r) return l > r;
    l = @intFromBool(lhs.isCapture());
    r = @intFromBool(rhs.isCapture());
    if (l != r) return l > r;
    l = mvvLvaValue(ctx.board, lhs);
    r = mvvLvaValue(ctx.board, rhs);
    if (l != r) return l > r;
    l = readHistory(ctx.board, lhs);
    r = readHistory(ctx.board, rhs);
    return l > r;
}

pub fn mvvLva(board: *const Board, moves: []Move) void {
    sort(Move, moves, board, mvvLvaCompare);
}

pub fn order(board: *const Board, tt_move: Move, moves: []Move) void {
    sort(Move, moves, MoveOrderContext{
        .board = board,
        .tt_move = tt_move,
    }, compare);
}

pub fn reset() void {
    @memset(std.mem.asBytes(&history), 0);
}

var history: [PieceType.all.len][64]i16 = .{.{0} ** 64} ** PieceType.all.len;
const MAX_HISTORY: i16 = 1 << 14;
