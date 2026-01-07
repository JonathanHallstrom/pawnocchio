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

const Self = @This();

p: u8,
m: []u8,

pub fn init(p_: u8, allocator: std.mem.Allocator) !Self {
    const size_ = @as(usize, 1) << @intCast(p_);
    const m_ = try allocator.alloc(u8, size_);
    @memset(m_, 0);
    return .{
        .p = p_,
        .m = m_,
    };
}

pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
    allocator.free(self.m);
}

pub fn add(self: *Self, x: u64) void {
    const idx: usize = @intCast(x >> @intCast(64 - self.p));
    const w = x << @intCast(self.p);
    const rho: u8 = if (w != 0) @clz(w) + 1 else (64 - self.p + 1);

    self.m[idx] = @max(self.m[idx], rho);
}

pub fn count(self: *const Self) u64 {
    const M = @as(f64, @floatFromInt(self.m.len));

    const alpha = switch (self.m.len) {
        16 => 0.673,
        32 => 0.697,
        64 => 0.709,
        else => 0.7213 / (1.0 + 1.079 / M),
    };

    var sum: f64 = 0;
    var V: f64 = 0;

    for (self.m) |val| {
        if (val == 0) {
            V += 1;
        }
        sum += @exp2(-@as(f64, @floatFromInt(val)));
    }
    var E = alpha * M * M / sum;

    if (E <= 2.5 * M and V > 0) {
        E = M * @log(M / V);
    }

    if (E > @as(f64, 1 << 64) / 30.0) {
        E = -(1 << 64) * @log(1 - E / (1 << 64));
    }

    return @intFromFloat(E);
}
