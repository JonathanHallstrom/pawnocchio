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
    pub const rfp_margin: i32 = 90;
    pub const aspiration_initial: i32 = 20;
    pub const aspiration_multiplier: i32 = 2048;
    pub const lmr_base: i32 = 2;
    pub const nmp_base: i32 = 4;
    pub const nmp_mult: i32 = 4;
    pub const fp_base: i32 = 250;
    pub const fp_mult: i32 = 100;
    pub const qs_see_threshold: i32 = 100;
    pub const see_quiet_pruning_mult: i32 = 80;
    pub const see_noisy_pruning_mult: i32 = 50;
    pub const razoring_margin: i32 = 200;
};

pub const tunables = [_]Tunable{
    .{ .name = "history_bonus_mult", .default = tunable_defaults.history_bonus_mult },
    .{ .name = "history_bonus_offs", .default = tunable_defaults.history_bonus_offs },
    .{ .name = "history_bonus_max", .default = tunable_defaults.history_bonus_max },
    .{ .name = "history_penalty_mult", .default = tunable_defaults.history_penalty_mult },
    .{ .name = "history_penalty_offs", .default = tunable_defaults.history_penalty_offs },
    .{ .name = "history_penalty_max", .default = tunable_defaults.history_penalty_max },
    .{ .name = "rfp_margin", .default = tunable_defaults.rfp_margin },
    .{ .name = "aspiration_initial", .default = tunable_defaults.aspiration_initial },
    .{ .name = "aspiration_multiplier", .default = tunable_defaults.aspiration_multiplier },
    .{ .name = "lmr_base", .default = tunable_defaults.lmr_base },
    .{ .name = "nmp_base", .default = tunable_defaults.nmp_base },
    .{ .name = "nmp_mult", .default = tunable_defaults.nmp_mult },
    .{ .name = "fp_base", .default = tunable_defaults.fp_base },
    .{ .name = "fp_mult", .default = tunable_defaults.fp_mult },
    .{ .name = "qs_see_threshold", .default = tunable_defaults.fp_mult },
    .{ .name = "see_quiet_pruning_mult", .default = tunable_defaults.see_quiet_pruning_mult },
    .{ .name = "see_noisy_pruning_mult", .default = tunable_defaults.see_noisy_pruning_mult },
    .{ .name = "razoring_margin", .default = tunable_defaults.razoring_margin },
};

pub const tunable_constants = if (do_tuning) struct {
    pub var history_bonus_mult = tunable_defaults.history_bonus_mult;
    pub var history_bonus_offs = tunable_defaults.history_bonus_offs;
    pub var history_bonus_max = tunable_defaults.history_bonus_max;
    pub var history_penalty_mult = tunable_defaults.history_penalty_mult;
    pub var history_penalty_offs = tunable_defaults.history_penalty_offs;
    pub var history_penalty_max = tunable_defaults.history_penalty_max;
    pub var rfp_margin = tunable_defaults.rfp_margin;
    pub var aspiration_initial = tunable_defaults.aspiration_initial;
    pub var aspiration_multiplier = tunable_defaults.aspiration_multiplier;
    pub var lmr_base = tunable_defaults.lmr_base;
    pub var nmp_base = tunable_defaults.nmp_base;
    pub var nmp_mult = tunable_defaults.nmp_mult;
    pub var fp_base = tunable_defaults.fp_base;
    pub var fp_mult = tunable_defaults.fp_mult;
    pub var qs_see_threshold = tunable_defaults.qs_see_threshold;
    pub var see_quiet_pruning_mult = tunable_defaults.see_quiet_pruning_mult;
    pub var see_noisy_pruning_mult = tunable_defaults.see_noisy_pruning_mult;
    pub var razoring_margin = tunable_defaults.razoring_margin;
} else tunable_defaults;
