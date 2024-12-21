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

const PestoEval = struct {
    const mg_value: [6]i16 = .{ 82, 337, 365, 477, 1025, 10_000 };
    const eg_value: [6]i16 = .{ 94, 281, 297, 512, 936, 10_000 };

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

inline fn evalPieceMg(piece_side: lib.Side, piece: Piece) i16 {
    const tp = piece.getType();
    const p: usize = @intFromEnum(tp);
    return PestoEval.mg_table[2 * p + @intFromBool(piece_side == .black)][piece.getLoc()];
}

inline fn evalPieceEg(piece_side: lib.Side, piece: Piece) i16 {
    const tp = piece.getType();
    const p: usize = @intFromEnum(tp);
    return PestoEval.eg_table[2 * p + @intFromBool(piece_side == .black)][piece.getLoc()];
}

fn evalWithoutGameOverMg(turn: lib.Side, board: Board) i16 {
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

fn historyCompare(_: void, lhs: Move, rhs: Move) bool {
    const mult: i64 = 1 << 48;
    return mvvlvaValue(lhs) * mult + readHistory(lhs) > mvvlvaValue(rhs) * mult + readHistory(rhs);
}

const CompareContext = struct {
    turn: lib.Side,
    tt_move: Move,
};

fn moveCompare(ctx: CompareContext, lhs: Move, rhs: Move) bool {
    if (lhs.eql(ctx.tt_move)) return true;
    if (rhs.eql(ctx.tt_move)) return false;
    var le: i32 = mvvlvaValue(lhs);
    var re: i32 = mvvlvaValue(rhs);
    if (le != re) return le > re;
    le = readHistory(lhs);
    re = readHistory(rhs);
    if (le != re) return le > re;
    le = evalPieceMg(ctx.turn, lhs.to());
    re = evalPieceMg(ctx.turn, rhs.to());
    return le > re;
}

inline fn historyEntry(move: Move) *i32 {
    return &history[@intFromEnum(move.to().getType())][move.to().getLoc()];
}

inline fn readHistory(move: Move) i32 {
    return historyEntry(move).*;
}

inline fn updateHistory(move: Move, bonus: i32) void {
    const clamped = std.math.clamp(bonus, -MAX_HISTORY, MAX_HISTORY);
    const entry = historyEntry(move);

    entry.* += clamped - @divTrunc(clamped * entry.*, MAX_HISTORY);
}

fn evaluate(board: Board) i16 {
    return EvalState.init(board).static();
}

fn mvvlvaValue(x: Move) i8 {
    @setRuntimeSafety(false);
    const is_cap: i8 = @intFromBool(x.isCapture());
    const attacker: i8 = @intFromEnum(x.to().getType());
    const victim: i8 = @intFromEnum(x._captured.getType());
    return (8 * victim - attacker) & -is_cap; // analog hors
}

fn mvvlvaCompare(_: void, lhs: Move, rhs: Move) bool {
    return mvvlvaValue(lhs) > mvvlvaValue(rhs);
}

const EvalState = struct {
    mg: i16,
    eg: i16,
    phase: i16,

    fn add(self: EvalState, other: EvalState) EvalState {
        return .{
            .mg = self.mg + other.mg,
            .eg = self.eg + other.eg,
            .phase = self.phase + other.phase,
        };
    }

    fn flipped(self: EvalState) EvalState {
        return .{
            .mg = -self.mg,
            .eg = -self.eg,
            .phase = self.phase,
        };
    }

    fn static(self: EvalState) i16 {
        const mg_phase: i32 = @min(24, self.phase);
        const eg_phase: i32 = 24 - mg_phase;
        return @intCast(@divTrunc(mg_phase * self.mg + eg_phase * self.eg, 24));
    }

    fn init(board: Board) EvalState {
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
        if (board.turn == .black) {
            mg = -mg;
            eg = -eg;
        }
        return EvalState{
            .mg = mg,
            .eg = eg,
            .phase = phase,
        };
    }
};

fn getMoveDelta(turn: lib.Side, move: Move) EvalState {
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

fn quiesce(comptime turn: lib.Side, board: *Board, current_depth: u8, eval_state: EvalState, alpha_: i16, beta: i16, move_buf: []Move) i16 {
    nodes_searched += 1;
    if (nodes_searched % 1024 == 0 and (nodes_searched >= max_nodes or timer.read() >= die_time)) {
        shutdown = true;
        return 0;
    }

    const static_eval = eval_state.static();
    var alpha = alpha_;
    if (static_eval >= beta) {
        return beta;
    }
    if (static_eval > alpha)
        alpha = static_eval;

    const num_moves = board.getAllCapturesUnchecked(move_buf, board.getSelfCheckSquares());
    const moves = move_buf[0..num_moves];
    std.sort.pdq(Move, moves, void{}, mvvlvaCompare);
    for (moves) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);
            const delta = getMoveDelta(turn, move);
            const score = -quiesce(
                turn.flipped(),
                board,
                current_depth + 1,
                eval_state.add(delta).flipped(),
                -beta,
                -alpha,
                move_buf[num_moves..],
            );

            if (shutdown) return 0;

            if (score > alpha)
                alpha = score;
            if (score >= beta)
                break;
        }
    }
    return alpha;
}

fn search(comptime turn: lib.Side, comptime is_pv: bool, board: *Board, current_depth: u8, depth_remaining: u8, eval_state: EvalState, alpha_: i16, beta_: i16, move_buf: []Move, hash_history: *std.ArrayList(u64)) i16 {
    if (depth_remaining == 0 or current_depth == max_depth) {
        return quiesce(turn, board, current_depth, eval_state, alpha_, beta_, move_buf);
    }

    nodes_searched += 1;
    var alpha = alpha_;
    var beta = beta_;
    _ = &alpha;
    _ = &beta;
    if (nodes_searched % 1024 == 0 and (nodes_searched >= max_nodes or timer.read() >= die_time)) {
        shutdown = true;
        return 0;
    }
    if (shutdown) return 0;

    {
        var num_repeats: u8 = 0;
        for (0..@min(hash_history.items.len, board.halfmove_clock)) |i| {
            if (hash_history.items[hash_history.items.len - 1 - i] == board.zobrist) {
                num_repeats += 1;
            }
        }
        if (num_repeats >= 3) {
            return 0;
        }
    }

    var tt_move = std.mem.zeroes(Move);
    const entry = tt[getTTIndex(board.zobrist)];
    if (entry.zobrist == board.zobrist) {
        tt_move = board.decompressMove(entry.move);
    }

    const num_moves = board.getAllMovesUnchecked(move_buf, board.getSelfCheckSquares());
    std.sort.pdq(Move, move_buf[0..num_moves], CompareContext{ .turn = turn, .tt_move = tt_move }, moveCompare);
    var best_score = -CHECKMATE_EVAL;
    var score_type: ScoreType = .uninitialized;
    var best_move = move_buf[0];
    var num_legal_moves: u8 = 0;
    for (move_buf[0..num_moves]) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            num_legal_moves += 1;
            defer board.undoMove(inv);
            hash_history.appendAssumeCapacity(board.zobrist);
            defer _ = hash_history.pop();
            const delta = getMoveDelta(turn, move);
            const extension: u8 = @intFromBool(board.isInCheck(.auto));

            const score = -search(
                turn.flipped(),
                is_pv,
                board,
                current_depth + 1,
                depth_remaining - 1 + extension,
                eval_state.add(delta).flipped(),
                -beta,
                -alpha,
                move_buf[num_moves..],
                hash_history,
            );
            if (shutdown) break;

            if (score > best_score) {
                best_score = score;
                best_move = move;
            }

            if (score > alpha) {
                if (score >= beta) {
                    score_type = .upper;
                    break;
                }
                score_type = .exact;
                alpha = score;
            }
        }
    }

    if (num_legal_moves == 0 and !shutdown) {
        return if (board.isInCheck(.auto)) -CHECKMATE_EVAL + current_depth else 0;
    }

    if (num_legal_moves >= 2 or !shutdown) {
        tt[getTTIndex(board.zobrist)] = TTentry{
            .zobrist = board.zobrist,
            .score = best_score,
            .move = board.compressMove(best_move),
            .score_type = .exact,
        };
    }

    return best_score;
}

fn convertScore(score: i16) struct { bool, i16 } {
    if (@abs(score) >= CHECKMATE_EVAL - 255) {
        const res = if (score > 0)
            @divTrunc(CHECKMATE_EVAL - score + 1, 2)
        else
            -@divTrunc(CHECKMATE_EVAL + score + 1, 2);
        return .{ true, res };
    } else {
        return .{ false, score };
    }
}

pub const SearchInfo = struct {
    best_score: i16,
    best_move: Move,
    depth_searched: u8,
    nodes_searched: u64,
    time_used: u64,
    is_mate: bool = false,

    fn init(best_score: i16, best_move: Move, depth_searched: u8, nodes: u64, ns_elapsed: u64) SearchInfo {
        var res = SearchInfo{
            .best_score = best_score,
            .best_move = best_move,
            .depth_searched = depth_searched,
            .is_mate = false,
            .nodes_searched = nodes,
            .time_used = ns_elapsed,
        };
        res.is_mate, res.best_score = convertScore(best_score);
        return res;
    }

    pub fn format(self: SearchInfo, comptime actual_fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = actual_fmt;
        _ = options;
        var buf: [256]u8 = undefined;
        var bytes_written: usize = 0;
        bytes_written += (try std.fmt.bufPrint(buf[bytes_written..], "info depth {} score ", .{self.depth_searched})).len;
        if (self.is_mate) {
            bytes_written += (try std.fmt.bufPrint(buf[bytes_written..], "mate {} ", .{self.best_score})).len;
        } else {
            bytes_written += (try std.fmt.bufPrint(buf[bytes_written..], "cp {} ", .{self.best_score})).len;
        }
        bytes_written += (try std.fmt.bufPrint(buf[bytes_written..], "time {} nodes {} nps {} pv {s}", .{
            self.time_used / std.time.ns_per_ms,
            self.nodes_searched,
            self.nodes_searched * std.time.ns_per_s / self.time_used,
            self.best_move.pretty().slice(),
        })).len;
        try writer.writeAll(buf[0..bytes_written]);
    }
};

fn searchWithoutTurn(comptime is_pv: bool, board: *Board, current_depth: u8, depth_remaining: u8, eval_state: EvalState, alpha_: i16, beta: i16, move_buf: []Move, hash_history: *std.ArrayList(u64)) i16 {
    return switch (board.turn) {
        inline else => |t| search(t, is_pv, board, current_depth, depth_remaining, eval_state, alpha_, beta, move_buf, hash_history),
    };
}

var err: bool = false;
var nodes_searched: u64 = 0;
var max_nodes: u64 = std.math.maxInt(u64);
var max_depth: u8 = 255;
var timer: std.time.Timer = undefined;
var die_time: u64 = std.math.maxInt(u64);
var shutdown: bool = false;
var tt_hits: usize = 0;
var tt_misses: usize = 0;
var tt_size: usize = 0;
var tt: []TTentry = &.{};
var history: [PieceType.all.len][64]i32 = .{.{0} ** 64} ** PieceType.all.len;
const MAX_HISTORY: i16 = 1 << 14;

const Self = @This();

const ScoreType = enum(u8) {
    uninitialized,
    lower,
    exact,
    upper,
};

const TTentry = struct {
    zobrist: u64 = 0,
    move: u16 = 0,
    score: i16 = 0,
    score_type: ScoreType = .uninitialized,
    depth: u8 = 0,
    const null_entry: TTentry = .{};
};

fn getTTIndex(hash: u64) usize {
    return (((hash & std.math.maxInt(u32)) ^ (hash >> 32)) * tt_size) >> 32;
}

fn resetSoft() void {
    nodes_searched = 0;
    shutdown = false;
    max_depth = 255;
    max_nodes = std.math.maxInt(u64);
    tt_hits = 0;
    tt_misses = 0;
}

pub fn setTTSize(megabytes: usize) !void {
    tt_size = (megabytes << 20) / @sizeOf(TTentry);
    tt = try std.heap.page_allocator.realloc(tt, tt_size);
}

pub fn init() void {
    reset();
}

pub fn reset() void {
    resetSoft();
    setTTSize(256) catch @panic("OOM");
    @memset(tt[0..tt_size], TTentry.null_entry);
    @memset(std.mem.asBytes(&history), 0);
}

const MoveScorePair = struct {
    move: Move,
    score: i16,

    fn orderByScore(_: void, lhs: @This(), rhs: @This()) bool {
        return lhs.score > rhs.score;
    }
};

pub fn findMove(board: Board, move_buf: []Move, depth: u8, nodes: u64, soft_time: u64, hard_time: u64, hash_history: *std.ArrayList(u64), disable_info: bool) SearchInfo {
    resetSoft();
    max_nodes = nodes;
    max_depth = depth;
    timer = std.time.Timer.start() catch unreachable;
    die_time = hard_time;

    var self = board;

    var best_move = std.mem.zeroes(Move);
    var best_score: i16 = 0;

    var depth_try: u8 = 1;
    var depth_searched: u8 = 0;
    const eval_state = EvalState.init(board);
    while (depth_try < depth and (timer.read() <= soft_time)) : (depth_try += 1) {
        _ = searchWithoutTurn(true, &self, 0, depth_try, eval_state, -CHECKMATE_EVAL, CHECKMATE_EVAL, move_buf, hash_history);
        const tt_entry = tt[getTTIndex(board.zobrist)];
        if (tt_entry.zobrist == board.zobrist) {
            depth_searched = depth_try;
            best_score = tt_entry.score;
            best_move = board.decompressMove(tt_entry.move);
            const info = SearchInfo.init(best_score, best_move, depth_searched, nodes_searched, timer.read());
            if (!disable_info)
                write("{}\n", .{info});
            if (shutdown) break;
            if (info.is_mate) break;
        }
    }

    return SearchInfo.init(best_score, best_move, depth_searched, nodes_searched, timer.read());
}

test "starting position even material" {
    try testing.expectEqual(0, evaluate(Board.init()));
}
