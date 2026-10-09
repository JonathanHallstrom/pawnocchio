const arch = @import("arch.zig");

pub const Accumulator = extern struct {
    data: arch.RawAccumulator align(64),

    pub fn copyAddSubMany(
        self: *Accumulator,
        src: *const Accumulator,
        adds: anytype,
        subs: anytype,
    ) void {
        inline for (adds) |a| @prefetch(a, .{ .rw = .read });
        inline for (subs) |s| @prefetch(s, .{ .rw = .read });
        for (0..arch.ACCUMULATOR_VECTOR_COUNT) |i| {
            var vals: arch.AccumulatorVec = src.data[i];
            inline for (adds) |a| {
                vals += a[i];
            }
            inline for (subs) |s| {
                vals -= s[i];
            }
            self.data[i] = vals;
        }
    }

    pub fn add(
        self: *Accumulator,
        weights: *const arch.RawAccumulator,
    ) void {
        self.copyAddSubMany(self, .{weights}, .{});
    }

    pub fn addSubInPlace(
        self: *Accumulator,
        weights: [*]const arch.RawAccumulator,
        add_indices: []const u16,
        sub_indices: []const u16,
    ) void {
        for (add_indices) |a| @prefetch(&weights[a], .{ .rw = .read });
        for (sub_indices) |s| @prefetch(&weights[s], .{ .rw = .read });
        const TILE = arch.ACCUMULATOR_TILE;
        var i: usize = 0;
        while (i < arch.ACCUMULATOR_VECTOR_COUNT) : (i += TILE) {
            const tile = self.data[i..][0..TILE];
            var v: [TILE]arch.AccumulatorVec = undefined;
            inline for (0..TILE) |t| v[t] = tile[t];
            for (add_indices) |a| {
                inline for (0..TILE) |t| v[t] += weights[a][i + t];
            }
            for (sub_indices) |s| {
                inline for (0..TILE) |t| v[t] -= weights[s][i + t];
            }
            inline for (0..TILE) |t| tile[t] = v[t];
        }
    }
};

pub const AccumulatorHalf = struct {
    pub const Generation = u64;

    ptr: *const Accumulator,
    generation: Generation = 0,
};
