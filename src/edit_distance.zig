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

pub fn Lookup(comptime Enum: type) type {
    return union(enum) {
        match: Enum,
        closest: Enum,
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

    var best_prefix: ?Enum = null;
    var best_prefix_len: usize = std.math.maxInt(usize);
    for (tags) |tag| {
        const name = @tagName(tag);
        const min_prefix_len = (name.len * percent + 99) / 100;
        if (!std.mem.startsWith(u8, name, input)) continue;
        if (input.len < min_prefix_len) continue;
        if (name.len >= best_prefix_len) continue;

        best_prefix = tag;
        best_prefix_len = name.len;
    }

    if (best_prefix) |tag| {
        return .{ .closest = tag };
    }

    var best_tag: ?Enum = null;
    var best_len: usize = std.math.maxInt(usize);
    var best_dist: usize = std.math.maxInt(usize);
    for (tags) |tag| {
        const name = @tagName(tag);
        const max_dist = (name.len * percent - 1) / 100;
        const dist = distanceAtMost(max_name_len, input, name, max_dist) orelse continue;
        if (dist > best_dist) continue;
        if (dist == best_dist and name.len >= best_len) continue;

        best_dist = dist;
        best_tag = tag;
        best_len = name.len;
    }

    if (best_tag) |tag| {
        return .{ .closest = tag };
    }

    return null;
}

pub fn distanceAtMost(
    comptime max_b_len: usize,
    a: []const u8,
    b: []const u8,
    max_dist: usize,
) ?usize {
    if (a.len > b.len + max_dist or b.len > a.len + max_dist) {
        return null;
    }

    var prev_prev: [max_b_len + 1]usize = undefined;
    var prev: [max_b_len + 1]usize = undefined;
    var curr: [max_b_len + 1]usize = undefined;

    for (0..b.len + 1) |j| {
        prev[j] = j;
    }

    for (1..a.len + 1) |i| {
        curr[0] = i;
        var row_min = curr[0];
        for (1..b.len + 1) |j| {
            const mismatch_cost: usize = @intFromBool(a[i - 1] != b[j - 1]);
            const deletion = prev[j] + 1;
            const insertion = curr[j - 1] + 1;
            const substitution = prev[j - 1] + mismatch_cost;

            var transposition: usize = std.math.maxInt(usize);
            if (i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1])
                transposition = prev_prev[j - 2] + 1;

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
