const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const SEE = @import("see.zig");

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

pub fn order(comptime turn: Side, board: *const Board, tt_move: Move, previous_move: Move, moves: []Move) void {
    var quiets = std.BoundedArray(ScoreMovePair, 256).init(0) catch unreachable;
    var captures = std.BoundedArray(ScoreMovePair, 256).init(0) catch unreachable;
    var has_tt_move = false;
    for (moves) |move| {
        if (tt_move != Move.null_move and move == tt_move) {
            has_tt_move = true;
            continue;
        }
        if (move.isCapture()) {
            // const see_bonus: i16 = if (SEE.scoreMove(board, move, 0)) 1000 else 0;
            const see_bonus: i16 = 0;

            captures.appendAssumeCapacity(.{ .move = move, .score = mvvLvaValue(board, move) + see_bonus });
        } else {
            quiets.appendAssumeCapacity(.{ .move = move, .score = getHistory(turn, board, move, previous_move) });
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
    @memset(std.mem.asBytes(&cont_hist), 0);
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
    // TODO: tuning
    return @intCast(@min(@as(i32, depth) * 300 - 300, 2300));
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

const max_history = 1 << 14;
var history = std.mem.zeroes([2][6][64][64]i16);
var cont_hist = std.mem.zeroes([2][6][64][6][64]i16);
