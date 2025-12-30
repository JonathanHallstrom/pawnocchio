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

fn parseSingleGame(input: []const u8, game: *Game) !usize {
    var i: usize = 0;
    var initial: viriformat.MarlinPackedBoard = undefined;
    @memcpy(std.mem.asBytes(&initial), input[0..32]);
    i += 32;

    var board = initial.toBoard() catch return error.FailedToParse;
    game.reset(board);
    game.setOutCome(@enumFromInt(initial.wdl));

    while (i < input.len) {
        var move_eval: viriformat.MoveEvalPair = undefined;
        @memcpy(std.mem.asBytes(&move_eval), input[i..][0..4]);
        i += 4;
        if (move_eval.move.data == 0) {
            break;
        }
        const move = move_eval.move.toMove(&board);

        switch (board.stm) {
            inline else => |stm| {
                if (board.isPseudoLegal(stm, move) and board.isLegal(stm, move)) {
                    board.makeMove(stm, move, Board.NullEvalState{});
                    try game.addMove(move, move_eval.eval.toNative());
                } else {
                    return error.FailedToParse;
                }
            },
        }
    }
    return i;
}

pub fn sanitiseBufferToFile(
    input: []const u8,
    output: *std.Io.Writer,
    allocator: std.mem.Allocator,
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
        const bytes_used = parseSingleGame(input[i..], &game) catch |e| switch (e) {
            error.FailedToParse => {
                skipped += 1;
                i += 1;
                continue;
            },
            else => return e,
        };
        i += bytes_used;
        parsed += 1;
        try game.serializeInto(output);
    }
    try output.flush();
    std.debug.print("\nparsed {} games and skipped {} bytes\n", .{ parsed, skipped });
}
