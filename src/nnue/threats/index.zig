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
const IdxType = if (TOTAL_THREATS + arch.TOTAL_PAWN_PAIRS < std.math.maxInt(u16)) u16 else u32;

const PIECE_TARGET_MAP: [6][6]i32 = if (arch.PAWN_PAIR_INPUTS) .{
    .{ -1, 0, -1, 1, -1, -1 },
    .{ 0, 1, 2, 3, 4, -1 },
    .{ 0, 1, 2, 3, -1, -1 },
    .{ 0, 1, 2, 3, -1, -1 },
    .{ 0, 1, 2, 3, 4, -1 },
    .{ -1, -1, -1, -1, -1, -1 },
} else .{
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

pub const PIECE_INDEX: [12][64][64]u8 = blk: {
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

pub const Offset = struct {
    indices: [12]struct { piece_offset: IdxType, global_offset: IdxType },
    offsets: [12][64]IdxType,
};

pub const OFFSETS: Offset = blk: {
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
                .piece_offset = @intCast(piece_offset),
                .global_offset = @intCast(global_offset),
            };
            global_offset += PIECE_TARGET_COUNT[pt_idx] * piece_offset;
        }
    }
    break :blk dst;
};

pub const ATTACK_INDEX: [12][12][2]IdxType = blk: {
    @setEvalBranchQuota(1 << 20);
    const SENTINEL: IdxType = @intCast(TOTAL_THREATS);
    var dst: [12][12][2]IdxType = @splat(@splat(.{ SENTINEL, SENTINEL }));

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

pub fn perspectiveSquareMask(colour: Colour, king: Square) u8 {
    return (0b111000 * @as(u8, @intFromBool(colour == .black))) ^
        (0b000111 * @as(u8, @intFromBool(king.getFile().toInt() >= File.e.toInt())));
}

pub fn threatIndexUnchecked(
    colour: Colour,
    king: Square,
    attacker_in: ColouredPieceType,
    from_in: Square,
    victim_in: ColouredPieceType,
    to_in: Square,
) IdxType {
    const colour_mask: u8 = @intFromBool(colour == .black);
    const sq_mask = perspectiveSquareMask(colour, king);

    const attacker = ColouredPieceType.fromInt(attacker_in.toInt() ^ colour_mask);
    const victim = ColouredPieceType.fromInt(victim_in.toInt() ^ colour_mask);
    const from = Square.fromInt(from_in.toInt() ^ sq_mask);
    const to = Square.fromInt(to_in.toInt() ^ sq_mask);

    const base = ATTACK_INDEX[attacker.toInt()][victim.toInt()][@intFromBool(from.toInt() < to.toInt())];

    const sq_offset = OFFSETS.offsets[attacker.toInt()][from.toInt()];
    const piece_idx = PIECE_INDEX[attacker.toInt()][from.toInt()][to.toInt()];

    return base + sq_offset + piece_idx;
}

pub fn threatIndex(
    colour: Colour,
    king: Square,
    attacker_in: ColouredPieceType,
    from_in: Square,
    victim_in: ColouredPieceType,
    to_in: Square,
) struct { IdxType, bool } {
    const colour_mask: u8 = @intFromBool(colour == .black);
    const sq_mask = perspectiveSquareMask(colour, king);

    const attacker = ColouredPieceType.fromInt(attacker_in.toInt() ^ colour_mask);
    const victim = ColouredPieceType.fromInt(victim_in.toInt() ^ colour_mask);
    const from = Square.fromInt(from_in.toInt() ^ sq_mask);
    const to = Square.fromInt(to_in.toInt() ^ sq_mask);

    const base: IdxType = ATTACK_INDEX[attacker.toInt()][victim.toInt()][@intFromBool(from.toInt() < to.toInt())];

    const sq_offset: IdxType = OFFSETS.offsets[attacker.toInt()][from.toInt()];
    const piece_idx: IdxType = PIECE_INDEX[attacker.toInt()][from.toInt()][to.toInt()];

    return .{ base +% sq_offset +% piece_idx, base != TOTAL_THREATS };
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

fn perspectiveBelow(from: Square, sq_mask: u8) u64 {
    const from_p = from.toInt() ^ sq_mask;
    const flip_files = sq_mask & 0b000111 != 0;
    const flip_ranks = sq_mask & 0b111000 != 0;
    var below: u64 = (@as(u64, 1) << @intCast(from_p)) - 1;
    if (flip_files and flip_ranks) {
        below = @bitReverse(below);
    } else if (flip_files) {
        below = @bitReverse(@byteSwap(below));
    } else if (flip_ranks) {
        below = @byteSwap(below);
    }
    return below;
}

pub fn collectRefreshThreats(out: []u16, board: *const Board, colour: Colour) usize {
    const occ = board.occupancy();
    const king_sq = Square.fromBitboard(board.kingFor(colour));
    const piece_bbs = board.pieceBBs();

    const sq_mask = perspectiveSquareMask(colour, king_sq);

    var victim_mask: [6]u64 = @splat(0);
    inline for (0..6) |apt| {
        inline for (0..6) |vpt| {
            if (PIECE_TARGET_MAP[apt][vpt] != -1) victim_mask[apt] |= piece_bbs[vpt];
        }
    }

    var n: usize = 0;
    var attackers_it = Bitboard.iterator(occ & ~board.kings());
    while (attackers_it.next()) |attacker_sq| {
        const attacker = board.colouredPieceOn(attacker_sq).?;
        const apt = attacker.toPieceType();

        const attacks = switch (apt) {
            .pawn => Bitboard.pawnAttacks(attacker_sq, attacker.toColour()),
            .knight => Bitboard.knightMoves(attacker_sq),
            .bishop => root.attacks.bishopAttacks(attacker_sq, occ),
            .rook => root.attacks.rookAttacks(attacker_sq, occ),
            .queen => root.attacks.queenAttacks(attacker_sq, occ),
            .king => unreachable,
        };

        const below = perspectiveBelow(attacker_sq, sq_mask);
        const same_type = piece_bbs[apt.toInt()];
        const attacked = attacks & victim_mask[apt.toInt()] & (~same_type | below);

        var victims_it = Bitboard.iterator(attacked);
        while (victims_it.next()) |victim_sq| {
            const victim = board.colouredPieceOnUnchecked(victim_sq);
            const idx = threatIndexUnchecked(colour, king_sq, attacker, attacker_sq, victim, victim_sq);
            out[n] = @intCast(idx + arch.TOTAL_PAWN_PAIRS);
            n += 1;
        }
    }
    return n;
}
