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
const BoundedArray = root.BoundedArray;
const OP_SCALE: usize = 100;
const MIN_INS_DEL_COST: usize = 15;
const MAX_INS_DEL_COST: usize = 100;
const TRANSPOSITION_COST: usize = 10;

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
    base_cost: usize,
    percent: usize,
) ?Lookup(Enum) {
    comptime if (@typeInfo(Enum) != .@"enum") {
        @compileError("matchEnum expects an enum type");
    };

    if (exactEnumMatch(Enum, input)) |tag| {
        return .{ .match = tag };
    }

    if (input.len == 0) {
        return null;
    }

    const max_name_len = maxEnumNameLen(Enum);
    if (bestPrefixMatch(Enum, input, base_cost, percent, max_name_len)) |closest| {
        return .{ .closest = closest };
    }

    if (bestDistanceMatch(Enum, input, base_cost, percent, max_name_len)) |closest| {
        return .{ .closest = closest };
    }

    const cleaned = cleanName(Enum, input);
    if (cleaned.len == input.len and std.mem.eql(u8, cleaned.slice(), input)) {
        return null;
    }

    if (bestPrefixMatch(Enum, cleaned.slice(), base_cost, percent, max_name_len)) |closest| {
        return .{ .closest = closest };
    }

    if (bestDistanceMatch(Enum, cleaned.slice(), base_cost, percent, max_name_len)) |closest| {
        return .{ .closest = closest };
    }

    return null;
}

fn exactEnumMatch(comptime Enum: type, input: []const u8) ?Enum {
    return std.meta.stringToEnum(Enum, input);
}

fn maxNameDistance(base_cost: usize, percent: usize, name_len: usize) usize {
    return base_cost + name_len * percent;
}

inline fn maxEnumNameLen(comptime Enum: type) usize {
    return comptime blk: {
        var max_len: usize = 0;
        for (std.meta.fields(Enum)) |field| {
            max_len = @max(max_len, field.name.len);
        }
        break :blk max_len;
    };
}

fn bestPrefixMatch(
    comptime Enum: type,
    input: []const u8,
    base_cost: usize,
    percent: usize,
    comptime max_name_len: usize,
) ?@FieldType(Lookup(Enum), "closest") {
    const Closest = @FieldType(Lookup(Enum), "closest");
    var best: ?Closest = null;
    var best_name_len: usize = std.math.maxInt(usize);
    var best_cost: usize = std.math.maxInt(usize);

    for (std.meta.tags(Enum)) |tag| {
        const name = @tagName(tag);
        if (!std.mem.startsWith(u8, name, input)) continue;
        const cost = distanceAtMost(max_name_len, input, name, maxNameDistance(base_cost, percent, name.len)) orelse continue;
        if (name.len > best_name_len) continue;
        if (name.len == best_name_len and cost >= best_cost) continue;

        best = .{
            .tag = tag,
            .cost = cost,
        };
        best_cost = cost;
        best_name_len = name.len;
    }

    return best;
}

fn bestDistanceMatch(
    comptime Enum: type,
    input: []const u8,
    base_cost: usize,
    percent: usize,
    comptime max_name_len: usize,
) ?@FieldType(Lookup(Enum), "closest") {
    const Closest = @FieldType(Lookup(Enum), "closest");
    var best: ?Closest = null;
    var best_name_len: usize = std.math.maxInt(usize);
    var best_cost: usize = std.math.maxInt(usize);

    for (std.meta.tags(Enum)) |tag| {
        const name = @tagName(tag);
        const cost = distanceAtMost(max_name_len, input, name, maxNameDistance(base_cost, percent, name.len)) orelse continue;
        if (cost > best_cost) continue;
        if (cost == best_cost and name.len >= best_name_len) continue;

        best = .{
            .tag = tag,
            .cost = cost,
        };
        best_cost = cost;
        best_name_len = name.len;
    }

    return best;
}

pub fn distanceAtMost(
    comptime max_b_len: usize,
    a: []const u8,
    b: []const u8,
    max_dist: usize,
) ?usize {
    var best: ?usize = null;
    const len_diff = if (a.len > b.len) a.len - b.len else b.len - a.len;

    var dy2: i8 = -6;
    while (dy2 <= 6) : (dy2 += 2) {
        var dx2: i8 = -4;
        while (dx2 <= 4) : (dx2 += 1) {
            const penalty = @as(usize, @intCast(dx2 * dx2 + dy2 * dy2)) * 3;

            if (penalty > max_dist) {
                continue;
            }

            const adjusted_max = max_dist - penalty;
            if (len_diff * MIN_INS_DEL_COST > adjusted_max) {
                continue;
            }

            var prev_prev: [max_b_len + 1]usize = undefined;
            var prev: [max_b_len + 1]usize = undefined;
            var curr: [max_b_len + 1]usize = undefined;

            prev[0] = 0;
            for (1..b.len + 1) |j| {
                prev[j] = prev[j - 1] + editCost(b, j - 1, dx2, dy2);
            }

            var exceeded = false;
            for (1..a.len + 1) |i| {
                curr[0] = prev[0] + editCost(a, i - 1, dx2, dy2);
                var row_min = curr[0];
                for (1..b.len + 1) |j| {
                    const substitution_cost = qwertyDistance(a[i - 1], b[j - 1], dx2, dy2);
                    const deletion = prev[j] + editCost(a, i - 1, dx2, dy2);
                    const insertion = curr[j - 1] + editCost(b, j - 1, dx2, dy2);
                    const substitution = prev[j - 1] + substitution_cost;

                    var transposition: usize = std.math.maxInt(usize);
                    if (i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1])
                        transposition = prev_prev[j - 2] + TRANSPOSITION_COST;

                    const value = @min(@min(deletion, insertion), @min(substitution, transposition));
                    curr[j] = value;
                    row_min = @min(row_min, value);
                }

                if (row_min > adjusted_max) {
                    exceeded = true;
                    break;
                }

                const old_prev = prev;
                prev = curr;
                prev_prev = old_prev;
            }

            if (exceeded) {
                continue;
            }

            const dist = prev[b.len];
            if (dist > adjusted_max) {
                continue;
            }

            const total = dist + penalty;
            if (best == null or total < best.?) {
                best = total;
            }
        }
    }
    return best;
}

fn editCost(chars: []const u8, idx: usize, dx: i8, dy: i8) usize {
    if (chars.len <= 1) return OP_SCALE;

    var total: usize = 0;
    var count: usize = 0;

    if (idx > 0) {
        total += qwertyDistance(chars[idx], chars[idx - 1], dx, dy);
        count += 1;
    }
    if (idx + 1 < chars.len) {
        total += qwertyDistance(chars[idx], chars[idx + 1], dx, dy);
        count += 1;
    }

    return MIN_INS_DEL_COST + (total * (MAX_INS_DEL_COST - MIN_INS_DEL_COST)) / (count * OP_SCALE);
}

fn qwertyDistance(a_char: u8, b_char: u8, dx: i8, dy: i8) usize {
    if (a_char == b_char) return 0;

    const a = qwertyPos(a_char) orelse return OP_SCALE;
    const b = qwertyPos(b_char) orelse return OP_SCALE;
    const shifted_a = a.shift(dx, dy);
    return @min(
        OP_SCALE,
        @max(@as(usize, 1), KeyPos.squaredDistance(shifted_a, b) * OP_SCALE / MAX_QWERTY_SQUARED_DISTANCE),
    );
}

const KeyPos = struct {
    x: i8,
    y: i8,

    fn shift(self: KeyPos, dx: i8, dy: i8) KeyPos {
        return .{
            .x = self.x + dx,
            .y = self.y + dy,
        };
    }

    fn squaredDistance(a: KeyPos, b: KeyPos) usize {
        const dx: i32 = a.x - b.x;
        const dy: i32 = a.y - b.y;
        return @intCast(dx * dx + dy * dy);
    }
};

const QWERTY_POS_TABLE: [256]?KeyPos = blk: {
    var table: [256]?KeyPos = @splat(null);

    table['1'] = .{ .x = -1, .y = -2 };
    table['2'] = .{ .x = 1, .y = -2 };
    table['3'] = .{ .x = 3, .y = -2 };
    table['4'] = .{ .x = 5, .y = -2 };
    table['5'] = .{ .x = 7, .y = -2 };
    table['6'] = .{ .x = 9, .y = -2 };
    table['7'] = .{ .x = 11, .y = -2 };
    table['8'] = .{ .x = 13, .y = -2 };
    table['9'] = .{ .x = 15, .y = -2 };
    table['0'] = .{ .x = 17, .y = -2 };

    table['q'] = .{ .x = 0, .y = 0 };
    table['w'] = .{ .x = 2, .y = 0 };
    table['e'] = .{ .x = 4, .y = 0 };
    table['r'] = .{ .x = 6, .y = 0 };
    table['t'] = .{ .x = 8, .y = 0 };
    table['y'] = .{ .x = 10, .y = 0 };
    table['u'] = .{ .x = 12, .y = 0 };
    table['i'] = .{ .x = 14, .y = 0 };
    table['o'] = .{ .x = 16, .y = 0 };
    table['p'] = .{ .x = 18, .y = 0 };

    // not sure where these are on all keyboards, they seem to mostly cluster around here tho
    table['-'] = .{ .x = 20, .y = 0 };
    table['_'] = .{ .x = 20, .y = 0 };
    table[','] = .{ .x = 20, .y = 0 };
    table[';'] = .{ .x = 20, .y = 0 };
    table[':'] = .{ .x = 20, .y = 0 };
    table['^'] = .{ .x = 20, .y = 0 };
    table['\''] = .{ .x = 20, .y = 0 };
    table['´'] = .{ .x = 20, .y = 0 };
    table['`'] = .{ .x = 20, .y = 0 };

    table['a'] = .{ .x = 1, .y = 2 };
    table['s'] = .{ .x = 3, .y = 2 };
    table['d'] = .{ .x = 5, .y = 2 };
    table['f'] = .{ .x = 7, .y = 2 };
    table['g'] = .{ .x = 9, .y = 2 };
    table['h'] = .{ .x = 11, .y = 2 };
    table['j'] = .{ .x = 13, .y = 2 };
    table['k'] = .{ .x = 15, .y = 2 };
    table['l'] = .{ .x = 17, .y = 2 };

    table['z'] = .{ .x = 2, .y = 4 };
    table['x'] = .{ .x = 4, .y = 4 };
    table['c'] = .{ .x = 6, .y = 4 };
    table['v'] = .{ .x = 8, .y = 4 };
    table['b'] = .{ .x = 10, .y = 4 };
    table['n'] = .{ .x = 12, .y = 4 };
    table['m'] = .{ .x = 14, .y = 4 };
    table['<'] = .{ .x = 16, .y = 4 };
    table['>'] = .{ .x = 16, .y = 4 };

    break :blk table;
};

const MAX_QWERTY_SQUARED_DISTANCE: usize = blk: {
    @setEvalBranchQuota(1 << 20);
    var max_distance: usize = 1;
    for (QWERTY_POS_TABLE, 0..) |a_opt, i| {
        const a = a_opt orelse continue;
        for (QWERTY_POS_TABLE[i + 1 ..]) |b_opt| {
            const b = b_opt orelse continue;
            max_distance = @max(max_distance, KeyPos.squaredDistance(a, b));
        }
    }
    break :blk max_distance;
};

fn qwertyPos(char: u8) ?KeyPos {
    return QWERTY_POS_TABLE[std.ascii.toLower(char)];
}

const QWERTY_CONTAINED_CHARS = blk: {
    @setEvalBranchQuota(1 << 20);
    var res: std.StaticBitSet(256) = .initEmpty();
    for (0..256) |char| {
        res.setValue(char, qwertyPos(char) != null);
    }
    break :blk res;
};

fn cleanName(
    comptime Enum: type,
    input: []const u8,
) BoundedArray(u8, maxEnumNameLen(Enum) * 3 / 2) {
    var res: BoundedArray(u8, maxEnumNameLen(Enum) * 3 / 2) = .{};

    for (input) |char| {
        if (QWERTY_CONTAINED_CHARS.isSet(char)) {
            res.append(char) catch break;
        }
    }

    return res;
}
