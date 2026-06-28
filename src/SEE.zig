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

const PieceType = root.PieceType;
const Square = root.Square;
const Bitboard = root.Bitboard;
const attacks = root.attacks;
const Board = root.Board;
const Move = root.Move;
const Colour = root.Colour;

pub const Mode = enum {
    pruning,
    ordering,
    testing,
};

pub fn value(pt: PieceType, comptime mode: Mode) i16 {
    if (mode == .testing) {
        return ([_]i16{ 100, 300, 350, 500, 900, 0 })[pt.toInt()];
    }
    const SEE_weight = if (mode == .pruning) [_]i16{
        @intCast(root.TUNABLE_CONSTANTS.see_pawn_pruning),
        @intCast(root.TUNABLE_CONSTANTS.see_knight_pruning),
        @intCast(root.TUNABLE_CONSTANTS.see_bishop_pruning),
        @intCast(root.TUNABLE_CONSTANTS.see_rook_pruning),
        @intCast(root.TUNABLE_CONSTANTS.see_queen_pruning),
        0,
    } else [_]i16{
        @intCast(root.TUNABLE_CONSTANTS.see_pawn_ordering),
        @intCast(root.TUNABLE_CONSTANTS.see_knight_ordering),
        @intCast(root.TUNABLE_CONSTANTS.see_bishop_ordering),
        @intCast(root.TUNABLE_CONSTANTS.see_rook_ordering),
        @intCast(root.TUNABLE_CONSTANTS.see_queen_ordering),
        0,
    };
    return (if (root.tuning.DO_TUNING) SEE_weight else comptime SEE_weight)[pt.toInt()];
}

fn pickFirstScalar(board: *const Board, mask: u64) u8 {
    const pieces = board.pieceBBs();
    var res: u8 = 0;
    while (res < 6) {
        if (pieces[res] & mask != 0) {
            break;
        }
        res += 1;
    }
    return res;
}

fn pickFirstVectorized(board: *const Board, mask: u64) u8 {
    const bbs = &board.bbs;
    const mask_vec: @Vector(8, u64) = @splat(mask);
    const zero: @Vector(8, u64) = @splat(0);
    const eql: u8 = @bitCast(mask_vec & bbs.* != zero);
    std.debug.assert(eql != 0);
    return switch (@import("builtin").cpu.arch.endian()) {
        .little => @ctz(eql),
        .big => @clz(eql),
    };
}

// if we have SIMD support use it otherwise use the scalar version
const pickFirst = switch (std.simd.suggestVectorLength(u64) orelse 0) {
    0, 1 => pickFirstScalar,
    else => pickFirstVectorized,
};

fn pack(piece_counts: [6]i8) u48 {
    return @bitCast(piece_counts);
}

fn unpack(piece_counts: u48) [6]i8 {
    return @bitCast(piece_counts);
}

pub var piece_count_set = std.AutoHashMap(u48, u64).init(std.heap.smp_allocator);

pub fn printPieceCounts() void {
    var iter = piece_count_set.iterator();

    const P = struct { u64, [6]i8 };
    var list = std.array_list.Managed(P).init(std.heap.smp_allocator);
    defer list.deinit();

    while (iter.next()) |e| {
        const piece_counts = unpack(e.key_ptr.*);
        const count = e.value_ptr.*;

        list.append(.{ count, piece_counts }) catch @panic("oom");
    }

    std.mem.sort(P, list.items, void{}, struct {
        fn impl(_: void, a: P, b: P) bool {
            return a.@"0" > b.@"0";
        }
    }.impl);

    for (list.items) |e| {
        const count, const piece_counts = e;

        for (piece_counts, root.PieceType.all) |c, pt| {
            if (c <= 0) continue;
            if (c != 1) std.debug.print("{}", .{c});
            std.debug.print("{c} ", .{pt.toAsciiLetter()});
        }

        std.debug.print("- ", .{});

        for (piece_counts, root.PieceType.all) |c, pt| {
            if (c >= 0) continue;
            if (c != -1) std.debug.print("{}", .{-c});
            std.debug.print("{c} ", .{pt.toAsciiLetter()});
        }
        std.debug.print(": {}\n", .{count});
    }
}

pub noinline fn scoreMove(board: *const Board, move: Move, threshold: i32, comptime mode: Mode) bool {
    const from = move.from();
    const to = move.to();
    const from_type = board.pieceOn(from) orelse return false;
    var captured_type: ?PieceType = null;
    var captured_value: i16 = 0;
    if (board.isEnPassant(move)) {
        captured_type = .pawn;
        captured_value = value(.pawn, mode);
    } else if (board.isCapture(move)) {
        captured_type = board.pieceOn(to) orelse return false;
        captured_value = value(captured_type.?, mode);
    }

    var score = captured_value - threshold;
    if (board.isPromo(move)) {
        const pt = move.promoType();
        const promo_value = value(pt, mode);
        score += promo_value - value(.pawn, mode); // add promoted piece, remove pawn since it disappears
        if (score < 0) return false; // if we're worse off than we need to be even just after promoting and possibly capturing, theres no point continuing

        score -= promo_value; // remove the promoted piece, assuming it was captured, if we're still okay even assuming we lose it immeditely, we're good!
        if (score >= 0) return true;
    } else {
        if (score < 0) return false; // if the capture is immeditely not good enough just return
        score -= value(from_type, mode);
        if (score >= 0) return true; // if we can lose the piece we used to capture and still be okay, we're good!
    }

    var occ = board.occupancy() & ~from.toBitboard() & ~to.toBitboard();
    const queens = board.queens();
    const rooks = board.rooks() | queens;
    const bishops = board.bishops() | queens;

    var stm = board.stm.flipped();

    const all_pinned = board.pinnedFor(.white) | board.pinnedFor(.black);

    const white_king_to_ray = Bitboard.extendingRayBb(Square.fromBitboard(board.kingFor(.white)), to);
    const black_king_to_ray = Bitboard.extendingRayBb(Square.fromBitboard(board.kingFor(.black)), to);

    const white_allowed_pinned = board.pinnedFor(.white) & white_king_to_ray;
    const black_allowed_pinned = board.pinnedFor(.black) & black_king_to_ray;

    const allowed_pinned = all_pinned & (white_allowed_pinned | black_allowed_pinned);

    const allowed = ~all_pinned | allowed_pinned;

    var attackers =
        root.movegen.attackersFor(.white, board, to, occ) |
        root.movegen.attackersFor(.black, board, to, occ);

    attackers &= allowed & occ;

    var attacker: PieceType = undefined;

    var piece_counts: [7]i8 = @splat(0);
    var sign: i8 = -1;

    var previous_attacker: u8 = if (captured_type) |c| c.toInt() else 6;
    while (true) {
        if (attackers & board.occupancyFor(stm) == 0) {
            break;
        }
        const our_attackers = board.occupancyFor(stm) & attackers;
        const attacker_i = pickFirst(board, our_attackers);
        const attacker_bb = board.pieceBBs()[attacker_i] & our_attackers;
        occ ^= attacker_bb & -%attacker_bb;

        attacker = PieceType.fromInt(attacker_i);
        // if our last attacker is the king, and they still have an attacker, we can't actually recapture
        if (attacker == .king and attackers & board.occupancyFor(stm.flipped()) != 0) {
            break;
        }

        if (attacker == .pawn or attacker == .bishop or attacker == .queen) {
            attackers |= root.attacks.bishopAttacks(to, occ) & bishops;
        }
        if (attacker == .rook or attacker == .queen) {
            attackers |= root.attacks.rookAttacks(to, occ) & rooks;
        }

        attackers &= occ;
        piece_counts[previous_attacker] += sign;
        previous_attacker = attacker.toInt();
        sign = -sign;
        score = -score - 1 - value(attacker, mode);
        stm = stm.flipped();

        if (score >= 0) {
            break;
        }
    }
    var s: i8 = 1;
    for (piece_counts) |p| {
        s *= @as(i8, @intFromBool(p >= 0)) - @as(i8, @intFromBool(p < 0));
    }

    for (&piece_counts) |*p| p.* *= s;

    const gop = piece_count_set.getOrPut(pack(piece_counts[0..6].*)) catch @panic("oom");
    if (!gop.found_existing) gop.value_ptr.* = 0;
    gop.value_ptr.* += 1;

    return stm != board.stm;
}

test scoreMove {
    root.init(std.testing.io);
    try std.testing.expect(scoreMove(&(Board.parseFen("k6b/8/8/8/8/8/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .testing), .testing));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2p5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .testing), .testing));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k7/8/8/8/8/2p5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .testing), .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("k7/8/8/8/8/2q5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .testing), .testing));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2q5/1p6/BK6 w - - 0 1", false) catch unreachable), Move.capture(.a1, .b2), value(.pawn, .testing), .testing));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k3n2r/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), value(.rook, .testing), .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("k3n3/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), value(.rook, .testing), .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("k3n3/3P4/8/8/8/8/8/1K6 w - - 0 1", false) catch unreachable), Move.promo(.d7, .e8, .queen), value(.rook, .testing), .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("rn2k2r/p3bpp1/2p4p/8/2P3Q1/1P1q4/P4P1P/RNB1K2R w KQkq - 0 8", false) catch unreachable), Move.capture(.g4, .g7), 0, .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("r1bq1rk1/pppp1Npp/2nb1n2/4p3/2B1P3/2P5/PP1P1PPP/RNBQK2R b KQ - 0 6", false) catch unreachable), Move.capture(.f8, .f7), 0, .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("r1bqkb1r/ppp1pppp/2n2n2/8/2BPP3/5P2/PP4PP/RNBQK1NR b KQkq - 0 5", false) catch unreachable), Move.capture(.c6, .d4), 0, .testing));
    try std.testing.expect(!scoreMove(&(Board.parseFen("3b2k1/1b6/8/3R2p1/4K3/5N2/8/8 w - - 0 1", false) catch unreachable), Move.capture(.f3, .g5), 0, .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("5k2/1b6/8/3B4/4K3/8/8/8 w - - 0 1", false) catch unreachable), Move.capture(.d5, .b7), 0, .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("6b1/k7/8/3Pp3/2K2N1r/8/8/8 w - e6 0 1", false) catch unreachable), Move.enPassant(.d5, .e6), 0, .testing));
    try std.testing.expect(!scoreMove(&(Board.parseFen("6b1/k7/8/3Pp3/2K2N1r/8/8/8 w - e6 0 1", false) catch unreachable), Move.enPassant(.d5, .e6), 1, .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("6b1/k7/8/3Pp3/2K2N2/8/8/8 w - e6 0 1", false) catch unreachable), Move.enPassant(.d5, .e6), value(.pawn, .testing), .testing));
    try std.testing.expect(scoreMove(&(Board.parseFen("8/8/8/1k6/6b1/4N3/2p3K1/3n4 w - - 0 1", false) catch unreachable), Move.capture(.e3, .c2), value(.pawn, .testing) - value(.queen, .testing), .testing));
}
