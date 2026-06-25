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
const Move = root.Move;
const WDL = root.WDL;
const dataformat = root.dataformat;
const ScoredPly = dataformat.ScoredPly;
const ScoredMove = dataformat.ScoredMove;

pub const ScoredPlyReader = struct {
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),
    move_buffer: std.ArrayListUnmanaged(ScoredMove),
    initial_board: Board,

    pub const Iter = struct {
        text: []const u8,
        cursor: usize,
        board: Board,
        pending: ?Move = null,
        exhausted: bool = false,

        pub fn next(self: *Iter) !?ScoredPly {
            if (self.exhausted) return null;

            if (self.pending) |move| {
                self.board.makeMoveSimple(move);
                self.pending = null;
            }

            while (self.cursor < self.text.len) {
                const remainder = self.text[self.cursor..];

                if (isStartOfGameTerminationMarker(remainder)) {
                    self.exhausted = true;
                    return null;
                }

                switch (remainder[0]) {
                    '0'...'9' => {
                        const end_of_num = std.mem.indexOfNone(u8, remainder, "0123456789") orelse remainder.len;
                        if (end_of_num < remainder.len and remainder[end_of_num] == '.') {
                            self.cursor += std.mem.indexOfNone(u8, remainder, "0123456789.") orelse remainder.len;
                            continue;
                        }
                    },
                    '{' => {
                        self.cursor += if (std.mem.indexOfScalar(u8, remainder, '}')) |end| end + 1 else remainder.len;
                        continue;
                    },
                    '$' => {
                        self.cursor += if (std.mem.indexOfNone(u8, remainder[1..], "0123456789")) |end| end + 1 else remainder.len;
                        continue;
                    },
                    '(' => {
                        var depth: usize = 0;
                        for (remainder, 0..) |c, i| {
                            if (c == '(') depth += 1;
                            if (c == ')') depth -= 1;
                            if (depth == 0) {
                                self.cursor += i + 1;
                                break;
                            }
                        } else {
                            self.cursor = self.text.len;
                        }
                        continue;
                    },
                    else => |c| {
                        if (std.ascii.isWhitespace(c)) {
                            self.cursor += 1;
                            continue;
                        }
                    },
                }

                const move_text_len = std.mem.indexOfAny(u8, remainder, &std.ascii.whitespace ++ "{(!$!?") orelse remainder.len;
                if (move_text_len == 0) {
                    self.cursor += 1;
                    continue;
                }
                const move_text = remainder[0..move_text_len];
                self.cursor += move_text_len;

                const move = self.board.parseSANMove(move_text) orelse {
                    continue;
                };

                var eval: ?i16 = null;
                const after_move = self.text[self.cursor..];
                const trimmed_after = std.mem.trimStart(u8, after_move, &std.ascii.whitespace);
                if (std.mem.startsWith(u8, trimmed_after, "{")) {
                    if (std.mem.indexOfScalar(u8, trimmed_after, '}')) |end_brace| {
                        const comment = trimmed_after[1..end_brace];
                        self.cursor += (trimmed_after.ptr - after_move.ptr) + end_brace + 1;

                        eval = parseEval(comment);
                    }
                }

                const white_eval = if (eval) |ev| (if (self.board.stm == .black) -ev else ev) else null;
                self.pending = move;

                return ScoredPly{
                    .board = &self.board,
                    .move = move,
                    ._eval = white_eval,
                };
            }

            self.exhausted = true;
            return null;
        }
    };

    pub fn next(self: *ScoredPlyReader) !?GameView {
        self.buffer.clearRetainingCapacity();

        var byte: u8 = undefined;
        while (true) {
            byte = self.reader.takeByte() catch |e| switch (e) {
                error.EndOfStream => return null,
                else => return e,
            };
            if (!std.ascii.isWhitespace(byte)) break;
        }

        try self.buffer.append(self.allocator, byte);

        var bracket_depth: usize = if (byte == '[') 1 else 0;
        var brace_depth: usize = if (byte == '{') 1 else 0;
        var paren_depth: usize = if (byte == '(') 1 else 0;

        var seen_marker = false;
        while (true) {
            byte = self.reader.takeByte() catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
            };
            try self.buffer.append(self.allocator, byte);

            switch (byte) {
                '[' => if (brace_depth == 0 and paren_depth == 0) {
                    bracket_depth += 1;
                },
                ']' => if (brace_depth == 0 and paren_depth == 0 and bracket_depth > 0) {
                    bracket_depth -= 1;
                },
                '{' => brace_depth += 1,
                '}' => if (brace_depth > 0) {
                    brace_depth -= 1;
                },
                '(' => if (brace_depth == 0) {
                    paren_depth += 1;
                },
                ')' => if (brace_depth == 0 and paren_depth > 0) {
                    paren_depth -= 1;
                },
                else => {},
            }

            if (bracket_depth == 0 and brace_depth == 0 and paren_depth == 0) {
                if (isGameTerminationMarker(self.buffer.items)) {
                    seen_marker = true;
                    break;
                }
            }
        }

        if (self.buffer.items.len == 0 or !seen_marker) return null;

        return try GameView.fromText(self.buffer.items);
    }

    pub fn deinit(self: *ScoredPlyReader) void {
        self.buffer.deinit(self.allocator);
        self.move_buffer.deinit(self.allocator);
    }

    pub fn toDynamic(self: *ScoredPlyReader) root.dynamic_reader.DynamicReader {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &pgn_reader_vtable,
        };
    }
};

const TERMINATION_MARKERS = [_][]const u8{ "1-0", "0-1", "1/2-1/2" };

fn isGameTerminationMarker(text: []const u8) bool {
    const trimmed = std.mem.trimEnd(u8, text, &std.ascii.whitespace);
    inline for (TERMINATION_MARKERS) |marker| {
        if (std.mem.endsWith(u8, trimmed, marker)) {
            const prefix = trimmed[0 .. trimmed.len - marker.len];
            if (prefix.len == 0 or std.ascii.isWhitespace(prefix[prefix.len - 1])) {
                return true;
            }
        }
    }
    return false;
}

fn isStartOfGameTerminationMarker(text: []const u8) bool {
    const trimmed = std.mem.trimStart(u8, text, &std.ascii.whitespace);
    inline for (TERMINATION_MARKERS) |marker| {
        if (std.mem.startsWith(u8, trimmed, marker)) {
            return true;
        }
    }
    return false;
}

const DynamicReader = root.dynamic_reader.DynamicReader;
const DynamicGameView = root.dynamic_reader.DynamicGameView;

const pgn_reader_vtable: DynamicReader.VTable = .{
    .next = pgnReaderNext,
    .deinit = pgnReaderDeinit,
};

fn pgnReaderNext(ptr: *anyopaque) !?DynamicGameView {
    const reader: *ScoredPlyReader = @ptrCast(@alignCast(ptr));
    const game_view = try reader.next() orelse return null;

    reader.initial_board = game_view.initial_board;
    reader.move_buffer.clearRetainingCapacity();
    var it = game_view.iter();
    while (try it.next()) |ply| {
        try reader.move_buffer.append(reader.allocator, .{
            .move = ply.move,
            .score = ply.whiteEval(),
        });
    }

    return DynamicGameView{
        .initial_board = &reader.initial_board,
        .outcome = game_view.outcome,
        .moves = reader.move_buffer.items,
    };
}

fn pgnReaderDeinit(ptr: *anyopaque) void {
    const reader: *ScoredPlyReader = @ptrCast(@alignCast(ptr));
    reader.deinit();
}

pub const GameView = struct {
    text: []const u8,
    initial_board: Board,
    outcome: WDL,
    move_section_offset: usize,

    pub fn fromText(text: []const u8) !GameView {
        var initial_board = Board.startpos();
        var outcome: WDL = .draw;
        var move_section_offset: usize = 0;

        while (move_section_offset < text.len) {
            const remainder = text[move_section_offset..];
            switch (remainder[0]) {
                '[' => {
                    if (std.mem.indexOfScalar(u8, remainder, ']')) |end| {
                        const header = remainder[1..end];
                        if (std.mem.indexOf(u8, header, "FEN")) |fen_idx| {
                            if (std.mem.indexOfScalar(u8, header[fen_idx..], '"')) |q1| {
                                const start = fen_idx + q1 + 1;
                                if (std.mem.indexOfScalar(u8, header[start..], '"')) |q2| {
                                    const fen = header[start .. start + q2];
                                    initial_board = try Board.parseFen(fen, true);
                                }
                            }
                        } else if (std.mem.indexOf(u8, header, "Result")) |res_idx| {
                            if (std.mem.indexOfScalar(u8, header[res_idx..], '"')) |q1| {
                                const start = res_idx + q1 + 1;
                                if (std.mem.indexOfScalar(u8, header[start..], '"')) |q2| {
                                    const result_val = header[start .. start + q2];
                                    if (std.mem.eql(u8, result_val, "1-0")) outcome = .win;
                                    if (std.mem.eql(u8, result_val, "0-1")) outcome = .loss;
                                    if (std.mem.eql(u8, result_val, "1/2-1/2")) outcome = .draw;
                                }
                            }
                        }
                        move_section_offset += end + 1;
                        continue;
                    }
                    break;
                },
                inline else => |c| if (std.ascii.isWhitespace(c)) {
                    move_section_offset += 1;
                    continue;
                } else break,
            }
        }

        const trimmed = std.mem.trim(u8, text, &std.ascii.whitespace);
        if (std.mem.endsWith(u8, trimmed, "1-0")) {
            outcome = .win;
        } else if (std.mem.endsWith(u8, trimmed, "0-1")) {
            outcome = .loss;
        } else if (std.mem.endsWith(u8, trimmed, "1/2-1/2")) {
            outcome = .draw;
        }

        return .{
            .text = text,
            .initial_board = initial_board,
            .outcome = outcome,
            .move_section_offset = move_section_offset,
        };
    }

    pub fn iter(self: GameView) ScoredPlyReader.Iter {
        return .{
            .text = self.text,
            .cursor = self.move_section_offset,
            .board = self.initial_board,
        };
    }
};

fn parseEval(info: []const u8) ?i16 {
    if (std.mem.indexOf(u8, info, "[%eval ")) |index| {
        const start = index + "[%eval ".len;
        const end = std.mem.indexOfScalarPos(u8, info, start, ']') orelse info.len;
        return parseScoreStr(info[start..end]) catch null;
    }

    var it = std.mem.tokenizeAny(u8, info, &std.ascii.whitespace ++ "/{}");
    if (it.next()) |score_str| {
        return parseScoreStr(score_str) catch null;
    }
    return null;
}

fn parseScoreStr(score_str: []const u8) !i16 {
    if (score_str.len == 0) return error.Empty;
    if (std.mem.indexOfAny(u8, score_str, "M#") != null) {
        const sign: i16 = if (std.mem.startsWith(u8, score_str, "-")) -1 else 1;
        return sign * 32767;
    }
    const val = try std.fmt.parseFloat(f64, score_str);
    const clamped = std.math.clamp(val, -327.67, 327.67);
    return @intFromFloat(clamped * 100);
}

pub fn scoredPlyReader(reader: *std.Io.Reader, allocator: std.mem.Allocator) ScoredPlyReader {
    return .{
        .reader = reader,
        .allocator = allocator,
        .buffer = .empty,
        .move_buffer = .empty,
        .initial_board = undefined,
    };
}
