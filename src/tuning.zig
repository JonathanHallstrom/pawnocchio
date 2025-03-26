const std = @import("std");
const write = @import("main.zig").write;

pub const do_tuning = false;

pub const Tunable = struct {
    name: []const u8,
    default: i32,
    min: i32,
    max: i32,
    C_end: f64,
};

const tunable_defaults = struct {
    pub const rfp_mult: i32 = 87;

    pub const quiesce_see_pruning_threshold: i32 = -100;
    pub const quiesce_futility_margin: i32 = 93;

    pub const see_quiet_pruning_mult: i32 = -80;
    pub const see_noisy_pruning_mult: i32 = -50;

    pub const lmr_base: i32 = 3063;
    pub const lmr_depth_mult: i32 = 262;
    pub const lmr_improving_mult: i32 = 1024;
    pub const lmr_pv_mult: i32 = 1025;
    pub const lmr_cutnode_mult: i32 = 2048;

    pub const double_extension_margin: i32 = 20;

    pub const razoring_margin: i32 = 208;
    pub const singular_beta_depth_mult: i32 = 32;

    pub const history_bonus_mult: i32 = 296;
    pub const history_bonus_offs: i32 = 298;
    pub const history_bonus_max: i32 = 2323;

    pub const history_malus_mult: i32 = 294;
    pub const history_malus_offs: i32 = 305;
    pub const history_malus_max: i32 = 2311;

    pub const pawn_corrhist_weight: i32 = 1024;
    pub const nonpawn_corrhist_weight: i32 = 1024;

    pub const aspiration_window_mult: i32 = 2048;
    pub const aspiration_window_diff_mult: i32 = 1024;
    pub const aspiration_window_lower_bound: i32 = 15360;
    pub const aspiration_window_upper_bound: i32 = 102400;

    pub const nodetm_base: i32 = 1536;
    pub const nodetm_mult: i32 = 819;
};

pub const tunables = [_]Tunable{
    .{ .name = "rfp_mult", .default = tunable_defaults.rfp_mult, .min = 0, .max = 300, .C_end = 7 },

    .{ .name = "quiesce_see_pruning_threshold", .default = tunable_defaults.quiesce_see_pruning_threshold, .min = -200, .max = 0, .C_end = 10 },
    .{ .name = "quiesce_futility_margin", .default = tunable_defaults.quiesce_futility_margin, .min = -200, .max = 200, .C_end = 7 },

    .{ .name = "see_quiet_pruning_mult", .default = tunable_defaults.see_quiet_pruning_mult, .min = -200, .max = 0, .C_end = 3 },
    .{ .name = "see_noisy_pruning_mult", .default = tunable_defaults.see_noisy_pruning_mult, .min = -200, .max = 0, .C_end = 3 },

    .{ .name = "lmr_base", .default = tunable_defaults.lmr_base, .min = 0, .max = 8192, .C_end = 5 },
    .{ .name = "lmr_depth_mult", .default = tunable_defaults.lmr_depth_mult, .min = 1, .max = 4096, .C_end = 5 },
    .{ .name = "lmr_improving_mult", .default = tunable_defaults.lmr_improving_mult, .min = 1, .max = 2048, .C_end = 5 },
    .{ .name = "lmr_pv_mult", .default = tunable_defaults.lmr_pv_mult, .min = 1, .max = 2048, .C_end = 5 },
    .{ .name = "lmr_cutnode_mult", .default = tunable_defaults.lmr_cutnode_mult, .min = 1, .max = 4096, .C_end = 5 },

    .{ .name = "razoring_margin", .default = tunable_defaults.razoring_margin, .min = 0, .max = 400, .C_end = 10 },

    .{ .name = "singular_beta_depth_mult", .default = tunable_defaults.singular_beta_depth_mult, .min = 0, .max = 400, .C_end = 0.5 },
    .{ .name = "double_extension_margin", .default = tunable_defaults.double_extension_margin, .min = 0, .max = 64, .C_end = 0.5 },

    .{ .name = "history_bonus_mult", .default = tunable_defaults.history_bonus_mult, .min = 100, .max = 600, .C_end = 10 },
    .{ .name = "history_bonus_offs", .default = tunable_defaults.history_bonus_offs, .min = 100, .max = 600, .C_end = 10 },
    .{ .name = "history_bonus_max", .default = tunable_defaults.history_bonus_max, .min = 1000, .max = 5000, .C_end = 50 },

    .{ .name = "history_malus_mult", .default = tunable_defaults.history_malus_mult, .min = 100, .max = 600, .C_end = 10 },
    .{ .name = "history_malus_offs", .default = tunable_defaults.history_malus_offs, .min = 100, .max = 600, .C_end = 10 },
    .{ .name = "history_malus_max", .default = tunable_defaults.history_malus_max, .min = 1000, .max = 5000, .C_end = 50 },

    .{ .name = "pawn_corrhist_weight", .default = tunable_defaults.pawn_corrhist_weight, .min = 1, .max = 2048, .C_end = 0.5 },
    .{ .name = "nonpawn_corrhist_weight", .default = tunable_defaults.nonpawn_corrhist_weight, .min = 1, .max = 2048, .C_end = 0.5 },

    .{ .name = "aspiration_window_mult", .default = tunable_defaults.aspiration_window_mult, .min = 1, .max = 4096, .C_end = 5 },
    .{ .name = "aspiration_window_diff_mult", .default = tunable_defaults.aspiration_window_diff_mult, .min = 1, .max = 4096, .C_end = 5 },
    .{ .name = "aspiration_window_lower_bound", .default = tunable_defaults.aspiration_window_lower_bound, .min = 1, .max = 32768, .C_end = 10 },
    .{ .name = "aspiration_window_upper_bound", .default = tunable_defaults.aspiration_window_upper_bound, .min = 1, .max = 204800, .C_end = 50 },

    .{ .name = "nodetm_base", .default = tunable_defaults.nodetm_base, .min = 0, .max = 3072, .C_end = 10 },
    .{ .name = "nodetm_mult", .default = tunable_defaults.nodetm_mult, .min = 1, .max = 2048, .C_end = 50 },
};

pub const tunable_constants = if (do_tuning) struct {
    pub var rfp_mult: i32 = tunable_defaults.rfp_mult;

    pub var quiesce_see_pruning_threshold: i32 = tunable_defaults.quiesce_see_pruning_threshold;
    pub var quiesce_futility_margin: i32 = tunable_defaults.quiesce_futility_margin;

    pub var see_quiet_pruning_mult: i32 = tunable_defaults.see_quiet_pruning_mult;
    pub var see_noisy_pruning_mult: i32 = tunable_defaults.see_noisy_pruning_mult;

    pub var lmr_base: i32 = tunable_defaults.lmr_base;
    pub var lmr_depth_mult: i32 = tunable_defaults.lmr_depth_mult;
    pub var lmr_improving_mult: i32 = tunable_defaults.lmr_improving_mult;
    pub var lmr_pv_mult: i32 = tunable_defaults.lmr_pv_mult;
    pub var lmr_cutnode_mult: i32 = tunable_defaults.lmr_cutnode_mult;

    pub var double_extension_margin: i32 = tunable_defaults.double_extension_margin;
    pub var razoring_margin: i32 = tunable_defaults.razoring_margin;
    pub var singular_beta_depth_mult: i32 = tunable_defaults.singular_beta_depth_mult;

    pub var history_bonus_mult: i32 = tunable_defaults.history_bonus_mult;
    pub var history_bonus_offs: i32 = tunable_defaults.history_bonus_offs;
    pub var history_bonus_max: i32 = tunable_defaults.history_bonus_max;

    pub var history_malus_mult: i32 = tunable_defaults.history_malus_mult;
    pub var history_malus_offs: i32 = tunable_defaults.history_malus_offs;
    pub var history_malus_max: i32 = tunable_defaults.history_malus_max;

    pub var pawn_corrhist_weight: i32 = tunable_defaults.pawn_corrhist_weight;
    pub var nonpawn_corrhist_weight: i32 = tunable_defaults.nonpawn_corrhist_weight;

    pub var aspiration_window_mult: i32 = tunable_defaults.aspiration_window_mult;
    pub var aspiration_window_diff_mult: i32 = tunable_defaults.aspiration_window_diff_mult;
    pub var aspiration_window_lower_bound: i32 = tunable_defaults.aspiration_window_lower_bound;
    pub var aspiration_window_upper_bound: i32 = tunable_defaults.aspiration_window_upper_bound;

    pub var nodetm_base: i32 = tunable_defaults.nodetm_base;
    pub var nodetm_mult: i32 = tunable_defaults.nodetm_mult;
} else tunable_defaults;

comptime {
    const zig_0_14_0_version = std.SemanticVersion.parse("0.14.0") catch unreachable;
    if (@import("builtin").zig_version.order(zig_0_14_0_version) != .lt) {
        std.debug.assert(@typeInfo(tunable_defaults).@"struct".decls.len == tunables.len);
        std.debug.assert(@typeInfo(tunable_constants).@"struct".decls.len == tunables.len);
    }
}
