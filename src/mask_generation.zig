const std = @import("std");
const Bitboard = @import("Bitboard.zig");
const Board = @import("Board.zig");
const Square = @import("square.zig").Square;
const Side = @import("side.zig").Side;

const knight_moves = @import("knight_moves.zig");

pub const Masks = struct {
    checks: u64,
    bishop_pins: u64,
    rook_pins: u64,
};

pub fn getMasks(comptime turn: Side, board: Board) Masks {
    const occ = board.white.all | board.black.all;
    const us = board.getSide(turn);
    const them = board.getSide(turn.flipped());
    const rooks = them.getBoard(.rook) | them.getBoard(.queen);
    const bishops = them.getBoard(.bishop) | them.getBoard(.queen);

    var bishop_pins: u64 = 0;
    var rook_pins: u64 = 0;
    var checks: u64 = 0;
    const king = us.getBoard(.king);
    const king_loc = Square.fromBitboard(king);

    inline for (Bitboard.rook_d_ranks, Bitboard.rook_d_files) |d_rank, d_file| {
        const ray = Bitboard.ray(king, d_rank, d_file);

        const blockers = ray & occ;

        const threats = blockers & rooks;
        const non_threats = blockers & ~rooks;
        const non_threat_ray = Bitboard.ray(non_threats, d_rank, d_file);
        const threat_ray = ray & ~non_threat_ray;
        rook_pins |= if (threats & non_threat_ray != 0) ray else 0;
        checks |= if (threats & ~non_threat_ray != 0) threat_ray else 0;
    }
    inline for (Bitboard.bishop_d_ranks, Bitboard.bishop_d_files) |d_rank, d_file| {
        const ray = Bitboard.ray(king, d_rank, d_file);

        const blockers = ray & occ;

        const threats = blockers & bishops;
        const non_threats = blockers & ~bishops;
        const non_threat_ray = Bitboard.ray(non_threats, d_rank, d_file);
        const threat_ray = ray & ~non_threat_ray;
        bishop_pins |= if (threats & non_threat_ray != 0) ray else 0;
        checks |= if (threats & ~non_threat_ray != 0) threat_ray else 0;
    }

    checks |= knight_moves.knight_moves_arr[king_loc.toInt()] & them.getBoard(.knight);

    if (checks == 0) checks = ~checks;

    return Masks{
        .checks = checks,
        .bishop_pins = bishop_pins,
        .rook_pins = rook_pins,
    };
}

pub fn getWhiteMasks(board: Board) Masks {
    return getMasks(.white, board);
}

export const pointer_to_decl_pointers = blk: {
    var res: []const *const anyopaque = &.{};
    for (std.meta.declarations(@This())) |decl| {
        if (std.mem.eql(u8, decl.name, "panic")) continue;
        res = res ++ &[_]*const anyopaque{@ptrCast(&@field(@This(), decl.name))};
    }
    break :blk res.ptr;
};

test "mask generation" {
    const zero: u64 = 0;
    const ray_down_from_d8 = Bitboard.ray(Square.d8.toBitboard(), -1, 0);
    const ray_down_right_from_d8 = Bitboard.ray(Square.d8.toBitboard(), -1, 1);
    try std.testing.expectEqualDeep(Masks{
        .checks = ~zero,
        .bishop_pins = 0,
        .rook_pins = ray_down_from_d8,
    }, getMasks(.black, Board.parseFen("3k4/8/3q4/8/8/8/2P5/1K1R4 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = ray_down_from_d8,
        .bishop_pins = 0,
        .rook_pins = 0,
    }, getMasks(.black, Board.parseFen("3k4/8/2q5/8/8/8/2P5/1K1R4 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = ray_down_right_from_d8,
        .bishop_pins = 0,
        .rook_pins = 0,
    }, getMasks(.black, Board.parseFen("3k4/8/2q5/8/7B/8/2P5/1K6 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = ~zero,
        .bishop_pins = ray_down_right_from_d8,
        .rook_pins = 0,
    }, getMasks(.black, Board.parseFen("3k4/8/5q2/8/7B/8/2P5/1K6 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = ~zero,
        .bishop_pins = ray_down_right_from_d8,
        .rook_pins = ray_down_from_d8,
    }, getMasks(.black, Board.parseFen("3k4/3nn3/8/8/7B/8/2P5/1K1R4 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = Square.e6.toBitboard(),
        .bishop_pins = 0,
        .rook_pins = 0,
    }, getMasks(.black, Board.parseFen("3k4/8/4N3/8/8/8/8/1K6 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = ~zero,
        .bishop_pins = ray_down_right_from_d8,
        .rook_pins = ray_down_from_d8,
    }, getMasks(.black, Board.parseFen("3k4/3nn3/3R1B2/8/8/8/2P5/1K6 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = ~zero,
        .bishop_pins = ray_down_right_from_d8,
        .rook_pins = ray_down_from_d8,
    }, getMasks(.black, Board.parseFen("3k4/3nn3/3R1B2/3R4/7Q/8/2P5/1K6 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = ~zero,
        .bishop_pins = Bitboard.ray(Square.d5.toBitboard(), -1, -1),
        .rook_pins = Bitboard.ray(Square.d5.toBitboard(), 0, 1) | Bitboard.ray(Square.d5.toBitboard(), -1, 0),
    }, getMasks(.black, Board.parseFen("8/8/8/3kn2Q/2pn4/8/B1PR4/1K6 b - - 0 1") catch unreachable));
}
