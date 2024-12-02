const std = @import("std");
const lib = @import("lib.zig");

const Piece = lib.Piece;
const PieceType = lib.PieceType;

const piece_entries: usize = 64;
const side_entries: usize = piece_entries * PieceType.all.len;
const castling_entries: usize = 16;
const en_passant_entries: usize = 8;
const side_diff_entries: usize = 1;
const data = blk: {
    @setEvalBranchQuota(1 << 30);
    var res: [side_entries * 2 + castling_entries + en_passant_entries + side_diff_entries + @sizeOf(u64) - 1]u8 = undefined;
    const seed: [std.Random.DefaultCsprng.secret_seed_length]u8 = .{
        83,  8,   124, 62,
        209, 228, 102, 90,
        139, 94,  247, 234,
        23,  237, 227, 83,
        185, 187, 249, 170,
        187, 168, 131, 116,
        40,  160, 121, 239,
        88,  54,  185, 83,
    };
    var prng = std.Random.DefaultCsprng.init(seed);
    prng.random().bytes(&res);
    break :blk res;
};

const native_endianness = @import("builtin").cpu.arch.endian();

pub fn get(piece: Piece, side: lib.Side) u64 {
    const offset = @intFromEnum(piece.getType()) * piece_entries + piece.getLoc() + if (side == .white) side_entries else 0;
    return std.mem.readInt(u64, data[offset..][0..8], native_endianness);
}

pub fn getCastling(rights: u4) u64 {
    return std.mem.readInt(u64, data[side_entries * 2 ..][rights..][0..@sizeOf(u64)], native_endianness);
}

pub fn getEnPassant(where: u6) u64 {
    const file = where % 8;
    return std.mem.readInt(u64, data[side_entries * 2 + castling_entries ..][file..][0..@sizeOf(u64)], native_endianness);
}

pub fn getTurn() u64 {
    return std.mem.readInt(u64, data[side_entries * 2 + castling_entries + en_passant_entries ..][0..@sizeOf(u64)], native_endianness);
}
