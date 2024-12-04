const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const lib = @import("lib.zig");

const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const BitBoard = lib.BitBoard;
const Piece = lib.Piece;
const PieceType = lib.PieceType;
const Move = lib.Move;
const Board = lib.Board;

// havent quite gotten this working yet
const PestoEval = struct {
    const mg_value: [6]i16 = .{ 82, 337, 365, 477, 1025, 0 };
    const eg_value: [6]i16 = .{ 94, 281, 297, 512, 936, 0 };

    const mg_pawn_table: [64]i16 = .{
        0,   0,   0,   0,   0,   0,   0,  0,
        98,  134, 61,  95,  68,  126, 34, -11,
        -6,  7,   26,  31,  65,  56,  25, -20,
        -14, 13,  6,   21,  23,  12,  17, -23,
        -27, -2,  -5,  12,  17,  6,   10, -25,
        -26, -4,  -4,  -10, 3,   3,   33, -12,
        -35, -1,  -20, -23, -15, 24,  38, -22,
        0,   0,   0,   0,   0,   0,   0,  0,
    };

    const eg_pawn_table: [64]i16 = .{
        0,   0,   0,   0,   0,   0,   0,   0,
        178, 173, 158, 134, 147, 132, 165, 187,
        94,  100, 85,  67,  56,  53,  82,  84,
        32,  24,  13,  5,   -2,  4,   17,  17,
        13,  9,   -3,  -7,  -7,  -8,  3,   -1,
        4,   7,   -6,  1,   0,   -5,  -1,  -8,
        13,  8,   8,   10,  13,  0,   2,   -7,
        0,   0,   0,   0,   0,   0,   0,   0,
    };

    const mg_knight_table: [64]i16 = .{
        -167, -89, -34, -49, 61,  -97, -15, -107,
        -73,  -41, 72,  36,  23,  62,  7,   -17,
        -47,  60,  37,  65,  84,  129, 73,  44,
        -9,   17,  19,  53,  37,  69,  18,  22,
        -13,  4,   16,  13,  28,  19,  21,  -8,
        -23,  -9,  12,  10,  19,  17,  25,  -16,
        -29,  -53, -12, -3,  -1,  18,  -14, -19,
        -105, -21, -58, -33, -17, -28, -19, -23,
    };

    const eg_knight_table: [64]i16 = .{
        -58, -38, -13, -28, -31, -27, -63, -99,
        -25, -8,  -25, -2,  -9,  -25, -24, -52,
        -24, -20, 10,  9,   -1,  -9,  -19, -41,
        -17, 3,   22,  22,  22,  11,  8,   -18,
        -18, -6,  16,  25,  16,  17,  4,   -18,
        -23, -3,  -1,  15,  10,  -3,  -20, -22,
        -42, -20, -10, -5,  -2,  -20, -23, -44,
        -29, -51, -23, -15, -22, -18, -50, -64,
    };

    const mg_bishop_table: [64]i16 = .{
        -29, 4,  -82, -37, -25, -42, 7,   -8,
        -26, 16, -18, -13, 30,  59,  18,  -47,
        -16, 37, 43,  40,  35,  50,  37,  -2,
        -4,  5,  19,  50,  37,  37,  7,   -2,
        -6,  13, 13,  26,  34,  12,  10,  4,
        0,   15, 15,  15,  14,  27,  18,  10,
        4,   15, 16,  0,   7,   21,  33,  1,
        -33, -3, -14, -21, -13, -12, -39, -21,
    };

    const eg_bishop_table: [64]i16 = .{
        -14, -21, -11, -8,  -7, -9,  -17, -24,
        -8,  -4,  7,   -12, -3, -13, -4,  -14,
        2,   -8,  0,   -1,  -2, 6,   0,   4,
        -3,  9,   12,  9,   14, 10,  3,   2,
        -6,  3,   13,  19,  7,  10,  -3,  -9,
        -12, -3,  8,   10,  13, 3,   -7,  -15,
        -14, -18, -7,  -1,  4,  -9,  -15, -27,
        -23, -9,  -23, -5,  -9, -16, -5,  -17,
    };

    const mg_rook_table: [64]i16 = .{
        32,  42,  32,  51,  63, 9,  31,  43,
        27,  32,  58,  62,  80, 67, 26,  44,
        -5,  19,  26,  36,  17, 45, 61,  16,
        -24, -11, 7,   26,  24, 35, -8,  -20,
        -36, -26, -12, -1,  9,  -7, 6,   -23,
        -45, -25, -16, -17, 3,  0,  -5,  -33,
        -44, -16, -20, -9,  -1, 11, -6,  -71,
        -19, -13, 1,   17,  16, 7,  -37, -26,
    };

    const eg_rook_table: [64]i16 = .{
        13, 10, 18, 15, 12, 12,  8,   5,
        11, 13, 13, 11, -3, 3,   8,   3,
        7,  7,  7,  5,  4,  -3,  -5,  -3,
        4,  3,  13, 1,  2,  1,   -1,  2,
        3,  5,  8,  4,  -5, -6,  -8,  -11,
        -4, 0,  -5, -1, -7, -12, -8,  -16,
        -6, -6, 0,  2,  -9, -9,  -11, -3,
        -9, 2,  3,  -1, -5, -13, 4,   -20,
    };

    const mg_queen_table: [64]i16 = .{
        -28, 0,   29,  12,  59,  44,  43,  45,
        -24, -39, -5,  1,   -16, 57,  28,  54,
        -13, -17, 7,   8,   29,  56,  47,  57,
        -27, -27, -16, -16, -1,  17,  -2,  1,
        -9,  -26, -9,  -10, -2,  -4,  3,   -3,
        -14, 2,   -11, -2,  -5,  2,   14,  5,
        -35, -8,  11,  2,   8,   15,  -3,  1,
        -1,  -18, -9,  10,  -15, -25, -31, -50,
    };

    const eg_queen_table: [64]i16 = .{
        -9,  22,  22,  27,  27,  19,  10,  20,
        -17, 20,  32,  41,  58,  25,  30,  0,
        -20, 6,   9,   49,  47,  35,  19,  9,
        3,   22,  24,  45,  57,  40,  57,  36,
        -18, 28,  19,  47,  31,  34,  39,  23,
        -16, -27, 15,  6,   9,   17,  10,  5,
        -22, -23, -30, -16, -16, -23, -36, -32,
        -33, -28, -22, -43, -5,  -32, -20, -41,
    };

    const mg_king_table: [64]i16 = .{
        -65, 23,  16,  -15, -56, -34, 2,   13,
        29,  -1,  -20, -7,  -8,  -4,  -38, -29,
        -9,  24,  2,   -16, -20, 6,   22,  -22,
        -17, -20, -12, -27, -30, -25, -14, -36,
        -49, -1,  -27, -39, -46, -44, -33, -51,
        -14, -14, -22, -46, -44, -30, -15, -27,
        1,   7,   -8,  -64, -43, -16, 9,   8,
        -15, 36,  12,  -54, 8,   -28, 24,  14,
    };

    const eg_king_table: [64]i16 = .{
        -74, -35, -18, -18, -11, 15,  4,   -17,
        -12, 17,  14,  17,  17,  38,  23,  11,
        10,  17,  23,  15,  20,  45,  44,  13,
        -8,  22,  24,  27,  26,  33,  26,  3,
        -18, -4,  21,  24,  27,  23,  9,   -11,
        -19, -3,  11,  21,  23,  16,  7,   -9,
        -27, -11, 4,   13,  14,  4,   -5,  -17,
        -53, -34, -21, -11, -28, -14, -24, -43,
    };

    const mg_pesto_table: [6][64]i16 = .{
        mg_pawn_table,
        mg_knight_table,
        mg_bishop_table,
        mg_rook_table,
        mg_queen_table,
        mg_king_table,
    };

    const eg_pesto_table: [6][64]i16 = .{
        eg_pawn_table,
        eg_knight_table,
        eg_bishop_table,
        eg_rook_table,
        eg_queen_table,
        eg_king_table,
    };

    const gamephaseInc: [6]i16 = .{ 0, 1, 1, 2, 4, 0 };
    const mg_table = blk: {
        var res: [12][64]i16 = undefined;
        for (PieceType.all) |pt| {
            const p: usize = @intFromEnum(pt);
            for (0..64) |sq| {
                res[2 * p + 0][sq] = mg_value[p] + mg_pesto_table[p][sq ^ 56];
                res[2 * p + 1][sq] = mg_value[p] + mg_pesto_table[p][sq];
            }
        }
        break :blk res;
    };
    const eg_table = blk: {
        var res: [12][64]i16 = undefined;
        for (PieceType.all) |pt| {
            const p: usize = @intFromEnum(pt);
            for (0..64) |sq| {
                res[2 * p + 0][sq] = eg_value[p] + eg_pesto_table[p][sq ^ 56];
                res[2 * p + 1][sq] = eg_value[p] + eg_pesto_table[p][sq];
            }
        }
        break :blk res;
    };
};

const CHECKMATE_EVAL: i16 = 32000;

fn evalPieceMg(comptime piece_side: lib.Side, piece: Piece) i16 {
    const tp = piece.getType();
    const p: usize = @intFromEnum(tp);
    return PestoEval.mg_table[2 * p + @intFromBool(piece_side == .black)][piece.getLoc()];
}

fn evalPieceEg(comptime piece_side: lib.Side, piece: Piece) i16 {
    const tp = piece.getType();
    const p: usize = @intFromEnum(tp);
    return PestoEval.eg_table[2 * p + @intFromBool(piece_side == .black)][piece.getLoc()];
}

fn evalWithoutGameOverMg(comptime turn: lib.Side, board: Board) i16 {
    var res: i16 = 0;
    inline for (PieceType.all) |pt| {
        var iter = board.white.getBoard(pt).iterator();
        while (iter.next()) |b|
            res += evalPieceMg(.white, Piece.init(pt, b));
        iter = board.black.getBoard(pt).iterator();
        while (iter.next()) |b|
            res -= evalPieceMg(.black, Piece.init(pt, b));
    }
    if (turn == .black) res = -res;
    return res;
}

fn evalWithoutGameOverEg(comptime turn: lib.Side, board: Board) i16 {
    var res: i16 = 0;
    inline for (PieceType.all) |pt| {
        var iter = board.white.getBoard(pt).iterator();
        while (iter.next()) |b|
            res += evalPieceEg(.white, Piece.init(pt, b));
        iter = board.black.getBoard(pt).iterator();
        while (iter.next()) |b|
            res -= evalPieceEg(.black, Piece.init(pt, b));
    }
    if (turn == .black) res = -res;
    return res;
}

fn getPhase(pt: PieceType) i16 {
    return PestoEval.gamephaseInc[@intFromEnum(pt)];
}

fn getPhaseBoard(board: Board) i16 {
    var phase: i16 = 0;
    inline for (PieceType.all) |pt| {
        phase += board.white.getBoard(pt).iterator().numRemaining() * getPhase(pt);
        phase += board.black.getBoard(pt).iterator().numRemaining() * getPhase(pt);
    }
    return phase;
}

fn eval(comptime turn: lib.Side, board: Board) i16 {
    var mg: i16 = 0;
    var eg: i16 = 0;
    var phase: i16 = 0;
    inline for (PieceType.all) |pt| {
        var iter = board.white.getBoard(pt).iterator();
        phase += iter.numRemaining() * getPhase(pt);
        while (iter.next()) |b| {
            mg += evalPieceMg(.white, Piece.init(pt, b));
            eg += evalPieceEg(.white, Piece.init(pt, b));
        }
        iter = board.black.getBoard(pt).iterator();
        phase += iter.numRemaining() * getPhase(pt);
        while (iter.next()) |b| {
            mg -= evalPieceMg(.black, Piece.init(pt, b));
            eg -= evalPieceEg(.black, Piece.init(pt, b));
        }
    }
    if (turn == .black) {
        mg = -mg;
        eg = -eg;
    }
    const mg_phase = @min(phase, 24);
    const eg_phase = 24 - mg_phase;
    return @intCast(@divTrunc(mg_phase * @as(i32, mg) + eg_phase * eg, 24));
}

fn mvvlvaValue(x: Move) i16 {
    const PieceValues = [_]i16{
        100, // pawn
        320, // knight
        330, // bishop
        500, // rook
        900, // queen
        10_000, // king
    };
    if (!x.isCapture()) return 0;
    return PieceValues[@intFromEnum(x.captured().?.getType())] - PieceValues[@intFromEnum(x.to().getType())];
}

fn mvvlvaCompare(_: void, lhs: Move, rhs: Move) bool {
    return mvvlvaValue(lhs) > mvvlvaValue(rhs);
}

const MoveDelta = struct {
    mg: i16,
    eg: i16,
    phase: i16,
};

fn getMoveDelta(comptime turn: lib.Side, move: Move) MoveDelta {
    var d_mg = evalPieceMg(turn, move.to()) - evalPieceMg(turn, move.from());
    var d_eg = evalPieceEg(turn, move.to()) - evalPieceEg(turn, move.from());
    var d_phase: i16 = getPhase(move.to().getType()) - getPhase(move.from().getType());
    if (move.captured()) |cap| {
        d_mg += evalPieceMg(turn.flipped(), cap);
        d_eg += evalPieceEg(turn.flipped(), cap);
        d_phase -= getPhase(cap.getType());
    }
    if (move.isCastlingMove()) {
        const rm = move.getCastlingRookMove();
        d_mg += evalPieceMg(turn, rm.to()) - evalPieceMg(turn, rm.from());
        d_eg += evalPieceEg(turn, rm.to()) - evalPieceEg(turn, rm.from());
    }
    return .{
        .mg = d_mg,
        .eg = d_eg,
        .phase = d_phase,
    };
}

fn search(comptime turn: lib.Side, board: *Board, current_depth: u8, depth_remaining: u8, phase: i16, mg: i16, eg: i16, alpha_: i16, beta: i16, move_buf: []Move, hash_history: *std.ArrayList(u64)) i16 {
    nodes_searched += 1;
    var alpha = alpha_;
    if (timer.read() >= die_time) {
        shutdown = true;
        return 0;
    }
    if (shutdown) return 0;

    if (std.debug.runtime_safety and
        (phase != getPhaseBoard(board.*) or
        mg != evalWithoutGameOverMg(turn, board.*) or
        eg != evalWithoutGameOverEg(turn, board.*)))
    {
        log_writer.print("board: {s}\n", .{board.toFen().slice()}) catch {};
        err = true;
        shutdown = true;
        return 0;
    }

    if (board.gameOver()) |gr| {
        return if (gr == .tie) 0 else -CHECKMATE_EVAL + current_depth;
    }
    var num_repeats: u8 = 0;
    for (0..board.halfmove_clock) |i| {
        if (hash_history.items[hash_history.items.len - 1 - i] == board.zobrist) {
            num_repeats += 1;
        }
    }
    if (num_repeats >= 3) {
        return 0;
    }
    if (depth_remaining == 0) {
        const mg_phase: i32 = @min(24, phase);
        const eg_phase: i32 = 24 - mg_phase;
        const static_eval = @divTrunc(mg_phase * mg + eg_phase * eg, 24);
        return @intCast(static_eval);
    }

    const num_moves = board.getAllMovesUnchecked(move_buf, board.getSelfCheckSquares());
    const moves = move_buf[0..num_moves];
    std.sort.pdq(Move, moves, void{}, mvvlvaCompare);
    for (moves) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);
            hash_history.appendAssumeCapacity(board.zobrist);
            defer _ = hash_history.pop();
            const delta = getMoveDelta(turn, move);
            const cur = -search(
                turn.flipped(),
                board,
                current_depth + 1,
                depth_remaining - 1,
                phase + delta.phase,
                -(mg + delta.mg),
                -(eg + delta.eg),
                -beta,
                -alpha,
                move_buf[num_moves..],
                hash_history,
            );
            if (err) {
                log_writer.print("move: {}\n", .{move}) catch {};
            }
            if (shutdown) return 0;

            if (cur > alpha)
                alpha = cur;
            if (cur >= beta)
                break;
        }
    }
    return alpha;
}

pub fn doSearch(board: *Board, depth: u8, move_buf: []Move, hash_history: *std.ArrayList(u64)) i16 {
    return switch (board.turn) {
        inline else => |t| search(
            t,
            board,
            1,
            depth,
            getPhaseBoard(board.*),
            evalWithoutGameOverMg(t, board.*),
            evalWithoutGameOverEg(t, board.*),
            -CHECKMATE_EVAL,
            CHECKMATE_EVAL,
            move_buf,
            hash_history,
        ),
    };
}

var err = false;
var nodes_searched: u64 = 0;
var max_nodes: u64 = std.math.maxInt(u64);
var max_depth: u8 = 255;
var timer: std.time.Timer = undefined;
var die_time: u64 = std.math.maxInt(u64);
var shutdown = false;
// var tt_hits: usize = 0;

pub const MoveInfo = struct {
    eval: i16,
    move: Move,
    depth_evaluated: usize,
    nodes_evaluated: u64,
    is_mate: bool = false,
    time_used: u64,
};

// const TTentry = struct {
//     zobrist: u64 = 0,
//     bestmove: Move = std.mem.zeroes(Move),
//     const null_entry: TTentry = .{};
// };

// const tt_size = 1 << 20;
// var tt: [tt_size]TTentry = .{TTentry.null_entry} ** tt_size;

// fn getTTIndex(hash: u64) usize {
//     return (((hash & std.math.maxInt(u32)) ^ (hash >> 32)) * tt_size) >> 32;
// }

fn resetSoft() void {
    nodes_searched = 0;
    shutdown = false;
    // tt_hits = 0;
}

pub fn reset() void {
    resetSoft();
    // @memset(&tt, TTentry.null_entry);
}

var rand = std.Random.DefaultPrng.init(0);
pub fn findMove(board: Board, move_buf: []Move, depth: u8, nodes: usize, soft_time: u64, hard_time: u64, hash_history: *std.ArrayList(u64)) MoveInfo {
    max_nodes = nodes;
    timer = std.time.Timer.start() catch unreachable;
    die_time = timer.read() + hard_time;
    resetSoft();

    const num_moves = board.getAllMoves(move_buf, board.getSelfCheckSquares());
    const moves = move_buf[0..num_moves];
    var best_move = moves[0];
    var best_eval = -CHECKMATE_EVAL;
    var self = board;
    var depth_try: u8 = 1;
    var depth_evaluated: u8 = 0;
    while (depth_try <= depth and timer.read() <= soft_time) : (depth_try += 1) {
        var best_move_iter = moves[0];
        var best_eval_iter = -CHECKMATE_EVAL;

        for (moves) |move| {
            const inv = self.playMove(move);
            defer self.undoMove(inv);

            hash_history.appendAssumeCapacity(self.zobrist);
            defer _ = hash_history.pop();

            const cur = -doSearch(&self, depth_try, move_buf[num_moves..], hash_history);

            if (err) {
                log_writer.print("move: {}\n", .{move}) catch {};
            }
            if (shutdown) break;
            if (cur > best_eval_iter) {
                best_eval_iter = cur;
                best_move_iter = move;
            }
        }
        if (!shutdown) {
            depth_evaluated = depth_try;
            best_eval = best_eval_iter;
            best_move = best_move_iter;
        }
    }

    var res = MoveInfo{
        .eval = best_eval,
        .move = best_move,
        .depth_evaluated = depth_evaluated,
        .is_mate = false,
        .nodes_evaluated = nodes_searched,
        .time_used = timer.read() / std.time.ns_per_ms,
    };
    if (@abs(best_eval) >= CHECKMATE_EVAL - max_depth) {
        res.is_mate = true;
        if (best_eval > 0) {
            res.eval = CHECKMATE_EVAL - best_eval;
        } else {
            res.eval = best_eval - CHECKMATE_EVAL;
        }
    }
    return res;
}

test "starting position even material" {
    try testing.expectEqual(0, eval(.white, Board.init()));
}
