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

fn endOfInfo(line: []const u8, i: usize) usize {
    if (std.mem.indexOfScalar(u8, line[i..], '}')) |offs| {
        return i + offs + 1;
    }
    return line.len;
}

pub fn convert(input: []const u8, skip_broken_games: bool, output_unbuffered: anytype, allocator: std.mem.Allocator) !void {
    var bw = std.io.bufferedWriter(output_unbuffered);

    var start_stm = root.Colour.white;
    var board = Board.startpos();
    var game = Game.from(board, allocator);
    var position_count: usize = 0;
    var timer = try std.time.Timer.start();
    var iter = std.mem.tokenizeScalar(u8, input, '\n');
    var skip_game = false;
    outer_loop: while (iter.next()) |line| {
        if (line.len == 0) {
            continue;
        }

        // std.debug.print("{s}\n", .{line});
        if (std.mem.indexOf(u8, line, "FEN")) |offs| {
            const fen = std.mem.trim(u8, line[offs + 3 ..], " \"[]");
            board = try Board.parseFen(fen, true);
            game.reset(board);
            start_stm = board.stm;
            skip_game = false;
            continue;
        }

        if (skip_game) continue;

        if (line[0] == '[') {
            continue;
        }

        var i: usize = 0;
        while (i < line.len) {
            if (line[i] == ' ') {
                i += 1;
                continue;
            }
            defer i = endOfInfo(line, i) + 1;

            if (std.mem.eql(u8, line[i..], "1-0")) {
                game.setOutCome(.win);
                break;
            }
            if (std.mem.eql(u8, line[i..], "0-1")) {
                game.setOutCome(.loss);
                break;
            }
            if (std.mem.eql(u8, line[i..], "1/2-1/2")) {
                game.setOutCome(.draw);
                break;
            }

            var chars_in_move = std.mem.indexOfScalar(u8, line[i..], ' ').?;
            var move_str = line[i .. i + chars_in_move];
            if (std.ascii.isDigit(move_str[0])) {
                // std.debug.print("discarded '{s}'\n", .{move_str});
                i += chars_in_move + 1;
                chars_in_move = std.mem.indexOfScalar(u8, line[i..], ' ').?;
                move_str = line[i .. i + chars_in_move];
            }

            if (line[i + chars_in_move + 1] != '{') {
                std.debug.print("move '{s}' is missing info block in '{s}' \n", .{ move_str, line });

                if (skip_broken_games) {
                    skip_game = true;
                    continue :outer_loop;
                } else {
                    return error.InvalidInfoBlock;
                }
            }

            if (board.parseSANMove(move_str)) |move| {
                var mated = false;
                var winning = false;
                const chars_in_score = std.mem.indexOfScalar(u8, line[i + chars_in_move + 2 ..], ' ').?;
                const score_str = std.mem.trim(
                    u8,
                    line[i + chars_in_move + 2 .. i + chars_in_move + 2 + chars_in_score],
                    &std.ascii.whitespace,
                );
                if (std.mem.count(u8, score_str, "M") > 0) {
                    mated = true;
                    winning = std.mem.count(u8, score_str, "-") == 0;
                }
                // std.debug.print("'{s}'->{s} '{s}' {}\n", .{ move_str, move.toString(&board).slice(), score_str, mated });

                var score: f64 = if (mated) (if (winning) 1000 else -1000) else std.fmt.parseFloat(f64, score_str) catch |e| {
                    std.debug.print("failed to parse score '{s}' in line '{s}'\n", .{ score_str, line });
                    if (skip_broken_games) {
                        skip_game = true;
                        continue :outer_loop;
                    } else {
                        return e;
                    }
                };
                if (board.stm == .black) score = -score;

                try game.addMove(move, @intFromFloat(std.math.clamp(
                    score * 100,
                    std.math.minInt(i16),
                    std.math.maxInt(i16),
                )));
                position_count += 1;
                switch (board.stm) {
                    inline else => |stm| board.makeMove(stm, move, &Board.NullEvalState{}),
                }
            } else {
                std.debug.print("failed to parse {s} in position {s}\n", .{ move_str, board.toFen().slice() });
                if (skip_broken_games) {
                    skip_game = true;
                    continue :outer_loop;
                } else {
                    return error.InvalidMove;
                }
            }
        }
        if (game.moves.items.len > 0) {
            try game.serializeInto(bw.writer());
        }
    }
    try bw.flush();
    std.debug.print("{}pos {}pos/s\n", .{
        position_count,
        position_count * @as(u128, std.time.ns_per_s) / timer.read(),
    });
}
