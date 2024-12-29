const knight_moves = @import("knight_moves.zig");
const pawn_moves = @import("pawn_moves.zig");
const sliding_moves = @import("sliding_moves.zig");

const getAllKnightMoves = knight_moves.getAllKnightMoves;
const getAllPawnMoves = pawn_moves.getAllPawnMoves;
const getAllSlidingMoves = sliding_moves.getSlidingMoves;

test "all movegen tests" {
    _ = knight_moves;
    _ = pawn_moves;
    _ = sliding_moves;
}
