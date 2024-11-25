const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const lib = @import("lib.zig");

const BitBoard = lib.BitBoard;
const Piece = lib.Piece;
const PieceType = lib.PieceType;
const Move = lib.Move;
const Board = lib.Board;

const PieceValues = [_]i32{
    100, // pawn
    320, // knight
    330, // bishop
    500, // rook
    900, // queen
    100_000, // king
};

const CHECKMATE_EVAL = 1000_000_000;

fn pawnEval(pawns: BitBoard, king: BitBoard) i32 {
    // // source? made it tf up
    // const pawn_values: [64]i32 = .{
    //     0,  0,  0,  0,  0,  0,  0,  0,
    //     30, 30, 30, 40, 40, 30, 30, 30,
    //     15, 20, 25, 30, 30, 25, 20, 15,
    //     10, 15, 25, 25, 25, 25, 15, 10,
    //     5,  10, 10, 10, 10, 10, 10, 5,
    //     5,  10, 10, 10, 10, 10, 10, 5,
    //     0,  0,  0,  0,  0,  0,  0,  0,
    //     0,  0,  0,  0,  0,  0,  0,  0,
    // };

    var res = @popCount(pawns.toInt()) * PieceValues[@intFromEnum(PieceType.pawn)];

    const first = BitBoard.fromSquareUnchecked("A3").allRight()
        .getCombination(BitBoard.fromSquareUnchecked("A5"))
        .getCombination(BitBoard.fromSquareUnchecked("A7"));
    res += @popCount(first.getOverlap(pawns).toInt()) * 5;

    const second = BitBoard.fromSquareUnchecked("A4").allRight()
        .getCombination(BitBoard.fromSquareUnchecked("A5"));
    res += @popCount(second.getOverlap(pawns).toInt()) * 10;

    const third = BitBoard.fromSquareUnchecked("A6").allRight()
        .getCombination(BitBoard.fromSquareUnchecked("A7"));
    res += @popCount(third.getOverlap(pawns).toInt()) * 20;

    const central = comptime blk: {
        var cent = BitBoard.fromSquareUnchecked("D3");
        cent.add(cent.right(1));
        break :blk cent.allForward();
    };
    res += @popCount(central.getOverlap(pawns).toInt()) * 5;

    const in_front_of_king = king.getCombination(king.left(1)).getCombination(king.right(1)).forwardMasked(1).getOverlap(BitBoard.fromSquareUnchecked("A2").allRight());
    res += @popCount(in_front_of_king.getOverlap(pawns).toInt()) * 10;

    return res;
}

fn getEdges(dist: comptime_int) BitBoard {
    var res = BitBoard.initEmpty().complement();
    res = res.getOverlap(res.forwardMasked(dist));
    res = res.getOverlap(res.backwardMasked(dist));
    res = res.getOverlap(res.leftMasked(dist));
    res = res.getOverlap(res.rightMasked(dist));
    return res;
}

fn knightEval(knights: BitBoard) i32 {
    var res = @popCount(knights.toInt()) * PieceValues[@intFromEnum(PieceType.knight)];

    // knights on the rim
    res -= @popCount(knights.getOverlap(getEdges(1).complement()).toInt()) * 10;

    // knights in the middle
    res += @popCount(knights.getOverlap(getEdges(2)).toInt()) * 10;

    return res;
}

fn eval(comptime turn: lib.Side, board: Board) i32 {
    if (board.gameOver()) |res| return switch (res) {
        .tie => 0,
        else => -CHECKMATE_EVAL + @as(i32, @intCast(search_depth)),
    };
    var res: i32 = 0;

    res += pawnEval(board.white.pawn, board.white.king);
    res -= pawnEval(board.black.pawn.flipped(), board.black.king.flipped());

    res += knightEval(board.white.knight);
    res -= knightEval(board.black.knight);

    res += @popCount(board.white.bishop.toInt()) * PieceValues[@intFromEnum(PieceType.bishop)];
    res -= @popCount(board.black.bishop.toInt()) * PieceValues[@intFromEnum(PieceType.bishop)];

    res += @popCount(board.white.rook.toInt()) * PieceValues[@intFromEnum(PieceType.rook)];
    res -= @popCount(board.black.rook.toInt()) * PieceValues[@intFromEnum(PieceType.rook)];

    res += @popCount(board.white.queen.toInt()) * PieceValues[@intFromEnum(PieceType.queen)];
    res -= @popCount(board.black.queen.toInt()) * PieceValues[@intFromEnum(PieceType.queen)];

    res = if (turn == .white) res else -res;
    if (board.isInCheck(Board.TurnMode.from(turn))) {
        res -= 25;
    }
    return res;
}

fn mvvlvaValue(x: Move) i32 {
    if (!x.isCapture()) return 0;
    return PieceValues[@intFromEnum(x.captured().?.getType())] - PieceValues[@intFromEnum(x.to().getType())];
}

fn mvvlvaCompare(_: void, lhs: Move, rhs: Move) bool {
    return mvvlvaValue(lhs) > mvvlvaValue(rhs);
}

fn quiesce(comptime turn: lib.Side, board: *Board, move_buf: []Move, alpha_: i32, beta: i32) i32 {
    if (shutdown)
        return 0;
    search_depth += 1;
    defer search_depth -= 1;
    nodes_searched += 1;

    const zobrist = board.zobrist;
    future_hashes[future_hash_count] = zobrist;
    future_hash_count += 1;
    defer future_hash_count -= 1;
    var num_prev: u8 = 0;
    for (past_hashes) |past| {
        num_prev += @intFromBool(past == zobrist);
    }
    for (future_hashes[0..future_hash_count]) |past| {
        num_prev += @intFromBool(past == zobrist);
    }

    // tie
    if (num_prev >= 3 or
        board.isFiftyMoveTie() or
        board.isTieByInsufficientMaterial())
        return 0;

    if (nodes_searched % (1 << 20) == 0) {
        @import("main.zig").log_writer.print("n nodes {} depth {}\n", .{ nodes_searched, search_depth }) catch {};
    }

    if (timer.read() >= die_time) {
        shutdown = true;
        return 0;
    }

    var alpha = alpha_;
    const static_eval = eval(turn, board.*);
    if (static_eval >= beta)
        return beta;
    if (alpha < static_eval)
        alpha = static_eval;

    const num_moves = board.getAllMovesUnchecked(move_buf, board.getSelfCheckSquares());
    if (num_moves == 0) {
        return eval(turn, board.*);
    }
    const moves = move_buf[0..num_moves];
    const rem_buf = move_buf[num_moves..];
    std.sort.pdq(Move, moves, void{}, mvvlvaCompare);
    for (moves) |move| {
        if (move.isCapture()) {
            if (board.playMovePossibleSelfCheck(move)) |inv| {
                defer board.undoMove(inv);

                const cur = -quiesce(
                    turn.flipped(),
                    board,
                    rem_buf,
                    -beta,
                    -alpha,
                );
                if (shutdown)
                    return 0;

                alpha = @max(alpha, cur);
                if (cur >= beta) break;
            }
        }
    }

    return alpha;
}

fn negaMaxImpl(comptime turn: lib.Side, board: *Board, depth: u16, move_buf: []Move, alpha_: i32, beta: i32) i32 {
    if (shutdown)
        return 0;
    search_depth += 1;
    defer search_depth -= 1;
    nodes_searched += 1;

    const zobrist = board.zobrist;
    // board.resetZobrist();
    // if (zobrist != board.zobrist) {
    //     @import("main.zig").log_writer.print("zobrist broke {s}\n", .{board.toFen().slice()}) catch {};
    // }

    future_hashes[future_hash_count] = zobrist;
    future_hash_count += 1;
    defer future_hash_count -= 1;
    var num_prev: u8 = 0;
    for (past_hashes) |past| {
        num_prev += @intFromBool(past == zobrist);
    }
    for (future_hashes[0..future_hash_count]) |past| {
        num_prev += @intFromBool(past == zobrist);
    }

    // tie
    if (num_prev >= 3 or
        board.isFiftyMoveTie() or
        board.isTieByInsufficientMaterial())
        return 0;

    if (nodes_searched % (1 << 20) == 0) {
        @import("main.zig").log_writer.print("n nodes {} depth {}\n", .{ nodes_searched, search_depth }) catch {};
    }

    const tt_entry = &tt[board.zobrist % tt.len];
    if (tt_entry.zobrist == board.zobrist and tt_entry.depth >= depth) {
        return tt_entry.eval;
    }

    if (timer.read() >= die_time) {
        shutdown = true;
        return 0;
    }

    var alpha = alpha_;
    if (depth == 0) {
        return quiesce(turn, board, move_buf, alpha, beta);
        // return eval(turn, board.*);
    }
    const num_moves = board.getAllMovesUnchecked(move_buf, board.getSelfCheckSquares());
    if (num_moves == 0) {
        return eval(turn, board.*);
    }
    const moves = move_buf[0..num_moves];
    const rem_buf = move_buf[num_moves..];
    std.sort.pdq(Move, moves, void{}, mvvlvaCompare);
    for (moves) |move| {
        if (board.playMovePossibleSelfCheck(move)) |inv| {
            defer board.undoMove(inv);

            const cur = -negaMaxImpl(
                turn.flipped(),
                board,
                depth - 1,
                rem_buf,
                -beta,
                -alpha,
            );
            if (shutdown)
                return 0;

            alpha = @max(alpha, cur);
            if (cur >= beta) break;
        }
    }

    tt_entry.* = TTentry{
        .depth = depth,
        .eval = alpha,
        .zobrist = zobrist,
    };
    return alpha;
}

pub fn negaMax(board: Board, depth: u16, move_buf: []Move) i32 {
    var self = board;
    return switch (self.turn) {
        inline else => |t| negaMaxImpl(t, &self, depth, move_buf, -CHECKMATE_EVAL, CHECKMATE_EVAL),
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

var past_hashes: [64]u64 = .{0} ** 64;
var past_hash_count: usize = 0;
var future_hashes: [256]u64 = .{0} ** 256;
var future_hash_count: usize = 0;

pub const MoveInfo = struct {
    eval: i32,
    move: Move,
    depth_evaluated: usize,
    nodes_evaluated: u64,
};

const TTentry = struct {
    zobrist: u64 = 0,
    eval: i32 = 0,
    depth: u16 = 0,
};

// 1000_003 is the next prime after 1000_000
var tt: [1000_003]TTentry = .{.{}} ** 1000_003;

fn resetSoft() void {
    search_depth = 0;
    max_depth_seen = 0;
    nodes_searched = 0;
    shutdown = false;
    @memset(&future_hashes, 0);
    future_hash_count = 0;
}

pub fn reset() void {
    resetSoft();
    @memset(&past_hashes, 0);
    @memset(&tt, .{});
    past_hash_count = 0;
}

var rand = std.Random.DefaultPrng.init(0);
pub fn findMove(board: Board, move_buf: []Move, depth: u16, nodes: usize, soft_time: u64, hard_time: u64) MoveInfo {
    resetSoft();
    max_depth = depth;
    max_nodes = nodes;
    const prev_idx = (past_hash_count + past_hashes.len - 1) % past_hashes.len;
    assert(past_hashes[prev_idx] != board.zobrist);
    past_hashes[past_hash_count] = board.zobrist;
    past_hash_count = (past_hash_count + 1) % past_hashes.len;

    var self = board;
    const num_moves = board.getAllMoves(move_buf, board.getSelfCheckSquares());
    const moves = move_buf[0..num_moves];
    var best_eval: i32 = -CHECKMATE_EVAL;
    var best_move: Move = moves[0];

    var depth_to_try: u16 = 1;
    timer = std.time.Timer.start() catch unreachable;
    die_time = timer.read() + hard_time;

    std.sort.pdq(Move, moves, void{}, mvvlvaCompare);
    rand.random().shuffle(Move, moves);
    while (timer.read() < soft_time and depth_to_try < depth) : (depth_to_try += 1) {
        best_eval = -CHECKMATE_EVAL;
        var new_best_move = best_move;
        for (moves) |move| {
            if (self.playMovePossibleSelfCheck(move)) |inv| {
                defer self.undoMove(inv);

                const cur_eval = -negaMax(self, depth_to_try, move_buf[num_moves..]);
                if (cur_eval > best_eval) {
                    best_eval = cur_eval;
                    new_best_move = move;
                }
                if (shutdown) {
                    @import("main.zig").log_writer.print("shutdown after {}\n", .{std.fmt.fmtDuration(timer.read())}) catch {};
                    break;
                }
            }
        }
        @import("main.zig").log_writer.print("depth {} bestmove {s}\n", .{ depth_to_try, new_best_move.pretty().slice() }) catch {};
        if (!shutdown) best_move = new_best_move;
    }

    return MoveInfo{
        .depth_evaluated = depth_to_try,
        .eval = best_eval,
        .move = best_move,
        .nodes_evaluated = nodes_searched,
    };
}

test "starting position even material" {
    try testing.expectEqual(0, eval(.white, Board.init()));
}
