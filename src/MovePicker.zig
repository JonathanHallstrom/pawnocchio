const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const SEE = @import("see.zig");

quietsmoves: [256]ScoredMove,

const ScoredMove = struct {
    move: Move,
    score: i16,

    pub fn init(move: Move) ScoredMove {
        return .{
            .move = move,
            .score = 0,
        };
    }
};

const Self = @This();

pub fn init(comptime turn: Side, board: *const Board, tt_move: Move, previous_move: Move, ply: u8) Self {
    _ = turn; // autofix
    _ = board; // autofix
    _ = tt_move; // autofix
    _ = previous_move; // autofix
    _ = ply; // autofix
}

export const pointer_to_decl_pointers = blk: {
    var res: []const *const anyopaque = &.{};
    for (std.meta.declarations(@This())) |decl| {
        if (std.mem.eql(u8, decl.name, "panic")) continue;
        res = res ++ &[_]*const anyopaque{@ptrCast(&@field(@This(), decl.name))};
    }
    break :blk res.ptr;
};
