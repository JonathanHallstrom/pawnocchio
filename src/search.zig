const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const lib = @import("lib.zig");

const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const BitBoard = lib.BitBoard;
const Piece = lib.Piece;
const PieceType = lib.PieceType;
const Move = lib.Move;
const Board = lib.Board;

const eval = @import("eval.zig").eval;
const engine = @import("engine.zig");

const shouldStopSearching = engine.shouldStopSearching;

fn search() struct { i16, Move } {}

fn iterativeDeepening(board: Board, max_depth: u8, searchParams: engine.SearchParams) struct { i16, Move } {
    _ = board; // autofix
    _ = max_depth; // autofix

}
