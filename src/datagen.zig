const std = @import("std");
const Square = @import("square.zig").Square;
const Rank = @import("square.zig").Rank;
const File = @import("square.zig").File;
const PieceType = @import("piece_type.zig").PieceType;
const Move = @import("Move.zig").Move;
const Board = @import("Board.zig");
const Bitboard = @import("Bitboard.zig");
const Side = @import("side.zig").Side;
const Allocator = std.mem.Allocator;
const engine = @import("engine.zig");
const movegen = @import("movegen.zig");
const nnue = @import("nnue.zig");
const magics = @import("magics.zig");

// very much based on https://github.com/cosmobobak/viriformat/tree/ef1c383f7ecfce02477eec1dd378c4242e022bfd

fn LittleEndian(comptime T: type) type {
    return packed struct {
        val: T,

        const Self = @This();

        pub fn fromNative(x: T) Self {
            return .{ .val = std.mem.nativeToLittle(T, x) };
        }

        pub fn toNative(self: Self) T {
            return std.mem.littleToNative(T, self.val);
        }
    };
}

fn PackedIntArray(comptime N: comptime_int, comptime T: type) type {
    return packed struct {
        data: @Vector(N, T),

        const Self = @This();

        pub fn init() Self {
            return .{ .data = @splat(0) };
        }

        pub fn set(self: *Self, idx: usize, val: T) void {
            self.data[idx] = val;
        }

        pub fn get(self: Self, idx: usize) T {
            return self.data[idx];
        }
    };
}

const MarlinPackedBoard = extern struct {
    occupancy: LittleEndian(u64),
    pieces: PackedIntArray(32, u4) align(8),
    stm_ep_square: u8,
    halfmove_clock: u8,
    fullmove_number: LittleEndian(u16),
    eval: LittleEndian(i16),
    wdl: u8,
    extra: u8,

    const unmoved_rook = 6;

    pub fn from(board: Board, loss_draw_win: u8, score: i16) MarlinPackedBoard {
        const occ = board.white.all | board.black.all;
        var pieces = PackedIntArray(32, u4).init();
        {
            var i: usize = 0;
            var iter = Bitboard.iterator(occ);
            while (iter.next()) |sq| : (i += 1) {
                const piece_type = board.mailbox[sq.toInt()].?;
                const side: Side = if (Bitboard.contains(board.white.all, sq)) .white else .black;
                const starting_rank: Rank = if (side == .white) .first else .eighth;

                var piece_code: u4 = piece_type.toInt();
                if (piece_type == .rook and sq.getRank() == starting_rank) {
                    const can_kingside_castle = 0 != board.castling_rights & if (side == .white) Board.white_kingside_castle else Board.black_kingside_castle;
                    const can_queenside_castle = 0 != board.castling_rights & if (side == .white) Board.white_queenside_castle else Board.black_queenside_castle;
                    const kingside_file = if (side == .white) board.white_kingside_rook_file else board.black_kingside_rook_file;
                    const queenside_file = if (side == .white) board.white_queenside_rook_file else board.black_queenside_rook_file;
                    if ((sq.getFile() == kingside_file and can_kingside_castle) or
                        (sq.getFile() == queenside_file and can_queenside_castle))
                    {
                        piece_code = unmoved_rook;
                    }
                }

                pieces.set(i, piece_code | @as(u4, if (side == .black) 1 << 3 else 0));
            }
        }
        return MarlinPackedBoard{
            .occupancy = LittleEndian(u64).fromNative(board.white.all | board.black.all),
            .pieces = pieces,
            .stm_ep_square = @as(u8, if (board.turn == .black) 1 << 7 else 0) | @as(u8, if (board.en_passant_target) |ep_target| ep_target.toInt() else 64),
            .halfmove_clock = board.halfmove_clock,
            .fullmove_number = LittleEndian(u16).fromNative(@intCast(board.fullmove_clock)),
            .eval = LittleEndian(i16).fromNative(score),
            .wdl = loss_draw_win,
            .extra = 164,
        };
    }
};

const ViriMove = struct {
    const promo_flag_bits: u16 = 0b1100_0000_0000_0000;
    const ep_flag_bits: u16 = 0b0100_0000_0000_0000;
    const castle_flag_bits: u16 = 0b1000_0000_0000_0000;

    const Self = @This();

    data: u16,

    const MoveFlags = enum(u16) {
        Promotion = promo_flag_bits,
        EnPassant = ep_flag_bits,
        Castle = castle_flag_bits,
    };

    pub fn newWithPromo(from: Square, to: Square, promotion: PieceType) Self {
        const promotion_int = promotion.toInt() - 1;
        return .{ .data = @as(u16, from.toInt()) | @as(u16, to.toInt()) << 6 | @as(u16, promotion_int) << 12 | promo_flag_bits };
    }

    pub fn newWithFlags(from: Square, to: Square, flags: MoveFlags) Self {
        return .{ .data = @as(u16, from.toInt()) | @as(u16, to.toInt()) << 6 | @intFromEnum(flags) };
    }

    pub fn new(from: Square, to: Square) Self {
        return .{ .data = @as(u16, from.toInt()) | @as(u16, to.toInt()) << 6 };
    }

    pub fn isPromo(self: Self) bool {
        return self.data & promo_flag_bits == promo_flag_bits;
    }

    pub fn isEp(self: Self) bool {
        return self.data & ep_flag_bits == ep_flag_bits;
    }

    pub fn isCastle(self: Self) bool {
        return self.data & castle_flag_bits == castle_flag_bits;
    }

    pub fn fromMove(move: Move) Self {
        if (move.isCastlingMove()) return newWithFlags(move.getFrom(), move.getTo(), .Castle);
        if (move.isEnPassant()) return newWithFlags(move.getFrom(), move.getTo(), .EnPassant);
        if (move.isPromotion()) return newWithPromo(move.getFrom(), move.getTo(), move.getPromotedPieceType().?);
        return new(move.getFrom(), move.getTo());
    }
};

const MoveEvalPair = struct {
    move: ViriMove,
    eval: LittleEndian(i16),
};

const Game = struct {
    initial_position: MarlinPackedBoard,
    moves: std.ArrayList(MoveEvalPair),

    fn serializeInto(self: Game, writer: anytype) !void {
        try writer.writeAll(std.mem.asBytes(&self.initial_position));
        for (self.moves.items) |move_eval_pair| {
            try writer.writeAll(std.mem.asBytes(&std.mem.nativeToLittle(u16, move_eval_pair.move.data)));
            try writer.writeAll(std.mem.asBytes(&move_eval_pair.eval.val));
        }
        try writer.writeAll(&(.{0} ** @sizeOf(MoveEvalPair)));
    }

    fn setOutCome(self: *Game, wdl: u8) void {
        self.initial_position.wdl = wdl;
    }

    fn from(board: Board, allocator: Allocator) Game {
        return Game{
            .initial_position = MarlinPackedBoard.from(board, 1, 0),
            .moves = std.ArrayList(MoveEvalPair).init(allocator),
        };
    }

    fn deinit(self: Game) void {
        self.moves.deinit();
    }

    fn addMove(self: *Game, move: Move, score: i16) !void {
        try self.moves.append(MoveEvalPair{
            .eval = LittleEndian(i16).fromNative(score),
            .move = ViriMove.fromMove(move),
        });
    }
};

comptime {
    std.debug.assert(@sizeOf(MarlinPackedBoard) == 32);
    std.debug.assert(@bitSizeOf(MarlinPackedBoard) == 32 * 8);
}

fn viriformatTest(fen: []const u8, move: Move, expected: u32) !void {
    var game = Game.from(try Board.parseFen(fen), std.testing.allocator);
    defer game.deinit();
    try game.addMove(move, 0);
    var buf: [40]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try game.serializeInto(fbs.writer());
    try std.testing.expectEqual(expected, std.mem.readInt(u32, fbs.getWritten()[32..][0..4], .little));
}

test "viriformat moves" {
    try viriformatTest("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Move.initQuiet(.e2, .e4), 0x070c);
    try std.testing.expect(Move.initCastling(.e1, .h1).isCastlingMove());
    try viriformatTest("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1", Move.initCastling(.e1, .h1), 0x81c4);
    try viriformatTest("8/6P1/8/8/1k6/4K3/8/8 w - - 0 1", Move.initPromotion(.g7, .g8, .queen), 0xffb6);
    try viriformatTest("rnbqkbnr/2pppppp/p7/Pp6/8/8/1PPPPPPP/RNBQKBNR w KQkq b6 0 1", Move.initEnPassant(.a5, .b6), 0x4a60);
}

pub fn main() !void {
    // var buf: [1024]Move = undefined;
    // for (0..960 * 960) |i| {
    //     var board = Board.dfrcPosition(@intCast(i));
    //     std.mem.doNotOptimizeAway(board);
    //     std.debug.assert(board.computePhase() == Board.init().computePhase());
    //     const white_bish = board.white.getBoard(.bishop);
    //     const white_first = @ctz(white_bish);
    //     const white_second = @ctz(white_bish & white_bish - 1);
    //     const black_bish = board.white.getBoard(.bishop);
    //     const black_first = @ctz(black_bish);
    //     const black_second = @ctz(black_bish & black_bish - 1);
    //     std.debug.assert((white_first ^ white_second) & 1 != 0);
    //     std.debug.assert((black_first ^ black_second) & 1 != 0);

    //     std.debug.print("{}: {}\n", .{ i, board.perftSingleThreaded(&buf, 2, false) });
    // }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    var output_file_name_opt: ?[]const u8 = null;
    var game_count_opt: ?u64 = null;
    var random_moves_opt: ?u8 = null;
    var nodes_opt: ?u64 = null;
    while (args.next()) |arg| {
        if (std.ascii.eqlIgnoreCase(arg, "-o")) {
            output_file_name_opt = args.next();
        }

        if (std.ascii.eqlIgnoreCase(arg, "-g")) {
            game_count_opt = std.fmt.parseInt(u64, args.next() orelse "", 10) catch null;
        }

        if (std.ascii.eqlIgnoreCase(arg, "-r")) {
            random_moves_opt = std.fmt.parseInt(u8, args.next() orelse "", 10) catch null;
        }

        if (std.ascii.eqlIgnoreCase(arg, "-n")) {
            nodes_opt = std.fmt.parseInt(u64, args.next() orelse "", 10) catch null;
        }
    }

    if (output_file_name_opt == null or game_count_opt == null or random_moves_opt == null) {
        std.debug.print("usage: -o [file] -g [# of games] -r [# of random moves to play] -n [# of nodes (soft)]\n", .{});
        std.process.exit(1);
    }

    const output_file_name = output_file_name_opt.?;
    const random_moves = random_moves_opt.?;
    const max_nodes = nodes_opt.?;
    var hash_history = try std.ArrayList(u64).initCapacity(allocator, 16384);
    defer hash_history.deinit();
    var rng = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    // var rng = std.Random.DefaultPrng.init(0);
    engine.reset();
    nnue.init();
    magics.init();

    try engine.setTTSize(16);
    std.fs.cwd().deleteFile(output_file_name) catch {};
    const output_file = std.fs.cwd().openFile(output_file_name, .{
        .mode = .write_only,
    }) catch |e| if (e == error.FileNotFound) try std.fs.cwd().createFile(output_file_name, .{}) else return e;
    defer output_file.close();

    var bw = std.io.bufferedWriter(output_file.writer());
    defer bw.flush() catch @panic("oh no flush failed");
    const output = bw.writer();

    var timer = try std.time.Timer.start();
    const remainder = rng.random().int(u7);
    var num_games: u64 = 0;
    var num_positions: u64 = 0;
    var num_nodes_searched: u256 = 0;
    var adjudicate_counter: u8 = 0;
    const win_adjudicate_score = 3000;
    const win_adjudicate_count = 5;
    game_loop: while (num_games < game_count_opt.?) {
        // std.debug.print("started a position!\n", .{});
        if (num_games % 128 == remainder) {
            const time = timer.read();
            const remaining_games = game_count_opt.? - num_games;
            const games_per_sec = @as(u256, num_games) * std.time.ns_per_s / time;
            const time_remaining = @as(u256, remaining_games) * time / num_games;
            const positions_per_sec = @as(u256, num_positions) * std.time.ns_per_s / time;
            const nodes_per_sec = num_nodes_searched * std.time.ns_per_s / time;
            std.debug.print("games {} positions {} time {} games/s {} positions/s {} nps {} remaining {}\n", .{
                num_games,
                num_positions,
                std.fmt.fmtDuration(time),
                games_per_sec,
                positions_per_sec,
                nodes_per_sec,
                std.fmt.fmtDuration(@intCast(time_remaining)),
            });
        }
        defer hash_history.clearRetainingCapacity();
        engine.reset();
        var board = if (rng.random().boolean()) Board.init() else Board.dfrcPosition(rng.random().uintLessThan(u20, 960 * 960));
        // var board = Board.dfrcPosition(rng.random().uintLessThan(u20, 960 * 960));
        // var board = Board.init();
        // std.debug.print("{s}\n", .{board.toFen().slice()});
        hash_history.appendAssumeCapacity(board.zobrist);
        for (0..random_moves) |_| {
            switch (board.turn) {
                inline else => |t| {
                    const num_moves = movegen.getMoves(t, board, move_buf);
                    if (num_moves == 0)
                        continue :game_loop;
                    const move = move_buf[rng.random().uintLessThan(usize, num_moves)];
                    _ = board.playMove(t, move);
                    hash_history.appendAssumeCapacity(board.zobrist);
                    if (movegen.countMoves(t.flipped(), board) == 0)
                        continue :game_loop;
                },
            }
        }
        var game = Game.from(board, allocator);
        defer game.deinit();
        for (0..1000) |i| {
            // std.debug.print("{s} ", .{board.toFen().slice()});

            switch (board.turn) {
                inline else => |t| {
                    if (movegen.countMoves(t, board) == 0) {
                        break;
                    }
                },
            }

            num_positions += 1;
            const search_result = engine.searchSync(
                board,
                .{
                    .nodes = max_nodes,
                },
                move_buf,
                &hash_history,
                true,
            );
            if (i == 0 and @abs(search_result.score) >= 2000) continue :game_loop;
            num_nodes_searched += search_result.stats.nodes + search_result.stats.qnodes;
            if (search_result.move == Move.null_move) {
                break;
            }
            const score_to_add = if (board.turn == .black) -search_result.score else search_result.score;
            // std.debug.print("{}\n", .{score_to_add});
            switch (board.turn) {
                inline else => |t| {
                    _ = board.playMove(t, search_result.move);
                    hash_history.appendAssumeCapacity(board.zobrist);
                },
            }
            if (board.white.getBoard(.king) == 0 or board.black.getBoard(.king) == 0)
                continue :game_loop;
            try game.addMove(
                search_result.move,
                score_to_add,
            );
            if (@abs(score_to_add) > win_adjudicate_score) {
                adjudicate_counter += 1;
                if (adjudicate_counter >= win_adjudicate_count) {
                    if (score_to_add > 0) {
                        game.setOutCome(2);
                        break;
                    } else {
                        game.setOutCome(0);
                        break;
                    }
                }
            } else {
                adjudicate_counter = 0;
            }
            // std.debug.print("{s} {}\n", .{ board.toFen().slice(), score_to_add });
        }
        if (game.moves.items.len == 0)
            continue :game_loop;

        switch (board.turn) {
            inline else => |t| {
                const num_moves, const masks = movegen.getMovesWithInfo(t, false, board, move_buf);

                if (num_moves == 0) {
                    if (masks.is_in_check) {
                        game.setOutCome(if (t == .white) 0 else 2);

                        // if (t == .white) {
                        //     std.debug.print("white lost: {s}\n", .{board.toFen().slice()});
                        // } else {
                        //     std.debug.print("black lost: {s}\n", .{board.toFen().slice()});
                        // }
                    }
                }
            },
        }
        // std.debug.print("{s} {}\n", .{ board.toFen().slice(), game.initial_position.wdl });

        try game.serializeInto(output);
        num_games += 1;
        // std.debug.print("serialized one!\n", .{});
    }
}
