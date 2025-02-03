const std = @import("std");
const Board = @import("Board.zig");
const Square = @import("square.zig").Square;
const PieceType = @import("piece_type.zig").PieceType;
const Bitboard = @import("Bitboard.zig");
const Side = @import("side.zig").Side;
const eval = @import("eval.zig");
const Move = @import("Move.zig").Move;

// dummy weights
const Weights = struct {
    hidden_layer_weights: [HIDDEN_SIZE * INPUT_SIZE]i16 align(64) = .{0} ** (HIDDEN_SIZE * INPUT_SIZE),
    hidden_layer_biases: [HIDDEN_SIZE]i16 align(64) = .{0} ** HIDDEN_SIZE,
    output_weights: [HIDDEN_SIZE * 2]i16 align(64) = .{0} ** (HIDDEN_SIZE * 2),
    output_bias: i16 align(64) = 0,
};

var weights: Weights = undefined;

pub const Accumulator = struct {
    white: [HIDDEN_SIZE]i16,
    black: [HIDDEN_SIZE]i16,

    fn idx(comptime perspective: Side, comptime side: Side, tp: PieceType, sq: Square) usize {
        const side_offs: usize = if (perspective == side) 0 else 1;
        const sq_offs: usize = if (perspective == .black) sq.flipRank().toInt() else sq.toInt();
        const tp_offs: usize = tp.toInt();
        return side_offs * 64 * 6 + tp_offs * 64 + sq_offs;
    }

    pub fn default() Accumulator {
        return .{
            .white = weights.hidden_layer_biases,
            .black = weights.hidden_layer_biases,
        };
    }

    pub fn init(board: *const Board) Accumulator {
        var acc = default();
        for (PieceType.all) |tp| {
            {
                var iter = Bitboard.iterator(board.white.getBoard(tp));
                while (iter.next()) |sq| {
                    acc.add(.white, tp, sq);
                }
            }
            {
                var iter = Bitboard.iterator(board.black.getBoard(tp));
                while (iter.next()) |sq| {
                    acc.add(.black, tp, sq);
                }
            }
        }
        return acc;
    }

    pub fn add(self: *Accumulator, comptime side: Side, tp: PieceType, sq: Square) void {
        const white_idx = idx(.white, side, tp, sq);
        const black_idx = idx(.black, side, tp, sq);
        for (0..HIDDEN_SIZE) |i| {
            self.white[i] += weights.hidden_layer_weights[white_idx * HIDDEN_SIZE + i];
        }
        for (0..HIDDEN_SIZE) |i| {
            self.black[i] += weights.hidden_layer_weights[black_idx * HIDDEN_SIZE + i];
        }
    }

    pub fn addSub(self: *Accumulator, comptime side: Side, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square) void {
        const add_white_idx = idx(.white, side, add_tp, add_sq);
        const add_black_idx = idx(.black, side, add_tp, add_sq);
        const sub_white_idx = idx(.white, side, sub_tp, sub_sq);
        const sub_black_idx = idx(.black, side, sub_tp, sub_sq);
        for (0..HIDDEN_SIZE) |i| {
            self.white[i] += weights.hidden_layer_weights[add_white_idx * HIDDEN_SIZE + i] - weights.hidden_layer_weights[sub_white_idx * HIDDEN_SIZE + i];
        }
        for (0..HIDDEN_SIZE) |i| {
            self.black[i] += weights.hidden_layer_weights[add_black_idx * HIDDEN_SIZE + i] - weights.hidden_layer_weights[sub_black_idx * HIDDEN_SIZE + i];
        }
    }

    pub fn addSubSub(self: *Accumulator, comptime side: Side, add_tp: PieceType, add_sq: Square, sub_tp: PieceType, sub_sq: Square, opp_sub_tp: PieceType, opp_sub_sq: Square) void {
        const add_white_idx = idx(.white, side, add_tp, add_sq);
        const add_black_idx = idx(.black, side, add_tp, add_sq);
        const sub_white_idx = idx(.white, side, sub_tp, sub_sq);
        const sub_black_idx = idx(.black, side, sub_tp, sub_sq);
        const opp_sub_white_idx = idx(.white, side.flipped(), opp_sub_tp, opp_sub_sq);
        const opp_sub_black_idx = idx(.black, side.flipped(), opp_sub_tp, opp_sub_sq);
        for (0..HIDDEN_SIZE) |i| {
            self.white[i] +=
                weights.hidden_layer_weights[add_white_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub_white_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[opp_sub_white_idx * HIDDEN_SIZE + i];
        }
        for (0..HIDDEN_SIZE) |i| {
            self.black[i] +=
                weights.hidden_layer_weights[add_black_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[sub_black_idx * HIDDEN_SIZE + i] -
                weights.hidden_layer_weights[opp_sub_black_idx * HIDDEN_SIZE + i];
        }
    }

    pub fn forward(self: Accumulator, turn: Side) i16 {
        const us_acc = if (turn == .white) &self.white else &self.black;
        const them_acc = if (turn == .white) &self.black else &self.white;

        var res: i32 = 0;

        for (0..HIDDEN_SIZE) |i| {
            res += screlu(us_acc[i]) * weights.output_weights[i];
            res += screlu(them_acc[i]) * weights.output_weights[i + HIDDEN_SIZE];
        }

        res = @divTrunc(res, QA); // res /= QA

        res += weights.output_bias;

        return @intCast(std.math.clamp(@divTrunc(res * SCALE, QA * QB), -(eval.win_score - 1), eval.win_score - 1)); // res * SCALE / (QA * QB)
    }

    pub fn updateWith(self: Accumulator, comptime turn: Side, board: *const Board, move: Move) Accumulator {
        const from = move.getFrom();
        const to = move.getTo();
        const from_type = board.mailbox[from.toInt()].?;
        const to_type = if (move.isPromotion()) move.getPromotedPieceType().? else from_type;
        var res = self;
        if (move.isCapture()) {
            if (move.isEnPassant()) {
                res.addSubSub(turn, .pawn, to, .pawn, from, .pawn, move.getEnPassantPawn(turn));
            } else {
                res.addSubSub(turn, to_type, to, from_type, from, board.mailbox[to.toInt()].?, to);
            }
        } else {
            if (move.isCastlingMove()) {
                res.addSub(turn, .king, move.getCastlingKingDest(turn), .king, from);
                res.addSub(turn, .rook, move.getCastlingRookDest(turn), .rook, to);
            } else {
                res.addSub(turn, to_type, to, from_type, from);
            }
        }

        return res;
    }

    pub fn negate(self: Accumulator) Accumulator {
        return self;
    }
};

pub const EvalState = Accumulator;

fn screlu(x: i32) i32 {
    const clamped = std.math.clamp(x, 0, QA);
    return clamped * clamped;
}

pub fn init() void {
    var fbs = std.io.fixedBufferStream(@embedFile("networks/beans1024.nnue"));

    // first read the weights for the first layer (there should be HIDDEN_SIZE * INPUT_SIZE of them)
    for (0..weights.hidden_layer_weights.len) |i| {
        weights.hidden_layer_weights[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then the biases for the first layer (there should be HIDDEN_SIZE of them)
    for (0..weights.hidden_layer_biases.len) |i| {
        weights.hidden_layer_biases[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then the weights for the second layer (there should be HIDDEN_SIZE * 2 of them)
    for (0..weights.output_weights.len) |i| {
        weights.output_weights[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then finally the bias
    weights.output_bias = fbs.reader().readInt(i16, .little) catch unreachable;
}

pub fn nnEval(board: *const Board) i16 {
    var acc = Accumulator.init(board);

    return acc.forward(board.turn);
}

pub const INPUT_SIZE = 768;
pub const HIDDEN_SIZE = 1024;
pub const SCALE = 400;
pub const QA = 255;
pub const QB = 64;
