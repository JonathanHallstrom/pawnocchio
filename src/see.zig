const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const eval = @import("eval.zig");
const move_ordering = @import("move_ordering.zig");
const Square = @import("square.zig").Square;
const Bitboard = @import("Bitboard.zig");
const PieceType = @import("piece_type.zig").PieceType;
const magics = @import("magics.zig");
const knight_moves = @import("knight_moves.zig");
const king_moves = @import("king_moves.zig");

// based on impl in https://github.com/SnowballSH/Avalanche/blob/c44569afbee44716e18a9698430c1016438d3874/src/engine/see.zig

const SEE_weight = [_]i16{ 93, 308, 346, 521, 994, 0 };

fn getAttacks(comptime turn: anytype, comptime tp: PieceType, sq: Square, occ: u64) u64 {
    return switch (tp) {
        .pawn => Bitboard.move(sq.toBitboard(), if (turn == .white) -1 else 1, 1) | Bitboard.move(sq.toBitboard(), if (turn == .white) -1 else 1, -1),
        .knight => knight_moves.knight_moves_arr[sq.toInt()],
        .bishop => magics.getBishopAttacks(sq, occ),
        .rook => magics.getRookAttacks(sq, occ),
        .queen => magics.getBishopAttacks(sq, occ) | magics.getRookAttacks(sq, occ),
        .king => king_moves.king_moves_arr[sq.toInt()],
    };
}

pub fn value(piece_type: PieceType) i16 {
    return SEE_weight[piece_type.toInt()];
}

pub fn scoreMove(board: *const Board, move: Move, threshold: i32) bool {
    const from = move.getFrom();
    const to = move.getTo();
    const from_type = board.mailbox[from.toInt()].?;
    const captured_type: ?PieceType = if (move.isEnPassant()) .pawn else board.mailbox[to.toInt()];
    const captured_value: i16 = if (move.isCapture()) SEE_weight[captured_type.?.toInt()] else 0;

    var score = captured_value - threshold;
    if (move.getPromotedPieceType()) |pt| {
        const promo_value = SEE_weight[pt.toInt()];
        score += promo_value - SEE_weight[0]; // add promoted piece, remove pawn since it disappears
        if (score < 0) return false; // if we're worse off than we need to be even just after promoting and possibly capturing, theres no point continuing

        score -= promo_value; // remove the promoted piece, assuming it was captured, if we're still okay even assuming we lose it immeditely, we're good!
        if (score >= 0) return true;
    } else {
        if (score < 0) return false; // if the capture is immeditely not good enough just return
        score -= SEE_weight[from_type.toInt()];
        if (score >= 0) return true; // if we can lose the piece we used to capture and still be okay, we're good!
    }

    var occ = (board.white.all | board.black.all) & ~from.toBitboard() & ~to.toBitboard();
    const kings = board.white.getBoard(.king) | board.black.getBoard(.king);
    const queens = board.white.getBoard(.queen) | board.black.getBoard(.queen);
    const rooks = board.white.getBoard(.rook) | board.black.getBoard(.rook) | queens;
    const bishops = board.white.getBoard(.bishop) | board.black.getBoard(.bishop) | queens;
    const knights = board.white.getBoard(.knight) | board.black.getBoard(.knight);

    var stm = board.turn.flipped();

    var attackers =
        (getAttacks(undefined, .king, to, occ) & kings) |
        (getAttacks(undefined, .knight, to, occ) & knights) |
        (getAttacks(undefined, .bishop, to, occ) & bishops) |
        (getAttacks(undefined, .rook, to, occ) & rooks) |
        (getAttacks(.white, .pawn, to, occ) & board.white.getBoard(.pawn)) |
        (getAttacks(.black, .pawn, to, occ) & board.black.getBoard(.pawn));

    var attacker: PieceType = undefined;
    while (true) {
        if (attackers & board.getSide(stm).all == 0)
            break;
        for (PieceType.all) |pt| {
            const potential_attacker_board = board.getSide(stm).getBoard(pt) & attackers;
            if (potential_attacker_board != 0) {
                occ ^= potential_attacker_board & -%potential_attacker_board;
                attacker = pt;
                break;
            }
        }
        // if our last attacker is the king, and they still have an attacker, we can't actually recapture
        if (attacker == .king and attackers & board.getSide(stm.flipped()).all != 0) break;

        switch (attacker) {
            .pawn, .bishop => attackers |= getAttacks(undefined, .bishop, to, occ),
            .rook => attackers |= getAttacks(undefined, .rook, to, occ),
            .queen => attackers |= getAttacks(undefined, .queen, to, occ),
            else => {},
        }

        attackers &= occ;
        score = -score - 1 - SEE_weight[attacker.toInt()];
        stm = stm.flipped();

        if (score >= 0) {
            break;
        }
    }
    return stm != board.turn;
}

test scoreMove {
    try std.testing.expect(scoreMove(&(Board.parseFen("k6b/8/8/8/8/8/1p6/BK6 w - - 0 1") catch unreachable), Move.initCapture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2p5/1p6/BK6 w - - 0 1") catch unreachable), Move.initCapture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k7/8/8/8/8/2p5/1p6/BK6 w - - 0 1") catch unreachable), Move.initCapture(.a1, .b2), 93));
    try std.testing.expect(scoreMove(&(Board.parseFen("k7/8/8/8/8/2q5/1p6/BK6 w - - 0 1") catch unreachable), Move.initCapture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k6b/8/8/8/8/2q5/1p6/BK6 w - - 0 1") catch unreachable), Move.initCapture(.a1, .b2), 93));
    try std.testing.expect(!scoreMove(&(Board.parseFen("k3n2r/3P4/8/8/8/8/8/1K6 w - - 0 1") catch unreachable), Move.initPromotionCapture(.d7, .e8, .queen), 500));
    try std.testing.expect(scoreMove(&(Board.parseFen("k3n3/3P4/8/8/8/8/8/1K6 w - - 0 1") catch unreachable), Move.initPromotionCapture(.d7, .e8, .queen), 500));
}
