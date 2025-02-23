const std = @import("std");
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const Side = @import("side.zig").Side;
const PieceType = @import("piece_type.zig").PieceType;
const SEE = @import("see.zig");

moves: [256]Move,

const Self = @This();

pub fn init(comptime turn: Side, board: *const Board, tt_move: Move, previous_move: Move, ply: u8) Self {}
