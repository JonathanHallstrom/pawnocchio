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
const OP_SCALE: usize = 100;
const MIN_INS_DEL_COST: usize = 75;
const MAX_INS_DEL_COST: usize = 125;

pub fn Lookup(comptime Enum: type) type {
    return union(enum) {
        match: Enum,
        closest: struct {
            tag: Enum,
            cost: usize,
        },
    };
}

pub fn matchEnum(
    comptime Enum: type,
    input: []const u8,
    percent: usize,
) ?Lookup(Enum) {
    comptime if (@typeInfo(Enum) != .@"enum") {
        @compileError("matchEnum expects an enum type");
    };

    if (std.meta.stringToEnum(Enum, input)) |tag| {
        return .{ .match = tag };
    }

    if (input.len == 0 or percent == 0) {
        return null;
    }

    const max_name_len: usize = comptime blk: {
        var max_len: usize = 0;
        for (std.meta.fields(Enum)) |field| {
            max_len = @max(max_len, field.name.len);
        }
        break :blk max_len;
    };

    const tags = std.meta.tags(Enum);

    const Closest = @FieldType(Lookup(Enum), "closest");
    var best_prefix: ?Closest = null;
    var best_prefix_len: usize = std.math.maxInt(usize);
    for (tags) |tag| {
        const name = @tagName(tag);
        const min_prefix_len = (name.len * percent + 99) / 100;
        if (!std.mem.startsWith(u8, name, input)) continue;
        if (input.len < min_prefix_len) continue;
        if (name.len >= best_prefix_len) continue;

        const prefix_cost = distanceAtMost(max_name_len, input, name, std.math.maxInt(usize)) orelse continue;
        best_prefix = .{ .tag = tag, .cost = prefix_cost };
        best_prefix_len = name.len;
    }

    if (best_prefix) |closest| {
        return .{ .closest = closest };
    }

    var best_tag: ?Enum = null;
    var best_len: usize = std.math.maxInt(usize);
    var best_dist: usize = std.math.maxInt(usize);
    for (tags) |tag| {
        const name = @tagName(tag);
        const max_dist = name.len * percent - 1;
        const dist = distanceAtMost(max_name_len, input, name, max_dist) orelse continue;
        if (dist > best_dist) continue;
        if (dist == best_dist and name.len >= best_len) continue;

        best_dist = dist;
        best_tag = tag;
        best_len = name.len;
    }

    if (best_tag) |tag| {
        return .{ .closest = .{ .tag = tag, .cost = best_dist } };
    }

    return null;
}

pub fn distanceAtMost(
    comptime max_b_len: usize,
    a: []const u8,
    b: []const u8,
    max_dist: usize,
) ?usize {
    const len_diff = if (a.len > b.len) a.len - b.len else b.len - a.len;
    if (len_diff * MIN_INS_DEL_COST > max_dist) {
        return null;
    }

    var prev_prev: [max_b_len + 1]usize = undefined;
    var prev: [max_b_len + 1]usize = undefined;
    var curr: [max_b_len + 1]usize = undefined;

    prev[0] = 0;
    for (1..b.len + 1) |j| {
        prev[j] = prev[j - 1] + insDelCost(b, j - 1);
    }

    for (1..a.len + 1) |i| {
        curr[0] = prev[0] + insDelCost(a, i - 1);
        var row_min = curr[0];
        for (1..b.len + 1) |j| {
            const substitution_cost = qwertySubCost(a[i - 1], b[j - 1]);
            const deletion = prev[j] + insDelCost(a, i - 1);
            const insertion = curr[j - 1] + insDelCost(b, j - 1);
            const substitution = prev[j - 1] + substitution_cost;

            var transposition: usize = std.math.maxInt(usize);
            if (i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1])
                transposition = prev_prev[j - 2] + OP_SCALE;

            const value = @min(@min(deletion, insertion), @min(substitution, transposition));

            curr[j] = value;
            row_min = @min(row_min, value);
        }

        if (row_min > max_dist) {
            return null;
        }

        const old_prev = prev;
        prev = curr;
        prev_prev = old_prev;
    }

    const dist = prev[b.len];
    return if (dist <= max_dist) dist else null;
}

fn insDelCost(chars: []const u8, idx: usize) usize {
    if (chars.len <= 1) return OP_SCALE;

    var total: usize = 0;
    var count: usize = 0;

    if (idx > 0) {
        total += qwertySubCost(chars[idx], chars[idx - 1]);
        count += 1;
    }
    if (idx + 1 < chars.len) {
        total += qwertySubCost(chars[idx], chars[idx + 1]);
        count += 1;
    }
    if (count == 0) return OP_SCALE;

    const avg = total / count; // [0, 100]
    return MIN_INS_DEL_COST + (avg * (MAX_INS_DEL_COST - MIN_INS_DEL_COST)) / OP_SCALE;
}

fn qwertySubCost(a_char: u8, b_char: u8) usize {
    if (a_char == b_char) return 0;

    const a = qwertyPos(a_char) orelse return OP_SCALE;
    const b = qwertyPos(b_char) orelse return OP_SCALE;

    const dx = if (a.x2 > b.x2) a.x2 - b.x2 else b.x2 - a.x2;
    const dy = if (a.y2 > b.y2) a.y2 - b.y2 else b.y2 - a.y2;
    const manhattan = dx + dy;

    const max_manhattan: usize = 24; // '-' to 'z' in doubled-x coordinates.
    const scaled = manhattan * OP_SCALE / max_manhattan;
    return @max(@as(usize, 1), scaled);
}

const KeyPos = struct {
    x2: usize,
    y2: usize,
};

fn qwertyPos(char: u8) ?KeyPos {
    return switch (std.ascii.toLower(char)) {
        'q' => .{ .x2 = 0, .y2 = 0 },
        'w' => .{ .x2 = 2, .y2 = 0 },
        'e' => .{ .x2 = 4, .y2 = 0 },
        'r' => .{ .x2 = 6, .y2 = 0 },
        't' => .{ .x2 = 8, .y2 = 0 },
        'y' => .{ .x2 = 10, .y2 = 0 },
        'u' => .{ .x2 = 12, .y2 = 0 },
        'i' => .{ .x2 = 14, .y2 = 0 },
        'o' => .{ .x2 = 16, .y2 = 0 },
        'p' => .{ .x2 = 18, .y2 = 0 },
        '-' => .{ .x2 = 20, .y2 = 0 },
        'a' => .{ .x2 = 1, .y2 = 2 },
        's' => .{ .x2 = 3, .y2 = 2 },
        'd' => .{ .x2 = 5, .y2 = 2 },
        'f' => .{ .x2 = 7, .y2 = 2 },
        'g' => .{ .x2 = 9, .y2 = 2 },
        'h' => .{ .x2 = 11, .y2 = 2 },
        'j' => .{ .x2 = 13, .y2 = 2 },
        'k' => .{ .x2 = 15, .y2 = 2 },
        'l' => .{ .x2 = 17, .y2 = 2 },
        'z' => .{ .x2 = 2, .y2 = 4 },
        'x' => .{ .x2 = 4, .y2 = 4 },
        'c' => .{ .x2 = 6, .y2 = 4 },
        'v' => .{ .x2 = 8, .y2 = 4 },
        'b' => .{ .x2 = 10, .y2 = 4 },
        'n' => .{ .x2 = 12, .y2 = 4 },
        'm' => .{ .x2 = 14, .y2 = 4 },
        else => null,
    };
}
