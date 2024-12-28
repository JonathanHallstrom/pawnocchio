const knight_moves = @import("knight_moves.zig");
const pawn_moves = @import("pawn_moves.zig");
const getAllKnightMoves = knight_moves.getAllKnightMoves;
const getAllPawnMoves = pawn_moves.getAllPawnMoves;

test {
    _ = knight_moves;
    _ = pawn_moves;
}
