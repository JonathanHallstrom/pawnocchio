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

const root = @import("root.zig");
const BoundedArray = root.BoundedArray;
const Board = root.Board;
const viriformat = root.viriformat;
const Game = viriformat.Game;
const File = root.File;
const Rank = root.Rank;
const Square = root.Square;
const PieceType = root.PieceType;
const Move = root.Move;
const WDL = root.WDL;

const ParseError = error{
    InputTooShortForHeader,
    InvalidWdl,
    InputTooShortForMoveEvalPair,
    MoveNotPseudoLegal,
    MoveNotLegal,
    MoveWronglyEncoded,
    InvalidInitialPos,
};

const ErrorContext = struct {
    in_game_byte_offset: usize = 0,
    fen_buffer: BoundedArray(u8, 128) = .{},
    move_buffer: BoundedArray(u8, 5) = .{},
    score: ?i16 = null,
    initial_position_from_file: ?viriformat.MarlinPackedBoard = null,
    initial_position_decoded: ?viriformat.MarlinPackedBoard = null,

    fn reset(self: *ErrorContext) void {
        self.* = .{};
    }

    fn capturePos(
        self: *ErrorContext,
        in_game_byte_offset: usize,
        board: *const Board,
        mv: ?Move,
        score: ?i16,
    ) void {
        self.in_game_byte_offset = in_game_byte_offset;
        self.fen_buffer = board.toFen();
        self.move_buffer.clear();

        if (mv) |m| {
            self.move_buffer = m.toString(board);
        }
        self.score = score;
    }

    fn captureInitialPositionDiff(
        self: *ErrorContext,
        board: *const Board,
        initial_position_from_file: viriformat.MarlinPackedBoard,
        initial_position_decoded: viriformat.MarlinPackedBoard,
    ) void {
        self.capturePos(0, board, null, null);
        self.initial_position_from_file = initial_position_from_file;
        self.initial_position_decoded = initial_position_decoded;
    }

    fn fen(self: *const ErrorContext) ?[]const u8 {
        return if (self.fen_buffer.len == 0) null else self.fen_buffer.slice();
    }

    fn move(self: *const ErrorContext) ?[]const u8 {
        return if (self.move_buffer.len == 0) null else self.move_buffer.slice();
    }
};

fn isIgnoredInitialPositionField(comptime field_name: []const u8) bool {
    return comptime std.mem.eql(u8, field_name, "eval") or std.mem.eql(u8, field_name, "extra");
}

fn printParsedGameLine(game: *const Game, error_ctx: *const ErrorContext) void {
    var board = game.initial_position.toBoard() catch return;

    std.debug.print("  game: {s}", .{board.toFen().slice()});
    for (game.moves.items) |move_eval| {
        const move = move_eval.move.toMove(&board);
        std.debug.print(" {s}({})", .{ move.toString(&board).slice(), move_eval.eval.toNative() });
        switch (board.stm) {
            inline else => |stm| board.makeMove(stm, move, Board.NullEvalState{}),
        }
    }
    if (error_ctx.move()) |move| {
        if (error_ctx.score) |score| {
            std.debug.print(" ERROR: {s}({})", .{ move, score });
        } else {
            std.debug.print(" ERROR: {s}", .{move});
        }
    }
    std.debug.print("\n", .{});
}

fn printInitialPositionDiff(error_ctx: *const ErrorContext) void {
    const initial_position_from_file = error_ctx.initial_position_from_file orelse return;
    const initial_position_decoded = error_ctx.initial_position_decoded orelse return;

    std.debug.print("  initial_position diff:\n", .{});
    inline for (std.meta.fields(viriformat.MarlinPackedBoard)) |field| {
        if (comptime isIgnoredInitialPositionField(field.name)) {
            continue;
        }
        if (!std.meta.eql(@field(initial_position_from_file, field.name), @field(initial_position_decoded, field.name))) {
            std.debug.print(
                "    {s}: file={any} decoded={any}\n",
                .{
                    field.name,
                    @field(initial_position_from_file, field.name),
                    @field(initial_position_decoded, field.name),
                },
            );
        }
    }
    std.debug.print("  initial_position bytes (file): {any}\n", .{
        std.mem.asBytes(&initial_position_from_file),
    });
    std.debug.print("  initial_position bytes (decoded): {any}\n", .{
        std.mem.asBytes(&initial_position_decoded),
    });
}

fn isRecoverableParseError(e: anyerror) bool {
    return switch (e) {
        error.InputTooShortForHeader,
        error.InvalidWdl,
        error.TooManyPieces,
        error.MissingKing,
        error.PawnsOnFirstLastRank,
        error.KingOnWrongRankAndCanCastle,
        error.InvalidEpSquare,
        error.InputTooShortForMoveEvalPair,
        error.MoveNotPseudoLegal,
        error.MoveNotLegal,
        error.MoveWronglyEncoded,
        error.InvalidInitialPos,
        => true,
        else => false,
    };
}

const ParseGameError =
    ParseError ||
    viriformat.Error ||
    std.mem.Allocator.Error;

fn sameInitialPosition(
    a: viriformat.MarlinPackedBoard,
    b: viriformat.MarlinPackedBoard,
) bool {
    inline for (std.meta.fields(viriformat.MarlinPackedBoard)) |field| {
        if (comptime isIgnoredInitialPositionField(field.name)) {
            continue;
        }
        if (!std.meta.eql(@field(a, field.name), @field(b, field.name))) {
            return false;
        }
    }
    return true;
}

fn parseSingleGame(
    input: []const u8,
    game: *Game,
    error_ctx: *ErrorContext,
    config: Config,
) ParseGameError!usize {
    error_ctx.reset();
    if (input.len < 32) {
        return error.InputTooShortForHeader;
    }

    var i: usize = 0;
    var initial: viriformat.MarlinPackedBoard = undefined;
    @memcpy(std.mem.asBytes(&initial), input[0..32]);
    i += 32;
    if (initial.wdl > 2) {
        return error.InvalidWdl;
    }

    var board = initial.toBoard() catch |e| {
        return e;
    };
    game.reset(board);
    game.setOutCome(@enumFromInt(initial.wdl));

    if (!sameInitialPosition(initial, game.initial_position)) {
        error_ctx.captureInitialPositionDiff(&board, initial, game.initial_position);
        return error.InvalidInitialPos;
    }

    var prev_move: Move = undefined;
    while (i < input.len) {
        if (input.len - i < 4) {
            error_ctx.capturePos(i, &board, null, null);
            return error.InputTooShortForMoveEvalPair;
        }

        var move_eval: viriformat.MoveEvalPair = undefined;
        @memcpy(std.mem.asBytes(&move_eval), input[i..][0..4]);
        defer i += 4;
        if (move_eval.move.data == 0) {
            break;
        }
        const move = move_eval.move.toMove(&board);

        if (move == prev_move and
            config.sp_stalemate_fix)
        {
            game.setOutCome(.draw);
            break;
        }
        prev_move = move;

        var moves = root.movegen.MoveListReceiver{};

        root.movegen.generateAll(&board, &moves);

        if (for (moves.vals.slice()) |generated| {
            if (move == generated) break false;
        } else true) {
            error_ctx.capturePos(i, &board, move, move_eval.eval.toNative());
            return error.MoveNotPseudoLegal;
        }

        if (for (moves.vals.slice()) |generated| {
            if (move_eval.move.data == viriformat.ViriMove.fromMove(generated).data) break false;
        } else true) {
            error_ctx.capturePos(i, &board, move, move_eval.eval.toNative());
            return error.MoveWronglyEncoded;
        }

        switch (board.stm) {
            inline else => |stm| {
                if (!board.isLegal(stm, move)) {
                    error_ctx.capturePos(i, &board, move, move_eval.eval.toNative());
                    return error.MoveNotLegal;
                }

                board.makeMove(stm, move, Board.NullEvalState{});
                game.addMove(move, move_eval.eval.toNative()) catch |e| {
                    error_ctx.capturePos(i, &board, move, move_eval.eval.toNative());
                    return e;
                };
            },
        }
    }
    return i;
}

pub const Config = struct {
    print_errors: bool,
    sp_stalemate_fix: bool,
};

pub fn sanitiseBufferToFile(
    input: []const u8,
    output: ?*std.Io.Writer,
    allocator: std.mem.Allocator,
    config: Config,
) !usize {
    var game: Game = .from(.startpos(), allocator);
    defer game.moves.deinit();

    var parsed: usize = 0;
    var skipped: usize = 0;
    var error_ctx: ErrorContext = .{};

    var i: usize = 0;
    var iters: usize = 0;
    while (i < input.len) : (iters += 1) {
        if (iters % (1 << 10) == 0) {
            std.debug.print("progress: {}/{}\r", .{ i, input.len });
        }
        const bytes_used = parseSingleGame(input[i..], &game, &error_ctx, config) catch |e| {
            if (isRecoverableParseError(e)) {
                if (config.print_errors) {
                    std.debug.print("failed to parse game at byte offset {} (offset {}): {}\n", .{ i, error_ctx.in_game_byte_offset, e });
                    if (error_ctx.fen()) |fen| {
                        std.debug.print("  final_fen: {s}\n", .{fen});
                        printParsedGameLine(&game, &error_ctx);
                    }
                    printInitialPositionDiff(&error_ctx);
                }
                skipped += 1;
                i += 1;
                continue;
            }
            if (config.print_errors) {
                std.debug.print("fatal sanitiser error at byte offset {} (offset {}): {}\n", .{ i, error_ctx.in_game_byte_offset, e });
                if (error_ctx.fen()) |fen| {
                    std.debug.print("  final_fen: {s}\n", .{fen});
                    printParsedGameLine(&game, &error_ctx);
                }
                printInitialPositionDiff(&error_ctx);
            }
            return e;
        };
        i += bytes_used;
        parsed += 1;
        if (output) |writer| {
            try game.serializeInto(writer);
        }
    }
    if (output) |writer| {
        try writer.flush();
    }
    std.debug.print("\nparsed {} games and skipped {} bytes\n", .{ parsed, skipped });
    return skipped;
}
