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
const ScoredMove = root.dataformat.ScoredMove;

pub const MissingEvalFill = union(enum) {
    none,
    prev,
    next,
    value: i16,

    pub fn apply(self: MissingEvalFill, moves: []ScoredMove) ?u64 {
        var filled: u64 = 0;
        switch (self) {
            .none => {},
            .value => |v| {
                for (moves) |*m| {
                    if (m.score == null) {
                        m.score = v;
                        filled += 1;
                    }
                }
            },
            .prev => {
                var carry: ?i16 = null;
                for (moves) |*m| {
                    if (m.score) |s| {
                        carry = s;
                    } else if (carry) |s| {
                        m.score = s;
                        filled += 1;
                    }
                }
            },
            .next => {
                var carry: ?i16 = null;
                var i: usize = moves.len;
                while (i > 0) {
                    i -= 1;
                    if (moves[i].score) |s| {
                        carry = s;
                    } else if (carry) |s| {
                        moves[i].score = s;
                        filled += 1;
                    }
                }
            },
        }

        for (moves) |m| {
            if (m.score == null) return null;
        }

        return filled;
    }
};

pub fn convert(
    io: std.Io,
    allocator: std.mem.Allocator,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
    skip_broken_games: bool,
    fill: MissingEvalFill,
) !void {
    var position_count: u64 = 0;
    const start_time = std.Io.Timestamp.now(io, .awake);
    var num_broken_games: u64 = 0;
    var num_okay_games: u64 = 0;
    var num_filled_evals: u64 = 0;

    var ply_reader = pgn.scoredPlyReader(input, allocator);
    defer ply_reader.deinit();

    var game_record = GameRecord.from(.{}, allocator);
    defer game_record.deinit();

    var scored_moves: std.ArrayListUnmanaged(ScoredMove) = .empty;
    defer scored_moves.deinit(allocator);

    while (try ply_reader.next()) |game_view| {
        game_record.reset(game_view.initial_board);
        game_record.setOutCome(game_view.outcome);

        scored_moves.clearRetainingCapacity();
        var it = game_view.iter();
        var parsed_correctly = true;
        while (it.next() catch |e| blk: {
            std.debug.print("error parsing game: {}\n", .{e});
            if (!skip_broken_games) return e;
            parsed_correctly = false;
            num_broken_games += 1;
            break :blk null;
        }) |ply| {
            try scored_moves.append(allocator, .{ .move = ply.move, .score = ply.whiteEval() });
        }

        if (!parsed_correctly) continue;

        if (fill.apply(scored_moves.items)) |filled| {
            num_filled_evals += filled;
        } else {
            if (!skip_broken_games) {
                return error.MissingEvaluation;
            }
            num_broken_games += 1;
            continue;
        }

        for (scored_moves.items) |m| {
            try game_record.addMove(m.move, m.score.?);
        }

        num_okay_games += 1;
        try game_record.serializeInto(output);
        position_count += game_record.moves.items.len;
    }

    const elapsed = start_time.untilNow(io, .awake);

    try output.flush();
    std.debug.print(
        \\broken games: {}
        \\parsed games: {}
        \\total games: {}
        \\total positions: {}
        \\filled evals: {}
        \\time taken: {f}
        \\positions/s: {}
        \\
    , .{
        num_broken_games,
        num_okay_games,
        num_broken_games + num_okay_games,
        position_count,
        num_filled_evals,
        elapsed,
        position_count * @as(u128, std.time.ns_per_s) / @max(1, elapsed.toNanoseconds()),
    });
}
