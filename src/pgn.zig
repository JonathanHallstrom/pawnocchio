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
const LeanBoard = root.LeanBoard;
const Move = root.Move;
const WDL = root.WDL;
const dataformat = root.dataformat;
const ScoredPly = dataformat.ScoredPly;

pub const ScoredPlyReader = struct {
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),

    pub const Iter = struct {
        text: []const u8,
        cursor: usize,
        board: LeanBoard,
        pending: ?Move = null,
        exhausted: bool = false,

        pub fn next(self: *Iter) !?ScoredPly {
            if (self.exhausted) return null;

            if (self.pending) |move| {
                self.board.makeMove(move);
                self.pending = null;
            }

            while (self.cursor < self.text.len) {
                const remainder = self.text[self.cursor..];

                switch (remainder[0]) {
                    ' ', '\t', '\r', '\n' => {
                        self.cursor += 1;
                        continue;
                    },
                    '0'...'9' => {
                        if (isStartOfGameTerminationMarker(remainder)) {
                            self.exhausted = true;
                            return null;
                        }
                        var end: usize = 1;
                        while (end < remainder.len and std.ascii.isDigit(remainder[end])) end += 1;
                        if (end < remainder.len and remainder[end] == '.') {
                            while (end < remainder.len and (std.ascii.isDigit(remainder[end]) or remainder[end] == '.')) end += 1;
                            self.cursor += end;
                            continue;
                        }
                    },
                    '{' => {
                        var end: usize = 1;
                        while (end < remainder.len and remainder[end] != '}') end += 1;
                        self.cursor += @min(end + 1, remainder.len);
                        continue;
                    },
                    '$' => {
                        var end: usize = 1;
                        while (end < remainder.len and std.ascii.isDigit(remainder[end])) end += 1;
                        self.cursor += end;
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
                    else => {},
                }

                var move_text_len: usize = 0;
                while (move_text_len < remainder.len and !TOKEN_END[remainder[move_text_len]]) move_text_len += 1;
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
                var comment_start: usize = self.cursor;
                while (comment_start < self.text.len and std.ascii.isWhitespace(self.text[comment_start])) comment_start += 1;
                if (comment_start < self.text.len and self.text[comment_start] == '{') {
                    var comment_end: usize = comment_start + 1;
                    while (comment_end < self.text.len and self.text[comment_end] != '}') comment_end += 1;
                    if (comment_end < self.text.len) {
                        eval = parseEval(self.text[comment_start + 1 .. comment_end]);
                        self.cursor = comment_end + 1;
                    }
                }

                const white_eval = if (eval) |ev| (if (self.board.stm == .black) -ev else ev) else null;
                self.pending = move;

                return .{
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

        while (true) {
            const window = self.reader.buffered();
            if (window.len == 0) {
                self.reader.fillMore() catch |e| switch (e) {
                    error.EndOfStream => return null,
                    else => return e,
                };
                continue;
            }
            const non_ws = std.mem.indexOfNone(u8, window, &std.ascii.whitespace) orelse {
                self.reader.toss(window.len);
                continue;
            };
            self.reader.toss(non_ws);
            break;
        }

        var seen_movetext = false;

        while (true) {
            const window = self.reader.buffered();
            if (window.len == 0) {
                self.reader.fillMore() catch |e| switch (e) {
                    error.EndOfStream => {
                        if (self.buffer.items.len > 0 and isGameTerminationMarker(self.buffer.items)) {
                            return try GameView.fromText(self.buffer.items);
                        }
                        return null;
                    },
                    else => return e,
                };
                continue;
            }
            if (self.buffer.items.len > 0 and self.buffer.items[self.buffer.items.len - 1] == '\n') {
                const first_byte = window[0];
                if (first_byte == '[') {
                    if (seen_movetext) {
                        return try GameView.fromText(self.buffer.items);
                    }
                } else if (first_byte != '\r' and first_byte != '\n') {
                    seen_movetext = true;
                }
            }
            var scan_pos: usize = 0;
            while (scan_pos < window.len) {
                const newline = findByteFrom(window, scan_pos, '\n') orelse break;
                if (newline + 1 >= window.len) break;
                const next_byte = window[newline + 1];
                if (next_byte == '[') {
                    if (seen_movetext) {
                        try self.buffer.appendSlice(self.allocator, window[0 .. newline + 1]);
                        self.reader.toss(newline + 1);
                        return try GameView.fromText(self.buffer.items);
                    }
                } else if (next_byte != '\r' and next_byte != '\n') {
                    seen_movetext = true;
                }
                scan_pos = newline + 1;
            }
            try self.buffer.appendSlice(self.allocator, window);
            self.reader.toss(window.len);
        }
    }

    pub fn deinit(self: *ScoredPlyReader) void {
        self.buffer.deinit(self.allocator);
    }
};

const SCAN_WIDTH = 32;

fn findByteFrom(haystack: []const u8, start: usize, comptime needle: u8) ?usize {
    var i = start;
    while (i + SCAN_WIDTH <= haystack.len) : (i += SCAN_WIDTH) {
        const chunk: @Vector(SCAN_WIDTH, u8) = haystack[i..][0..SCAN_WIDTH].*;
        const matches: u32 = @bitCast(chunk == @as(@Vector(SCAN_WIDTH, u8), @splat(needle)));
        if (matches != 0) return i + @ctz(matches);
    }
    while (i < haystack.len) : (i += 1) {
        if (haystack[i] == needle) return i;
    }
    return null;
}

fn byteSet(comptime chars: []const u8) [256]bool {
    var set = std.mem.zeroes([256]bool);
    for (chars) |c| set[c] = true;
    return set;
}

const TOKEN_END = byteSet(std.ascii.whitespace ++ "{(!$?");
const EVAL_DELIMS = byteSet(std.ascii.whitespace ++ "/{}");

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

pub const GameView = struct {
    text: []const u8,
    initial_board: LeanBoard,
    outcome: WDL,
    move_section_offset: usize,

    pub fn fromText(text: []const u8) !GameView {
        var fen: ?[]const u8 = null;
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
                                    fen = header[start .. start + q2];
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

        const initial_board = if (fen) |f| try LeanBoard.parseFen(f, true) else LeanBoard.fromBoard(&Board.startpos());
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
    var i: usize = 0;
    while (i < info.len and EVAL_DELIMS[info[i]]) i += 1;
    var j: usize = i;
    while (j < info.len and !EVAL_DELIMS[info[j]]) j += 1;
    if (j == i) return null;
    return parseScoreStr(info[i..j]) catch null;
}

fn parseScoreStr(score_str: []const u8) !i16 {
    var s = score_str;
    var neg = false;
    if (s.len > 0 and (s[0] == '+' or s[0] == '-')) {
        neg = s[0] == '-';
        s = s[1..];
    }
    if (s.len == 0 or s.len > 8) return error.InvalidScore;
    if (s[0] == 'M') return if (neg) -32767 else 32767;
    if (s.len < 4 or s[s.len - 3] != '.') return error.InvalidScore;
    var cp: i64 = 0;
    for (s[0 .. s.len - 3]) |c| {
        const d = c -% '0';
        if (d > 9) return error.InvalidScore;
        cp = cp * 10 + d;
    }
    const tenths = s[s.len - 2] -% '0';
    const hundredths = s[s.len - 1] -% '0';
    if (tenths > 9 or hundredths > 9) return error.InvalidScore;
    cp = cp * 100 + tenths * 10 + hundredths;
    if (neg) cp = -cp;
    return @intCast(std.math.clamp(cp, -32767, 32767));
}

pub fn scoredPlyReader(reader: *std.Io.Reader, allocator: std.mem.Allocator) ScoredPlyReader {
    return .{
        .reader = reader,
        .allocator = allocator,
        .buffer = .empty,
    };
}
