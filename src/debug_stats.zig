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

const StatField = struct {
    label: []const u8,
    name: []const u8,
};

fn formatStatValue(writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void {
    if (value == @round(value)) {
        try writer.print("{d:.0}", .{value});
    } else {
        try writer.print("{d:.4}", .{value});
    }
}

pub const PERCENTILES = [_]f64{
    0.1,
    1,
    5,
    25,
    50,
    75,
    95,
    99,
    99.9,
};

pub const Scalar = struct {
    sum: i64 = 0,
    sum_abs: u64 = 0,
    sum_sqr: u128 = 0,
    count: i64 = 0,
    min: i64 = std.math.maxInt(i64),
    max: i64 = std.math.minInt(i64),

    percentiles: [PERCENTILES.len]f64 = .{0} ** PERCENTILES.len,

    pub const printed_stats = [_]StatField{
        .{ .label = "avg", .name = "getAverage" },
        .{ .label = "avg abs", .name = "getAverageAbs" },
        .{ .label = "std dev", .name = "getStandardDeviation" },
        .{ .label = "min", .name = "getMin" },
        .{ .label = "max", .name = "getMax" },
        .{ .label = "skew", .name = "getSkewness" },
        .{ .label = "count", .name = "getCount" },
    };

    const Self = @This();

    pub fn reset(self: *Self) void {
        self.* = .{};
    }

    pub fn add(self: *Self, data_point: i64, rng: std.Random) void {
        self.sum += data_point;
        self.sum_abs += @abs(data_point);
        self.sum_sqr += @as(u128, @abs(data_point)) * @abs(data_point);
        self.count += 1;
        self.min = @min(self.min, data_point);
        self.max = @max(self.max, data_point);

        const data_point_f: f64 = @floatFromInt(data_point);
        const step = 0.001 * (1 + self.getStandardDeviation());

        const r = rng.float(f64);
        inline for (PERCENTILES, 0..) |pct, i| {
            const p = pct / 100.0;

            if (data_point_f > self.percentiles[i] and r > 1 - p) {
                self.percentiles[i] += step;
            } else if (data_point_f < self.percentiles[i] and r > p) {
                self.percentiles[i] -= step;
            }
            self.percentiles[i] = std.math.clamp(
                self.percentiles[i],
                @as(f64, @floatFromInt(self.min)),
                @as(f64, @floatFromInt(self.max)),
            );
        }
    }

    pub fn getMedian(self: *const Self) f64 {
        return inline for (PERCENTILES, 0..) |pct, i| {
            if (pct == 50) {
                break self.percentiles[i];
            }
        } else @compileError("need 50th percentile to compute median\n");
    }

    pub fn getSkewness(self: *const Self) f64 {
        const std_dev = self.getStandardDeviation();
        if (std_dev == 0) return 0;
        return (self.getAverage() - self.getMedian()) / std_dev;
    }

    pub fn getAverage(self: *const Self) f64 {
        const n = @max(1, self.count);
        return @as(f64, @floatFromInt(self.sum)) / @as(f64, @floatFromInt(n));
    }

    pub fn getAverageAbs(self: *const Self) f64 {
        const n = @max(1, self.count);
        return @as(f64, @floatFromInt(self.sum_abs)) / @as(f64, @floatFromInt(n));
    }

    pub fn getVariance(self: *const Self) f64 {
        const s: f64 = @floatFromInt(self.sum);
        const ss: f64 = @floatFromInt(self.sum_sqr);
        const n: f64 = @floatFromInt(@max(1, self.count));
        return (ss - s * s / n) / n;
    }

    pub fn getStandardDeviation(self: *const Self) f64 {
        return @sqrt(self.getVariance());
    }

    pub fn getMin(self: *const Self) f64 {
        return @floatFromInt(self.min);
    }

    pub fn getMax(self: *const Self) f64 {
        return @floatFromInt(self.max);
    }

    pub fn getCount(self: *const Self) f64 {
        return @floatFromInt(self.count);
    }

    pub fn format(
        self: Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        inline for (printed_stats) |field| {
            try writer.print("  {s}:  ", .{field.label});
            try formatStatValue(writer, self.statValue(field.name));
            try writer.writeByte('\n');
        }
        try writer.writeAll("  percentiles:\n");
        inline for (PERCENTILES, 0..) |pct, i| {
            const percentile_str = std.fmt.comptimePrint("{d}:", .{pct});
            try writer.print("    {s:<5} ", .{percentile_str});
            try formatStatValue(writer, self.percentiles[i]);
            try writer.writeByte('\n');
        }
    }

    fn statValue(self: *const Self, comptime name: []const u8) f64 {
        return @field(Self, name)(self);
    }
};

pub const Range = struct {
    granularity: i64,
    min_bucket: i64 = std.math.maxInt(i64),
    max_bucket: i64 = std.math.minInt(i64),
    overall: Scalar = .{},
    buckets: std.AutoHashMap(i64, Scalar),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, granularity: i64) Self {
        std.debug.assert(granularity > 0);
        return .{
            .granularity = granularity,
            .buckets = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buckets.deinit();
    }

    pub fn reset(self: *Self) void {
        self.min_bucket = std.math.maxInt(i64);
        self.max_bucket = std.math.minInt(i64);
        self.overall.reset();
        self.buckets.clearRetainingCapacity();
    }

    pub fn add(self: *Self, index: i64, data_point: i64, rng: std.Random) void {
        self.overall.add(data_point, rng);

        const bucket = @divFloor(index, self.granularity);
        self.min_bucket = @min(self.min_bucket, bucket);
        self.max_bucket = @max(self.max_bucket, bucket);

        const gp = self.buckets.getOrPut(bucket) catch unreachable;
        if (!gp.found_existing) {
            gp.value_ptr.* = .{};
        }
        gp.value_ptr.add(data_point, rng);
    }

    pub fn format(
        self: *const Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try self.overall.format(writer);
        try writer.writeAll("  buckets:\n");
        try writer.print("    start: {d}\n", .{if (self.hasBuckets()) self.min_bucket * self.granularity else 0});
        try writer.print("    granularity: {d}\n", .{self.granularity});
        inline for (Scalar.printed_stats) |field| {
            try writer.print("    {s}: [", .{field.label});
            if (self.hasBuckets()) {
                var first = true;
                var bucket = self.min_bucket;
                while (bucket <= self.max_bucket) : (bucket += 1) {
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    const value = if (self.buckets.get(bucket)) |stats| stats.statValue(field.name) else 0;
                    try formatStatValue(writer, value);
                }
            }
            try writer.writeAll("]\n");
        }
        try writer.writeAll("    percentiles:\n");
        inline for (PERCENTILES, 0..) |pct, i| {
            const percentile_str = std.fmt.comptimePrint("{d}:", .{pct});
            try writer.print("      {s:<5} [", .{percentile_str});
            if (self.hasBuckets()) {
                var first = true;
                var bucket = self.min_bucket;
                while (bucket <= self.max_bucket) : (bucket += 1) {
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    const value = if (self.buckets.get(bucket)) |stats| stats.percentiles[i] else 0;
                    try formatStatValue(writer, value);
                }
            }
            try writer.writeAll("]\n");
        }
    }

    fn hasBuckets(self: *const Self) bool {
        return self.min_bucket <= self.max_bucket;
    }
};
