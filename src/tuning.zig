const std = @import("std");

pub const do_tuning = false;

pub const Tunable = struct {
    name: []const u8,
    default: i32,
    min: ?i32 = null,
    max: ?i32 = null,
    c_end: ?f64 = null,

    pub fn getMin(self: Tunable) i32 {
        if (self.min) |m|
            return m;
        return self.default >> 1;
    }

    pub fn getMax(self: Tunable) i32 {
        if (self.max) |m|
            return m;
        return self.default * 2 + std.math.sign(self.default) * 16;
    }

    pub fn getCend(self: Tunable) f64 {
        if (self.c_end) |m|
            return m;
        const d: f64 = @floatFromInt(self.default);
        return @max(0.5, d / 20);
    }
};

const tunable_defaults = struct {
    pub const history_bonus_mult: i32 = 300;
    pub const history_bonus_offs: i32 = 300;
    pub const history_bonus_max: i32 = 2300;
    pub const history_penalty_mult: i32 = 300;
    pub const history_penalty_offs: i32 = 300;
    pub const history_penalty_max: i32 = 2300;
};

pub const tunables = [_]Tunable{
    .{ .name = "history_bonus_mult", .default = tunable_defaults.history_bonus_mult },
    .{ .name = "history_bonus_offs", .default = tunable_defaults.history_bonus_offs },
    .{ .name = "history_bonus_max", .default = tunable_defaults.history_bonus_max },
    .{ .name = "history_penalty_mult", .default = tunable_defaults.history_penalty_mult },
    .{ .name = "history_penalty_offs", .default = tunable_defaults.history_penalty_offs },
    .{ .name = "history_penalty_max", .default = tunable_defaults.history_penalty_max },
};

pub const tunable_constants = if (do_tuning) struct {
    pub var history_bonus_mult = tunable_defaults.history_bonus_mult;
    pub var history_bonus_offs = tunable_defaults.history_bonus_offs;
    pub var history_bonus_max = tunable_defaults.history_bonus_max;
    pub var history_penalty_mult = tunable_defaults.history_penalty_mult;
    pub var history_penalty_offs = tunable_defaults.history_penalty_offs;
    pub var history_penalty_max = tunable_defaults.history_penalty_max;
} else tunable_defaults;
