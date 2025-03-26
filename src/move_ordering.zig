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
    comptime lessThanFn: fn (@TypeOf(context), lhs: T, rhs: T) bool,
) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        const current = items[i];
        var j = i;
        while (j > 0 and lessThanFn(context, current, items[j - 1])) : (j -= 1) {
            items[j] = items[j - 1];
        }
        items[j] = current;
    }
}

// inline fn sort(
//     comptime T: type,
//     items: []T,
//     context: anytype,
//     comptime lessThanFn: fn (context: @TypeOf(context), lhs: T, rhs: T) bool,
// ) void {
//     @call(.always_inline, std.sort.insertion, .{ T, items, context, lessThanFn });
// }

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

pub fn order(comptime turn: Side, board: *const Board, tt_move: Move, previous_move: Move, ply: u8, moves: []Move) void {
    var quiets = std.BoundedArray(ScoreMovePair, 256).init(0) catch unreachable;
    var good_noisies = std.BoundedArray(ScoreMovePair, 256).init(0) catch unreachable;
    var bad_noisies = std.BoundedArray(ScoreMovePair, 256).init(0) catch unreachable;
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
    sort(ScoreMovePair, good_noisies.slice(), void{}, ScoreMovePair.cmp);
    sort(ScoreMovePair, bad_noisies.slice(), void{}, ScoreMovePair.cmp);
    sort(ScoreMovePair, quiets.slice(), void{}, ScoreMovePair.cmp);
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
    if (previous_move.isNull()) {
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
