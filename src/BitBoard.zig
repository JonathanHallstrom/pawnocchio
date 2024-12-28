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

pub fn contains(bitboard: u64, square: Square) bool {
    return bitboard >> square.toInt() & 1 != 0;
}

pub fn allDirectionArray(d_rank: anytype, d_file: anytype) [64]u64 {
    var res: [64]u64 = undefined;
    inline for (0..64) |i| {
        res[i] = allDirection(1 << i, d_rank, d_file);
    }
    return res;
}

pub fn allDirection(bitboard: u64, d_rank: anytype, d_file: anytype) u64 {
    var res = bitboard;
    res |= move(res, d_rank * 1, d_file * 1);
    res |= move(res, d_rank * 2, d_file * 2);
    res |= move(res, d_rank * 4, d_file * 4);
    return res;
}

pub fn fromSquare(square: Square) u64 {
    return @as(u64, 1) << square.toInt();
}

pub const all_left = blk: {
    @setEvalBranchQuota(1 << 30);
    break :blk allDirectionArray(0, -1);
};
pub const all_right = blk: {
    @setEvalBranchQuota(1 << 30);
    break :blk allDirectionArray(0, 1);
};
pub const all_forward = blk: {
    @setEvalBranchQuota(1 << 30);
    break :blk allDirectionArray(1, 0);
};
pub const all_backward = blk: {
    @setEvalBranchQuota(1 << 30);
    break :blk allDirectionArray(-1, 0);
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
