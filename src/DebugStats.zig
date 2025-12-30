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

sum: i64 = 0,
sum_sqr: u128 = 0,
count: i64 = 0,
min: i64 = std.math.maxInt(i64),
max: i64 = std.math.minInt(i64),

percentiles: [PERCENTILES.len]f64 = .{0} ** PERCENTILES.len,

const Self = @This();

pub fn add(self: *Self, data_point: i64, rng: std.Random) void {
    self.sum += data_point;
    self.sum_sqr += @as(u128, @abs(data_point)) * @abs(data_point);
    self.count += 1;
    self.min = @min(self.min, data_point);
    self.max = @max(self.max, data_point);

    const data_point_f: f64 = @floatFromInt(data_point);
    const step = 0.001 * (1 + self.standardDeviation());

    const r = rng.float(f64);
    inline for (PERCENTILES, 0..) |percentile, i| {
        const p = percentile / 100.0;

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

pub fn median(self: *const Self) f64 {
    return inline for (PERCENTILES, 0..) |percentile, i| {
        if (percentile == 50) {
            break self.percentiles[i];
        }
    } else @compileError("need 50th percentile to compute median\n");
}

pub fn skewness(self: *const Self) f64 {
    return (self.average() - self.median()) / self.standardDeviation();
}

pub fn average(self: *const Self) f64 {
    return @as(f64, @floatFromInt(self.sum)) / @as(f64, @floatFromInt(self.count));
}

pub fn variance(self: *const Self) f64 {
    const s: f64 = @floatFromInt(self.sum);
    const ss: f64 = @floatFromInt(self.sum_sqr);
    const n: f64 = @floatFromInt(self.count);
    return (ss - s * s / n) / n;
}

pub fn standardDeviation(self: *const Self) f64 {
    return @sqrt(self.variance());
}

const std = @import("std");
