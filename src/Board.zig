const std = @import("std");
const Side = @import("Side.zig");
const Board = @This();

// starting pos
// 8 r n b q k b n r
// 7 p p p p p p p p
// 6
// 5
// 4
// 3
// 2 P P P P P P P P
// 1 R N B Q K B N R
//   A B C D E F G H

// indices
// 8 56 57 58 59 60 61 62 63
// 7 48 49 50 51 52 53 54 55
// 6 40 41 42 43 44 45 46 47
// 5 32 33 34 35 36 37 38 39
// 4 24 25 26 27 28 39 30 31
// 3 16 17 18 19 20 21 22 23
// 2  8  9 10 11 12 13 14 15
// 1  0  1  2  3  4  5  6  7
//    A  B  C  D  E  F  G  H

turn: Side = .white,
// if u can castle queenside as white `C1` will be set
castling_squares: u4 = 0,
en_passant_target: ?u6 = null,

halfmove_clock: u8 = 0,
fullmove_clock: u64 = 1,
zobrist: u64 = 0,

const Self = @This();
