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
const root = @import("../../root.zig");
const nnue = root.nnue;
const arch = @import("../arch.zig");
const Accumulator = nnue.Accumulator;
const Bitboard = root.Bitboard;
const Board = root.Board;
const Square = root.Square;
const Colour = root.Colour;
const PieceType = root.PieceType;
const ColouredPieceType = root.ColouredPieceType;
const File = root.File;

const TOTAL_THREATS = arch.TOTAL_THREATS;

const PIECE_TARGET_MAP: [6][6]i32 = .{
    .{ 0, 1, -1, 2, -1, -1 },
    .{ 0, 1, 2, 3, 4, -1 },
    .{ 0, 1, 2, 3, -1, -1 },
    .{ 0, 1, 2, 3, -1, -1 },
    .{ 0, 1, 2, 3, 4, -1 },
    .{ -1, -1, -1, -1, -1, -1 },
};

const PIECE_TARGET_COUNT: [6]i32 = blk: {
    var count: [6]i32 = @splat(0);
    for (0..6) |pt| {
        var c: i32 = 0;
        for (0..6) |vpt| {
            if (PIECE_TARGET_MAP[pt][vpt] != -1) c += 1;
        }
        count[pt] = 2 * c;
    }
    break :blk count;
};

fn emptyBoardAttacks(piece: ColouredPieceType, sq: Square) u64 {
    return switch (piece.toPieceType()) {
        .pawn => Bitboard.pawnAttacks(sq, piece.toColour()),
        .knight => Bitboard.knightMoves(sq),
        .bishop => Bitboard.bishopAttacks(sq),
        .rook => Bitboard.rookAttacks(sq),
        .queen => Bitboard.queenAttacks(sq),
        .king => Bitboard.kingMoves(sq),
    };
}

const PIECE_INDEX: [12][64][64]u8 = blk: {
    @setEvalBranchQuota(1 << 28);
    var table: [12][64][64]u8 = @splat(@splat(@splat(0)));
    for (0..12) |piece_idx| {
        const piece = ColouredPieceType.fromInt(@intCast(piece_idx));
        for (0..64) |from_idx| {
            const from = Square.fromInt(@intCast(from_idx));
            const attacks = emptyBoardAttacks(piece, from);
            for (0..64) |to_idx| {
                var count: u8 = 0;
                var it = Bitboard.iterator(attacks);
                while (it.next()) |to| {
                    if (to.toInt() < to_idx) count += 1;
                }
                table[piece_idx][from_idx][to_idx] = count;
            }
        }
    }
    break :blk table;
};

const Offset = struct {
    indices: [12]struct { piece_offset: i32, global_offset: i32 },
    offsets: [12][64]u32,
};

const OFFSETS: Offset = blk: {
    @setEvalBranchQuota(1 << 20);
    var dst: Offset = .{
        .indices = @splat(.{ .piece_offset = 0, .global_offset = 0 }),
        .offsets = @splat(@splat(0)),
    };
    var global_offset: i32 = 0;

    for (0..2) |col_idx| {
        const col = Colour.fromInt(@intCast(col_idx));
        for (0..6) |pt_idx| {
            const pt = PieceType.fromInt(@intCast(pt_idx));
            const piece = ColouredPieceType.fromPieceType(pt, col);
            const pidx = piece.toInt();
            var piece_offset: i32 = 0;
            for (0..64) |sq_idx| {
                const sq = Square.fromInt(@intCast(sq_idx));
                dst.offsets[pidx][sq_idx] = @intCast(piece_offset);
                const is_pawn_end_rank = pt == .pawn and
                    (sq.getRank() == .first or sq.getRank() == .eighth);
                if (!is_pawn_end_rank) {
                    const attacks = emptyBoardAttacks(piece, sq);
                    piece_offset += @intCast(@popCount(attacks));
                }
            }
            dst.indices[pidx] = .{
                .piece_offset = piece_offset,
                .global_offset = global_offset,
            };
            global_offset += PIECE_TARGET_COUNT[pt_idx] * piece_offset;
        }
    }
    break :blk dst;
};

const ATTACK_INDEX: [12][12][2]u32 = blk: {
    @setEvalBranchQuota(1 << 20);
    const SENTINEL: u32 = @intCast(TOTAL_THREATS);
    var dst: [12][12][2]u32 = @splat(@splat(.{ SENTINEL, SENTINEL }));

    for (0..12) |a_idx| {
        const attacker = ColouredPieceType.fromInt(@intCast(a_idx));
        const apt = attacker.toPieceType().toInt();

        for (0..12) |v_idx| {
            const victim = ColouredPieceType.fromInt(@intCast(v_idx));
            const vpt = victim.toPieceType().toInt();

            const map = PIECE_TARGET_MAP[apt][vpt];
            const full_excluded = map == -1;

            const opposed = attacker.toColour().toInt() != victim.toColour().toInt();
            const semi_excluded = (apt == vpt) and
                (opposed or apt != PieceType.pawn.toInt());

            const entry = OFFSETS.indices[a_idx];
            const colour_base: i32 = @as(i32, @intCast(victim.toColour().toInt())) *
                @divExact(PIECE_TARGET_COUNT[apt], 2);
            const feature: i32 = entry.global_offset + (colour_base + map) * entry.piece_offset;

            dst[a_idx][v_idx][0] = if (full_excluded) SENTINEL else @intCast(feature);
            dst[a_idx][v_idx][1] = if (full_excluded or semi_excluded) SENTINEL else @intCast(feature);
        }
    }
    break :blk dst;
};

pub fn threatIndex(
    colour: Colour,
    king: Square,
    attacker_in: ColouredPieceType,
    from_in: Square,
    victim_in: ColouredPieceType,
    to_in: Square,
) ?u32 {
    var attacker = attacker_in;
    var victim = victim_in;
    var from = from_in;
    var to = to_in;

    if (colour == .black) {
        @branchHint(.unpredictable);
        attacker = attacker.flipColor();
        victim = victim.flipColor();
        from = from.flipRank();
        to = to.flipRank();
    }

    if (king.getFile().toInt() >= File.e.toInt()) {
        @branchHint(.unpredictable);
        from = from.flipFile();
        to = to.flipFile();
    }

    const fwd_idx: usize = if (from.toInt() < to.toInt()) 1 else 0;
    const base = ATTACK_INDEX[attacker.toInt()][victim.toInt()][fwd_idx];

    const sq_offset = OFFSETS.offsets[attacker.toInt()][from.toInt()];
    const piece_idx = PIECE_INDEX[attacker.toInt()][from.toInt()][to.toInt()];

    const idx = base + sq_offset + piece_idx;
    if (base != TOTAL_THREATS) {
        std.debug.assert(idx < TOTAL_THREATS);
    }

    return if (base == TOTAL_THREATS) null else idx;
}

comptime {
    var total_offset: i32 = 0;
    for (0..2) |col_idx| {
        const col = Colour.fromInt(@intCast(col_idx));
        for (0..6) |pt_idx| {
            const pt = PieceType.fromInt(@intCast(pt_idx));
            const piece = ColouredPieceType.fromPieceType(pt, col);
            const pidx = piece.toInt();
            total_offset += PIECE_TARGET_COUNT[pt_idx] * OFFSETS.indices[pidx].piece_offset;
        }
    }
    std.debug.assert(total_offset == TOTAL_THREATS);
}

fn testAttacks(piece: ColouredPieceType, sq: Square, occ: u64) u64 {
    return switch (piece.toPieceType()) {
        .pawn => Bitboard.pawnAttacks(sq, piece.toColour()),
        .knight => Bitboard.knightMoves(sq),
        .bishop => root.attacks.bishopAttacks(sq, occ),
        .rook => root.attacks.rookAttacks(sq, occ),
        .queen => root.attacks.queenAttacks(sq, occ),
        .king => 0,
    };
}

const TestThreatIndices = root.BoundedArray(u32, 128);

fn positionThreatIndices(board: *const root.Board, colour: Colour) TestThreatIndices {
    const king = Square.fromBitboard(board.kingFor(colour));
    const occ = board.occupancy();
    var indices: TestThreatIndices = .{};

    var attacker_squares = Bitboard.iterator(occ);
    while (attacker_squares.next()) |attacker_sq| {
        const attacker = board.colouredPieceOn(attacker_sq).?;
        if (attacker.toPieceType() == .king) continue;

        const attacked_occupied = testAttacks(attacker, attacker_sq, occ) & occ;
        var victim_squares = Bitboard.iterator(attacked_occupied);
        while (victim_squares.next()) |victim_sq| {
            const victim = board.colouredPieceOn(victim_sq).?;
            if (victim.toPieceType() == .king) continue;

            if (threatIndex(colour, king, attacker, attacker_sq, victim, victim_sq)) |idx| {
                indices.appendAssumeCapacity(idx);
            }
        }
    }

    std.mem.sort(u32, indices.slice(), {}, std.sort.asc(u32));

    return indices;
}

fn startposThreatIndices(colour: Colour) TestThreatIndices {
    const board = root.Board.startpos();
    return positionThreatIndices(&board, colour);
}

pub fn refreshThreats(
    acc: *Accumulator,
    board: *const Board,
    colour: Colour,
    weights: *const arch.Weights,
) void {
    @memset(&acc.data, 0);
    const king_sq = Square.fromBitboard(board.kingFor(colour));
    const occ = board.occupancy();

    var attackers_it = Bitboard.iterator(occ);
    while (attackers_it.next()) |attacker_sq| {
        const attacker = board.colouredPieceOn(attacker_sq).?;

        if (attacker.toPieceType() == .king) continue;

        const attacked = switch (attacker.toPieceType()) {
            .pawn => Bitboard.pawnAttacks(attacker_sq, attacker.toColour()),
            .knight => Bitboard.knightMoves(attacker_sq),
            .bishop => root.attacks.bishopAttacks(attacker_sq, occ),
            .rook => root.attacks.rookAttacks(attacker_sq, occ),
            .queen => root.attacks.queenAttacks(attacker_sq, occ),
            .king => unreachable,
        } & occ;

        var victims_it = Bitboard.iterator(attacked);
        while (victims_it.next()) |victim_sq| {
            if (board.colouredPieceOn(victim_sq)) |victim| {
                if (threatIndex(colour, king_sq, attacker, attacker_sq, victim, victim_sq)) |idx| {
                    acc.addThreat(&weights.input.threat_w[idx]);
                }
            }
        }
    }
}

test "startpos threat indices" {
    const expected = [_]u32{
        506,   525,   3878,  3879,  3899,  3900,  8351,  8449,
        9240,  9344,  15603, 15604, 15605, 18512, 32570, 32589,
        36699, 36700, 36720, 36721, 42790, 42888, 43687, 43791,
        54247, 54248, 54249, 57166,
    };

    const white_indices = startposThreatIndices(.white);
    const black_indices = startposThreatIndices(.black);
    try std.testing.expectEqualSlices(u32, &expected, white_indices.slice());
    try std.testing.expectEqualSlices(u32, &expected, black_indices.slice());
}

test "kiwipete threat indices" {
    const board = try root.Board.parseFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", false);
    const white_expected = [_]u32{
        34,    95,    605,   606,   608,   1276,  2034,  2374,
        2376,  2377,  4517,  8351,  8449,  15907, 15908, 15919,
        17370, 18821, 23190, 24659, 30086, 30134, 30195, 30397,
        30398, 30401, 30488, 30491, 30807, 30809, 30840, 32491,
        32521, 33531, 35486, 37185, 38306, 42786, 42888, 54045,
        54050, 54054, 54055, 55505,
    };
    const black_expected = [_]u32{
        3,     4,     7,     94,    97,    389,   581,   612,
        1619,  2263,  2265,  2293,  4490,  5607,  8355,  8449,
        15752, 15753, 15758, 15765, 17213, 30107, 30143, 30372,
        30489, 30710, 30711, 30712, 32510, 32512, 32515, 33186,
        33740, 35517, 37212, 42790, 42888, 46560, 48008, 53839,
        53847, 53848, 55300, 56761,
    };

    const white_indices = positionThreatIndices(&board, .white);
    const black_indices = positionThreatIndices(&board, .black);
    try std.testing.expectEqualSlices(u32, &white_expected, white_indices.slice());
    try std.testing.expectEqualSlices(u32, &black_expected, black_indices.slice());
}
