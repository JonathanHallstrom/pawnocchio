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

pub const do_tuning = false;

pub const Tunable = struct {
    name: []const u8,
    default: i32,
    min: ?i32 = null,
    max: ?i32 = null,
    c_end: ?f64 = null,

    fn margin(self: Tunable) i32 {
        return 10 + (self.default * std.math.sign(self.default) >> 1);
    }

    pub fn getMin(self: Tunable) i32 {
        if (self.min) |m|
            return m;
        return -self.margin() + if (self.default > 0) self.default >> 1 else self.default * 2;
    }

    pub fn getMax(self: Tunable) i32 {
        if (self.max) |m|
            return m;
        return self.margin() + if (self.default > 0) self.default * 2 else self.default >> 1;
    }

    pub fn getCend(self: Tunable) f64 {
        if (self.c_end) |m|
            return m;
        const d: f64 = @floatFromInt(@abs(self.default));
        return @max(0.5, d / 20);
    }
};

const tunable_defaults = struct {
    pub const history_bonus_mult: i32 = 397;
    pub const history_bonus_offs: i32 = 333;
    pub const history_bonus_max: i32 = 2556;
    pub const history_penalty_mult: i32 = 254;
    pub const history_penalty_offs: i32 = 263;
    pub const history_penalty_max: i32 = 2028;
    pub const rfp_margin: i32 = 59;
    pub const rfp_cutnode_margin: i32 = 20;
    pub const aspiration_initial: i32 = 20;
    pub const aspiration_multiplier: i32 = 2091;
    pub const lmr_base: i32 = 2226;
    pub const lmr_log_mult: i32 = 937;
    pub const lmr_pv_mult: i32 = 1199;
    pub const lmr_cutnode_mult: i32 = 952;
    pub const lmr_improving_mult: i32 = 1042;
    pub const lmr_quiet_history_mult: i32 = 987;
    pub const lmr_noisy_history_mult: i32 = 987;
    pub const lmr_corrhist_mult: i32 = 12288;
    pub const nmp_base: i32 = 35893;
    pub const nmp_mult: i32 = 1076;
    pub const nmp_allnode_margin: i32 = 30;
    pub const fp_base: i32 = 250;
    pub const fp_mult: i32 = 114;
    pub const qs_see_threshold: i32 = -101;
    pub const see_quiet_pruning_mult: i32 = -77;
    pub const see_noisy_pruning_mult: i32 = -48;
    pub const razoring_margin: i32 = 187;
    pub const history_pruning_mult: i32 = -2183;
    pub const nmp_eval_reduction_scale: i32 = 30;
    pub const nmp_eval_reduction_max: i32 = 25022;
    pub const qs_futility_margin: i32 = 95;
    pub const corrhist_pawn_weight: i32 = 1050;
    pub const corrhist_nonpawn_weight: i32 = 522;
    pub const corrhist_countermove_weight: i32 = 1011;
    pub const corrhist_major_weight: i32 = 1016;
    pub const corrhist_minor_weight: i32 = 1015;
    pub const lmp_legal_base: i32 = -3118;
    pub const lmp_legal_mult: i32 = 1030;
    pub const lmp_standard_mult: i32 = 1049;
    pub const lmp_improving_mult: i32 = 1020;
    pub const nodetm_base: i32 = 1672;
    pub const nodetm_mult: i32 = 812;
    pub const singular_depth_limit: i32 = 8;
    pub const singular_tt_depth_margin: i32 = 3;
    pub const singular_beta_mult: i32 = 17;
    pub const singular_depth_mult: i32 = 17;
    pub const singular_dext_margin: i32 = 14;
};

pub const tunables = [_]Tunable{
    .{ .name = "history_bonus_mult", .default = tunable_defaults.history_bonus_mult },
    .{ .name = "history_bonus_offs", .default = tunable_defaults.history_bonus_offs },
    .{ .name = "history_bonus_max", .default = tunable_defaults.history_bonus_max },
    .{ .name = "history_penalty_mult", .default = tunable_defaults.history_penalty_mult },
    .{ .name = "history_penalty_offs", .default = tunable_defaults.history_penalty_offs },
    .{ .name = "history_penalty_max", .default = tunable_defaults.history_penalty_max },
    .{ .name = "rfp_margin", .default = tunable_defaults.rfp_margin },
    .{ .name = "rfp_cutnode_margin", .default = tunable_defaults.rfp_cutnode_margin },
    .{ .name = "aspiration_initial", .default = tunable_defaults.aspiration_initial },
    .{ .name = "aspiration_multiplier", .default = tunable_defaults.aspiration_multiplier },
    .{ .name = "lmr_base", .default = tunable_defaults.lmr_base },
    .{ .name = "lmr_log_mult", .default = tunable_defaults.lmr_log_mult },
    .{ .name = "lmr_pv_mult", .default = tunable_defaults.lmr_pv_mult },
    .{ .name = "lmr_cutnode_mult", .default = tunable_defaults.lmr_cutnode_mult },
    .{ .name = "lmr_improving_mult", .default = tunable_defaults.lmr_improving_mult },
    .{ .name = "lmr_quiet_history_mult", .default = tunable_defaults.lmr_quiet_history_mult },
    .{ .name = "lmr_noisy_history_mult", .default = tunable_defaults.lmr_noisy_history_mult },
    .{ .name = "lmr_corrhist_mult", .default = tunable_defaults.lmr_corrhist_mult },
    .{ .name = "nmp_base", .default = tunable_defaults.nmp_base },
    .{ .name = "nmp_mult", .default = tunable_defaults.nmp_mult },
    .{ .name = "nmp_allnode_margin", .default = tunable_defaults.nmp_allnode_margin },
    .{ .name = "fp_base", .default = tunable_defaults.fp_base },
    .{ .name = "fp_mult", .default = tunable_defaults.fp_mult },
    .{ .name = "qs_see_threshold", .default = tunable_defaults.qs_see_threshold },
    .{ .name = "see_quiet_pruning_mult", .default = tunable_defaults.see_quiet_pruning_mult },
    .{ .name = "see_noisy_pruning_mult", .default = tunable_defaults.see_noisy_pruning_mult },
    .{ .name = "razoring_margin", .default = tunable_defaults.razoring_margin },
    .{ .name = "history_pruning_mult", .default = tunable_defaults.history_pruning_mult },
    .{ .name = "nmp_eval_reduction_scale", .default = tunable_defaults.nmp_eval_reduction_scale },
    .{ .name = "nmp_eval_reduction_max", .default = tunable_defaults.nmp_eval_reduction_max },
    .{ .name = "qs_futility_margin", .default = tunable_defaults.qs_futility_margin },
    .{ .name = "corrhist_pawn_weight", .default = tunable_defaults.corrhist_pawn_weight },
    .{ .name = "corrhist_nonpawn_weight", .default = tunable_defaults.corrhist_nonpawn_weight },
    .{ .name = "corrhist_countermove_weight", .default = tunable_defaults.corrhist_countermove_weight },
    .{ .name = "corrhist_major_weight", .default = tunable_defaults.corrhist_major_weight },
    .{ .name = "corrhist_minor_weight", .default = tunable_defaults.corrhist_minor_weight },
    .{ .name = "lmp_legal_base", .default = tunable_defaults.lmp_legal_base },
    .{ .name = "lmp_legal_mult", .default = tunable_defaults.lmp_legal_mult },
    .{ .name = "lmp_standard_mult", .default = tunable_defaults.lmp_standard_mult },
    .{ .name = "lmp_improving_mult", .default = tunable_defaults.lmp_improving_mult },
    .{ .name = "nodetm_base", .default = tunable_defaults.nodetm_base },
    .{ .name = "nodetm_mult", .default = tunable_defaults.nodetm_mult },
    .{ .name = "singular_depth_limit", .default = tunable_defaults.singular_depth_limit },
    .{ .name = "singular_tt_depth_margin", .default = tunable_defaults.singular_tt_depth_margin },
    .{ .name = "singular_beta_mult", .default = tunable_defaults.singular_beta_mult },
    .{ .name = "singular_depth_mult", .default = tunable_defaults.singular_depth_mult },
    .{ .name = "singular_dext_margin", .default = tunable_defaults.singular_dext_margin },
};

pub const tunable_constants = if (do_tuning) struct {
    pub var history_bonus_mult = tunable_defaults.history_bonus_mult;
    pub var history_bonus_offs = tunable_defaults.history_bonus_offs;
    pub var history_bonus_max = tunable_defaults.history_bonus_max;
    pub var history_penalty_mult = tunable_defaults.history_penalty_mult;
    pub var history_penalty_offs = tunable_defaults.history_penalty_offs;
    pub var history_penalty_max = tunable_defaults.history_penalty_max;
    pub var rfp_margin = tunable_defaults.rfp_margin;
    pub var rfp_cutnode_margin = tunable_defaults.rfp_cutnode_margin;
    pub var aspiration_initial = tunable_defaults.aspiration_initial;
    pub var aspiration_multiplier = tunable_defaults.aspiration_multiplier;
    pub var lmr_base = tunable_defaults.lmr_base;
    pub var lmr_log_mult = tunable_defaults.lmr_log_mult;
    pub var lmr_pv_mult = tunable_defaults.lmr_pv_mult;
    pub var lmr_cutnode_mult = tunable_defaults.lmr_cutnode_mult;
    pub var lmr_improving_mult = tunable_defaults.lmr_improving_mult;
    pub var lmr_quiet_history_mult = tunable_defaults.lmr_quiet_history_mult;
    pub var lmr_noisy_history_mult = tunable_defaults.lmr_noisy_history_mult;
    pub var lmr_corrhist_mult = tunable_defaults.lmr_corrhist_mult;
    pub var nmp_base = tunable_defaults.nmp_base;
    pub var nmp_mult = tunable_defaults.nmp_mult;
    pub var nmp_allnode_margin = tunable_defaults.nmp_allnode_margin;
    pub var fp_base = tunable_defaults.fp_base;
    pub var fp_mult = tunable_defaults.fp_mult;
    pub var qs_see_threshold = tunable_defaults.qs_see_threshold;
    pub var see_quiet_pruning_mult = tunable_defaults.see_quiet_pruning_mult;
    pub var see_noisy_pruning_mult = tunable_defaults.see_noisy_pruning_mult;
    pub var razoring_margin = tunable_defaults.razoring_margin;
    pub var history_pruning_mult = tunable_defaults.history_pruning_mult;
    pub var nmp_eval_reduction_scale = tunable_defaults.nmp_eval_reduction_scale;
    pub var nmp_eval_reduction_max = tunable_defaults.nmp_eval_reduction_max;
    pub var qs_futility_margin = tunable_defaults.qs_futility_margin;
    pub var corrhist_pawn_weight = tunable_defaults.corrhist_pawn_weight;
    pub var corrhist_nonpawn_weight = tunable_defaults.corrhist_nonpawn_weight;
    pub var corrhist_countermove_weight = tunable_defaults.corrhist_countermove_weight;
    pub var corrhist_major_weight = tunable_defaults.corrhist_major_weight;
    pub var corrhist_minor_weight = tunable_defaults.corrhist_minor_weight;
    pub var lmp_legal_base = tunable_defaults.lmp_legal_base;
    pub var lmp_legal_mult = tunable_defaults.lmp_legal_mult;
    pub var lmp_standard_mult = tunable_defaults.lmp_standard_mult;
    pub var lmp_improving_mult = tunable_defaults.lmp_improving_mult;
    pub var nodetm_base = tunable_defaults.nodetm_base;
    pub var nodetm_mult = tunable_defaults.nodetm_mult;
    pub var singular_depth_limit = tunable_defaults.singular_depth_limit;
    pub var singular_tt_depth_margin = tunable_defaults.singular_tt_depth_margin;
    pub var singular_beta_mult = tunable_defaults.singular_beta_mult;
    pub var singular_depth_mult = tunable_defaults.singular_depth_mult;
    pub var singular_dext_margin = tunable_defaults.singular_dext_margin;
} else tunable_defaults;

comptime {
    std.debug.assert(std.meta.declarations(tunable_defaults).len == tunables.len);
    std.debug.assert(std.meta.declarations(tunable_constants).len == tunables.len);
}
