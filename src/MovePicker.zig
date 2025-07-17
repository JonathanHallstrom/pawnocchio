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

const root = @import("root.zig");

const Move = root.Move;
const Board = root.Board;
const ScoredMove = root.ScoredMove;
const MoveReceiver = root.FilteringScoredMoveReceiver;
const movegen = root.movegen;
const SEE = root.SEE;
const PieceType = root.PieceType;
const Square = root.Square;
const Bitboard = root.Bitboard;

const MovePicker = @This();

movelist: *MoveReceiver,
first: usize,
last: usize,
board: *const Board,
stage: Stage,
skip_quiets: bool,
histories: *const root.history.HistoryTable,
ttmove: Move,
cur: root.history.TypedMove,
prev: root.history.TypedMove,
last_bad_noisy: usize = 0,
next_func: *const fn (*MovePicker) ScoredMove,
recapture_move: Move = Move.init(),

pub const Stage = enum {
    tt,
    lva_recapture,
    generate_noisies,
    good_noisies,
    generate_quiets,
    quiets,
    bad_noisy_prep,
    bad_noisies,
};

pub fn init(
    board_: *const Board,
    movelist_: *MoveReceiver,
    histories_: *root.history.HistoryTable,
    ttmove_: Move,
    cur_: root.history.TypedMove,
    prev_: root.history.TypedMove,
    is_singular_search: bool,
) MovePicker {
    movelist_.vals.len = 0;
    movelist_.filter = ttmove_;
    return .{
        .movelist = movelist_,
        .board = board_,
        .first = 0,
        .last = 0,
        .stage = if (is_singular_search) .generate_noisies else .tt,
        .next_func = if (is_singular_search) &generateNoisies else &tt,
        .skip_quiets = false,
        .histories = histories_,
        .ttmove = ttmove_,
        .cur = cur_,
        .prev = prev_,
    };
}

pub fn initQs(
    board_: *const Board,
    movelist_: *MoveReceiver,
    histories_: *root.history.HistoryTable,
    ttmove_: Move,
    cur_: root.history.TypedMove,
    prev_: root.history.TypedMove,
) MovePicker {
    movelist_.vals.len = 0;
    movelist_.filter = ttmove_;
    return .{
        .movelist = movelist_,
        .board = board_,
        .first = 0,
        .last = 0,
        .stage = .tt,
        .next_func = &tt,
        .skip_quiets = board_.checkers == 0,
        .histories = histories_,
        .ttmove = ttmove_,
        .cur = cur_,
        .prev = prev_,
    };
}

pub fn deinit(self: MovePicker) void {
    self.movelist.vals.len = 0;
}

inline fn findBest(noalias self: *MovePicker) usize {
    const scored_moves = self.movelist.vals.slice()[self.first..self.last];

    const unroll = 4;
    const loadVals = struct {
        fn impl(moves: []ScoredMove, i: usize) @Vector(unroll, u64) {
            var res: @Vector(unroll, u64) = undefined;
            inline for (0..unroll) |j| {
                res[j] = moves.ptr[i + j].toScoreU64();
            }
            return res;
        }
    }.impl;
    const masks = comptime blk: {
        var res: [unroll]@Vector(unroll, u64) = undefined;
        res[0] = @splat(0);
        for (1..unroll) |j| {
            res[j] = res[j - 1];
            res[j][j - 1] = std.math.maxInt(u64);
        }
        break :blk res;
    };
    var best: @Vector(unroll, u64) = [_]u64{scored_moves[0].toScoreU64()} ** unroll;
    var i: u64 = 0;
    var index_vec = std.simd.iota(u64, unroll);
    while (i + unroll <= scored_moves.len) : (i += unroll) {
        best = @max(best, loadVals(scored_moves, i) | index_vec);
        index_vec += @splat(unroll);
    }
    best = @max(best, (loadVals(scored_moves, i) & masks[scored_moves.len % unroll]) | index_vec);

    const best_idx: u64 = @reduce(.Max, best) & std.math.maxInt(u32);

    if (best_idx != 0) {
        std.mem.swap(ScoredMove, &scored_moves[0], &scored_moves[best_idx]);
    }
    const res = self.first;
    self.first += 1;
    return res;
}

fn noisyValue(self: MovePicker, move: Move) i32 {
    var res: i32 = 0;

    // if (self.board.isPromo(move)) {
    //     res += SEE.value(move.promoType());
    // }
    if ((&self.board.mailbox)[move.to().toInt()].opt()) |captured_type| {
        res += SEE.value(captured_type.toPieceType(), .ordering);
    } else if (self.board.isEnPassant(move)) {
        res += SEE.value(.pawn, .ordering);
    }
    res = @divFloor(res * root.tunable_constants.mvv_mult, 32);
    res += self.histories.readNoisy(self.board, move);

    return res;
}

const call_modifier: std.builtin.CallModifier = if (@import("builtin").mode == .Debug) .auto else .always_tail;

fn tt(self: *MovePicker) ScoredMove {
    self.stage = .lva_recapture;
    self.next_func = &lvaRecapture;
    if (self.skip_quiets and self.board.isQuiet(self.ttmove)) {
        return @call(call_modifier, lvaRecapture, .{self});
    }
    switch (self.board.stm) {
        inline else => |stm| {
            if (self.board.isPseudoLegal(stm, self.ttmove)) {
                return ScoredMove{ .move = self.ttmove, .score = 0 };
            }
        },
    }
    return @call(call_modifier, lvaRecapture, .{self});
}

fn lvaRecapture(self: *MovePicker) ScoredMove {
    self.stage = .generate_noisies;
    self.next_func = &generateNoisies;
    const board = self.board;
    const dest = self.cur.move.to();
    var check_mask: u64 = std.math.maxInt(u64);
    if (board.checkers != 0) {
        if (@popCount(board.checkers) == 1) {
            check_mask = Bitboard.checkMask(Square.fromBitboard(board.kingFor(board.stm)), Square.fromBitboard(board.checkers));
        } else {
            check_mask = 0;
        }
    }
    if (!self.cur.move.isNull() and
        Bitboard.contains(check_mask, dest) and
        Bitboard.contains(board.occupancyFor(board.stm.flipped()), dest))
    {
        switch (board.stm) {
            inline else => |stm| {
                const pawns = board.pawnsFor(stm);

                // for now only handle recaptures by unpinned pieces
                const knights = board.knightsFor(stm) & ~board.pinned[stm.toInt()];
                const bishops = board.bishopsFor(stm) & ~board.pinned[stm.toInt()];
                const rooks = board.rooksFor(stm) & ~board.pinned[stm.toInt()];
                const queens = board.queensFor(stm) & ~board.pinned[stm.toInt()];

                const forward: i8 = if (stm == .white) 1 else -1;

                if (Bitboard.contains(Bitboard.move(pawns, forward, 1), dest)) {
                    const mv = Move.capture(dest.move(-forward, -1), dest);
                    if (mv != self.ttmove) {
                        self.recapture_move = mv;
                        return ScoredMove{ .move = mv, .score = 0 };
                    }
                }
                if (Bitboard.contains(Bitboard.move(pawns, forward, -1), dest)) {
                    const mv = Move.capture(dest.move(-forward, 1), dest);
                    if (mv != self.ttmove) {
                        self.recapture_move = mv;
                        return ScoredMove{ .move = mv, .score = 0 };
                    }
                }
                const attacking_knights = Bitboard.knightMoves(dest) & knights;
                if (attacking_knights != 0) {
                    const mv = Move.capture(Square.fromInt(@ctz(attacking_knights)), dest);
                    if (mv != self.ttmove) {
                        self.recapture_move = mv;
                        return ScoredMove{ .move = mv, .score = 0 };
                    }
                }
                const bishop_attacks = root.attacks.getBishopAttacks(dest, board.occupancy());
                const attacking_bishops = bishop_attacks & bishops;
                if (attacking_bishops != 0) {
                    const mv = Move.capture(Square.fromInt(@ctz(attacking_bishops)), dest);
                    if (mv != self.ttmove) {
                        self.recapture_move = mv;
                        return ScoredMove{ .move = mv, .score = 0 };
                    }
                }
                const rook_attacks = root.attacks.getRookAttacks(dest, board.occupancy());
                const attacking_rooks = rook_attacks & rooks;
                if (attacking_rooks != 0) {
                    const mv = Move.capture(Square.fromInt(@ctz(attacking_rooks)), dest);
                    if (mv != self.ttmove) {
                        self.recapture_move = mv;
                        return ScoredMove{ .move = mv, .score = 0 };
                    }
                }
                const attacking_queens = (bishop_attacks | rook_attacks) & queens;
                if (attacking_queens != 0) {
                    const mv = Move.capture(Square.fromInt(@ctz(attacking_queens)), dest);
                    if (mv != self.ttmove) {
                        self.recapture_move = mv;
                        return ScoredMove{ .move = mv, .score = 0 };
                    }
                }
            },
        }
    }
    return @call(call_modifier, generateNoisies, .{self});
}

fn generateNoisies(self: *MovePicker) ScoredMove {
    self.movelist.vals.len = 0;
    switch (self.board.stm) {
        inline else => |stm| {
            std.debug.assert(self.movelist.vals.len == 0);
            movegen.generateAllNoisies(stm, self.board, self.movelist);
            var new_len: usize = 0;
            for (self.movelist.vals.slice()) |scored_move| {
                if (scored_move.move == self.recapture_move) {
                    continue;
                }
                self.movelist.vals.slice()[new_len] = .{
                    .move = scored_move.move,
                    .score = self.noisyValue(scored_move.move),
                };
                new_len += 1;
            }
            self.movelist.vals.len = new_len;
        },
    }
    self.last = self.movelist.vals.len;
    self.stage = .good_noisies;
    self.next_func = &goodNoises;
    return @call(call_modifier, goodNoises, .{self});
}
fn goodNoises(self: *MovePicker) ScoredMove {
    if (self.first == self.last) {
        self.stage = .generate_quiets;
        self.next_func = &generateQuiets;
        return @call(call_modifier, generateQuiets, .{self});
    }
    const res = self.movelist.vals.slice()[self.findBest()];
    const history_score = self.histories.readNoisy(self.board, res.move);
    const margin = @divTrunc(-history_score * root.tunable_constants.good_noisy_ordering_mult, 32768) +
        root.tuning.tunable_constants.good_noisy_ordering_base;
    if (SEE.scoreMove(self.board, res.move, margin, .ordering)) {
        return res;
    }
    self.movelist.vals.slice()[self.last_bad_noisy] = res;
    self.last_bad_noisy += 1;
    return @call(call_modifier, goodNoises, .{self});
}

fn generateQuiets(self: *MovePicker) ScoredMove {
    if (self.skip_quiets) {
        self.stage = .quiets;
        return ScoredMove{ .move = Move.init(), .score = 0 };
        // self.next_func = &quiets;
        // return @call(tail_call, &quiets, .{self});
    }
    self.first = self.movelist.vals.len;
    switch (self.board.stm) {
        inline else => |stm| {
            movegen.generateAllQuiets(stm, self.board, self.movelist);
            for (self.movelist.vals.slice()[self.last..]) |*scored_move| {
                scored_move.score = self.histories.readQuiet(self.board, scored_move.move, self.cur, self.prev);
            }
        },
    }
    self.last = self.movelist.vals.len;
    self.stage = .quiets;
    self.next_func = &quiets;
    return @call(call_modifier, quiets, .{self});
}

fn quiets(self: *MovePicker) ScoredMove {
    if (self.first == self.last or self.skip_quiets) {
        self.stage = .bad_noisy_prep;
        self.next_func = &badNoisyPrep;
        return @call(call_modifier, badNoisyPrep, .{self});
    }
    return self.movelist.vals.slice()[self.findBest()];
}
fn badNoisyPrep(self: *MovePicker) ScoredMove {
    self.first = 0;
    self.last = self.last_bad_noisy;
    self.stage = .bad_noisies;
    self.next_func = &badNoisies;
    return @call(call_modifier, badNoisies, .{self});
}
fn badNoisies(self: *MovePicker) ScoredMove {
    if (self.first == self.last) {
        return ScoredMove{ .move = Move.init(), .score = 0 };
    }
    return self.movelist.vals.slice()[self.findBest()];
}

pub inline fn next(self: *MovePicker) ?ScoredMove {
    const res = @call(.auto, self.next_func, .{self});
    if (res.move.isNull()) {
        return null;
    }
    // std.debug.print("{s} {s}\n", .{ self.board.toFen().slice(), res.move.toString(self.board).slice() });
    return res;
}
