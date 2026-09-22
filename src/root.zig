// pawnocchio, UCI chess engine
// Copyright (C) 2025 Jonathan Hallström
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const builtin = @import("builtin");

test {
    std.testing.refAllDecls(@This());
}

comptime {
    if (USE_TBS) {
        _ = pyrrhic;
    }
}

pub const USE_TBS = @import("build_options").use_tbs;
pub const TOOLS_ONLY = @import("build_options").tools_only;
pub const SEARCH_MAX_PLY: u16 = 256;
pub const SEARCH_MAX_HALFMOVE: u8 = 100;
pub const BoundedArray = @import("bounded_array.zig").BoundedArray;
pub const pyrrhic = @import("pyrrhic.zig");
pub const evaluation = @import("evaluation.zig");
pub const EvalMode = @import("eval_mode.zig").EvalMode;
pub const numa = @import("numa.zig");
pub const EVAL_MODE: EvalMode = std.meta.stringToEnum(EvalMode, @import("build_options").eval) orelse unreachable;
pub const eval_mode: EvalMode = EVAL_MODE;
pub const nnue = if (EVAL_MODE == .nnue) @import("nnue/nnue.zig") else void;
pub const simd = @import("simd.zig");
pub const Bitboard = @import("Bitboard.zig");
pub const cuckoo = @import("cuckoo.zig");
pub const Board = @import("Board.zig");
pub const LeanBoard = @import("LeanBoard.zig");
pub const Move = @import("move.zig").Move;
pub const MoveType = @import("move.zig").MoveType;
pub const movegen = @import("movegen.zig");
pub const attacks = @import("attacks.zig");
pub const zobrist = @import("zobrist.zig");
pub const PerftEPDParser = @import("PerftEPDParser.zig");
pub const Searcher = if (TOOLS_ONLY) void else @import("Searcher.zig");
pub const ThreadPool = if (TOOLS_ONLY) void else @import("ThreadPool.zig").ThreadPool;
pub const engine = if (TOOLS_ONLY) struct {
    fn deinit() void {}
} else @import("engine.zig");
pub const Limits = if (TOOLS_ONLY) void else @import("Limits.zig");
pub const MovePicker = @import("MovePicker.zig");
pub const CastlingRights = @import("CastlingRights.zig");
pub const history = @import("history.zig");
pub const tuning = @import("tuning.zig");
pub const TUNABLE_CONSTANTS = tuning.TUNABLE_CONSTANTS;
pub const SEE = @import("SEE.zig");
pub const refreshCache = @import("refresh_cache.zig").refreshCache;
pub const dataformat = @import("dataformat.zig");
pub const viriformat = @import("viriformat.zig");
pub const pgn = @import("pgn.zig");
pub const wdl = @import("wdl.zig");
pub const fit_wdl = @import("fit_wdl.zig");
pub const input_features = @import("nnue/features.zig");
pub const PSQTFeature = input_features.PSQTFeature;
pub const FeatureKind = input_features.FeatureKind;
pub const fastmath = @import("fastmath.zig");

const assert = std.debug.assert;

pub const WDL = enum(u8) {
    win = 2,
    draw = 1,
    loss = 0,

    pub inline fn toInt(self: WDL) u8 {
        return @intFromEnum(self);
    }
    pub inline fn flipped(self: WDL) WDL {
        return @enumFromInt(2 - self.toInt());
    }
};

pub const Colour = enum(u8) {
    white = 0,
    black = 1,

    pub inline fn fromInt(i: u8) Colour {
        return @enumFromInt(i);
    }

    pub inline fn toInt(self: Colour) u8 {
        return @intFromBool(self == .black);
    }

    pub fn flipped(self: Colour) Colour {
        return fromInt(self.toInt() ^ 1);
    }
};

fn initImpl(io_init: std.Io) void {
    io = io_init;
    stdout = std.Io.File.stdout();
    if (needsNonBlockingIo(stdout.handle)) {
        stdout.flags.nonblocking = true;
    }

    stdout_wrapper = stdout.writerStreaming(io, &stdout_buf);
    stdout_writer = &stdout_wrapper.interface;
    attacks.init();
    cuckoo.init();
    numa.init() catch |e| std.debug.panic("Fatal: couldn't initialize NUMA support, error: {}\n", .{e});
    if (EVAL_MODE == .nnue) {
        nnue.init() catch |e| std.debug.panic("Fatal: couldn't initialize NNUE state, error: {}\n", .{e});
    }
    if (!TOOLS_ONLY) {
        engine.init(io_init) catch |e| std.debug.panic("Fatal: couldn't initialize the engine, error: {}\n", .{e});
    }
}

var init_mutex: std.Io.Mutex = .init;
var inited = false;

pub fn init(io_init: std.Io) void {
    init_mutex.lockUncancelable(io_init);
    defer init_mutex.unlock(io_init);
    if (inited) return;
    initImpl(io_init);
    inited = true;
}

fn deinitImpl() void {
    pyrrhic.deinit();
    if (EVAL_MODE == .nnue) {
        nnue.deinit();
    }
    numa.deinit();
    engine.deinit();
    stdout_writer.flush() catch std.debug.panic("failed to flush stdout", .{});
}

var deinit_mutex: std.Io.Mutex = .init;
var deinited = false;

pub fn deinit() void {
    deinit_mutex.lockUncancelable(io);
    defer deinit_mutex.unlock(io);
    if (deinited) return;
    deinitImpl();
    deinited = true;
}

pub const Square = enum(u8) {
    // zig fmt: off
    a1, b1, c1, d1, e1, f1, g1, h1,
    a2, b2, c2, d2, e2, f2, g2, h2,
    a3, b3, c3, d3, e3, f3, g3, h3,
    a4, b4, c4, d4, e4, f4, g4, h4,
    a5, b5, c5, d5, e5, f5, g5, h5,
    a6, b6, c6, d6, e6, f6, g6, h6,
    a7, b7, c7, d7, e7, f7, g7, h7,
    a8, b8, c8, d8, e8, f8, g8, h8,
    // zig fmt: on

    pub inline fn fromInt(int: u8) Square {
        return @enumFromInt(int);
    }

    pub inline fn toInt(self: Square) u8 {
        return @intFromEnum(self);
    }

    pub fn getFile(self: Square) File {
        return File.fromInt(@intCast(self.toInt() % 8));
    }

    pub fn getRank(self: Square) Rank {
        return Rank.fromInt(@intCast(self.toInt() / 8));
    }

    pub fn fromBitboard(bitboard: u64) Square {
        assert(@popCount(bitboard) == 1);
        return fromInt(@intCast(@ctz(bitboard)));
    }

    pub fn toBitboard(self: Square) u64 {
        return @as(u64, 1) << @intCast(self.toInt());
    }

    pub fn fromRankFile(rank: anytype, file: anytype) Square {
        return Square.a1.move(rank, file);
    }

    pub fn move(self: Square, d_rank: anytype, d_file: anytype) Square {
        const actual_d_rank = if (std.meta.hasFn(@TypeOf(d_rank), "toInt")) d_rank.toInt() else d_rank;
        const actual_d_file = if (std.meta.hasFn(@TypeOf(d_file), "toInt")) d_file.toInt() else d_file;
        return fromInt(@intCast(@as(i16, self.toInt()) + @as(i8, @intCast(actual_d_rank)) * 8 + @as(i8, @intCast(actual_d_file))));
    }

    pub fn parse(square: []const u8) !Square {
        const rank = square[1] -% '1';
        if (rank > 7) return error.InvalidRank;
        const file = std.ascii.toLower(square[0]) -% 'a';
        if (file > 7) return error.InvalidFile;
        return @enumFromInt(rank * 8 + file);
    }

    pub fn flipRank(self: Square) Square {
        return fromInt(self.toInt() ^ 0b111000);
    }

    pub fn flipFile(self: Square) Square {
        return fromInt(self.toInt() ^ 0b000111);
    }

    pub fn chebyshev(self: Square, other: Square) u8 {
        return self.getRank().absDiff(other.getRank()) + self.getFile().absDiff(other.getFile());
    }
};

pub const File = enum {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,

    pub fn fromInt(int: u8) File {
        return @enumFromInt(int);
    }

    pub fn toInt(self: File) u8 {
        return @intFromEnum(self);
    }

    pub fn parse(file: u8) !File {
        const idx = std.ascii.toLower(file) -% 'a';
        if (idx >= 8) return error.InvalidFile;
        return @enumFromInt(idx);
    }

    pub fn cmp(_: void, lhs: File, rhs: File) bool {
        return @intFromEnum(lhs) < @intFromEnum(rhs);
    }

    pub fn toAsciiLetter(self: File) u8 {
        return @as(u8, 'a') + self.toInt();
    }

    pub fn absDiff(self: File, other: File) u8 {
        const ss: i16 = self.toInt();
        const so: i16 = other.toInt();
        return @intCast(@abs(ss - so));
    }
};

pub const Rank = enum {
    first,
    second,
    third,
    fourth,
    fifth,
    sixth,
    seventh,
    eighth,

    pub fn fromInt(int: u8) Rank {
        return @enumFromInt(int);
    }

    pub fn toInt(self: Rank) u8 {
        return @intFromEnum(self);
    }

    pub fn parse(rank: u8) !Rank {
        const idx = rank -% '1';
        if (idx >= 8) return error.InvalidRank;
        return @enumFromInt(idx);
    }

    pub fn cmp(_: void, lhs: Rank, rhs: Rank) bool {
        return @intFromEnum(lhs) < @intFromEnum(rhs);
    }

    pub fn absDiff(self: Rank, other: Rank) u8 {
        const ss: i16 = self.toInt();
        const so: i16 = other.toInt();
        return @intCast(@abs(ss - so));
    }
};

pub const PieceType = enum(u8) {
    pawn = 0,
    knight = 1,
    bishop = 2,
    rook = 3,
    queen = 4,
    king = 5,

    pub const all = [_]PieceType{
        .pawn,
        .knight,
        .bishop,
        .rook,
        .queen,
        .king,
    };

    pub inline fn fromInt(i: u8) PieceType {
        return @enumFromInt(i);
    }

    pub inline fn toInt(self: PieceType) u8 {
        return @intFromEnum(self);
    }

    pub fn toAsciiLetter(self: PieceType) u8 {
        return switch (self) {
            .pawn => 'p',
            .knight => 'n',
            .bishop => 'b',
            .rook => 'r',
            .queen => 'q',
            .king => 'k',
        };
    }

    pub fn fromAsciiLetter(char: u8) ?PieceType {
        return switch (std.ascii.toLower(char)) {
            'p' => .pawn,
            'n' => .knight,
            'b' => .bishop,
            'r' => .rook,
            'q' => .queen,
            'k' => .king,
            else => null,
        };
    }

    pub inline fn withColour(self: PieceType, col: Colour) ColouredPieceType {
        return ColouredPieceType.fromPieceType(self, col);
    }
};

pub const ColouredPieceType = enum(u8) {
    white_pawn = 0,
    black_pawn = 1,

    white_knight = 2,
    black_knight = 3,

    white_bishop = 4,
    black_bishop = 5,

    white_rook = 6,
    black_rook = 7,

    white_queen = 8,
    black_queen = 9,

    white_king = 10,
    black_king = 11,

    none = 12,

    pub inline fn fromInt(i: u8) ColouredPieceType {
        return @enumFromInt(i);
    }

    pub inline fn toInt(self: ColouredPieceType) u8 {
        return @intFromEnum(self);
    }

    pub inline fn fromPieceType(pt: PieceType, col: Colour) ColouredPieceType {
        return fromInt(pt.toInt() << 1 | col.toInt());
    }

    pub inline fn toPieceType(self: ColouredPieceType) PieceType {
        return PieceType.fromInt(self.toInt() >> 1);
    }

    pub inline fn isWhite(self: ColouredPieceType) bool {
        return self.toColour() == .white;
    }

    pub inline fn isBlack(self: ColouredPieceType) bool {
        return self.toColour() == .black;
    }

    pub inline fn toColour(self: ColouredPieceType) Colour {
        return Colour.fromInt(self.toInt() & 1);
    }

    pub inline fn fromAsciiLetter(char: u8) ?ColouredPieceType {
        return fromPieceType(PieceType.fromAsciiLetter(char) orelse return null, if (std.ascii.isUpper(char)) .white else .black);
    }

    pub inline fn toAsciiLetter(self: ColouredPieceType) u8 {
        const pt_char = self.toPieceType().toAsciiLetter();
        return if (self.toColour() == .white) std.ascii.toUpper(pt_char) else std.ascii.toLower(pt_char);
    }

    pub fn flipColor(self: ColouredPieceType) ColouredPieceType {
        return .fromInt(self.toInt() ^ 1);
    }
};

pub const ScoredMove = packed struct {
    move: Move,
    padding: u16 = 0,
    score: i32,

    pub fn toScoreU64(self: ScoredMove) u64 {
        var res: u64 = @bitCast(self);
        res &= @bitCast(ScoredMove{ .move = @enumFromInt(0), .score = -1 });
        res ^= @bitCast(ScoredMove{ .move = @enumFromInt(0), .score = @bitCast(@as(u32, 0x80000000)) });
        return res << comptime scoreShift();
    }

    fn scoreShift() comptime_int {
        comptime return @clz(@as(u64, @bitCast(ScoredMove{ .move = @enumFromInt(0), .score = -1 })));
    }

    // comptime {
    //     const x: u64 = @bitCast(ScoredMove{ .move = @enumFromInt(0), .score = -1 });
    //     @compileLog(std.fmt.comptimePrint("{b}", .{x}));
    // }

    pub fn desc(_: void, lhs: ScoredMove, rhs: ScoredMove) bool {
        return lhs.score > rhs.score;
    }
};

pub const ScoredMoveReceiver = struct {
    vals: BoundedArray(ScoredMove, 256) = .{},

    pub fn receive(self: *@This(), move: Move) void {
        self.vals.appendAssumeCapacity(.{ .move = move, .score = 0 });
    }
};

pub const FilteringMoveReceiver = struct {
    vals: BoundedArray(Move, 256) = .{},
    filter: Move,

    pub fn receive(self: *@This(), move: Move) void {
        var len = self.vals.len;
        self.vals.buffer[len] = move;
        len += @intFromBool(move != self.filter);
        self.vals.len = len;
    }
};

pub const ScoreType = enum(u8) {
    none = 0,
    lower = 1,
    upper = 2,
    exact = 3,

    pub fn givesLowerBound(self: ScoreType) bool {
        return @intFromEnum(self) & 1 != 0;
    }
    pub fn givesUpperBound(self: ScoreType) bool {
        return @intFromEnum(self) & 2 != 0;
    }
};

pub const TTFlags = packed struct(u8) {
    raw: u8 = 0,

    const SCORE_MASK = 0b00000011;
    const SCORE_SHIFT = 0;
    const PV_MASK = 0b00000100;
    const PV_SHIFT = @ctz(@as(u8, PV_MASK));
    const AGE_MASK = 0b11111;
    const AGE_SHIFT = 3;

    pub fn init(
        score_type: ScoreType,
        is_pv: bool,
        age: u8,
    ) TTFlags {
        const score: u8 = @intFromEnum(score_type);
        const pv: u8 = if (is_pv) PV_MASK else 0;
        return .{
            .raw = score | pv | age << 3,
        };
    }

    fn toInt(self: TTFlags) u8 {
        return self.raw;
    }

    pub fn getPV(self: TTFlags) bool {
        return self.raw & PV_MASK != 0;
    }

    pub fn getScoreType(self: TTFlags) ScoreType {
        return @enumFromInt(self.raw & SCORE_MASK);
    }

    pub fn getAge(self: TTFlags) u8 {
        return self.raw >> AGE_SHIFT;
    }
};

test TTFlags {
    inline for (.{
        .{ .score_type = .none, .is_pv = false, .age = 0 },
        .{ .score_type = .lower, .is_pv = true, .age = 1 },
        .{ .score_type = .upper, .is_pv = false, .age = 17 },
        .{ .score_type = .exact, .is_pv = true, .age = 31 },
    }) |case| {
        const flags = TTFlags.init(case.score_type, case.is_pv, case.age);
        try std.testing.expectEqual(case.score_type, flags.getScoreType());
        try std.testing.expectEqual(case.is_pv, flags.getPV());
        try std.testing.expectEqual(case.age, flags.getAge());
    }
}

comptime {
    assert(@sizeOf(TTFlags) == 1);
}

const TTPICK_TYPE_VALS = [_]i32{
    -1000_000_000,
    TUNABLE_CONSTANTS.ttpick_lower_weight,
    TUNABLE_CONSTANTS.ttpick_upper_weight,
    TUNABLE_CONSTANTS.ttpick_exact_weight,
};

pub const TTEntry = packed struct(u64) {
    flags: TTFlags = .{},
    depth: u8 = 0,
    move: Move = Move.init(),
    score: i16 = 0,
    raw_static_eval: i16 = 0,

    inline fn getValue(self: *const TTEntry, cur_age: i32) i32 {
        const depth_val = TUNABLE_CONSTANTS.ttpick_depth_weight * self.depth;
        const age_val = TUNABLE_CONSTANTS.ttpick_age_weight * (cur_age - self.flags.getAge() & 31);
        const pv_val = TUNABLE_CONSTANTS.ttpick_pv_weight * @intFromBool(self.flags.getPV());
        const type_val = TTPICK_TYPE_VALS[@intFromEnum(self.flags.getScoreType())];
        const move_val = TUNABLE_CONSTANTS.ttpick_move_weight * @intFromBool(!self.move.isNull());
        return depth_val - age_val + pv_val + type_val + move_val;
    }
};

// short lived object for writing to tt
pub const TTProxy = struct {
    entry: *TTEntry,
    hash: *u16,

    pub inline fn depth(self: TTProxy) u8 {
        return self.entry.depth;
    }

    pub inline fn flags(self: TTProxy) TTFlags {
        return self.entry.flags;
    }

    pub inline fn hashEql(self: TTProxy, other: u64) bool {
        return self.hash.* == TTCluster.compress(other);
    }

    pub inline fn write(self: TTProxy, entry: TTEntry, hash: u16) void {
        self.entry.* = entry;
        self.hash.* = hash;
    }
};

pub const TTCluster = extern struct {
    // entries: [3]TTEntry align(8) = @splat(.{}),
    // hashes: [4]u16 align(8) = @splat(0),
    raw: [4]u64 = @splat(0),

    pub fn hashes(self: TTCluster) [4]u16 {
        return @bitCast(self.raw[3]);
    }

    fn hashesPtr(self: *TTCluster) *[4]u16 {
        return @ptrCast(&self.raw[3]);
    }

    pub fn entries(self: TTCluster) [3]TTEntry {
        return @bitCast(self.raw[0..3].*);
    }

    fn entriesPtr(self: *TTCluster) *[3]TTEntry {
        return @ptrCast(self.raw[0..3]);
    }

    inline fn entryFieldVec(low: @Vector(4, u32), comptime name: []const u8) @Vector(4, u32) {
        const BIT_OFFSET = @bitOffsetOf(TTEntry, name);
        const BITS = @bitSizeOf(@FieldType(TTEntry, name));
        comptime assert(BIT_OFFSET + BITS <= 32);

        const mask: @Vector(4, u32) = @splat(std.math.maxInt(std.meta.Int(.unsigned, BITS)));
        return low >> @splat(BIT_OFFSET) & mask;
    }

    inline fn getValues(self: TTCluster, cur_age: i32) [4]i32 {
        const V = @Vector(4, i32);
        const U = @Vector(4, u32);

        const AGE_MASK: V = @splat(TTFlags.AGE_MASK);
        const SCORE_MASK: U = @splat(TTFlags.SCORE_MASK);
        const NULL_MOVE: U = @splat(@intFromEnum(Move.init()));
        const ONE: U = @splat(1);

        const raw_vec: @Vector(4, u64) = self.raw;
        const low: U = @truncate(raw_vec);

        const flags = entryFieldVec(low, "flags");
        const depth = entryFieldVec(low, "depth");
        const move = entryFieldVec(low, "move");

        const age: V = @intCast(flags >> @splat(TTFlags.AGE_SHIFT));
        const pv: V = @intCast(flags >> @splat(TTFlags.PV_SHIFT) & ONE);
        const score_type = flags & SCORE_MASK;
        const has_move: V = @intCast(@intFromBool(move != NULL_MOVE));

        var type_val: V = @splat(TTPICK_TYPE_VALS[0]);
        inline for (TTPICK_TYPE_VALS[1..], 1..) |value, index| {
            const i: U = @splat(index);
            const v: V = @splat(value);
            type_val = @select(i32, score_type == i, v, type_val);
        }

        const cur_ages: V = @splat(cur_age);
        const aged = (cur_ages - age) & AGE_MASK;

        var sum_values = type_val;
        inline for (.{
            TUNABLE_CONSTANTS.ttpick_depth_weight,
            -TUNABLE_CONSTANTS.ttpick_age_weight,
            TUNABLE_CONSTANTS.ttpick_pv_weight,
            TUNABLE_CONSTANTS.ttpick_move_weight,
        }, .{ @as(V, @intCast(depth)), aged, pv, has_move }) |weight, value| {
            const w: V = @splat(weight);
            sum_values += w * value;
        }
        return sum_values;
    }

    pub fn compress(h: u64) u16 {
        return @intCast(h & 0xffff);
    }

    inline fn idxEqualHashEntry(noalias self: *const TTCluster, hash: u16) usize {
        const swap = @import("builtin").cpu.arch.endian() == .big;
        const key: u16 = if (swap) @byteSwap(hash) else hash;

        var haystack: u64 = if (swap) @byteSwap(self.raw[3]) else self.raw[3];
        haystack |= @as(u64, key) << 48;

        const low_bits: u64 = 0x0001000100010001;
        const high_bits: u64 = 0x8000800080008000;
        const needle = key * low_bits;
        const zeroes = haystack ^ needle;
        const matches = zeroes -% low_bits & ~zeroes & high_bits;

        return @ctz(matches) / 16;
    }

    inline fn proxy(self: *TTCluster, idx: usize) TTProxy {
        return .{
            .entry = &self.entriesPtr()[idx],
            .hash = &self.hashesPtr()[idx],
        };
    }

    pub const TTData = struct { TTEntry, bool };

    pub fn read(self: *const TTCluster, hash: u16) TTData {
        const idx = self.idxEqualHashEntry(hash);
        var res: TTEntry = @bitCast(self.raw[idx]);
        if (idx == 3) {
            @branchHint(.unpredictable);
            res = .{};
        }
        return .{ res, idx != 3 };
    }

    pub noinline fn write(noalias self: *TTCluster, hash: u16, cur_age: u8) TTProxy {
        const idx = self.idxEqualHashEntry(hash);
        if (idx != 3) {
            @branchHint(.likely);
            return self.proxy(idx);
        }

        const values = self.getValues(cur_age);

        var best_entry: u32 = 0;
        var best_value: i32 = values[0];

        inline for (1..3) |i| {
            if (values[i] < best_value) {
                best_value = values[i];
                best_entry = i;
            }
        }
        return self.proxy(best_entry);
    }

    test getValues {
        var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
        const r = prng.random();
        for (0..1024) |_| {
            var cluster: TTCluster = .{};
            for (&cluster.raw) |*w| w.* = r.int(u64);
            const cur_age: i32 = r.int(u5);
            const vec: [4]i32 = cluster.getValues(cur_age);
            const entr: [4]TTEntry = @bitCast(cluster.raw);
            for (0..3) |i| {
                try std.testing.expectEqual(entr[i].getValue(cur_age), vec[i]);
            }
        }
    }
};

comptime {
    assert(@sizeOf(TTEntry) == 8);
    assert(@sizeOf(TTCluster) == 32);
}

pub var io: std.Io = undefined;
var stdout_wrapper: std.Io.File.Writer = undefined;
pub var stdout_writer: *std.Io.Writer = undefined;
var stdout_buf: [4096]u8 = undefined;
var stdout: std.Io.File = undefined;
var write_mutex: std.Io.Mutex = .init;

pub const IS_WINDOWS = @import("builtin").os.tag == .windows;
const windows_h = @cImport(@cInclude("windows.h"));

pub fn initConsole() void {
    if (IS_WINDOWS) {
        if (windows_h.SetConsoleCP(windows_h.CP_UTF8) == 0) {
            return;
        }
        if (windows_h.SetConsoleOutputCP(windows_h.CP_UTF8) == 0) {
            return;
        }
    }
}

pub fn needsNonBlockingIo(handle: std.posix.fd_t) bool {
    if (@import("builtin").os.tag != .windows) {
        return false;
    }

    const windows = std.os.windows;

    var iosb: windows.IO_STATUS_BLOCK = undefined;
    var mode: windows.ULONG = 0;

    const rc = windows.ntdll.NtQueryInformationFile(handle, &iosb, &mode, @sizeOf(windows.ULONG), .Mode);

    if (rc != .SUCCESS) {
        return false;
    }

    const flags = windows_h.FILE_SYNCHRONOUS_IO_ALERT | windows_h.FILE_SYNCHRONOUS_IO_NONALERT;

    return mode & flags == 0;
}

pub fn writeUnicode(
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    write_mutex.lockUncancelable(io);
    defer write_mutex.unlock(io);

    var utf8_writer = std.Io.Writer.Allocating.init(allocator);
    defer utf8_writer.deinit();
    try utf8_writer.writer.print(fmt, args);
    const utf8 = utf8_writer.written();

    if (IS_WINDOWS) {
        const handle = windows_h.GetStdHandle(windows_h.STD_OUTPUT_HANDLE);
        var console_mode: windows_h.DWORD = undefined;
        if (windows_h.GetConsoleMode(handle, &console_mode) != 0) {
            const wtf16_buf = try std.unicode.wtf8ToWtf16LeAlloc(allocator, utf8);
            defer allocator.free(wtf16_buf);

            stdout_writer.flush() catch |e| std.debug.panic("flushing stdout failed! Error: {}\n", .{e});

            var written: windows_h.DWORD = 0;
            if (windows_h.WriteConsoleW(handle, wtf16_buf.ptr, @intCast(wtf16_buf.len), &written, null) == 0) {
                std.debug.panic("WriteConsoleW failed\n", .{});
            }
            return;
        }
    }

    stdout_writer.writeAll(utf8) catch |e| std.debug.panic("writing to stdout failed! Error: {}\n", .{e});

    stdout_writer.flush() catch |e| std.debug.panic("flushing stdout failed! Error: {}\n", .{e});
}

pub fn write(comptime fmt: []const u8, args: anytype) void {
    write_mutex.lockUncancelable(io);
    defer write_mutex.unlock(io);

    stdout_writer.print(fmt, args) catch |e| std.debug.panic("writing to stdout failed! Error: {}\n", .{e});

    stdout_writer.flush() catch |e| std.debug.panic("flushing stdout failed! Error: {}\n", .{e});
}

pub fn isConstPointer(comptime T: type) bool {
    if (@typeInfo(T) == .pointer) {
        return @typeInfo(T).pointer.is_const;
    }
    return false;
}

pub fn InheritConstness(comptime Base: type, comptime Pointer: type) type {
    const info = @typeInfo(Pointer).pointer;
    const is_const = if (@typeInfo(Base) == .pointer) @typeInfo(Base).pointer.is_const else false;
    return @Pointer(info.size, .{
        .@"const" = is_const,
        .@"volatile" = info.is_volatile,
        .@"allowzero" = info.is_allowzero,
        .@"align" = info.alignment,
        .@"addrspace" = info.address_space,
    }, info.child, info.sentinel());
}

inline fn ValueTypeOf(x: anytype) type {
    comptime {
        if (@TypeOf(x) != type) {
            return ValueTypeOf(@TypeOf(x));
        }
        if (@typeInfo(x) == .pointer) {
            return ValueTypeOf(@typeInfo(x).pointer.child);
        }
        return x;
    }
}

pub fn bytesOf(value: anytype) [@divExact(@bitSizeOf(@TypeOf(value)), 8)]u8 {
    return @bitCast(value);
}

pub const NT_MEMSET_THRESHOLD: usize = 16 << 20;

noinline fn memsetNonTemporal(comptime T: type, x: []T, v: T) void {
    const VEC_ELEMS = simd.vecSize(T);
    const VEC_BYTES = simd.vecSize(u8);
    const t_arr: [VEC_ELEMS]T = @splat(v);

    const b = std.mem.sliceAsBytes(x);
    const base = @intFromPtr(b.ptr);
    const alignment_offs = std.mem.alignForward(usize, base, VEC_BYTES) - base;

    // head may be unaligned
    if (alignment_offs > 0) {
        @branchHint(.unlikely);
        x[0..VEC_ELEMS].* = t_arr;
    }

    const b_aligned = b[alignment_offs..];
    var i: usize = 0;
    while (i + VEC_BYTES <= b_aligned.len) : (i += VEC_BYTES) {
        simd.ntStore(u8, &b_aligned[i], asBytes(&t_arr).*);
    }
    simd.ntFence();

    // tail may be unaligned
    if (i < b_aligned.len) {
        @branchHint(.unlikely);
        x[x.len - VEC_ELEMS ..][0..VEC_ELEMS].* = t_arr;
    }
}

pub inline fn unrollBarrier() void {
    if (!@inComptime()) {
        asm volatile ("");
    }
}
// 0.16.0 memset is slow
pub inline fn memset(comptime T: type, x: []T, v: T) void {
    var i: usize = 0;
    const VEC_ELEMS = @max(1, simd.vecSize(T));
    const REG_ELEMS = comptime std.math.clamp(@sizeOf(usize) / @sizeOf(T), 1, VEC_ELEMS);

    const n = x.len;

    if (n < VEC_ELEMS) {
        @branchHint(.unlikely);
        if (n < REG_ELEMS) {
            if (n == 0) {
                return;
            }
            for (0..REG_ELEMS - 1) |j| {
                x[@min(n - 1, j)] = v;
            }
            return;
        }
        for (0..VEC_ELEMS / REG_ELEMS) |j| {
            x[@min(n - REG_ELEMS, REG_ELEMS * j)..][0..REG_ELEMS].* = @splat(v);
        }
        return;
    }

    if (comptime simd.HAS_NT_STORES and simd.vecSize(u8) % @sizeOf(T) == 0) {
        if (!@inComptime() and n *| @sizeOf(T) >= NT_MEMSET_THRESHOLD) {
            @branchHint(.unlikely);
            return memsetNonTemporal(T, x, v);
        }
    }

    const UNROLL = comptime std.math.clamp(128 / (VEC_ELEMS * @sizeOf(T)), 1, 8);
    while (i + UNROLL * VEC_ELEMS <= n) : (i += UNROLL * VEC_ELEMS) {
        for (0..UNROLL) |j| {
            x[i + j * VEC_ELEMS ..][0..VEC_ELEMS].* = @splat(v);
        }
        unrollBarrier();
    }

    while (i + VEC_ELEMS < n) : (i += VEC_ELEMS) {
        x[i..][0..VEC_ELEMS].* = @splat(v);
        unrollBarrier();
    }
    x[n - VEC_ELEMS ..][0..VEC_ELEMS].* = @splat(v);
}

test memset {
    const PAGE_SIZE = std.heap.page_size_max;
    const buf = try std.testing.allocator.alignedAlloc(u8, .fromByteUnits(PAGE_SIZE), PAGE_SIZE + (1 << 16));
    defer std.testing.allocator.free(buf);

    const TRIALS = 1024;
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    for (0..TRIALS) |_| {
        const l = prng.random().int(u16) >> prng.random().int(u4);
        const v = prng.random().int(u8);
        const off = prng.random().uintLessThan(usize, PAGE_SIZE);

        memset(u8, buf, ~v);
        const actual = buf[off..][0..l];
        memset(u8, actual, v);

        for (actual) |a| try std.testing.expectEqual(v, a);
        for (buf[0..off]) |a| try std.testing.expectEqual(~v, a);
        for (buf[off + l ..]) |a| try std.testing.expectEqual(~v, a);
    }

    if (simd.HAS_NT_STORES) {
        for (0..TRIALS) |_| {
            const v = prng.random().int(u8);
            const off = prng.random().uintLessThan(usize, PAGE_SIZE);
            const l = @max(simd.vecSize(u8), prng.random().int(u16) >> prng.random().int(u4));

            memset(u8, buf, ~v);
            const actual = buf[off..][0..l];
            memsetNonTemporal(u8, actual, v);

            for (actual) |a| try std.testing.expectEqual(v, a);
            for (buf[0..off]) |a| try std.testing.expectEqual(~v, a);
            for (buf[off + l ..]) |a| try std.testing.expectEqual(~v, a);
        }
    }
}

pub fn AsBytes(comptime T: type) type {
    const info = @typeInfo(T).pointer;
    return InheritConstness(
        T,
        switch (info.size) {
            .slice => []u8,
            else => *[@divExact(@bitSizeOf(info.child), 8)]u8,
        },
    );
}

pub inline fn asBytes(pointer: anytype) AsBytes(@TypeOf(pointer)) {
    return @ptrCast(pointer);
}

pub inline fn memzero(pointer: anytype) void {
    memset(u8, asBytes(pointer), 0);
}
