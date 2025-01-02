const Move = @import("Move.zig");
const Square = @import("square.zig").Square;
const Piece = @import("Piece.zig");

move: Move,
halfmove: u8,
castling: u4,
en_passant: ?Square,
captured: ?Piece,
zobrist: u64, // couldn't be bothered updating zobrist in undomove
