const std = @import("std");
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
    res = if (d_rank < 0) forward(res, rank_difference) else backward(res, rank_difference);
    res = if (d_file < 0) res >> file_difference else res << file_difference;
    return res;
}

pub fn allDirection(d_rank: anytype, d_file: anytype) [64]u64 {
    var res: [64]u64 = undefined;
    inline for (0..64) |i| {
        res[i] = 1 << i;
        res[i] |= move(res[i], d_rank * 1, d_file * 1);
        res[i] |= move(res[i], d_rank * 2, d_file * 2);
        res[i] |= move(res[i], d_rank * 4, d_file * 4);
    }
}

pub const all_left = allDirection(0, -1);
pub const all_right = allDirection(0, 1);
pub const all_forward = allDirection(1, 0);
pub const all_backward = allDirection(-1, 0);
