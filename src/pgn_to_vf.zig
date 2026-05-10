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
const pgn = root.pgn;
const GameRecord = viriformat.GameRecord;

pub fn convert(
    allocator: std.mem.Allocator,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
    skip_broken_games: bool,
) !void {
    var position_count: u64 = 0;
    const start_time = std.Io.Timestamp.now(root.io, .awake);
    var num_broken_games: u64 = 0;
    var num_okay_games: u64 = 0;

    var ply_reader = pgn.scoredPlyReader(input, allocator);
    defer ply_reader.deinit();

    var game_record = GameRecord.from(.{}, allocator);
    defer game_record.deinit();
    while (try ply_reader.next()) |game_view| {
        game_record.reset(game_view.initial_board);
        game_record.setOutCome(game_view.outcome);

        var it = game_view.iter();
        var parsed_correctly = true;
        while (it.next() catch |e| blk: {
            std.debug.print("error parsing game: {}\n", .{e});
            if (!skip_broken_games) return e;
            parsed_correctly = false;
            num_broken_games += 1;
            break :blk null;
        }) |ply| {
            if (ply.whiteEval()) |ev| {
                try game_record.addMove(ply.move, ev);
            } else {
                if (!skip_broken_games) return error.MissingEvaluation;
                parsed_correctly = false;
                num_broken_games += 1;
                break;
            }
        }

        if (parsed_correctly) {
            num_okay_games += 1;
            try game_record.serializeInto(output);
            position_count += game_record.moves.items.len;
        }
    }

    const now = std.Io.Timestamp.now(root.io, .awake);
    const elapsed = @as(u64, @intCast(start_time.durationTo(now).nanoseconds));

    try output.flush();
    std.debug.print(
        \\broken games: {}
        \\parsed games: {}
        \\total games: {}
        \\total positions: {}
        \\time taken: {}ns
        \\positions/s: {}
        \\
    , .{
        num_broken_games,
        num_okay_games,
        num_broken_games + num_okay_games,
        position_count,
        elapsed,
        position_count * @as(u128, std.time.ns_per_s) / @max(1, elapsed),
    });
}
