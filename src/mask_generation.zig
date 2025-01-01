const std = @import("std");
const assert = std.debug.assert;
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

    var num_checks: usize = 0;
    inline for (Bitboard.rook_d_ranks, Bitboard.rook_d_files) |d_rank, d_file| {
        const ray = Bitboard.ray(king, d_rank, d_file);

        const blockers = ray & occ;

        const threats = blockers & rooks;
        const non_threats = blockers & ~rooks;
        const threat_ray = Bitboard.ray(threats, d_rank, d_file);

        const check_blocking_pieces = non_threats & ray & ~threat_ray;

        const num_in_between = @popCount(check_blocking_pieces);

        rook_pins |= if (num_in_between == 1 and threats != 0 and ray & ~threat_ray & us.all != 0) ray & ~threat_ray else 0;
        checks |= if (num_in_between == 0 and threats != 0) ray & ~threat_ray else 0;
        num_checks += @intFromBool(num_in_between == 0 and threats != 0);
    }
    inline for (Bitboard.bishop_d_ranks, Bitboard.bishop_d_files) |d_rank, d_file| {
        const ray = Bitboard.ray(king, d_rank, d_file);

        const blockers = ray & occ;

        const threats = blockers & bishops;
        const non_threats = blockers & ~bishops;
        const threat_ray = Bitboard.ray(threats, d_rank, d_file);

        const check_blocking_pieces = non_threats & ray & ~threat_ray;

        const num_in_between = @popCount(check_blocking_pieces);

        bishop_pins |= if (num_in_between == 1 and threats != 0 and ray & ~threat_ray & us.all != 0) ray & ~threat_ray else 0;
        checks |= if (num_in_between == 0 and threats != 0) ray & ~threat_ray else 0;
        num_checks += @intFromBool(num_in_between == 0 and threats != 0);
    }

    checks |= knight_moves.knight_moves_arr[king_loc.toInt()] & them.getBoard(.knight);
    num_checks += @intFromBool(knight_moves.knight_moves_arr[king_loc.toInt()] & them.getBoard(.knight) != 0);

    const pawn_d_rank: i8 = if (turn == .white) 1 else -1;

    const pawn_threats_left = Bitboard.move(king, pawn_d_rank, -1) & them.getBoard(.pawn);
    const pawn_threats_right = Bitboard.move(king, pawn_d_rank, 1) & them.getBoard(.pawn);
    checks |= pawn_threats_left;
    num_checks += @intFromBool(pawn_threats_left != 0);
    checks |= pawn_threats_right;
    num_checks += @intFromBool(pawn_threats_right != 0);

    if (checks == 0) checks = ~checks;
    if (num_checks > 1) checks = 0;

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
        .bishop_pins = Bitboard.bishop_ray_between[Square.d8.toInt()][Square.f6.toInt()],
        .rook_pins = Bitboard.rook_ray_between[Square.d8.toInt()][Square.d6.toInt()],
    }, getMasks(.black, Board.parseFen("3k4/3nn3/3R1B2/8/8/8/2P5/1K6 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = ~zero,
        .bishop_pins = Bitboard.bishop_ray_between[Square.d8.toInt()][Square.f6.toInt()],
        .rook_pins = Bitboard.rook_ray_between[Square.d8.toInt()][Square.d6.toInt()],
    }, getMasks(.black, Board.parseFen("3k4/3nn3/3R1B2/3R4/7Q/8/2P5/1K6 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = ~zero,
        .bishop_pins = Bitboard.bishop_ray_between[Square.d5.toInt()][Square.a2.toInt()],
        .rook_pins = Bitboard.rook_ray_between[Square.d5.toInt()][Square.d2.toInt()] | Bitboard.rook_ray_between[Square.d5.toInt()][Square.h5.toInt()],
    }, getMasks(.black, Board.parseFen("8/8/8/3kn2Q/2pn4/8/B1PR4/1K6 b - - 0 1") catch unreachable));
    try std.testing.expectEqualDeep(Masks{
        .checks = Square.c7.toBitboard(),
        .bishop_pins = 0,
        .rook_pins = 0,
    }, getMasks(.black, Board.parseFen("3k4/2P5/8/8/8/8/8/1K6 b - - 0 1") catch unreachable));
}
