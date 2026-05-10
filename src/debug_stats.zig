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

fn formatStatValue(writer: *std.Io.Writer, value: f64) std.Io.Writer.Error!void {
    if (value == @round(value)) {
        try writer.print("{d:.0}", .{value});
    } else {
        try writer.print("{d:.4}", .{value});
    }
}

fn formatNamedStat(writer: *std.Io.Writer, label: []const u8, value: f64) std.Io.Writer.Error!void {
    try writer.print("  {s}:  ", .{label});
    try formatStatValue(writer, value);
    try writer.writeByte('\n');
}

pub const PERCENTILES = [_]f64{
    5,
    25,
    40,
    50,
    60,
    75,
    95,
};

pub const SCALAR_VALIDATION = false;
pub const SCALAR_RESERVOIR_SIZE = 16384;

pub const P2Quantile = struct {
    percentile: f64,
    initialized: bool = false,
    heights: [5]f64 = .{0} ** 5,
    positions: [5]i64 = .{0} ** 5,
    desired_positions: [5]f64 = .{0} ** 5,
    desired_position_increments: [5]f64,

    const Self = @This();

    pub fn init(percentile: f64) Self {
        std.debug.assert(percentile > 0 and percentile < 100);
        const p = percentile / 100.0;
        return .{
            .percentile = percentile,
            .desired_position_increments = .{ 0, p / 2.0, p, (1.0 + p) / 2.0, 1.0 },
        };
    }

    pub fn reset(self: *Self) void {
        self.* = init(self.percentile);
    }

    pub fn initFromSamples(self: *Self, samples: *const [5]i64) void {
        var sorted = samples.*;
        std.sort.pdq(i64, &sorted, void{}, std.sort.asc(i64));

        const p = self.percentile / 100.0;
        inline for (0..5) |i| {
            self.heights[i] = @floatFromInt(sorted[i]);
            self.positions[i] = @intCast(i + 1);
        }
        self.desired_positions = .{
            1.0,
            1.0 + 2.0 * p,
            1.0 + 4.0 * p,
            3.0 + 2.0 * p,
            5.0,
        };
        self.initialized = true;
    }

    pub fn add(self: *Self, sample: i64) void {
        std.debug.assert(self.initialized);

        const sample_f: f64 = @floatFromInt(sample);
        const k = self.findCell(sample_f);
        for (k + 1..self.positions.len) |i| {
            self.positions[i] += 1;
        }
        inline for (0..5) |i| {
            self.desired_positions[i] += self.desired_position_increments[i];
        }

        inline for (1..4) |i| {
            const delta = self.desired_positions[i] - @as(f64, @floatFromInt(self.positions[i]));
            if ((delta >= 1.0 and self.positions[i + 1] - self.positions[i] > 1) or
                (delta <= -1.0 and self.positions[i - 1] - self.positions[i] < -1))
            {
                const direction: i64 = if (delta > 0) 1 else -1;
                const candidate = self.parabolic(i, direction);
                if (self.heights[i - 1] < candidate and candidate < self.heights[i + 1]) {
                    self.heights[i] = candidate;
                } else {
                    self.heights[i] = self.linear(i, direction);
                }
                self.positions[i] += direction;
            }
        }
    }

    pub fn value(self: *const Self) f64 {
        if (!self.initialized) return 0;
        return self.heights[2];
    }

    fn findCell(self: *Self, sample: f64) usize {
        if (sample < self.heights[0]) {
            self.heights[0] = sample;
            return 0;
        }
        if (sample < self.heights[1]) return 0;
        if (sample < self.heights[2]) return 1;
        if (sample < self.heights[3]) return 2;
        if (sample <= self.heights[4]) return 3;

        self.heights[4] = sample;
        return 3;
    }

    fn parabolic(self: *const Self, i: usize, direction: i64) f64 {
        const dir_f = @as(f64, @floatFromInt(direction));
        const pos_im1: f64 = @floatFromInt(self.positions[i - 1]);
        const pos_i: f64 = @floatFromInt(self.positions[i]);
        const pos_ip1: f64 = @floatFromInt(self.positions[i + 1]);

        return self.heights[i] + dir_f / (pos_ip1 - pos_im1) *
            ((pos_i - pos_im1 + dir_f) * (self.heights[i + 1] - self.heights[i]) / (pos_ip1 - pos_i) +
                (pos_ip1 - pos_i - dir_f) * (self.heights[i] - self.heights[i - 1]) / (pos_i - pos_im1));
    }

    fn linear(self: *const Self, i: usize, direction: i64) f64 {
        const next_i: usize = if (direction > 0) i + 1 else i - 1;
        return self.heights[i] +
            @as(f64, @floatFromInt(direction)) *
                (self.heights[next_i] - self.heights[i]) /
                @as(f64, @floatFromInt(self.positions[next_i] - self.positions[i]));
    }
};

fn initP2Quantiles() [PERCENTILES.len]P2Quantile {
    var estimators: [PERCENTILES.len]P2Quantile = undefined;
    inline for (PERCENTILES, 0..) |pct, i| {
        estimators[i] = P2Quantile.init(pct);
    }
    return estimators;
}

const ReservoirSample = struct {
    seen: u64 = 0,
    len: usize = 0,
    data: [SCALAR_RESERVOIR_SIZE]i64 = .{0} ** SCALAR_RESERVOIR_SIZE,

    const Self = @This();

    fn reset(self: *Self) void {
        self.seen = 0;
        self.len = 0;
    }

    fn add(self: *Self, sample: i64, rng: std.Random) void {
        self.seen += 1;

        if (self.len < self.data.len) {
            self.data[self.len] = sample;
            self.len += 1;
            return;
        }

        const replacement_index = rng.uintLessThanBiased(u64, self.seen);
        if (replacement_index < self.data.len) {
            self.data[@intCast(replacement_index)] = sample;
        }
    }

    fn slice(self: *const Self) []const i64 {
        return self.data[0..self.len];
    }
};

const BasicStats = struct {
    sum: i64 = 0,
    sum_abs: u64 = 0,
    sum_sqr: u128 = 0,
    count: i64 = 0,
    min: i64 = std.math.maxInt(i64),
    max: i64 = std.math.minInt(i64),

    const Self = @This();

    fn reset(self: *Self) void {
        self.* = .{};
    }

    fn add(self: *Self, data_point: i64) void {
        const abs_data_point = @abs(data_point);

        self.sum += data_point;
        self.sum_abs += abs_data_point;
        self.sum_sqr += @as(u128, abs_data_point) * abs_data_point;
        self.count += 1;
        self.min = @min(self.min, data_point);
        self.max = @max(self.max, data_point);
    }

    fn getAverage(self: *const Self) f64 {
        const n = @max(1, self.count);
        return @as(f64, @floatFromInt(self.sum)) / @as(f64, @floatFromInt(n));
    }

    fn getAverageAbs(self: *const Self) f64 {
        const n = @max(1, self.count);
        return @as(f64, @floatFromInt(self.sum_abs)) / @as(f64, @floatFromInt(n));
    }

    fn getVariance(self: *const Self) f64 {
        const s: f64 = @floatFromInt(self.sum);
        const ss: f64 = @floatFromInt(self.sum_sqr);
        const n: f64 = @floatFromInt(@max(1, self.count));
        return (ss - s * s / n) / n;
    }

    fn getStandardDeviation(self: *const Self) f64 {
        return @sqrt(self.getVariance());
    }

    fn getMin(self: *const Self) f64 {
        if (self.count == 0) return 0;
        return @floatFromInt(self.min);
    }

    fn getMax(self: *const Self) f64 {
        if (self.count == 0) return 0;
        return @floatFromInt(self.max);
    }

    fn getCount(self: *const Self) f64 {
        return @floatFromInt(self.count);
    }

    fn skewnessFromMedian(self: *const Self, median: f64) f64 {
        const std_dev = self.getStandardDeviation();
        if (std_dev == 0) return 0;
        return (self.getAverage() - median) / std_dev;
    }

    fn format(self: *const Self, writer: *std.Io.Writer, skewness: f64) std.Io.Writer.Error!void {
        try formatNamedStat(writer, "avg", self.getAverage());
        try formatNamedStat(writer, "avg abs", self.getAverageAbs());
        try formatNamedStat(writer, "std dev", self.getStandardDeviation());
        try formatNamedStat(writer, "min", self.getMin());
        try formatNamedStat(writer, "max", self.getMax());
        try formatNamedStat(writer, "skew", skewness);
        try formatNamedStat(writer, "count", self.getCount());
    }
};

const PairCorrelation = struct {
    count: u64 = 0,
    sum_x: f64 = 0,
    sum_y: f64 = 0,
    sum_xx: f64 = 0,
    sum_yy: f64 = 0,
    sum_xy: f64 = 0,

    const Self = @This();

    fn reset(self: *Self) void {
        self.* = .{};
    }

    fn add(self: *Self, x: i64, y: i64) void {
        const x_f: f64 = @floatFromInt(x);
        const y_f: f64 = @floatFromInt(y);
        self.count += 1;
        self.sum_x += x_f;
        self.sum_y += y_f;
        self.sum_xx += x_f * x_f;
        self.sum_yy += y_f * y_f;
        self.sum_xy += x_f * y_f;
    }

    fn get(self: *const Self) f64 {
        const variance_x = self.varianceX();
        const variance_y = self.varianceY();
        if (self.count < 2 or variance_x <= 0 or variance_y <= 0) return 0;
        return self.covariance() / @sqrt(variance_x * variance_y);
    }

    fn getSlope(self: *const Self) f64 {
        const variance_x = self.varianceX();
        if (self.count < 2 or variance_x <= 0) return 0;
        return self.covariance() / variance_x;
    }

    fn getIntercept(self: *const Self) f64 {
        if (self.count == 0) return 0;
        const count_f: f64 = @floatFromInt(self.count);
        return self.sum_y / count_f - self.getSlope() * (self.sum_x / count_f);
    }

    fn covariance(self: *const Self) f64 {
        if (self.count == 0) return 0;
        const count_f: f64 = @floatFromInt(self.count);
        return self.sum_xy - self.sum_x * self.sum_y / count_f;
    }

    fn varianceX(self: *const Self) f64 {
        if (self.count == 0) return 0;
        const count_f: f64 = @floatFromInt(self.count);
        return self.sum_xx - self.sum_x * self.sum_x / count_f;
    }

    fn varianceY(self: *const Self) f64 {
        if (self.count == 0) return 0;
        const count_f: f64 = @floatFromInt(self.count);
        return self.sum_yy - self.sum_y * self.sum_y / count_f;
    }
};

pub const Correlation = struct {
    allocator: std.mem.Allocator,
    names: []const []const u8,
    sums: []f64,
    sum_squares: []f64,
    sum_products: []f64,
    count: u64 = 0,

    const Self = @This();
    const cell_width = 8;
    const top_correlation_count = 5;

    pub fn init(allocator: std.mem.Allocator, names: []const []const u8) Self {
        std.debug.assert(names.len > 0);

        const sums = allocator.alloc(f64, names.len) catch @panic("OOM");
        errdefer allocator.free(sums);
        @memset(sums, 0);

        const sum_squares = allocator.alloc(f64, names.len) catch @panic("OOM");
        errdefer allocator.free(sum_squares);
        @memset(sum_squares, 0);

        const sum_products = allocator.alloc(f64, names.len * names.len) catch @panic("OOM");
        errdefer allocator.free(sum_products);
        @memset(sum_products, 0);

        return .{
            .allocator = allocator,
            .names = names,
            .sums = sums,
            .sum_squares = sum_squares,
            .sum_products = sum_products,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.sums);
        self.allocator.free(self.sum_squares);
        self.allocator.free(self.sum_products);
    }

    pub fn reset(self: *Self) void {
        self.count = 0;
        @memset(self.sums, 0);
        @memset(self.sum_squares, 0);
        @memset(self.sum_products, 0);
    }

    pub fn add(self: *Self, values: []const f64) void {
        std.debug.assert(values.len == self.names.len);
        self.count += 1;

        for (values, 0..) |value, i| {
            self.sums[i] += value;
            self.sum_squares[i] += value * value;
        }

        for (values, 0..) |lhs, i| {
            for (values, 0..) |rhs, j| {
                self.sum_products[i * self.names.len + j] += lhs * rhs;
            }
        }
    }

    pub fn assertNames(self: *const Self, names: []const []const u8) void {
        std.debug.assert(self.names.len == names.len);
        for (names, self.names) |expected, actual| {
            std.debug.assert(std.mem.eql(u8, expected, actual));
        }
    }

    pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll("  variables:\n");
        for (self.names, 0..) |name, i| {
            try writer.print("    {d}: {s}\n", .{ i, name });
        }

        try writer.writeAll("  matrix:\n");
        try writer.writeAll("    ");
        try self.writeCell(writer, "");
        try writer.writeAll(" |");
        for (0..self.names.len) |i| {
            try self.writeIndexCell(writer, i);
            try writer.writeAll(" |");
        }
        try writer.writeByte('\n');

        for (0..self.names.len) |i| {
            try writer.writeAll("    ");
            try self.writeIndexCell(writer, i);
            try writer.writeAll(" |");
            for (0..self.names.len) |j| {
                if (j < i) {
                    try self.writeCell(writer, "");
                } else {
                    try self.writeCorrelationCell(writer, i, j);
                }
                try writer.writeAll(" |");
            }
            try writer.writeByte('\n');
        }

        try self.formatTopCorrelations(writer);
    }

    fn varianceAt(self: *const Self, idx: usize) f64 {
        if (self.count == 0) return 0;
        const count_f: f64 = @floatFromInt(self.count);
        return self.sum_squares[idx] - self.sums[idx] * self.sums[idx] / count_f;
    }

    fn covarianceAt(self: *const Self, lhs: usize, rhs: usize) f64 {
        if (self.count == 0) return 0;
        const count_f: f64 = @floatFromInt(self.count);
        return self.sum_products[lhs * self.names.len + rhs] -
            self.sums[lhs] * self.sums[rhs] / count_f;
    }

    fn correlationAt(self: *const Self, lhs: usize, rhs: usize) f64 {
        if (lhs == rhs) {
            return if (self.varianceAt(lhs) == 0) 0 else 1;
        }

        const variance_lhs = self.varianceAt(lhs);
        const variance_rhs = self.varianceAt(rhs);
        if (variance_lhs == 0 or variance_rhs == 0) return 0;
        return self.covarianceAt(lhs, rhs) / @sqrt(variance_lhs * variance_rhs);
    }

    fn writeIndexCell(self: *const Self, writer: *std.Io.Writer, idx: usize) std.Io.Writer.Error!void {
        var buffer: [32]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{d}", .{idx}) catch unreachable;
        try self.writeCell(writer, text);
    }

    fn writeCell(self: *const Self, writer: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
        _ = self;
        var padding: usize = cell_width;
        if (text.len < cell_width) {
            padding -= text.len;
            for (0..padding) |_| {
                try writer.writeByte(' ');
            }
        }
        try writer.writeAll(text);
    }

    fn writeCorrelationCell(self: *const Self, writer: *std.Io.Writer, lhs: usize, rhs: usize) std.Io.Writer.Error!void {
        var buffer: [32]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{d:.4}", .{self.correlationAt(lhs, rhs)}) catch unreachable;
        try self.writeCell(writer, text);
    }

    fn formatTopCorrelations(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var correlations: std.ArrayListUnmanaged(struct { f64, usize, usize }) = .empty;
        defer correlations.deinit(self.allocator);

        for (0..self.names.len) |i| {
            for (i + 1..self.names.len) |j| {
                correlations.append(self.allocator, .{ self.correlationAt(i, j), i, j }) catch @panic("OOM");
            }
        }

        if (correlations.items.len == 0) return;

        const Entry = @TypeOf(correlations.items[0]);
        std.sort.pdq(Entry, correlations.items, void{}, struct {
            fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
                return @abs(lhs.@"0") > @abs(rhs.@"0");
            }
        }.lessThan);

        try writer.writeAll("  top correlations:\n");
        for (correlations.items[0..@min(top_correlation_count, correlations.items.len)]) |entry| {
            try writer.print(
                "    {s} ~ {s}: ",
                .{ self.names[entry.@"1"], self.names[entry.@"2"] },
            );
            try formatStatValue(writer, entry.@"0");
            try writer.writeByte('\n');
        }
    }
};

fn percentileIndex(comptime target: f64) usize {
    return inline for (PERCENTILES, 0..) |pct, i| {
        if (pct == target) break i;
    } else @compileError("missing percentile");
}

const MEDIAN_INDEX = percentileIndex(50);

fn exactPercentile(sorted: []const i64, pct: f64) f64 {
    if (sorted.len == 0) return 0;

    const position = pct / 100.0 * @as(f64, @floatFromInt(sorted.len - 1));
    return @floatFromInt(sorted[@intFromFloat(position)]);
}

fn computePercentilesFromSamples(samples: []const i64) [PERCENTILES.len]f64 {
    if (samples.len == 0) return .{0} ** PERCENTILES.len;

    const allocator = std.heap.page_allocator;

    // yes its an ugly and inefficient solution, deal with it
    const sorted = allocator.alloc(i64, samples.len) catch @panic("OOM");
    defer allocator.free(sorted);

    @memcpy(sorted, samples);
    std.sort.pdq(i64, sorted, void{}, std.sort.asc(i64));

    var percentiles: [PERCENTILES.len]f64 = undefined;
    inline for (PERCENTILES, 0..) |pct, i| {
        percentiles[i] = exactPercentile(sorted, pct);
    }
    return percentiles;
}

fn formatPercentiles(
    writer: *std.Io.Writer,
    indent: []const u8,
    percentiles: [PERCENTILES.len]f64,
) std.Io.Writer.Error!void {
    inline for (PERCENTILES, 0..) |pct, i| {
        const percentile_str = std.fmt.comptimePrint("{d}:", .{pct});
        try writer.print("{s}{s:<5} ", .{ indent, percentile_str });
        try formatStatValue(writer, percentiles[i]);
        try writer.writeByte('\n');
    }
}

fn formatPrecisePercentiles(
    writer: *std.Io.Writer,
    approx_percentiles: [PERCENTILES.len]f64,
    precise_percentiles: [PERCENTILES.len]f64,
) std.Io.Writer.Error!void {
    try writer.writeAll("  precise percentiles:\n");
    inline for (PERCENTILES, 0..) |pct, i| {
        const percentile_str = std.fmt.comptimePrint("{d}:", .{pct});
        const diff = @abs(approx_percentiles[i] - precise_percentiles[i]);
        try writer.print("    {s:<5} ", .{percentile_str});
        try formatStatValue(writer, precise_percentiles[i]);
        try writer.writeAll(" (diff: ");
        try formatStatValue(writer, diff);
        try writer.writeAll(")\n");
    }
}

const ScalarValidation = if (SCALAR_VALIDATION) struct {
    samples: std.ArrayListUnmanaged(i64) = .empty,

    const Self = @This();

    fn deinit(self: *Self) void {
        self.samples.deinit(std.heap.page_allocator);
    }

    fn reset(self: *Self) void {
        self.samples.clearRetainingCapacity();
    }

    fn add(self: *Self, data_point: i64) void {
        self.samples.append(std.heap.page_allocator, data_point) catch @panic("OOM");
    }

    fn format(
        self: *const Self,
        writer: *std.Io.Writer,
        approx_percentiles: [PERCENTILES.len]f64,
    ) std.Io.Writer.Error!void {
        try formatPrecisePercentiles(
            writer,
            approx_percentiles,
            computePercentilesFromSamples(self.samples.items),
        );
    }
} else struct {
    fn deinit(self: *@This()) void {
        _ = self;
    }

    fn reset(self: *@This()) void {
        _ = self;
    }

    fn add(self: *@This(), data_point: i64) void {
        _ = self;
        _ = data_point;
    }

    fn format(
        self: *const @This(),
        writer: *std.Io.Writer,
        approx_percentiles: [PERCENTILES.len]f64,
    ) std.Io.Writer.Error!void {
        _ = self;
        _ = writer;
        _ = approx_percentiles;
    }
};

pub const Scalar = struct {
    basic: BasicStats = .{},
    reservoir: ReservoirSample = .{},
    validation: ScalarValidation = .{},

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.validation.deinit();
    }

    pub fn reset(self: *Self) void {
        self.basic.reset();
        self.reservoir.reset();
        self.validation.reset();
    }

    pub fn add(self: *Self, data_point: i64, rng: std.Random) void {
        self.basic.add(data_point);
        self.reservoir.add(data_point, rng);
        self.validation.add(data_point);
    }

    pub fn getMedian(self: *const Self) f64 {
        return self.reservoirPercentiles()[MEDIAN_INDEX];
    }

    pub fn getSkewness(self: *const Self) f64 {
        return self.basic.skewnessFromMedian(self.getMedian());
    }

    pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const approx_percentiles = self.reservoirPercentiles();
        const approx_skewness = self.basic.skewnessFromMedian(approx_percentiles[MEDIAN_INDEX]);

        try self.basic.format(writer, approx_skewness);
        try writer.writeAll("  percentiles:\n");
        try formatPercentiles(writer, "    ", approx_percentiles);
        try self.validation.format(writer, approx_percentiles);
    }

    fn reservoirPercentiles(self: *const Self) [PERCENTILES.len]f64 {
        return computePercentilesFromSamples(self.reservoir.slice());
    }
};

pub const BoolStat = struct {
    true_count: u64 = 0,
    count: u64 = 0,

    pub fn deinit(self: *BoolStat) void {
        _ = self;
    }

    pub fn reset(self: *BoolStat) void {
        self.* = .{};
    }

    pub fn add(self: *BoolStat, value: bool) void {
        self.true_count += @intFromBool(value);
        self.count += 1;
    }

    pub fn format(self: *const BoolStat, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll("  avg:  ");
        if (self.count == 0) {
            try formatStatValue(writer, 0);
        } else {
            try formatStatValue(
                writer,
                @as(f64, @floatFromInt(self.true_count)) / @as(f64, @floatFromInt(self.count)),
            );
        }
        try writer.writeByte('\n');
    }
};

const RangeScalar = struct {
    basic: BasicStats = .{},
    percentiles: [PERCENTILES.len]f64 = .{0} ** PERCENTILES.len,
    bootstrap_samples: [5]i64 = .{0} ** 5,
    estimators: [PERCENTILES.len]P2Quantile = initP2Quantiles(),

    const Self = @This();

    fn reset(self: *Self) void {
        self.* = .{};
    }

    fn add(self: *Self, data_point: i64) void {
        self.basic.add(data_point);

        const count: usize = @intCast(self.basic.count);
        if (count <= self.bootstrap_samples.len) {
            self.bootstrap_samples[count - 1] = data_point;
            self.percentiles = computePercentilesFromSamples(self.bootstrap_samples[0..count]);

            if (count == self.bootstrap_samples.len) {
                for (&self.estimators) |*estimator| {
                    estimator.initFromSamples(&self.bootstrap_samples);
                }
            }
            return;
        }

        for (&self.estimators) |*estimator| {
            estimator.add(data_point);
        }
        self.refreshEstimatorPercentiles();
    }

    fn getMedian(self: *const Self) f64 {
        return self.percentiles[MEDIAN_INDEX];
    }

    fn getAverage(self: *const Self) f64 {
        return self.basic.getAverage();
    }

    fn getAverageAbs(self: *const Self) f64 {
        return self.basic.getAverageAbs();
    }

    fn getStandardDeviation(self: *const Self) f64 {
        return self.basic.getStandardDeviation();
    }

    fn getMin(self: *const Self) f64 {
        return self.basic.getMin();
    }

    fn getMax(self: *const Self) f64 {
        return self.basic.getMax();
    }

    fn getSkewness(self: *const Self) f64 {
        return self.basic.skewnessFromMedian(self.getMedian());
    }

    fn getCount(self: *const Self) f64 {
        return self.basic.getCount();
    }

    fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try self.basic.format(writer, self.getSkewness());
        try writer.writeAll("  percentiles:\n");
        try formatPercentiles(writer, "    ", self.percentiles);
    }

    fn refreshEstimatorPercentiles(self: *Self) void {
        const min_value: f64 = @floatFromInt(self.basic.min);
        const max_value: f64 = @floatFromInt(self.basic.max);

        var previous = min_value;
        inline for (0..PERCENTILES.len) |i| {
            const estimate = std.math.clamp(self.estimators[i].value(), min_value, max_value);
            self.percentiles[i] = @max(previous, estimate);
            previous = self.percentiles[i];
        }
    }
};

pub const Range = struct {
    granularity: i64,
    min_bucket: i64 = std.math.maxInt(i64),
    max_bucket: i64 = std.math.minInt(i64),
    overall: RangeScalar = .{},
    correlation: PairCorrelation = .{},
    buckets: std.AutoHashMap(i64, RangeScalar),

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
        self.correlation.reset();
        self.buckets.clearRetainingCapacity();
    }

    pub fn add(self: *Self, index: i64, data_point: i64) void {
        self.overall.add(data_point);
        self.correlation.add(index, data_point);

        const bucket = @divFloor(index, self.granularity);
        self.min_bucket = @min(self.min_bucket, bucket);
        self.max_bucket = @max(self.max_bucket, bucket);

        const gp = self.buckets.getOrPut(bucket) catch unreachable;
        if (!gp.found_existing) {
            gp.value_ptr.* = .{};
        }
        gp.value_ptr.add(data_point);
    }

    pub fn format(
        self: *const Self,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        const slope = self.correlation.getSlope();
        const intercept = self.correlation.getIntercept();

        try self.overall.format(writer);
        try writer.print("  correlation:  ", .{});
        try formatStatValue(writer, self.correlation.get());
        try writer.writeByte('\n');
        try writer.print("  slope:  ", .{});
        try formatStatValue(writer, slope);
        try writer.writeByte('\n');
        try writer.writeAll("  linear model:  measured = ");
        try formatStatValue(writer, slope);
        try writer.writeAll(" * index ");
        if (intercept < 0) {
            try writer.writeAll("- ");
            try formatStatValue(writer, -intercept);
        } else {
            try writer.writeAll("+ ");
            try formatStatValue(writer, intercept);
        }
        try writer.writeByte('\n');
        try writer.writeAll("  buckets:\n");
        try writer.print("    start: {d}\n", .{if (self.hasBuckets()) self.min_bucket * self.granularity else 0});
        try writer.print("    granularity: {d}\n", .{self.granularity});
        try self.formatBucketLine(writer, "avg", RangeScalar.getAverage);
        try self.formatBucketLine(writer, "avg abs", RangeScalar.getAverageAbs);
        try self.formatBucketLine(writer, "std dev", RangeScalar.getStandardDeviation);
        try self.formatBucketLine(writer, "min", RangeScalar.getMin);
        try self.formatBucketLine(writer, "max", RangeScalar.getMax);
        try self.formatBucketLine(writer, "skew", RangeScalar.getSkewness);
        try self.formatBucketLine(writer, "count", RangeScalar.getCount);
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

    fn formatBucketLine(
        self: *const Self,
        writer: *std.Io.Writer,
        label: []const u8,
        comptime getter: fn (*const RangeScalar) f64,
    ) std.Io.Writer.Error!void {
        try writer.print("    {s}: [", .{label});
        if (self.hasBuckets()) {
            var first = true;
            var bucket = self.min_bucket;
            while (bucket <= self.max_bucket) : (bucket += 1) {
                if (!first) try writer.writeAll(", ");
                first = false;
                const value = if (self.buckets.get(bucket)) |stats| getter(&stats) else 0;
                try formatStatValue(writer, value);
            }
        }
        try writer.writeAll("]\n");
    }
};
