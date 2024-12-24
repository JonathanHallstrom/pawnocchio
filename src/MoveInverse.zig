const Move = @import("Move.zig");

move: Move,
halfmove: u8,
castling: u4,
en_passant: ?u6,
