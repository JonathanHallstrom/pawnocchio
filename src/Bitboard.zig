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
const Square = root.Square;

const assert = std.debug.assert;

pub inline fn forward(bitboard: u64, steps: u6) u64 {
    return bitboard << steps * 8;
}

pub inline fn backward(bitboard: u64, steps: u6) u64 {
    return bitboard >> steps * 8;
}

pub inline fn left(bitboard: u64, steps: u6) u64 {
    const mask = @as(u64, @as(u8, 255) >> @intCast(steps)) * (std.math.maxInt(u64) / 255);
    return bitboard >> steps & mask;
}

pub inline fn right(bitboard: u64, steps: u6) u64 {
    const mask = @as(u64, @as(u8, 255) << @intCast(steps)) * (std.math.maxInt(u64) / 255);
    return bitboard << steps & mask;
}

pub inline fn move(bitboard: u64, d_rank: anytype, d_file: anytype) u64 {
    assert(-7 <= d_rank and d_rank <= 7);
    assert(-7 <= d_file and d_file <= 7);
    var res = bitboard;
    const rank_difference: u6 = @intCast(@abs(d_rank));
    const file_difference: u6 = @intCast(@abs(d_file));
    res = if (d_rank < 0) backward(res, rank_difference) else forward(res, rank_difference);
    res = if (d_file < 0) left(res, file_difference) else right(res, file_difference);
    return res;
}

pub fn pext(src: u64, mask: u64) u64 {
    if (@inComptime() or !std.Target.x86.featureSetHas(@import("builtin").cpu.model.features, .bmi2)) {
        var res: u64 = 0;
        var i: u6, var m: u64 = .{ 0, mask };
        while (m != 0) {
            res |= ((src >> @intCast(@ctz(m))) & 1) << i;
            i += 1;
            m &= m - 1;
        }
        return res;
    } else return asm ("pextq %[mask], %[src], %[res]"
        : [res] "=r" (-> u64),
        : [src] "r" (src),
          [mask] "r" (mask),
    );
}

pub fn pdep(src: u64, mask: u64) u64 {
    if (@inComptime() or !std.Target.x86.featureSetHas(@import("builtin").cpu.model.features, .bmi2)) {
        var res: u64 = 0;
        var bit: u6 = 0;
        var m: u64 = mask;
        while (m != 0) {
            if (((src >> bit) & 1) != 0) {
                res |= m & -%m;
            }
            m &= m - 1;
            bit += 1;
        }
        return res;
    } else return asm ("pdepq %[mask], %[src], %[res]"
        : [res] "=r" (-> u64),
        : [src] "r" (src),
          [mask] "r" (mask),
    );
}

pub fn contains(bitboard: u64, square: Square) bool {
    return bitboard >> square.toInt() & 1 != 0;
}

pub fn rayArray(d_rank: anytype, d_file: anytype) [64]u64 {
    @setEvalBranchQuota(1 << 30);
    var res: [64]u64 = undefined;
    inline for (0..64) |i| {
        res[i] = ray(1 << i, d_rank, d_file);
    }
    return res;
}

pub fn rayArrayPtr(d_rank: anytype, d_file: anytype) *const [64]u64 {
    const arr: [64]u64 align(64) = comptime rayArray(d_rank, d_file);
    return &arr;
}

pub fn attackArray(d_ranks: anytype, d_files: anytype) [64]u64 {
    @setEvalBranchQuota(1 << 30);
    var res: [64]u64 = .{0} ** 64;
    inline for (0..64) |i| {
        for (d_ranks, d_files) |d_rank, d_file| {
            res[i] |= ray(1 << i, d_rank, d_file);
        }
    }
    return res;
}

pub fn attackArrayPtr(d_ranks: anytype, d_files: anytype) *const [64]u64 {
    const arr: [64]u64 align(64) = comptime attackArray(d_ranks, d_files);
    return &arr;
}

pub fn ray(bitboard: u64, d_rank: anytype, d_file: anytype) u64 {
    var res = move(bitboard, d_rank, d_file);
    res |= move(res, d_rank * 1, d_file * 1);
    res |= move(res, d_rank * 2, d_file * 2);
    res |= move(res, d_rank * 4, d_file * 4);
    return res;
}

pub fn relevantSquares(bitboard: u64, d_ranks: anytype, d_files: anytype) u64 {
    var res: u64 = 0;
    inline for (d_ranks, d_files) |d_rank, d_file| {
        var add = ray(bitboard, d_rank, d_file);
        add &= move(add, -d_rank, -d_file);
        res |= add;
    }
    return res & ~bitboard;
}
pub fn attackSquares(bitboard: u64, d_ranks: anytype, d_files: anytype) u64 {
    var res: u64 = 0;
    inline for (d_ranks, d_files) |d_rank, d_file| {
        res |= ray(bitboard, d_rank, d_file);
    }
    return res & ~bitboard;
}

pub const rook_d_ranks = [_]comptime_int{ 1, -1, 0, 0 };
pub const rook_d_files = [_]comptime_int{ 0, 0, 1, -1 };
pub fn rookRelevantSquares(bitboard: u64) u64 {
    return relevantSquares(bitboard, rook_d_ranks, rook_d_files);
}
pub fn rookAttackSquares(bitboard: u64) u64 {
    return attackSquares(bitboard, rook_d_ranks, rook_d_files);
}

pub const bishop_d_ranks = [_]comptime_int{ -1, -1, 1, 1 };
pub const bishop_d_files = [_]comptime_int{ 1, -1, 1, -1 };
pub fn bishopRelevantSquares(bitboard: u64) u64 {
    return relevantSquares(bitboard, bishop_d_ranks, bishop_d_files);
}
pub fn bishopAttackSquares(bitboard: u64) u64 {
    return attackSquares(bitboard, bishop_d_ranks, bishop_d_files);
}

pub const knight_d_ranks = [_]comptime_int{ 1, 1, -1, -1, 2, 2, -2, -2 };
pub const knight_d_files = [_]comptime_int{ 2, -2, 2, -2, 1, -1, 1, -1 };

const king_moves: [64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]u64 = undefined;
    for (0..64) |i| {
        res[i] = 1 << i;
        res[i] |= move(res[i], 1, 0);
        res[i] |= move(res[i], -1, 0);
        res[i] |= move(res[i], 0, 1);
        res[i] |= move(res[i], 0, -1);
        res[i] ^= 1 << i;
    }
    break :blk res;
};

const knight_moves: [64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]u64 = undefined;
    for (0..64) |i| {
        res[i] = 0;
        for (knight_d_ranks, knight_d_files) |dr, df| {
            res[i] |= move(1 << i, dr, df);
        }
    }
    break :blk res;
};

const pawn_attacks: [64][2]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][2]u64 = undefined;
    for (0..64) |i| {
        res[i][0] =
            move(1 << i, 1, 1) |
            move(1 << i, 1, -1); // white
        res[i][1] =
            move(1 << i, -1, 1) |
            move(1 << i, -1, -1); // black
    }
    break :blk res;
};

const bishop_attacks: [64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]u64 = undefined;
    for (0..64) |i| {
        res[i] = bishopAttackSquares(1 << i);
    }
    break :blk res;
};

const rook_attacks: [64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64]u64 = undefined;
    for (0..64) |i| {
        res[i] = rookAttackSquares(1 << i);
    }
    break :blk res;
};

const queen_attacks: [64]u64 = @as(@Vector(64, u64), bishop_attacks) | @as(@Vector(64, u64), rook_attacks);

const extending_ray_bb: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    @memset(std.mem.asBytes(&res), 0);
    for (0..64) |from| {
        for ([_][2]comptime_int{
            .{ 0, 1 },
            .{ 1, 0 },
            .{ 1, 1 },
            .{ 1, -1 },
        }) |d| {
            const dr, const df = d;
            var line: u64 = 1 << from;
            line |= move(line, dr, df);
            line |= move(line, dr * 2, df * 2);
            line |= move(line, dr * 4, df * 4);
            line |= move(line, -dr, -df);
            line |= move(line, -dr * 2, -df * 2);
            line |= move(line, -dr * 4, -df * 4);
            var iter = iterator(line);
            while (iter.next()) |sq| {
                if (sq.toInt() != from) {
                    res[from][sq.toInt()] = line;
                }
            }
        }
    }
    break :blk res;
};

const rook_ray_between: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    @memset(std.mem.asBytes(&res), 0);
    for (0..64) |from| {
        for (rook_d_ranks, rook_d_files) |d_rank, d_file| {
            const reachable = ray(Square.fromInt(@intCast(from)).toBitboard(), d_rank, d_file);
            var iter = iterator(reachable);
            while (iter.next()) |to| {
                res[from][to.toInt()] = reachable & ~ray(to.toBitboard(), d_rank, d_file);
            }
        }
    }

    break :blk res;
};

const bishop_ray_between: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    @memset(std.mem.asBytes(&res), 0);
    for (0..64) |from| {
        for (bishop_d_ranks, bishop_d_files) |d_rank, d_file| {
            const reachable = ray(Square.fromInt(@intCast(from)).toBitboard(), d_rank, d_file);
            var iter = iterator(reachable);
            while (iter.next()) |to| {
                res[from][to.toInt()] = reachable & ~ray(to.toBitboard(), d_rank, d_file);
            }
        }
    }

    break :blk res;
};

const queen_ray_between: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    for (0..64) |from| {
        res[from] = @as(@Vector(64, u64), bishop_ray_between[from]) | rook_ray_between[from];
    }
    break :blk res;
};

const rook_ray_between_inclusive: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    @memset(std.mem.asBytes(&res), 0);
    for (0..64) |f| {
        const from = Square.fromInt(@intCast(f));
        for (rook_d_ranks, rook_d_files) |d_rank, d_file| {
            const reachable = ray(from.toBitboard(), d_rank, d_file) | from.toBitboard();
            var iter = iterator(reachable);
            while (iter.next()) |to| {
                res[from.toInt()][to.toInt()] = (reachable & ~ray(to.toBitboard(), d_rank, d_file)) | from.toBitboard();
            }
        }
    }

    break :blk res;
};

const bishop_ray_between_inclusive: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    @memset(std.mem.asBytes(&res), 0);
    for (0..64) |f| {
        const from = Square.fromInt(@intCast(f));
        for (bishop_d_ranks, bishop_d_files) |d_rank, d_file| {
            const reachable = ray(from.toBitboard(), d_rank, d_file) | from.toBitboard();
            var iter = iterator(reachable);
            while (iter.next()) |to| {
                res[from.toInt()][to.toInt()] = (reachable & ~ray(to.toBitboard(), d_rank, d_file)) | from.toBitboard();
            }
        }
    }

    break :blk res;
};

const queen_ray_between_inclusive: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    for (0..64) |from| {
        res[from] = @as(@Vector(64, u64), bishop_ray_between_inclusive[from]) | rook_ray_between_inclusive[from];
    }
    break :blk res;
};

const rook_ray_between_exclusive: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    @memset(std.mem.asBytes(&res), 0);
    for (0..64) |f| {
        const from = Square.fromInt(@intCast(f));
        for (rook_d_ranks, rook_d_files) |d_rank, d_file| {
            const reachable = ray(from.toBitboard(), d_rank, d_file) | from.toBitboard();
            var iter = iterator(reachable);
            while (iter.next()) |to| {
                res[from.toInt()][to.toInt()] = reachable & ~ray(to.toBitboard(), d_rank, d_file) & ~(from.toBitboard() | to.toBitboard());
            }
        }
    }

    break :blk res;
};

const bishop_ray_between_exclusive: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    @memset(std.mem.asBytes(&res), 0);
    for (0..64) |f| {
        const from = Square.fromInt(@intCast(f));
        for (bishop_d_ranks, bishop_d_files) |d_rank, d_file| {
            const reachable = ray(from.toBitboard(), d_rank, d_file) | from.toBitboard();
            var iter = iterator(reachable);
            while (iter.next()) |to| {
                res[from.toInt()][to.toInt()] = reachable & ~ray(to.toBitboard(), d_rank, d_file) & ~(from.toBitboard() | to.toBitboard());
            }
        }
    }

    break :blk res;
};

const queen_ray_between_exclusive: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    for (0..64) |from| {
        res[from] = @as(@Vector(64, u64), bishop_ray_between_exclusive[from]) | rook_ray_between_exclusive[from];
    }
    break :blk res;
};

const check_ray_between: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    for (0..64) |from| {
        res[from] = queen_ray_between_inclusive[from];
        for (0..64) |to| {
            res[from][to] |= 1 << from;
            res[from][to] |= 1 << to;
        }
    }
    break :blk res;
};

fn idx(i: anytype) usize {
    if (std.meta.hasFn(@TypeOf(i), "toInt")) return i.toInt();
    return i;
}

pub fn kingMoves(square: anytype) u64 {
    return (&king_moves)[idx(square)];
}

pub fn knightMoves(square: anytype) u64 {
    return (&knight_moves)[idx(square)];
}

pub fn pawnAttacks(square: anytype, color: anytype) u64 {
    return (&(&pawn_attacks)[idx(square)])[idx(color)];
}

pub fn bishopAttacks(square: anytype) u64 {
    return (&bishop_attacks)[idx(square)];
}

pub fn rookAttacks(square: anytype) u64 {
    return (&rook_attacks)[idx(square)];
}

pub fn queenAttacks(square: anytype) u64 {
    return (&queen_attacks)[idx(square)];
}

pub fn extendingRayBb(from: anytype, to: anytype) u64 {
    return (&(&extending_ray_bb)[idx(from)])[idx(to)];
}

pub fn rookRayBetween(from: anytype, to: anytype) u64 {
    return (&(&rook_ray_between)[idx(from)])[idx(to)];
}

pub fn bishopRayBetween(from: anytype, to: anytype) u64 {
    return (&(&bishop_ray_between)[idx(from)])[idx(to)];
}

pub fn queenRayBetween(from: anytype, to: anytype) u64 {
    return (&(&queen_ray_between)[idx(from)])[idx(to)];
}

pub fn rookRayBetweenInclusive(from: anytype, to: anytype) u64 {
    return (&(&rook_ray_between_inclusive)[idx(from)])[idx(to)];
}

pub fn bishopRayBetweenInclusive(from: anytype, to: anytype) u64 {
    return (&(&bishop_ray_between_inclusive)[idx(from)])[idx(to)];
}

pub fn queenRayBetweenInclusive(from: anytype, to: anytype) u64 {
    return (&(&queen_ray_between_inclusive)[idx(from)])[idx(to)];
}

pub fn rookRayBetweenExclusive(from: anytype, to: anytype) u64 {
    return (&(&rook_ray_between_exclusive)[idx(from)])[idx(to)];
}

pub fn bishopRayBetweenExclusive(from: anytype, to: anytype) u64 {
    return (&(&bishop_ray_between_exclusive)[idx(from)])[idx(to)];
}

pub fn queenRayBetweenExclusive(from: anytype, to: anytype) u64 {
    return (&(&queen_ray_between_exclusive)[idx(from)])[idx(to)];
}

pub fn checkMask(from: anytype, to: anytype) u64 {
    return (&(&check_ray_between)[idx(from)])[idx(to)];
}

pub const LocIterator = struct {
    state: u64,

    pub fn init(bitboard: u64) LocIterator {
        return .{ .state = bitboard };
    }

    pub fn next(self: *LocIterator) ?Square {
        if (self.state == 0) return null;
        const res = @ctz(self.state);
        self.state &= self.state -% 1;
        return Square.fromInt(@intCast(res));
    }

    pub fn peek(self: *const LocIterator) ?Square {
        if (self.state == 0) return null;
        const res = @ctz(self.state);
        return Square.fromInt(@intCast(res));
    }
};

pub fn iterator(bitboard: u64) LocIterator {
    return LocIterator.init(bitboard);
}
