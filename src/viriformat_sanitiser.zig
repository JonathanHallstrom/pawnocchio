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
const Board = root.Board;
const viriformat = root.viriformat;
const Game = viriformat.Game;
const File = root.File;
const Rank = root.Rank;
const Square = root.Square;
const PieceType = root.PieceType;
const Move = root.Move;
const WDL = root.WDL;

const ParseSingleGameError = error{
    InputTooShortForHeader,
    InvalidWdl,
    InputTooShortForMoveEvalPair,
    MoveNotPseudoLegal,
    MoveNotLegal,
} || error{
    TooManyPieces,
    MissingKing,
    PawnsOnFirstLastRank,
    KingOnWrongRankAndCanCastle,
    InvalidEpSquare,
} || std.mem.Allocator.Error;

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

fn parseSingleGame(input: []const u8, game: *Game) ParseSingleGameError!usize {
    if (input.len < 32) return error.InputTooShortForHeader;

    var i: usize = 0;
    var initial: viriformat.MarlinPackedBoard = undefined;
    @memcpy(std.mem.asBytes(&initial), input[0..32]);
    i += 32;
    if (initial.wdl > 2) return error.InvalidWdl;

    var board = try initial.toBoard();
    game.reset(board);
    game.setOutCome(@enumFromInt(initial.wdl));

    while (i < input.len) {
        if (input.len - i < 4) return error.InputTooShortForMoveEvalPair;

        var move_eval: viriformat.MoveEvalPair = undefined;
        @memcpy(std.mem.asBytes(&move_eval), input[i..][0..4]);
        i += 4;
        if (move_eval.move.data == 0) {
            break;
        }
        const move = move_eval.move.toMove(&board);
        // std.debug.print("{s} {s} {} {s}\n", .{ board.toFen().slice(), move.toString(&board).slice(), move_eval.eval.toNative(), @tagName(@as(WDL, @enumFromInt(initial.wdl))) });

        switch (board.stm) {
            inline else => |stm| {
                if (!board.isPseudoLegal(stm, move)) return error.MoveNotPseudoLegal;
                if (!board.isLegal(stm, move)) return error.MoveNotLegal;

                board.makeMove(stm, move, Board.NullEvalState{});
                try game.addMove(move, move_eval.eval.toNative());
            },
        }
    }
    return i;
}

pub fn sanitiseBufferToFile(
    input: []const u8,
    output: *std.Io.Writer,
    allocator: std.mem.Allocator,
    print_errors: bool,
) !void {
    var game: Game = .from(.startpos(), allocator);
    defer game.moves.deinit();

    var parsed: usize = 0;
    var skipped: usize = 0;

    var i: usize = 0;
    while (i < input.len) {
        if (i / 4 % (1 << 10) == 0) {
            std.debug.print("progress: {}/{}\r", .{ i, input.len });
        }
        const bytes_used = parseSingleGame(input[i..], &game) catch |e| {
            if (isRecoverableParseError(e)) {
                if (print_errors) {
                    std.debug.print("failed to parse game at byte offset {}: {}\n", .{ i, e });
                }
                skipped += 1;
                i += 1;
                continue;
            }
            if (print_errors) {
                std.debug.print("fatal sanitiser error at byte offset {}: {}\n", .{ i, e });
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
