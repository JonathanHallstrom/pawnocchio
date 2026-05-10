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

test {
    _ = pyrrhic;
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
pub const nnue = if (EVAL_MODE == .nnue) @import("nnue.zig") else void;
pub const Bitboard = @import("Bitboard.zig");
pub const cuckoo = @import("cuckoo.zig");
pub const Board = @import("Board.zig");
pub const Move = @import("move.zig").Move;
pub const MoveType = @import("move.zig").MoveType;
pub const movegen = @import("movegen.zig");
pub const attacks = @import("attacks.zig");
pub const zobrist = @import("zobrist.zig");
pub const PerftEPDParser = @import("PerftEPDParser.zig");
pub const Searcher = if (TOOLS_ONLY) void else @import("Searcher.zig");
pub const ThreadPool = if (TOOLS_ONLY) void else @import("ThreadPool.zig").ThreadPool;
pub const engine = if (TOOLS_ONLY) void else @import("engine.zig");
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
pub const dynamic_reader = @import("dynamic_reader.zig");
pub const owning_reader = @import("owning_reader.zig");
pub const wdl = @import("wdl.zig");

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
    stdout_wrapper = stdout.writerStreaming(io, &stdout_buf);
    stdout_writer = &stdout_wrapper.interface;
    attacks.init();
    cuckoo.init();
    numa.init() catch |e| std.debug.panic("Fatal: couldn't initialize NUMA support, error: {}\n", .{e});
    if (EVAL_MODE == .nnue) {
        nnue.init() catch |e| std.debug.panic("Fatal: couldn't initialize NNUE state, error: {}\n", .{e});
    }
    if (!TOOLS_ONLY) {
        engine.init() catch |e| std.debug.panic("Fatal: couldn't initialize the engine, error: {}\n", .{e});
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

    const SCORE_MASK: u8 = 0b00000011;
    const PV_MASK: u8 = 0b00000100;
    const AGE_SHIFT: u3 = 3;

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

pub const TTEntry = extern struct {
    score: i16 = 0,
    flags: TTFlags = .{},
    depth: u8 = 0,
    move: Move = Move.init(),
    raw_static_eval: i16 = 0,

    inline fn getValue(self: *const TTEntry, cur_age: i32) i32 {
        const depth_val = TUNABLE_CONSTANTS.ttpick_depth_weight * self.depth;
        const age_val = TUNABLE_CONSTANTS.ttpick_age_weight * (32 + cur_age - self.flags.getAge() & 31);
        const pv_val = TUNABLE_CONSTANTS.ttpick_pv_weight * @intFromBool(self.flags.getPV());
        const TYPE_VALS = [_]i32{
            -1000_000_000,
            TUNABLE_CONSTANTS.ttpick_lower_weight,
            TUNABLE_CONSTANTS.ttpick_upper_weight,
            TUNABLE_CONSTANTS.ttpick_exact_weight,
        };
        const type_val = TYPE_VALS[@intFromEnum(self.flags.getScoreType())];
        const move_val = TUNABLE_CONSTANTS.ttpick_move_weight * @intFromBool(!self.move.isNull());
        // _ = engine.dbg("tt value", depth_val - age_val + pv_val + move_val);
        // _ = engine.dbg("age", (32 + cur_age - self.flags.getAge() & 31));
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
    entries: [3]TTEntry align(8) = @splat(.{}),
    hashes: [4]u16 align(8) = @splat(0),

    pub fn compress(h: u64) u16 {
        return @intCast(h & 0xffff);
    }

    inline fn idxEqualHashEntry(noalias self: *const TTCluster, hash: u16) usize {
        const endian = @import("builtin").cpu.arch.endian();

        var haystack: u64 = @bitCast(self.hashes);
        haystack |= if (endian == .little) @as(u64, hash) << 48 else hash;

        const low_bits: u64 = 0x0001000100010001;
        const high_bits: u64 = 0x8000800080008000;
        const needle = hash * low_bits;
        const zeroes = haystack ^ needle;
        const matches = zeroes -% low_bits & ~zeroes & high_bits;

        return switch (endian) {
            .little => @ctz(matches),
            .big => @clz(matches),
        } / 16;
    }

    inline fn proxy(self: *TTCluster, idx: usize) TTProxy {
        return .{
            .entry = &self.entries[idx],
            .hash = &self.hashes[idx],
        };
    }

    inline fn eqlHashEntry(noalias self: *TTCluster, hash: u16) ?TTProxy {
        const idx = self.idxEqualHashEntry(hash);
        if (idx == 3) {
            return null;
        }
        return self.proxy(idx);
    }

    pub const TTData = struct { TTEntry, bool };

    pub inline fn read(self: *const TTCluster, hash: u16) TTData {
        const idx = self.idxEqualHashEntry(hash);
        const data: TTEntry = if (idx == 3)
            .{}
        else
            self.entries[idx];
        return .{ data, idx != 3 };
    }

    pub inline fn write(noalias self: *TTCluster, hash: u16, cur_age: u8) TTProxy {
        if (self.eqlHashEntry(hash)) |entry| {
            @branchHint(.unpredictable);
            return entry;
        }

        var best_entry: u32 = 0;
        var best_value: i32 = self.entries[best_entry].getValue(cur_age);

        inline for (&self.entries, 0..) |*entry, i| {
            const value = entry.getValue(cur_age);
            if (value < best_value) {
                @branchHint(.unpredictable);
                best_value = value;
                best_entry = i;
            }
        }
        return self.proxy(best_entry);
    }
};

comptime {
    assert(@sizeOf(TTEntry) == 8);
    assert(@sizeOf(TTCluster) == 32);
}

pub var io: std.Io = undefined;
pub var stdout_wrapper: std.Io.File.Writer = undefined;
pub var stdout_writer: *std.Io.Writer = undefined;
var stdout_buf: [4096]u8 = undefined;
var stdout: std.Io.File = undefined;
var write_mutex: std.Io.Mutex = .init;
pub fn write(comptime fmt: []const u8, args: anytype) void {
    write_mutex.lockUncancelable(io);
    defer write_mutex.unlock(io);

    stdout_writer.print(fmt, args) catch |e| {
        std.debug.panic("writing to stdout failed! Error: {}\n", .{e});
    };
    stdout_writer.flush() catch |e| {
        std.debug.panic("flushing stdout failed! Error: {}\n", .{e});
    };
}

pub fn isConstPointer(comptime T: type) bool {
    if (@typeInfo(T) == .pointer) {
        return @typeInfo(T).pointer.is_const;
    }
    return false;
}

pub fn inheritConstness(comptime Base: type, comptime Pointer: type) type {
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
