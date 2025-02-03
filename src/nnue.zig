const std = @import("std");
const Board = @import("Board.zig");
const Square = @import("square.zig").Square;
const PieceType = @import("piece_type.zig").PieceType;
const Bitboard = @import("Bitboard.zig");
const Side = @import("side.zig").Side;
const eval = @import("eval.zig");

// dummy weights
const Weights = struct {
    hidden_layer_weights: [HIDDEN_SIZE * INPUT_SIZE]i16 align(64) = .{0} ** (HIDDEN_SIZE * INPUT_SIZE),
    l1_biases: [HIDDEN_SIZE]i16 align(64) = .{0} ** HIDDEN_SIZE,
    output_weights: [HIDDEN_SIZE * 2]i16 align(64) = .{0} ** (HIDDEN_SIZE * 2),
    output_bias: i16 align(64) = 0,
};

var weights: Weights = undefined;

pub const Accumulator = struct {
    white: [HIDDEN_SIZE]i16,
    black: [HIDDEN_SIZE]i16,

    fn idx(comptime perspective: Side, comptime side: Side, tp: PieceType, sq: Square) usize {
        const side_offs: usize = if (perspective.mult(side) == .white) 0 else 1;
        const sq_offs: usize = if (perspective == .black) sq.flipRank().toInt() else sq.toInt();
        const tp_offs: usize = tp.toInt();
        return side_offs * 64 * 6 + tp_offs * 64 + sq_offs;
    }

    pub fn init() Accumulator {
        return .{
            .white = weights.l1_biases,
            .black = weights.l1_biases,
        };
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
};

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
    for (0..weights.l1_biases.len) |i| {
        weights.l1_biases[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then the weights for the second layer (there should be HIDDEN_SIZE * 2 of them)
    for (0..weights.output_weights.len) |i| {
        weights.output_weights[i] = fbs.reader().readInt(i16, .little) catch unreachable;
    }

    // then finally the bias
    weights.output_bias = fbs.reader().readInt(i16, .little) catch unreachable;
    std.debug.print("{}\n", .{weights.output_bias});
}

pub fn nnEval(board: *const Board) i32 {
    var acc = Accumulator.init();

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

    const us_acc = if (board.turn == .white) &acc.white else &acc.black;
    const them_acc = if (board.turn == .white) &acc.black else &acc.white;

    var res: i32 = 0;

    for (0..HIDDEN_SIZE) |i| {
        res += screlu(@as(i32, std.math.clamp(us_acc[i], 0, QA)) * weights.output_weights[i]);
        res += screlu(@as(i32, std.math.clamp(them_acc[i], 0, QA)) * weights.output_weights[i + HIDDEN_SIZE]);
    }

    res = @divTrunc(res, QA); // res /= QA

    res += weights.output_bias;

    return @divTrunc(res * SCALE, QA * QB); // res * SCALE / (QA * QB)
}

pub const INPUT_SIZE = 768;
pub const HIDDEN_SIZE = 1024;
pub const SCALE = 400;
pub const QA = 255;
pub const QB = 64;
