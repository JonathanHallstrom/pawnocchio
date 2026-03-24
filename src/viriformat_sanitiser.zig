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
};

const ErrorContext = struct {
    in_game_byte_offset: usize = 0,
    fen_buffer: BoundedArray(u8, 128) = .{},
    move_buffer: BoundedArray(u8, 5) = .{},
    score: ?i16 = null,

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

    fn fen(self: *const ErrorContext) ?[]const u8 {
        return if (self.fen_buffer.len == 0) null else self.fen_buffer.slice();
    }

    fn move(self: *const ErrorContext) ?[]const u8 {
        return if (self.move_buffer.len == 0) null else self.move_buffer.slice();
    }
};

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
        => true,
        else => false,
    };
}

const ParseGameError =
    ParseError ||
    viriformat.Error ||
    std.mem.Allocator.Error;

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
    output: *std.Io.Writer,
    allocator: std.mem.Allocator,
    config: Config,
) !void {
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
            }
            return e;
        };
        i += bytes_used;
        parsed += 1;
        try game.serializeInto(output);
    }
    try output.flush();
    std.debug.print("\nparsed {} games and skipped {} bytes\n", .{ parsed, skipped });
}
