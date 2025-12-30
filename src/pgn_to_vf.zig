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

fn parseScoreFromInfoBlock(info: []const u8) !i16 {
    const end_score = std.mem.indexOfAny(u8, info, " /") orelse return error.BrokenInfoBlock;

    const score_str = info[1..end_score];
    const raw_score: f64 =
        if (std.mem.count(u8, score_str, "M") + std.mem.count(u8, score_str, "#") > 0)
            (if (score_str[0] == '+') 1000.0 else -1000.0)
        else
            try std.fmt.parseFloat(f64, score_str);
    const clamped = std.math.clamp(raw_score, @as(f64, -std.math.maxInt(i16)) / 100.0, @as(f64, std.math.maxInt(i16)) / 100.0);

    return @intFromFloat(clamped * 100);
}

fn parseOneGame(game_to_parse: []const u8, game: *Game) !void {
    var i: usize = 0;
    var board: Board = .startpos();
    var fen: ?[]const u8 = null;
    while (std.mem.indexOfScalarPos(u8, game_to_parse, i, ']')) |end_of_pgn_block| {
        defer i = end_of_pgn_block + 1;

        const current_block = game_to_parse[i..end_of_pgn_block];

        if (std.mem.indexOf(u8, current_block, "FEN")) |fen_index| {
            var fen_iter = std.mem.tokenizeScalar(u8, current_block[fen_index + 4 ..], '"');

            fen = fen orelse fen_iter.next();
        }
    }
    if (fen) |f| {
        board = Board.parseFen(f, true) catch |e| {
            std.debug.print("Parsing of fen '{s}' failed\n", .{f});
            return e;
        };
        game.reset(board);
    } else {
        std.debug.print("Missing fen\n", .{});
        return error.MissingFen;
    }

    // std.debug.print("{s}\n", .{game_to_parse[i..]});

    var previous_move_info_pair: []const u8 = "";
    while (std.mem.indexOfScalarPos(u8, game_to_parse, i, '}')) |final_info_block_char| {
        const end_info_block = final_info_block_char + 1;
        defer i = end_info_block;

        var start_move = i;
        while (start_move < game_to_parse.len and !std.ascii.isAlphabetic(game_to_parse[start_move])) {
            start_move += 1;
        }

        var end_move = start_move + 1;
        while (end_move < game_to_parse.len and game_to_parse[end_move] != ' ') {
            end_move += 1;
        }

        var start_info_block = end_move + 1;
        while (start_info_block < game_to_parse.len and game_to_parse[start_info_block] != '{') {
            start_info_block += 1;
        }

        if (start_info_block >= game_to_parse.len) {
            std.debug.print("invalid move: '{s}'\n", .{game_to_parse[i .. end_info_block + 1]});

            return error.BrokenMoveInfoBlock;
        }

        const move_str = game_to_parse[start_move..end_move];
        const info_block = game_to_parse[start_info_block..end_info_block];
        const move = board.parseSANMove(move_str) orelse {
            std.debug.print(
                \\invalid move: '{s}' with info block '{s}' in position: '{s}'
                \\previous parsed move (with associated info): '{s}'
                \\note: if it looks like there are two moves in the
                \\previous parsed move there might be a missing info block
                \\
            , .{
                move_str,
                info_block,
                board.toFen().slice(),
                previous_move_info_pair,
            });
            return error.InvalidMove;
        };
        const score = try parseScoreFromInfoBlock(info_block);
        const white_pov_score = if (board.stm == .black) -score else score;
        try game.addMove(move, white_pov_score);
        switch (board.stm) {
            inline else => |stm| board.makeMove(stm, move, &Board.NullEvalState{}),
        }
        previous_move_info_pair = game_to_parse[start_move..end_info_block];
    }
}

pub fn convert(
    input: *std.Io.Reader,
    output: *std.Io.Writer,
    skip_broken_games: bool,
    allocator: std.mem.Allocator,
) !void {
    var move_writer = std.Io.Writer.Allocating.init(allocator);
    var position_count: u64 = 0;
    var timer = try std.time.Timer.start();
    var game: viriformat.Game = .from(Board.startpos(), allocator);
    var num_broken_games: u64 = 0;
    var num_okay_games: u64 = 0;
    while (true) {
        var last = false;
        _ = input.streamDelimiter(&move_writer.writer, '\n') catch |e| switch (e) {
            error.EndOfStream => last = true,
            else => return e,
        };

        if (!last) {
            _ = try input.takeByte();
        }

        try move_writer.writer.writeByte(' ');
        const current_game = std.mem.trim(u8, move_writer.writer.buffered(), &std.ascii.whitespace);

        const white_won = std.mem.endsWith(u8, current_game, "1-0");
        const black_won = std.mem.endsWith(u8, current_game, "0-1");
        const draw = std.mem.endsWith(u8, current_game, "1/2-1/2");
        if (white_won or
            black_won or
            draw)
        {
            var parsed_correctly = true;
            parseOneGame(current_game, &game) catch |e| {
                std.debug.print(
                    \\error: {}
                    \\in game:
                    \\{s}
                    \\
                , .{ e, current_game });
                if (!skip_broken_games) {
                    return e;
                }
                num_broken_games += 1;
                parsed_correctly = false;
            };
            if (parsed_correctly) {
                num_okay_games += 1;
                if (white_won) {
                    game.setOutCome(.win);
                }
                if (black_won) {
                    game.setOutCome(.loss);
                }
                if (draw) {
                    game.setOutCome(.draw);
                }
                try game.serializeInto(output);
                position_count += game.moves.items.len;
            }

            _ = move_writer.clearRetainingCapacity();
        }
        if (last) break;
    }

    const elapsed = timer.read();

    try output.flush();
    std.debug.print(
        \\broken games: {}
        \\parsed games: {}
        \\total games: {}
        \\total positions: {}
        \\time taken: {D}
        \\positions/s: {}
        \\
    , .{
        num_broken_games,
        num_okay_games,
        num_broken_games + num_okay_games,
        position_count,
        elapsed,
        position_count * @as(u128, std.time.ns_per_s) / elapsed,
    });
}
