const std = @import("std");
const lib = @import("lib.zig");

const Piece = lib.Piece;
const PieceType = lib.PieceType;

const bytes_per_piece: usize = @sizeOf(u64) + 64 - 1;
const bytes_per_side: usize = bytes_per_piece * PieceType.all.len;
const castling_bytes: usize = @sizeOf(u64) + 16 - 1;
const en_passant_bytes: usize = @sizeOf(u64) + 8 - 1;
const bytes_for_side: usize = @sizeOf(u64);
const data = blk: {
    var res: [bytes_per_side * 2 + castling_bytes + en_passant_bytes + bytes_for_side]u8 = undefined;
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
    const offset = @intFromEnum(piece.getType()) * bytes_per_piece + piece.getLoc() + if (side == .white) bytes_per_side else 0;
    return std.mem.readInt(u64, data[offset..][0..8], native_endianness);
}

pub fn getCastling(rights: u4) u64 {
    return std.mem.readInt(u64, data[bytes_per_side * 2 ..][rights..][0..@sizeOf(u64)], native_endianness);
}

pub fn getEnPassant(where: u6) u64 {
    const file = where % 8;
    return std.mem.readInt(u64, data[bytes_per_side * 2 + castling_bytes ..][file..][0..@sizeOf(u64)], native_endianness);
}

pub fn getTurn() u64 {
    return std.mem.readInt(u64, data[bytes_per_side * 2 + castling_bytes + en_passant_bytes ..][0..@sizeOf(u64)], native_endianness);
}
