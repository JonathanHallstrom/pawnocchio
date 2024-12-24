const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;


const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const Move = @import("Move.zig");
const Board = @import("Board.zig");

const eval = @import("eval.zig").eval;
const engine = @import("engine.zig");

const shouldStopSearching = engine.shouldStopSearching;

fn search() struct { i16, Move } {}

fn iterativeDeepening(board: Board, max_depth: u8, searchParams: engine.SearchParams) struct { i16, Move } {
    _ = searchParams; // autofix
    _ = board; // autofix
    _ = max_depth; // autofix

}
