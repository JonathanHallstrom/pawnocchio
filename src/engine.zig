const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const Board = @import("Board.zig");
const Move = @import("Move.zig").Move;

const log_writer = &@import("main.zig").log_writer;
const write = @import("main.zig").write;

const search = @import("search.zig");

pub const setTTSize = search.setTTSize;

pub const SearchParameters = struct {
    soft_time: ?u64 = null,
    hard_time: ?u64 = null,
    depth: ?u8 = null,
    nodes: ?u64 = null,
    frc: bool = false,
    comptime datagen: bool = false,

    pub fn softTime(self: SearchParameters) u64 {
        return self.soft_time orelse std.math.maxInt(u64);
    }

    pub fn hardTime(self: SearchParameters) u64 {
        return self.hard_time orelse std.math.maxInt(u64);
    }

    pub fn maxDepth(self: SearchParameters) u8 {
        return self.depth orelse 255;
    }

    pub fn maxNodes(self: SearchParameters) u64 {
        return self.nodes orelse std.math.maxInt(u64);
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

var is_searching: std.atomic.Value(bool) align(std.atomic.cache_line) = std.atomic.Value(bool).init(false);
var stop_searching: std.atomic.Value(bool) align(std.atomic.cache_line) = std.atomic.Value(bool).init(false);
pub var infinite: std.atomic.Value(bool) align(std.atomic.cache_line) = std.atomic.Value(bool).init(false);
var thread_pool: ?std.Thread.Pool = null;

pub fn startAsyncSearch(board: Board, search_parameters: SearchParameters, move_buf: []Move, hash_history: *std.ArrayList(u64)) void {
    if (thread_pool == null) {
        thread_pool = @as(std.Thread.Pool, undefined);
        thread_pool.?.init(.{
            .allocator = std.heap.page_allocator,
            .n_jobs = 1,
        }) catch @panic("sadge");
    }
    stopAsyncSearch();

    const worker = struct {
        fn impl(board_: Board, search_params_: SearchParameters, move_buf_: []Move, hash_history_: *std.ArrayList(u64)) void {
            is_searching.store(true, .release);
            stop_searching.store(false, .release);
            _ = search.iterativeDeepening(board_, search_params_, move_buf_, hash_history_, false);
        }
    }.impl;

    thread_pool.?.spawn(worker, .{
        board,
        search_parameters,
        move_buf,
        hash_history,
    }) catch @panic("sadge");
}

pub fn reset() void {
    if (thread_pool == null) {
        thread_pool = @as(std.Thread.Pool, undefined);
        thread_pool.?.init(.{
            .allocator = std.heap.page_allocator,
            .n_jobs = 1,
        }) catch @panic("sadge");
    }
    stopAsyncSearch();
    search.resetHard();
}

pub fn shouldKeepSearching() bool {
    return is_searching.load(.seq_cst);
}

pub fn shouldStopSearching() bool {
    return stop_searching.load(.seq_cst);
}

pub fn stopAsyncSearch() void {
    if (is_searching.load(.seq_cst)) {
        is_searching.store(false, .seq_cst);
        infinite.store(false, .seq_cst);
        stop_searching.store(true, .seq_cst);
    }
}

pub fn stoppedSearching() void {
    is_searching.store(false, .seq_cst);
}

pub fn setInfinite() void {
    infinite.store(true, .seq_cst);
}

pub fn waitUntilWritingBestMoveAllowed() void {
    while (infinite.load(.seq_cst)) {
        std.time.sleep(1);
    }
}

pub fn searchSync(board: Board, search_parameters: SearchParameters, move_buf: []Move, hash_history: *std.ArrayList(u64), silence_output: bool) SearchResult {
    return search.iterativeDeepening(board, search_parameters, move_buf, hash_history, silence_output);
}

fn bestMove(fen: []const u8, nodes: u64, moves: []const u8, allocator: std.mem.Allocator) !Move {
    var board = try Board.parseFen(fen);

    const bignum = 32768;
    const move_buf: []Move = try allocator.alloc(Move, bignum);
    defer allocator.free(move_buf);
    var hash_history = try std.ArrayList(u64).initCapacity(allocator, bignum);
    defer hash_history.deinit();
    hash_history.appendAssumeCapacity(board.zobrist);
    var iter = std.mem.tokenizeScalar(u8, moves, ' ');
    while (iter.next()) |move| {
        _ = try board.playMoveFromStr(move);
        hash_history.appendAssumeCapacity(board.zobrist);
    }
    @import("move_ordering.zig").reset();
    try search.setTTSize(256);
    return searchSync(board, .{ .nodes = nodes }, move_buf, &hash_history, true).move;
}

test "50 move rule" {
    try std.testing.expectEqual(Move.initQuiet(.h6, .h7), bestMove("1R6/8/7P/8/3B4/k2B4/8/2K5 w - - 99 67", 20 << 10, "", std.testing.allocator));
    try std.testing.expectEqual(Move.initQuiet(.c7, .a7), bestMove("1R6/2R5/7P/8/8/k7/8/2K5 w - - 99 67", 20 << 10, "", std.testing.allocator));
    try std.testing.expectEqual(Move.initCapture(.f4, .g6), bestMove("1R6/8/6p1/8/5N2/k7/8/2KR4 w - - 99 67", 20 << 10, "", std.testing.allocator));
}

test "repetitions" {
    try std.testing.expect(Move.initQuiet(.c6, .d5) != try bestMove("1R6/8/7P/2BB4/8/8/k7/2K5 b - - 8 62", 20 << 10, "a2a1 d5c6 a1a2 c6d5 a2a1 d5c6 a1a2", std.testing.allocator));
}

test "random position where king has to cross middle, should test that accumulator refreshes are working" {
    try std.testing.expectEqual(Move.initQuiet(.d5, .e5), bestMove("2rr4/8/8/n1nK2k1/8/8/8/8 w - - 0 1", 20 << 10, "", std.testing.allocator));
    try std.testing.expectEqual(Move.initQuiet(.d5, .e5), bestMove("2RR4/8/8/N1Nk2K1/8/8/8/8 b - - 0 1", 20 << 10, "", std.testing.allocator));
}
