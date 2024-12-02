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
    const mg_value: [6]i32 = .{ 82, 337, 365, 477, 1025, 0 };
    const eg_value: [6]i32 = .{ 94, 281, 297, 512, 936, 0 };

    const mg_pawn_table: [64]i32 = .{
        0,   0,   0,   0,   0,   0,   0,  0,
        98,  134, 61,  95,  68,  126, 34, -11,
        -6,  7,   26,  31,  65,  56,  25, -20,
        -14, 13,  6,   21,  23,  12,  17, -23,
        -27, -2,  -5,  12,  17,  6,   10, -25,
        -26, -4,  -4,  -10, 3,   3,   33, -12,
        -35, -1,  -20, -23, -15, 24,  38, -22,
        0,   0,   0,   0,   0,   0,   0,  0,
    };

    const eg_pawn_table: [64]i32 = .{
        0,   0,   0,   0,   0,   0,   0,   0,
        178, 173, 158, 134, 147, 132, 165, 187,
        94,  100, 85,  67,  56,  53,  82,  84,
        32,  24,  13,  5,   -2,  4,   17,  17,
        13,  9,   -3,  -7,  -7,  -8,  3,   -1,
        4,   7,   -6,  1,   0,   -5,  -1,  -8,
        13,  8,   8,   10,  13,  0,   2,   -7,
        0,   0,   0,   0,   0,   0,   0,   0,
    };

    const mg_knight_table: [64]i32 = .{
        -167, -89, -34, -49, 61,  -97, -15, -107,
        -73,  -41, 72,  36,  23,  62,  7,   -17,
        -47,  60,  37,  65,  84,  129, 73,  44,
        -9,   17,  19,  53,  37,  69,  18,  22,
        -13,  4,   16,  13,  28,  19,  21,  -8,
        -23,  -9,  12,  10,  19,  17,  25,  -16,
        -29,  -53, -12, -3,  -1,  18,  -14, -19,
        -105, -21, -58, -33, -17, -28, -19, -23,
    };

    const eg_knight_table: [64]i32 = .{
        -58, -38, -13, -28, -31, -27, -63, -99,
        -25, -8,  -25, -2,  -9,  -25, -24, -52,
        -24, -20, 10,  9,   -1,  -9,  -19, -41,
        -17, 3,   22,  22,  22,  11,  8,   -18,
        -18, -6,  16,  25,  16,  17,  4,   -18,
        -23, -3,  -1,  15,  10,  -3,  -20, -22,
        -42, -20, -10, -5,  -2,  -20, -23, -44,
        -29, -51, -23, -15, -22, -18, -50, -64,
    };

    const mg_bishop_table: [64]i32 = .{
        -29, 4,  -82, -37, -25, -42, 7,   -8,
        -26, 16, -18, -13, 30,  59,  18,  -47,
        -16, 37, 43,  40,  35,  50,  37,  -2,
        -4,  5,  19,  50,  37,  37,  7,   -2,
        -6,  13, 13,  26,  34,  12,  10,  4,
        0,   15, 15,  15,  14,  27,  18,  10,
        4,   15, 16,  0,   7,   21,  33,  1,
        -33, -3, -14, -21, -13, -12, -39, -21,
    };

    const eg_bishop_table: [64]i32 = .{
        -14, -21, -11, -8,  -7, -9,  -17, -24,
        -8,  -4,  7,   -12, -3, -13, -4,  -14,
        2,   -8,  0,   -1,  -2, 6,   0,   4,
        -3,  9,   12,  9,   14, 10,  3,   2,
        -6,  3,   13,  19,  7,  10,  -3,  -9,
        -12, -3,  8,   10,  13, 3,   -7,  -15,
        -14, -18, -7,  -1,  4,  -9,  -15, -27,
        -23, -9,  -23, -5,  -9, -16, -5,  -17,
    };

    const mg_rook_table: [64]i32 = .{
        32,  42,  32,  51,  63, 9,  31,  43,
        27,  32,  58,  62,  80, 67, 26,  44,
        -5,  19,  26,  36,  17, 45, 61,  16,
        -24, -11, 7,   26,  24, 35, -8,  -20,
        -36, -26, -12, -1,  9,  -7, 6,   -23,
        -45, -25, -16, -17, 3,  0,  -5,  -33,
        -44, -16, -20, -9,  -1, 11, -6,  -71,
        -19, -13, 1,   17,  16, 7,  -37, -26,
    };

    const eg_rook_table: [64]i32 = .{
        13, 10, 18, 15, 12, 12,  8,   5,
        11, 13, 13, 11, -3, 3,   8,   3,
        7,  7,  7,  5,  4,  -3,  -5,  -3,
        4,  3,  13, 1,  2,  1,   -1,  2,
        3,  5,  8,  4,  -5, -6,  -8,  -11,
        -4, 0,  -5, -1, -7, -12, -8,  -16,
        -6, -6, 0,  2,  -9, -9,  -11, -3,
        -9, 2,  3,  -1, -5, -13, 4,   -20,
    };

    const mg_queen_table: [64]i32 = .{
        -28, 0,   29,  12,  59,  44,  43,  45,
        -24, -39, -5,  1,   -16, 57,  28,  54,
        -13, -17, 7,   8,   29,  56,  47,  57,
        -27, -27, -16, -16, -1,  17,  -2,  1,
        -9,  -26, -9,  -10, -2,  -4,  3,   -3,
        -14, 2,   -11, -2,  -5,  2,   14,  5,
        -35, -8,  11,  2,   8,   15,  -3,  1,
        -1,  -18, -9,  10,  -15, -25, -31, -50,
    };

    const eg_queen_table: [64]i32 = .{
        -9,  22,  22,  27,  27,  19,  10,  20,
        -17, 20,  32,  41,  58,  25,  30,  0,
        -20, 6,   9,   49,  47,  35,  19,  9,
        3,   22,  24,  45,  57,  40,  57,  36,
        -18, 28,  19,  47,  31,  34,  39,  23,
        -16, -27, 15,  6,   9,   17,  10,  5,
        -22, -23, -30, -16, -16, -23, -36, -32,
        -33, -28, -22, -43, -5,  -32, -20, -41,
    };

    const mg_king_table: [64]i32 = .{
        -65, 23,  16,  -15, -56, -34, 2,   13,
        29,  -1,  -20, -7,  -8,  -4,  -38, -29,
        -9,  24,  2,   -16, -20, 6,   22,  -22,
        -17, -20, -12, -27, -30, -25, -14, -36,
        -49, -1,  -27, -39, -46, -44, -33, -51,
        -14, -14, -22, -46, -44, -30, -15, -27,
        1,   7,   -8,  -64, -43, -16, 9,   8,
        -15, 36,  12,  -54, 8,   -28, 24,  14,
    };

    const eg_king_table: [64]i32 = .{
        -74, -35, -18, -18, -11, 15,  4,   -17,
        -12, 17,  14,  17,  17,  38,  23,  11,
        10,  17,  23,  15,  20,  45,  44,  13,
        -8,  22,  24,  27,  26,  33,  26,  3,
        -18, -4,  21,  24,  27,  23,  9,   -11,
        -19, -3,  11,  21,  23,  16,  7,   -9,
        -27, -11, 4,   13,  14,  4,   -5,  -17,
        -53, -34, -21, -11, -28, -14, -24, -43,
    };

    const mg_pesto_table: [6][64]i32 = .{
        mg_pawn_table,
        mg_knight_table,
        mg_bishop_table,
        mg_rook_table,
        mg_queen_table,
        mg_king_table,
    };

    const eg_pesto_table: [6][64]i32 = .{
        eg_pawn_table,
        eg_knight_table,
        eg_bishop_table,
        eg_rook_table,
        eg_queen_table,
        eg_king_table,
    };

    const gamephaseInc: [6]i32 = .{ 0, 1, 1, 2, 4, 0 };
    const mg_table = blk: {
        var res: [12][64]i32 = undefined;
        for (PieceType.all) |pt| {
            const p: usize = @intFromEnum(pt);
            for (0..64) |sq| {
                res[2 * p + 0][sq] = mg_value[p] + mg_pesto_table[p][sq] / 4;
                res[2 * p + 1][sq] = mg_value[p] + mg_pesto_table[p][sq ^ 56] / 4;
            }
        }
        break :blk res;
    };
    const eg_table = blk: {
        var res: [12][64]i32 = undefined;
        for (PieceType.all) |pt| {
            const p: usize = @intFromEnum(pt);
            for (0..64) |sq| {
                res[2 * p + 0][sq] = eg_value[p] + eg_pesto_table[p][sq];
                res[2 * p + 1][sq] = eg_value[p] + eg_pesto_table[p][sq ^ 56];
            }
        }
        break :blk res;
    };

    fn eval(comptime turn: lib.Side, board: Board) i32 {
        if (board.gameOver()) |res| return switch (res) {
            .tie => 0,
            else => -CHECKMATE_EVAL,
        };

        var mg: i32 = 0;
        var eg: i32 = 0;
        var mg_phase: i32 = 0;
        for (PieceType.all) |pt| {
            const p: usize = @intFromEnum(pt);
            var iter = board.white.getBoard(pt).iterator();
            while (iter.next()) |b| {
                mg += mg_table[2 * p][b.toLoc()];
                eg += eg_table[2 * p][b.toLoc()];
                mg_phase += gamephaseInc[p];
            }
            iter = board.black.getBoard(pt).iterator();
            while (iter.next()) |b| {
                mg -= mg_table[2 * p + 1][b.toLoc()];
                eg -= eg_table[2 * p + 1][b.toLoc()];
                mg_phase += gamephaseInc[p];
            }
        }
        mg_phase = @min(mg_phase, 24);
        const eg_phase = 24 - mg_phase;
        const res = @divTrunc(mg_phase * mg + eg_phase * eg, 24);
        return if (turn == .white) res else -res;
    }
};

const CHECKMATE_EVAL = 1000_000_000;

fn evalPiece(comptime piece_side: lib.Side, piece: Piece) i32 {
    const tp = piece.getType();
    const p: usize = @intFromEnum(tp);
    return PestoEval.mg_table[2 * p + @intFromBool(piece_side == .black)][piece.getLoc()];
}

fn evalWithoutGameOver(comptime turn: lib.Side, board: Board) i32 {
    var res: i32 = 0;
    inline for (PieceType.all) |pt| {
        var iter = board.white.getBoard(pt).iterator();
        while (iter.next()) |b|
            res += evalPiece(.white, Piece.init(pt, b));
        iter = board.black.getBoard(pt).iterator();
        while (iter.next()) |b|
            res -= evalPiece(.black, Piece.init(pt, b));
    }
    if (turn == .black) res = -res;
    return res;
}

fn eval(comptime turn: lib.Side, board: Board) i32 {
    if (board.gameOver()) |gr| {
        return if (gr == .tie) 0 else -CHECKMATE_EVAL + @as(i32, @intCast(board.fullmove_clock));
    }
    return evalWithoutGameOver(turn, board);
}

fn mvvlvaValue(x: Move) i32 {
    const PieceValues = [_]i32{
        100, // pawn
        320, // knight
        330, // bishop
        500, // rook
        900, // queen
        100_000, // king
    };
    if (!x.isCapture()) return 0;
    return PieceValues[@intFromEnum(x.captured().?.getType())] - PieceValues[@intFromEnum(x.to().getType())];
}

fn mvvlvaCompare(_: void, lhs: Move, rhs: Move) bool {
    return mvvlvaValue(lhs) > mvvlvaValue(rhs);
}

fn quiesce(comptime turn: lib.Side, board: *Board, move_buf: []Move, static_eval: i32, alpha_: i32, beta: i32, hash_history: *std.ArrayList(u64)) i32 {
    if (std.debug.runtime_safety) search_depth += 1;
    defer {
        if (std.debug.runtime_safety) search_depth -= 1;
    }
    nodes_searched += 1;
    if (nodes_searched >= max_nodes)
        shutdown = true;
    if (nodes_searched % 128 == 0 and timer.read() >= die_time)
        shutdown = true;
    if (shutdown)
        return 0;

    const zobrist = board.zobrist;

    if (board.isFiftyMoveTie() or board.isTieByInsufficientMaterial())
        return 0;

    const num_query = @min(hash_history.items.len, board.halfmove_clock);
    var num_prev: u8 = 0;
    for (hash_history.items[hash_history.items.len - num_query ..]) |past_hash| {
        num_prev += @intFromBool(past_hash == zobrist);
    }

    // tie
    if (num_prev >= 3)
        return 0;

    if (std.debug.runtime_safety and nodes_searched % (1 << 20) == 0) {
        log_writer.print("q nodes {} depth {}\n", .{ nodes_searched, search_depth }) catch {};
    }

    if (std.debug.runtime_safety and static_eval != evalWithoutGameOver(turn, board.*)) {
        log_writer.print("q evalerror {} {} {s}\n", .{ static_eval, evalWithoutGameOver(turn, board.*), board.toFen().slice() }) catch {};
    }

    // if (static_eval != evalWithoutGameOver(turn, board.*)) {
    //     const log_file_path = "/home/jonathanhallstrom/dev/zig/pawnocchio/LOGFILE.pawnocchio_log";
    //     const log_file = std.fs.openFileAbsolute(log_file_path, .{ .mode = .write_only }) catch null;
    //     defer if (log_file) |log| log.close();

    //     if (log_file) |lf| {
    //         lf.writer().print("q evalerror {} {} {s}\n", .{ static_eval, evalWithoutGameOver(turn, board.*), board.toFen().slice() }) catch {};
    //     }
    // }

    var alpha = alpha_;
    if (static_eval >= beta)
        return beta;
    if (alpha < static_eval)
        alpha = static_eval;
    if (static_eval < -CHECKMATE_EVAL / 2)
        return static_eval;

    const tt_entry = &tt[getTTIndex(zobrist)];
    var tt_hit: usize = 0;
    if (tt_entry.zobrist == zobrist) {
        if (std.debug.runtime_safety)
            tt_hits += 1;
        tt_hit = 1;
        move_buf[0] = tt_entry.bestmove;
    }

    const num_moves = board.getAllCapturesUnchecked(move_buf[tt_hit..], board.getSelfCheckSquares());
    if (num_moves == 0) {
        return eval(turn, board.*);
    }
    const moves = move_buf[tt_hit..][0..num_moves];
    const rem_buf = move_buf[tt_hit..][num_moves..];
    std.sort.pdq(Move, moves, void{}, mvvlvaCompare);
    var num_valid_moves: usize = 0;

    var bestmove: Move = move_buf[0];
    for (move_buf[0 .. num_moves + tt_hit], 0..) |move, i| {
        if (i > 0 and std.meta.eql(move, move_buf[0])) continue;
        if (move.isCapture()) {
            if (board.playMovePossibleSelfCheck(move)) |inv| {
                num_valid_moves += 1;
                defer board.undoMove(inv);
                hash_history.appendAssumeCapacity(board.zobrist);
                defer _ = hash_history.pop();

                const d_static_eval = evalPiece(turn, move.to()) - evalPiece(turn, move.from()) + evalPiece(turn.flipped(), move.captured().?);
                const cur = -quiesce(
                    turn.flipped(),
                    board,
                    rem_buf,
                    -(static_eval + d_static_eval),
                    -beta,
                    -alpha,
                    hash_history,
                );
                if (shutdown)
                    return 0;
                if (cur > alpha) {
                    alpha = cur;
                    bestmove = move;
                }
                if (cur >= beta) break;
            }
        }
    }
    if (num_valid_moves == 0) {
        return eval(turn, board.*);
    }
    tt_entry.zobrist = zobrist;
    tt_entry.bestmove = bestmove;
    return alpha;
}

var zobrist_collisions: usize = 0;

fn search(comptime turn: lib.Side, board: *Board, depth_: u16, move_buf: []Move, static_eval: i32, alpha_: i32, beta: i32, hash_history: *std.ArrayList(u64)) i32 {
    if (std.debug.runtime_safety) search_depth += 1;
    defer {
        if (std.debug.runtime_safety) search_depth -= 1;
    }
    nodes_searched += 1;
    if (nodes_searched >= max_nodes)
        shutdown = true;
    if (nodes_searched % 128 == 0 and timer.read() >= die_time)
        shutdown = true;
    if (shutdown)
        return 0;
    const zobrist = board.zobrist;
    // board.resetZobrist();
    // if (zobrist != board.zobrist) {
    //     log_writer.print("zobrist broke {s}\n", .{board.toFen().slice()}) catch {};
    // }

    if (board.isFiftyMoveTie() or board.isTieByInsufficientMaterial())
        return 0;

    const num_query = @min(hash_history.items.len, board.halfmove_clock);
    var num_prev: u8 = 0;
    for (hash_history.items[hash_history.items.len - num_query ..]) |past_hash| {
        num_prev += @intFromBool(past_hash == zobrist);
    }

    // tie
    if (num_prev >= 3)
        return 0;
    if (std.debug.runtime_safety and nodes_searched % (1 << 20) == 0) {
        log_writer.print("n nodes {} depth {}\n", .{ nodes_searched, search_depth }) catch {};
    }
    if (std.debug.runtime_safety and static_eval != evalWithoutGameOver(turn, board.*)) {
        log_writer.print("n evalerror {} {} {s}\n", .{ static_eval, evalWithoutGameOver(turn, board.*), board.toFen().slice() }) catch {};
    }

    // if (static_eval != evalWithoutGameOver(turn, board.*)) {
    //     const log_file_path = "/home/jonathanhallstrom/dev/zig/pawnocchio/LOGFILE.pawnocchio_log";
    //     const log_file = std.fs.openFileAbsolute(log_file_path, .{ .mode = .write_only }) catch null;
    //     defer if (log_file) |log| log.close();

    //     if (log_file) |lf| {
    //         lf.writer().print("q evalerror {} {} {s}\n", .{ static_eval, evalWithoutGameOver(turn, board.*), board.toFen().slice() }) catch {};
    //     }
    // }
    var depth = depth_;
    _ = &depth;
    if (board.isInCheck(.auto)) depth += 1;

    var alpha = alpha_;

    const tt_entry = &tt[getTTIndex(zobrist)];
    var tt_hit: usize = 0;
    if (tt_entry.zobrist == zobrist) {
        if (std.debug.runtime_safety)
            tt_hits += 1;
        tt_hit = 1;
        move_buf[0] = tt_entry.bestmove;
    }

    if (depth == 0) {
        return quiesce(turn, board, move_buf, evalWithoutGameOver(turn, board.*), alpha, beta, hash_history);
        // return eval(turn, board.*);
    }
    const num_moves = board.getAllMovesUnchecked(move_buf[tt_hit..], board.getSelfCheckSquares());
    const moves = move_buf[tt_hit..][0..num_moves];
    const rem_buf = move_buf[tt_hit..][num_moves..];
    std.sort.pdq(Move, moves, void{}, mvvlvaCompare);
    var num_valid_moves: usize = 0;

    var bestmove: Move = move_buf[0];
    for (move_buf[0 .. num_moves + tt_hit], 0..) |move, i| {
        if (i > 0 and std.meta.eql(move, move_buf[0])) continue;
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);

            num_valid_moves += 1;
            hash_history.appendAssumeCapacity(board.zobrist);
            defer _ = hash_history.pop();

            var d_static_eval = evalPiece(turn, move.to()) - evalPiece(turn, move.from());
            if (move.captured()) |cap| {
                d_static_eval += evalPiece(turn.flipped(), cap);
            }
            if (move.isCastlingMove()) {
                const rm = move.getCastlingRookMove();
                d_static_eval += evalPiece(turn, rm.to()) - evalPiece(turn, rm.from());
            }
            var cur = -search(
                turn.flipped(),
                board,
                depth - 1,
                rem_buf,
                -(static_eval + d_static_eval),
                -(alpha + 1),
                -alpha,
                hash_history,
            );
            if (cur > alpha and cur < beta) {
                cur = -search(
                    turn.flipped(),
                    board,
                    depth - 1,
                    rem_buf,
                    -(static_eval + d_static_eval),
                    -beta,
                    -alpha,
                    hash_history,
                );
            }
            if (shutdown)
                return 0;
            if (cur > alpha) {
                bestmove = move;
                alpha = cur;
            }

            alpha = @max(alpha, cur);
            if (cur >= beta) {
                break;
            }
        }
    }
    if (num_valid_moves == 0) {
        return if (board.isInCheck(.auto)) -CHECKMATE_EVAL else 0;
    }

    tt_entry.bestmove = bestmove;
    tt_entry.zobrist = zobrist;

    return alpha;
}

pub fn negaMax(board: Board, depth: u16, move_buf: []Move, hash_history: *std.ArrayList(u64), alpha: i32, beta: i32) i32 {
    var self = board;
    return switch (self.turn) {
        inline else => |t| search(t, &self, depth, move_buf, evalWithoutGameOver(t, board), alpha, beta, hash_history),
    };
}

var search_depth: u16 = 0;
var max_depth_seen: u16 = 0;
var nodes_searched: u64 = 0;
var max_nodes: u64 = std.math.maxInt(u64);
var max_depth: u16 = 256;
var timer: std.time.Timer = undefined;
var die_time: u64 = std.math.maxInt(u64);
var shutdown = false;
var tt_hits: usize = 0;

pub const MoveInfo = struct {
    eval: i32,
    move: Move,
    depth_evaluated: usize,
    nodes_evaluated: u64,
};

const TTentry = struct {
    zobrist: u64 = 0,
    bestmove: Move = std.mem.zeroes(Move),
    const null_entry: TTentry = .{};
};

const tt_size = 1 << 20;
var tt: [tt_size]TTentry = .{TTentry.null_entry} ** tt_size;

fn getTTIndex(hash: u64) usize {
    return (((hash & std.math.maxInt(u32)) ^ (hash >> 32)) * tt_size) >> 32;
}

fn resetSoft() void {
    search_depth = 0;
    max_depth_seen = 0;
    nodes_searched = 0;
    shutdown = false;
    tt_hits = 0;
}

pub fn reset() void {
    resetSoft();
    @memset(&tt, TTentry.null_entry);
}

var rand = std.Random.DefaultPrng.init(0);
pub fn findMove(board: Board, move_buf: []Move, depth: u16, nodes: usize, soft_time: u64, hard_time: u64, hash_history: *std.ArrayList(u64)) MoveInfo {
    resetSoft();
    max_depth = depth;
    max_nodes = nodes;

    var self = board;
    const num_moves = board.getAllMoves(move_buf, board.getSelfCheckSquares());
    const moves = move_buf[0..num_moves];

    const MoveEvalPair = struct {
        move: Move,
        eval: i32,

        fn orderByEval(_: void, lhs: @This(), rhs: @This()) bool {
            return lhs.eval > rhs.eval;
        }
    };

    var move_eval_buf: [400]MoveEvalPair = undefined;
    for (0..num_moves) |i| {
        move_eval_buf[i] = .{ .move = moves[i], .eval = mvvlvaValue(moves[i]) };
    }

    var depth_to_try: u16 = 1;
    var actual_eval: i32 = 0;
    timer = std.time.Timer.start() catch unreachable;
    die_time = timer.read() + hard_time;

    rand.random().shuffle(MoveEvalPair, move_eval_buf[0..num_moves]);
    std.sort.pdq(MoveEvalPair, move_eval_buf[0..num_moves], void{}, MoveEvalPair.orderByEval);
    var alpha: i32 = move_eval_buf[0].eval;
    const beta = CHECKMATE_EVAL;
    var best_move: Move = move_eval_buf[0].move;

    while (timer.read() < soft_time and depth_to_try <= depth) {
        alpha = -CHECKMATE_EVAL;
        var new_best_move = best_move;
        for (move_eval_buf[0..num_moves]) |*entry| {
            const move = entry.move;

            hash_history.appendAssumeCapacity(self.zobrist);
            defer _ = hash_history.pop();

            if (self.playMovePossibleSelfCheck(move)) |inv| {
                defer self.undoMove(inv);

                entry.eval = -negaMax(self, depth_to_try, move_buf, hash_history, -beta, -alpha);
                if (entry.eval > alpha) {
                    alpha = entry.eval;
                    new_best_move = move;
                }
                if (shutdown) {
                    if (std.debug.runtime_safety) log_writer.print("shutdown after {}\n", .{std.fmt.fmtDuration(timer.read())}) catch {};
                    break;
                }
            }
        }
        if (std.debug.runtime_safety) log_writer.print("depth {} bestmove {s} tt_hits: {} zobrist_errors: {}\n", .{
            depth_to_try,
            new_best_move.pretty().slice(),
            tt_hits,
            zobrist_collisions,
        }) catch {};

        if (!shutdown) {
            best_move = new_best_move;
            actual_eval = alpha;
            const elapsed_ns = timer.read();
            write("info depth {} score {} nodes {} nps {d} time {} pv {s}\n", .{
                depth_to_try,
                alpha,
                nodes_searched,
                nodes_searched * std.time.ns_per_s / elapsed_ns,
                elapsed_ns / std.time.ns_per_ms,
                best_move.pretty().slice(),
            });
        }
        if (shutdown) break;

        depth_to_try += 1;
        std.sort.pdq(MoveEvalPair, move_eval_buf[0..num_moves], void{}, MoveEvalPair.orderByEval);
    }

    return MoveInfo{
        .depth_evaluated = depth_to_try,
        .eval = actual_eval,
        .move = best_move,
        .nodes_evaluated = nodes_searched,
    };
}

test "starting position even material" {
    try testing.expectEqual(0, eval(.white, Board.init()));
}
