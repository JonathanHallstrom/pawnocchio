const Move = @import("Move.zig").Move;
const Square = @import("square.zig").Square;
const Piece = @import("Piece.zig");

move: Move,
halfmove: u8,
castling: u4,
en_passant: ?Square,
captured: ?Piece,
zobrist: u64,
pawn_zobrist: u64,
