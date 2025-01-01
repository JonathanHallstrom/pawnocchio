const std = @import("std");
const movegen = @import("movegen.zig");

const Board = @import("Board.zig");
const Move = @import("Move.zig");

test "double attack promotion" {
    var buf: [256]Move = undefined;
    try std.testing.expectEqual(1, movegen.getMoves(.white, try Board.parseFen("r4kQr/p1ppq1b1/bn4p1/4N3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R b KQ - 0 3"), &buf));
}

test "pinned pawn can't capture" {
    var buf: [256]Move = undefined;
    try std.testing.expectEqual(49, movegen.getMoves(.black, try Board.parseFen("r6r/p1pkqpb1/bnp1pnp1/3P4/1p2P1B1/2NQ3p/PPPB1PPP/R3K2R b KQ - 3 3"), &buf));
}
