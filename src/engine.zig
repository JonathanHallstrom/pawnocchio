const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const Board = @import("Board.zig");
const Move = @import("Move.zig");

const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const Search = @import("search.zig");

pub const SearchParameters = union(enum) {
    standard: struct { soft: u64, hard: u64 },
    fixed_time: u64,
    fixed_depth: u8,
};

pub const SearchResult = struct {
    move: Move,
    score: i16,
    nodes_searched: u64,
    time_used: u64,
};

var is_searching: std.atomic.Value(bool) align(std.atomic.cache_line) = .{ .raw = false };
var stop_searching: std.atomic.Value(bool) align(std.atomic.cache_line) = .{ .raw = false };
var search_thread: ?std.Thread = null;
var search_params: ?SearchParameters = null;

fn worker() noreturn {
    while (true) {
        if (is_searching.load(.acquire)) {} else {
            // std.Thread.yield();
        }
    }
}

pub fn startAsyncSearch(board: Board, search_parameters: SearchParameters, move_buf: []Move) void {
    if (search_thread == null) {
        search_thread = std.Thread.spawn(.{}, worker, .{}) catch @panic("couldn't spawn thread");
    }

    _ = move_buf; // autofix
    _ = board; // autofix
    _ = search_parameters; // autofix

}

pub fn shouldStopSearching() bool {
    return stop_searching.load(.acquire);
}

pub fn stopAsyncSearch() void {
    if (is_searching.load(.acquire))
        stop_searching.store(true, .release);
}

pub fn searchSync(board: Board, search_parameters: SearchParameters, move_buf: []Move) SearchResult {
    _ = board; // autofix
    _ = search_parameters; // autofix
    _ = move_buf; // autofix
    unreachable;
}
