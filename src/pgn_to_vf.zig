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

fn endOfInfo(line: []const u8, i: usize) usize {
    if (std.mem.indexOfScalar(u8, line[i..], '}')) |offs| {
        return i + offs + 1;
    }
    return line.len;
}

pub fn convert(input_unbuffered: std.io.AnyReader, output_unbuffered: std.io.AnyWriter, allocator: std.mem.Allocator) !void {
    var br = std.io.bufferedReader(input_unbuffered);
    var bw = std.io.bufferedWriter(output_unbuffered);

    var board = Board.startpos();
    var game = Game.from(board, allocator);
    while (br.reader().readUntilDelimiterAlloc(allocator, '\n', 1 << 20)) |line| {
        defer allocator.free(line);

        if (line.len == 0) {
            continue;
        }

        if (std.mem.indexOf(u8, line, "FEN")) |offs| {
            const fen = std.mem.trim(u8, line[offs + 3 ..], " \"[]");
            board = try Board.parseFen(fen, true);
            game.reset(board);
            continue;
        }
        if (line[0] == '[') {
            continue;
        }

        var i: usize = 0;
        while (i < line.len) {
            if (line[i] == ' ') {
                i += 1;
                continue;
            }
            i = sw: switch (line[i]) {
                ' ' => {
                    i += 1;
                    continue :sw line[i];
                },
                'a'...'h' => |c| { // pawn moves
                    const from_file = try File.parse(c);
                    const to_file: File, const to_rank: Rank = blk: {
                        if (line[i + 1] == 'x') {
                            break :blk .{ try File.parse(line[i + 2]), try Rank.parse(line[i + 3]) };
                        } else {
                            break :blk .{ from_file, try Rank.parse(line[i + 1]) };
                        }
                    };
                    // std.debug.print("{}\n", .{Square.fromRankFile(to_rank, to_file)});
                    const from_rank = Rank.fromInt(if (board.stm == .white)
                        to_rank.toInt() - 1
                    else
                        to_rank.toInt() + 1);
                    _ = from_rank;
                    _ = to_file;
                    // std.debug.print("{}\n", .{Square.fromRankFile(from_rank, from_file)});
                    break :sw endOfInfo(line, i) + 1;
                },
                'B' => endOfInfo(line, i) + 1,
                'N' => endOfInfo(line, i) + 1,
                'R' => endOfInfo(line, i) + 1,
                'Q' => endOfInfo(line, i) + 1,
                'K' => endOfInfo(line, i) + 1,
                'O' => endOfInfo(line, i) + 1, // castling
                '0', '1' => line.len,
                else => |c| std.debug.panic("unhandled character: '{c}' in line '{s}'\n", .{ c, line }),
            };
            board.stm = board.stm.flipped();
        }

        // std.debug.print("{s}\n", .{line});
    } else |e| switch (e) {
        error.EndOfStream => {},
        else => return e,
    }

    try bw.flush();
}
