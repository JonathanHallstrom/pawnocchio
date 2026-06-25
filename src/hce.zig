// pawnocchio, UCI chess engine
// Copyright (C) 2025 Jonathan Hallström
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");

const assert = std.debug.assert;

const root = @import("root.zig");

const Colour = root.Colour;
const PieceType = root.PieceType;
const Square = root.Square;
const Board = root.Board;
const Bitboard = root.Bitboard;
const Move = root.Move;
const evaluation = root.evaluation;

const MG_VALUE: [6]i16 = .{ 82, 337, 365, 477, 1025, 0 };
const EG_VALUE: [6]i16 = .{ 94, 281, 297, 512, 936, 0 };

const MG_PAWN_TABLE: [64]i16 = .{
    0,   0,   0,   0,   0,   0,   0,  0,
    98,  134, 61,  95,  68,  126, 34, -11,
    -6,  7,   26,  31,  65,  56,  25, -20,
    -14, 13,  6,   21,  23,  12,  17, -23,
    -27, -2,  -5,  12,  17,  6,   10, -25,
    -26, -4,  -4,  -10, 3,   3,   33, -12,
    -35, -1,  -20, -23, -15, 24,  38, -22,
    0,   0,   0,   0,   0,   0,   0,  0,
};

const EG_PAWN_TABLE: [64]i16 = .{
    0,   0,   0,   0,   0,   0,   0,   0,
    178, 173, 158, 134, 147, 132, 165, 187,
    94,  100, 85,  67,  56,  53,  82,  84,
    32,  24,  13,  5,   -2,  4,   17,  17,
    13,  9,   -3,  -7,  -7,  -8,  3,   -1,
    4,   7,   -6,  1,   0,   -5,  -1,  -8,
    13,  8,   8,   10,  13,  0,   2,   -7,
    0,   0,   0,   0,   0,   0,   0,   0,
};

const MG_KNIGHT_TABLE: [64]i16 = .{
    -167, -89, -34, -49, 61,  -97, -15, -107,
    -73,  -41, 72,  36,  23,  62,  7,   -17,
    -47,  60,  37,  65,  84,  129, 73,  44,
    -9,   17,  19,  53,  37,  69,  18,  22,
    -13,  4,   16,  13,  28,  19,  21,  -8,
    -23,  -9,  12,  10,  19,  17,  25,  -16,
    -29,  -53, -12, -3,  -1,  18,  -14, -19,
    -105, -21, -58, -33, -17, -28, -19, -23,
};

const EG_KNIGHT_TABLE: [64]i16 = .{
    -58, -38, -13, -28, -31, -27, -63, -99,
    -25, -8,  -25, -2,  -9,  -25, -24, -52,
    -24, -20, 10,  9,   -1,  -9,  -19, -41,
    -17, 3,   22,  22,  22,  11,  8,   -18,
    -18, -6,  16,  25,  16,  17,  4,   -18,
    -23, -3,  -1,  15,  10,  -3,  -20, -22,
    -42, -20, -10, -5,  -2,  -20, -23, -44,
    -29, -51, -23, -15, -22, -18, -50, -64,
};

const MG_BISHOP_TABLE: [64]i16 = .{
    -29, 4,  -82, -37, -25, -42, 7,   -8,
    -26, 16, -18, -13, 30,  59,  18,  -47,
    -16, 37, 43,  40,  35,  50,  37,  -2,
    -4,  5,  19,  50,  37,  37,  7,   -2,
    -6,  13, 13,  26,  34,  12,  10,  4,
    0,   15, 15,  15,  14,  27,  18,  10,
    4,   15, 16,  0,   7,   21,  33,  1,
    -33, -3, -14, -21, -13, -12, -39, -21,
};

const EG_BISHOP_TABLE: [64]i16 = .{
    -14, -21, -11, -8,  -7, -9,  -17, -24,
    -8,  -4,  7,   -12, -3, -13, -4,  -14,
    2,   -8,  0,   -1,  -2, 6,   0,   4,
    -3,  9,   12,  9,   14, 10,  3,   2,
    -6,  3,   13,  19,  7,  10,  -3,  -9,
    -12, -3,  8,   10,  13, 3,   -7,  -15,
    -14, -18, -7,  -1,  4,  -9,  -15, -27,
    -23, -9,  -23, -5,  -9, -16, -5,  -17,
};

const MG_ROOK_TABLE: [64]i16 = .{
    32,  42,  32,  51,  63, 9,  31,  43,
    27,  32,  58,  62,  80, 67, 26,  44,
    -5,  19,  26,  36,  17, 45, 61,  16,
    -24, -11, 7,   26,  24, 35, -8,  -20,
    -36, -26, -12, -1,  9,  -7, 6,   -23,
    -45, -25, -16, -17, 3,  0,  -5,  -33,
    -44, -16, -20, -9,  -1, 11, -6,  -71,
    -19, -13, 1,   17,  16, 7,  -37, -26,
};

const EG_ROOK_TABLE: [64]i16 = .{
    13, 10, 18, 15, 12, 12,  8,   5,
    11, 13, 13, 11, -3, 3,   8,   3,
    7,  7,  7,  5,  4,  -3,  -5,  -3,
    4,  3,  13, 1,  2,  1,   -1,  2,
    3,  5,  8,  4,  -5, -6,  -8,  -11,
    -4, 0,  -5, -1, -7, -12, -8,  -16,
    -6, -6, 0,  2,  -9, -9,  -11, -3,
    -9, 2,  3,  -1, -5, -13, 4,   -20,
};

const MG_QUEEN_TABLE: [64]i16 = .{
    -28, 0,   29,  12,  59,  44,  43,  45,
    -24, -39, -5,  1,   -16, 57,  28,  54,
    -13, -17, 7,   8,   29,  56,  47,  57,
    -27, -27, -16, -16, -1,  17,  -2,  1,
    -9,  -26, -9,  -10, -2,  -4,  3,   -3,
    -14, 2,   -11, -2,  -5,  2,   14,  5,
    -35, -8,  11,  2,   8,   15,  -3,  1,
    -1,  -18, -9,  10,  -15, -25, -31, -50,
};

const EG_QUEEN_TABLE: [64]i16 = .{
    -9,  22,  22,  27,  27,  19,  10,  20,
    -17, 20,  32,  41,  58,  25,  30,  0,
    -20, 6,   9,   49,  47,  35,  19,  9,
    3,   22,  24,  45,  57,  40,  57,  36,
    -18, 28,  19,  47,  31,  34,  39,  23,
    -16, -27, 15,  6,   9,   17,  10,  5,
    -22, -23, -30, -16, -16, -23, -36, -32,
    -33, -28, -22, -43, -5,  -32, -20, -41,
};

const MG_KING_TABLE: [64]i16 = .{
    -65, 23,  16,  -15, -56, -34, 2,   13,
    29,  -1,  -20, -7,  -8,  -4,  -38, -29,
    -9,  24,  2,   -16, -20, 6,   22,  -22,
    -17, -20, -12, -27, -30, -25, -14, -36,
    -49, -1,  -27, -39, -46, -44, -33, -51,
    -14, -14, -22, -46, -44, -30, -15, -27,
    1,   7,   -8,  -64, -43, -16, 9,   8,
    -15, 36,  12,  -54, 8,   -28, 24,  14,
};

const EG_KING_TABLE: [64]i16 = .{
    -74, -35, -18, -18, -11, 15,  4,   -17,
    -12, 17,  14,  17,  17,  38,  23,  11,
    10,  17,  23,  15,  20,  45,  44,  13,
    -8,  22,  24,  27,  26,  33,  26,  3,
    -18, -4,  21,  24,  27,  23,  9,   -11,
    -19, -3,  11,  21,  23,  16,  7,   -9,
    -27, -11, 4,   13,  14,  4,   -5,  -17,
    -53, -34, -21, -11, -28, -14, -24, -43,
};

const MG_PESTO_TABLE: [6][64]i16 = .{
    MG_PAWN_TABLE,
    MG_KNIGHT_TABLE,
    MG_BISHOP_TABLE,
    MG_ROOK_TABLE,
    MG_QUEEN_TABLE,
    MG_KING_TABLE,
};

const EG_PESTO_TABLE: [6][64]i16 = .{
    EG_PAWN_TABLE,
    EG_KNIGHT_TABLE,
    EG_BISHOP_TABLE,
    EG_ROOK_TABLE,
    EG_QUEEN_TABLE,
    EG_KING_TABLE,
};

const GAMEPHASE_INC: [6]u8 = .{ 0, 1, 1, 3, 6, 0 };
const MAX_PHASE = blk: {
    @setEvalBranchQuota(1 << 30);
    break :blk computePhase(&Board.startpos());
};

const MG_TABLE = blk: {
    var res: [12][64]i16 = undefined;
    for (PieceType.all) |pt| {
        const p: usize = @intFromEnum(pt);
        for (0..64) |sq| {
            res[2 * p + 0][sq] = MG_VALUE[p] + MG_PESTO_TABLE[p][sq ^ 56];
            res[2 * p + 1][sq] = -(MG_VALUE[p] + MG_PESTO_TABLE[p][sq]);
        }
    }
    break :blk res;
};
const EG_TABLE = blk: {
    var res: [12][64]i16 = undefined;
    for (PieceType.all) |pt| {
        const p: usize = @intFromEnum(pt);
        for (0..64) |sq| {
            res[2 * p + 0][sq] = EG_VALUE[p] + EG_PESTO_TABLE[p][sq ^ 56];
            res[2 * p + 1][sq] = -(EG_VALUE[p] + EG_PESTO_TABLE[p][sq]);
        }
    }
    break :blk res;
};

const PACKED_TABLE = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [12][64]Packed = undefined;
    for (0..12) |ti| {
        for (0..64) |sq| {
            res[ti][sq] = Packed.from(MG_TABLE[ti][sq], EG_TABLE[ti][sq]);
        }
    }
    break :blk res;
};

const Packed = enum(i32) {
    _,

    pub fn init(int: i32) Packed {
        return @enumFromInt(int);
    }

    pub fn toInt(self: Packed) i32 {
        return @intFromEnum(self);
    }

    pub fn from(mg: i16, eg: i16) Packed {
        return @enumFromInt((@as(i32, eg) << 16) + mg);
    }

    pub fn midgame(self: Packed) i16 {
        return @truncate(self.toInt());
    }

    pub fn endgame(self: Packed) i16 {
        // this gives identical assembly but doesnt work at compile time, not quite sure why
        // return @intCast((self + 0x8000) >> 16);

        var u: u32 = @bitCast(self.toInt() + 0x8000);
        u >>= 16;
        const low: u16 = @intCast(u);
        const res: i16 = @bitCast(low);
        if (!@inComptime()) {
            assert(res == @as(i16, @intCast((self.toInt() + 0x8000) >> 16)));
        }
        return res;
    }

    pub fn add(self: Packed, other: Packed) Packed {
        return init(self.toInt() +% other.toInt());
    }

    pub fn sub(self: Packed, other: Packed) Packed {
        return self.add(other.negate());
    }

    pub fn addScalar(self: Packed, scalar: i16) Packed {
        return self.add(from(scalar, scalar));
    }

    pub fn multiplyScalar(self: Packed, scalar: i16) Packed {
        assert(init(self.toInt() *% scalar) == from(self.midgame() * scalar, self.endgame() * scalar));
        return init(self.toInt() *% scalar);
    }

    pub fn negate(self: Packed) Packed {
        assert(init(-self.toInt()) == from(-self.midgame(), -self.endgame()));
        return init(-self.toInt());
    }

    comptime {
        @setEvalBranchQuota(1 << 30);
        for (0..32) |i| {
            for (0..32) |j| {
                var mg: i16 = i;
                mg -= 16;
                var eg: i16 = j;
                eg -= 16;
                if (from(mg, eg).midgame() != mg) {
                    @compileLog(mg, eg);
                    @compileError("");
                }
                if (from(mg, eg).endgame() != eg) {
                    @compileLog(mg, eg);
                    @compileError("");
                }
                if (from(mg, eg).negate() != from(-mg, -eg)) {
                    @compileError("");
                }
            }
        }
        for (0..16) |i| {
            for (0..16) |j| {
                var mg1: i16 = i;
                mg1 -= 8;
                var eg1: i16 = j;
                eg1 -= 8;
                for (0..4) |k| {
                    for (0..4) |l| {
                        var mg2: i16 = k;
                        mg2 -= 2;
                        var eg2: i16 = l;
                        eg2 -= 2;

                        if (from(mg1, eg1).add(from(mg2, eg2)) != from(mg1 + mg2, eg1 + eg2)) {
                            @compileError("");
                        }
                    }
                }
            }
        }
    }
};

fn computePhase(board: *const Board) u8 {
    var res: u8 = 0;
    for (0..6) |p| {
        res += GAMEPHASE_INC[p] * @popCount(board.pieceBB(PieceType.fromInt(@intCast(p))));
    }
    return res;
}

pub inline fn readPieceValue(pt: PieceType) Packed {
    return Packed.from(MG_VALUE[pt.toInt()], EG_VALUE[pt.toInt()]);
}

pub inline fn readPieceSquareTable(col: Colour, pt: PieceType, square: Square) Packed {
    return PACKED_TABLE[@as(usize, pt.toInt()) * 2 + col.toInt()][square.toInt()];
}

const Frame = struct {
    state: Packed,
    phase: u8,

    pub fn init(board: *const Board) Frame {
        var state = Packed.from(0, 0);

        for (PieceType.all) |pt| {
            var iter = Bitboard.iterator(board.pieceFor(.white, pt));
            while (iter.next()) |s| state = state.add(readPieceSquareTable(.white, pt, s));
            iter = Bitboard.iterator(board.pieceFor(.black, pt));
            while (iter.next()) |s| state = state.add(readPieceSquareTable(.black, pt, s));
        }

        return .{
            .state = state,
            .phase = computePhase(board),
        };
    }

    pub fn initInPlace(noalias self: *Frame, board: *const Board) void {
        self.* = init(board);
    }

    pub fn update(self: *Frame, other: *const Frame) void {
        self.* = other.*;
    }

    pub fn add(self: *Frame, a: root.PSQTFeature) void {
        self.state = self.state.add(readPieceSquareTable(a.col(), a.piece(), a.square()));
        self.phase += GAMEPHASE_INC[a.piece().toInt()];
    }

    pub fn sub(self: *Frame, s: root.PSQTFeature) void {
        self.state = self.state.sub(readPieceSquareTable(s.col(), s.piece(), s.square()));
        self.phase -= GAMEPHASE_INC[s.piece().toInt()];
    }

    pub fn eval(self: Frame, board: *const Board) i16 {
        const mg_phase: i32 = @min(self.phase, MAX_PHASE);
        const eg_phase = MAX_PHASE - mg_phase;

        var res = evaluation.clampScore(@divTrunc(mg_phase * self.state.midgame() + eg_phase * self.state.endgame(), MAX_PHASE));
        if (board.stm == .black) res = -res;
        return res;
    }
};

pub const Context = struct {
    frames: [root.SEARCH_MAX_PLY]Frame = undefined,

    pub fn initForThread(_: *Context, _: usize) void {}

    pub fn initRoot(self: *Context, board: *const Board) void {
        self.frames[0].initInPlace(board);
    }

    pub fn prepareChild(self: *Context, child_ply: usize, child_board: *const Board) void {
        _ = child_board;
        self.frames[child_ply].update(&self.frames[child_ply - 1]);
    }

    pub fn handle(self: *Context, ply: usize) evaluation.Handle(*Frame) {
        return evaluation.wrapHandle(&self.frames[ply]);
    }
};

pub fn evalPosition(board: *const Board) i16 {
    const ctx = evaluation.globalCtx.lock();
    defer evaluation.globalCtx.release();
    ctx.initRoot(board);
    return ctx.handle(0).eval(board);
}
