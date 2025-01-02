const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const Board = @import("Board.zig");
const Move = @import("Move.zig");

const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const search = @import("search.zig");

pub const SearchParameters = union(enum) {
    standard: struct { soft: u64, hard: u64 },
    fixed_time: u64,
    fixed_depth: u8,

    pub fn softTime(self: SearchParameters) u64 {
        return if (self == .standard) self.standard.soft else std.math.maxInt(u64);
    }

    pub fn hardTime(self: SearchParameters) u64 {
        return if (self == .standard) self.standard.hard else std.math.maxInt(u64);
    }

    pub fn maxDepth(self: SearchParameters) u8 {
        return if (self == .fixed_depth) self.fixed_depth else 255;
    }
};

pub const SearchStatistics = struct {
    ns_used: u64 = 0,
    nodes: u64,
    qnodes: u64,
};

pub const SearchResult = struct {
    move: Move,
    score: i16,
    stats: SearchStatistics,
};

var is_searching: std.atomic.Value(bool) align(std.atomic.cache_line) = .{ .raw = false };
var stop_searching: std.atomic.Value(bool) align(std.atomic.cache_line) = .{ .raw = false };

pub fn startAsyncSearch(board: Board, search_parameters: SearchParameters, move_buf: []Move, hash_history: *std.ArrayList(u64)) void {
    stopAsyncSearch();

    const worker = struct {
        fn impl(board_: Board, search_params_: SearchParameters, move_buf_: []Move, hash_history_: *std.ArrayList(u64)) void {
            is_searching.store(true, .release);
            stop_searching.store(false, .release);
            _ = search.iterativeDeepening(board_, search_params_, move_buf_, hash_history_, false) catch unreachable;
        }
    }.impl;

    (std.Thread.spawn(.{}, worker, .{
        board,
        search_parameters,
        move_buf,
        hash_history,
    }) catch unreachable).detach();
}

pub fn reset() void {
    stopAsyncSearch();
    search.reset();
}

pub fn shouldKeepSearching() bool {
    return is_searching.load(.acquire);
}

pub fn shouldStopSearching() bool {
    return stop_searching.load(.acquire);
}

pub fn stopAsyncSearch() void {
    if (shouldKeepSearching()) {
        stop_searching.store(true, .release);
    }
}

pub fn stoppedSearching() void {
    is_searching.store(false, .release);
}

pub fn searchSync(board: Board, search_parameters: SearchParameters, move_buf: []Move, hash_history: *std.ArrayList(u64), silence_output: bool) !SearchResult {
    return search.iterativeDeepening(board, search_parameters, move_buf, hash_history, silence_output);
}
