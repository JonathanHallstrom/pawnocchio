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

fn getConnectingMove(from: *const Board, to: *const Board) ?Move {
    const movegen = root.movegen;
    if (from.stm == to.stm)
        return null;
    const diff = from.occupancy() ^ to.occupancy();
    if (@popCount(diff) > 4)
        return null;

    for (0..6) |i|
        if (@popCount(from.pieces[i] ^ to.pieces[i]) > 3)
            return null;

    var movelist = movegen.MoveListReceiver{};
    movegen.generateAll(from, &movelist);
    for (movelist.vals.slice()) |move| {
        const might_be_correct = move.from().toBitboard() & diff != 0 or move.tp() == .castling;
        if (!might_be_correct) {
            continue;
        }
        var cp = from.*;
        cp.makeMoveSimple(move);
        if (std.meta.eql(cp.mailbox, to.mailbox)) {
            return move;
        }
    }

    return null;
}

inline fn parseLine(line: []const u8) !struct { Board, i16, WDL } {
    var parts = std.mem.tokenizeScalar(u8, line, '|');
    const parsed_board = try Board.parseFen(std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace), true);
    const score = try std.fmt.parseInt(i16, std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace), 10);
    const wdl_float = try std.fmt.parseFloat(f64, std.mem.trim(u8, parts.next() orelse "", &std.ascii.whitespace));
    const wdl: WDL = switch (@as(u2, @intFromFloat(wdl_float * 2))) {
        0 => .loss,
        1 => .draw,
        2 => .win,
        else => return error.InvalidWDL,
    };
    return .{ parsed_board, score, wdl };
}

pub fn convert(
    input: *std.Io.Reader,
    output: *std.Io.Writer,
    skip_broken_games: bool,
    white_relative_scores: bool,
    allocator: std.mem.Allocator,
) !void {
    var position_count: u64 = 0;
    var timer = try std.time.Timer.start();
    var game: viriformat.Game = .from(Board{}, allocator);
    var board: Board = .{};
    var num_broken_games: u64 = 0;
    var num_okay_games: u64 = 0;
    // var previous_hashes = root.BoundedArray(u64, 200){};
    while (try input.takeDelimiter('\n')) |line| {
        if (position_count % 1000 == 0) {
            std.debug.print("{}pos/s {}pos        \r", .{ position_count * std.time.ns_per_s / timer.read(), position_count });
        }
        const parsed_board, const score, const wdl = parseLine(line) catch |e| if (skip_broken_games) {
            std.debug.print("skipping '{s}'\n", .{line});
            num_broken_games += 1;
            continue;
        } else return e;
        position_count += 1;

        defer board = parsed_board;
        if (getConnectingMove(&board, &parsed_board)) |connecting_move| {
            // root.engine.searchers[0].tt = root.engine.tt;
            // root.engine.searchers[0].startSearch(.{
            //     .board = parsed_board,
            //     .limits = .initFixedDepth(3),
            //     .needs_full_reset = true,
            //     .minimal = true,
            //     .normalize = true,
            //     .previous_hashes = .{},
            // }, true, true);
            const white_relative_score = if (white_relative_scores)
                score
            else
                (if (parsed_board.stm == .white) score else -score);
            try game.addMove(connecting_move, white_relative_score);
            // if (board.isNoisy(connecting_move) or board.pieceOn(connecting_move.to()) == .pawn) {
            //     previous_hashes.clear();
            // }
            // previous_hashes.appendAssumeCapacity(parsed_board.hash);
            // const pawnocchio_score =
            //     root.engine.searchers[0].full_width_score_normalized;
            // std.debug.print("{} {}\n", .{ stm_score, pawnocchio_score });
        } else {
            num_okay_games += 1;
            if (game.moves.items.len > 0) {
                try game.serializeInto(output);
            }
            // previous_hashes.clear();
            // previous_hashes.appendAssumeCapacity(parsed_board.hash);
            game.reset(parsed_board);
            game.setOutCome(wdl);
        }
    }
    if (game.moves.items.len > 0) {
        try game.serializeInto(output);
        num_okay_games += 1;
    }

    const elapsed = timer.read();

    try output.flush();
    std.debug.print(
        \\
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
