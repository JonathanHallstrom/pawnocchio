const std = @import("std");
const Square = @import("square.zig").Square;
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

pub fn fromSquare(square: Square) u64 {
    return @as(u64, 1) << square.toInt();
}

pub const all_left = rayArray(0, -1);
pub const all_right = rayArray(0, 1);
pub const all_forward = rayArray(1, 0);
pub const all_backward = rayArray(-1, 0);

pub const rook_ray_between: [64][64]u64 = blk: {
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

pub const bishop_ray_between: [64][64]u64 = blk: {
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

pub const queen_ray_between: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    for (0..64) |from| {
        res[from] = @as(@Vector(64, u64), bishop_ray_between[from]) | rook_ray_between[from];
    }
    break :blk res;
};

pub const rook_ray_between_inclusive: [64][64]u64 = blk: {
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

pub const bishop_ray_between_inclusive: [64][64]u64 = blk: {
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

pub const queen_ray_between_inclusive: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    for (0..64) |from| {
        res[from] = @as(@Vector(64, u64), bishop_ray_between_inclusive[from]) | rook_ray_between_inclusive[from];
    }
    break :blk res;
};

pub const rook_ray_between_exclusive: [64][64]u64 = blk: {
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

pub const bishop_ray_between_exclusive: [64][64]u64 = blk: {
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

pub const queen_ray_between_exclusive: [64][64]u64 = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [64][64]u64 = undefined;
    for (0..64) |from| {
        res[from] = @as(@Vector(64, u64), bishop_ray_between_exclusive[from]) | rook_ray_between_exclusive[from];
    }
    break :blk res;
};

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
