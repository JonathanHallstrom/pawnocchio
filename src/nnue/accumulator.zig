const root = @import("../root.zig");
const arch = @import("arch.zig");
const simd = root.simd;

pub const Accumulator = struct {
    data: [arch.L1_SIZE]i16 align(64),

    pub inline fn vecs(self: anytype) root.inheritConstness(@TypeOf(self), *align(64) arch.RawAccumulator) {
        return @ptrCast(&self.data);
    }

    inline fn addImpl(
        self: *Accumulator,
        noalias src: *const Accumulator,
        adds: anytype,
        subs: anytype,
    ) void {
        for (0..arch.ACCUMULATOR_VECTOR_COUNT) |i| {
            var vals: arch.AccumulatorVec = src.vecs()[i];

            inline for (adds) |a| {
                vals += a[i];
            }
            inline for (subs) |s| {
                vals -= s[i];
            }

            self.vecs()[i] = vals;
        }
    }

    pub fn copyAddSubMany(
        self: *Accumulator,
        noalias src: *const Accumulator,
        adds: anytype,
        subs: anytype,
    ) void {
        self.addImpl(src, adds, subs);
    }

    pub fn addSubMany(
        self: *Accumulator,
        adds: anytype,
        subs: anytype,
    ) void {
        self.addImpl(self, adds, subs);
    }

    pub fn add(
        self: *Accumulator,
        weights: *const arch.RawAccumulator,
    ) void {
        self.addImpl(self, .{weights}, .{});
    }

    pub fn sub(
        self: *Accumulator,
        weights: *const arch.RawAccumulator,
    ) void {
        self.addImpl(self, .{}, .{weights});
    }

    pub fn addMany(
        self: *Accumulator,
        comptime N: usize,
        adds: [N]*const arch.RawAccumulator,
    ) void {
        self.addImpl(self, adds, .{});
    }

    pub fn subMany(
        self: *Accumulator,
        comptime N: usize,
        subs: [N]*const arch.RawAccumulator,
    ) void {
        self.addImpl(self, .{}, subs);
    }

    pub fn copyAdd(
        self: *Accumulator,
        noalias src: *const Accumulator,
        weights: *const arch.RawAccumulator,
    ) void {
        self.addImpl(src, .{weights}, .{});
    }

    pub fn addThreat(
        self: *Accumulator,
        weights: *const arch.ThreatWeight,
    ) void {
        self.addImpl(self, .{weights}, .{});
    }
};

pub const AccumulatorHalf = struct {
    pub const Generation = u64;

    ptr: *const Accumulator,
    generation: Generation = 0,
};

pub const zero_accumulator: Accumulator align(64) = .{
    .data = [_]i16{0} ** arch.L1_SIZE,
};

