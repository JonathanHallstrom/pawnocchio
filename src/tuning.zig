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
    pub const quiet_history_bonus_mult: i32 = 425;
    pub const quiet_history_bonus_offs: i32 = 340;
    pub const quiet_history_bonus_max: i32 = 2570;
    pub const quiet_history_penalty_mult: i32 = 209;
    pub const quiet_history_penalty_offs: i32 = 276;
    pub const quiet_history_penalty_max: i32 = 1917;
    pub const cont_history_bonus_mult: i32 = 433;
    pub const cont_history_bonus_offs: i32 = 308;
    pub const cont_history_bonus_max: i32 = 2819;
    pub const cont_history_penalty_mult: i32 = 215;
    pub const cont_history_penalty_offs: i32 = 280;
    pub const cont_history_penalty_max: i32 = 1814;
    pub const noisy_history_bonus_mult: i32 = 386;
    pub const noisy_history_bonus_offs: i32 = 321;
    pub const noisy_history_bonus_max: i32 = 2416;
    pub const noisy_history_penalty_mult: i32 = 227;
    pub const noisy_history_penalty_offs: i32 = 243;
    pub const noisy_history_penalty_max: i32 = 2025;
    pub const rfp_base: i32 = 60;
    pub const rfp_mult: i32 = 57;
    pub const rfp_improving_margin: i32 = 58;
    pub const rfp_worsening_margin: i32 = 11;
    pub const rfp_cutnode_margin: i32 = 20;
    pub const aspiration_initial: i32 = 19;
    pub const aspiration_multiplier: i32 = 2171;
    pub const lmr_quiet_base: i32 = 2285;
    pub const lmr_noisy_base: i32 = 2394;
    pub const lmr_quiet_log_mult: i32 = 215;
    pub const lmr_noisy_log_mult: i32 = 228;
    pub const lmr_quiet_depth_mult: i32 = 878;
    pub const lmr_noisy_depth_mult: i32 = 940;
    pub const lmr_quiet_legal_mult: i32 = 928;
    pub const lmr_noisy_legal_mult: i32 = 987;
    pub const lmr_pv_mult: i32 = 1230;
    pub const lmr_cutnode_mult: i32 = 1003;
    pub const lmr_improving_mult: i32 = 1034;
    pub const lmr_quiet_history_mult: i32 = 993;
    pub const lmr_noisy_history_mult: i32 = 1030;
    pub const lmr_corrhist_mult: i32 = 12232;
    pub const lmr_ttmove_mult: i32 = 544;
    pub const nmp_base: i32 = 43668;
    pub const nmp_mult: i32 = 1141;
    pub const nmp_eval_reduction_scale: i32 = 31;
    pub const nmp_eval_reduction_max: i32 = 21592;
    pub const fp_base: i32 = 252;
    pub const fp_mult: i32 = 104;
    pub const qs_see_threshold: i32 = -92;
    pub const see_quiet_pruning_mult: i32 = -66;
    pub const see_noisy_pruning_mult: i32 = -47;
    pub const razoring_margin: i32 = 181;
    pub const history_pruning_mult: i32 = -2339;
    pub const qs_futility_margin: i32 = 109;
    pub const corrhist_pawn_weight: i32 = 962;
    pub const corrhist_nonpawn_weight: i32 = 503;
    pub const corrhist_countermove_weight: i32 = 1088;
    pub const corrhist_major_weight: i32 = 1115;
    pub const corrhist_minor_weight: i32 = 963;
    pub const lmp_legal_base: i32 = -3375;
    pub const lmp_standard_mult: i32 = 988;
    pub const lmp_improving_mult: i32 = 939;
    pub const nodetm_base: i32 = 1741;
    pub const nodetm_mult: i32 = 861;
    pub const soft_limit_base: i32 = 51;
    pub const soft_limit_incr: i32 = 549;
    pub const hard_limit_base: i32 = 211;
    pub const singular_depth_limit: i32 = 8;
    pub const singular_tt_depth_margin: i32 = 3;
    pub const singular_beta_mult: i32 = 17;
    pub const singular_depth_mult: i32 = 17;
    pub const singular_dext_margin: i32 = 14;
};

pub const tunables = [_]Tunable{
    .{ .name = "quiet_history_bonus_mult", .default = tunable_defaults.quiet_history_bonus_mult },
    .{ .name = "quiet_history_bonus_offs", .default = tunable_defaults.quiet_history_bonus_offs },
    .{ .name = "quiet_history_bonus_max", .default = tunable_defaults.quiet_history_bonus_max },
    .{ .name = "quiet_history_penalty_mult", .default = tunable_defaults.quiet_history_penalty_mult },
    .{ .name = "quiet_history_penalty_offs", .default = tunable_defaults.quiet_history_penalty_offs },
    .{ .name = "quiet_history_penalty_max", .default = tunable_defaults.quiet_history_penalty_max },
    .{ .name = "cont_history_bonus_mult", .default = tunable_defaults.cont_history_bonus_mult },
    .{ .name = "cont_history_bonus_offs", .default = tunable_defaults.cont_history_bonus_offs },
    .{ .name = "cont_history_bonus_max", .default = tunable_defaults.cont_history_bonus_max },
    .{ .name = "cont_history_penalty_mult", .default = tunable_defaults.cont_history_penalty_mult },
    .{ .name = "cont_history_penalty_offs", .default = tunable_defaults.cont_history_penalty_offs },
    .{ .name = "cont_history_penalty_max", .default = tunable_defaults.cont_history_penalty_max },
    .{ .name = "noisy_history_bonus_mult", .default = tunable_defaults.noisy_history_bonus_mult },
    .{ .name = "noisy_history_bonus_offs", .default = tunable_defaults.noisy_history_bonus_offs },
    .{ .name = "noisy_history_bonus_max", .default = tunable_defaults.noisy_history_bonus_max },
    .{ .name = "noisy_history_penalty_mult", .default = tunable_defaults.noisy_history_penalty_mult },
    .{ .name = "noisy_history_penalty_offs", .default = tunable_defaults.noisy_history_penalty_offs },
    .{ .name = "noisy_history_penalty_max", .default = tunable_defaults.noisy_history_penalty_max },
    .{ .name = "rfp_base", .default = tunable_defaults.rfp_base },
    .{ .name = "rfp_mult", .default = tunable_defaults.rfp_mult },
    .{ .name = "rfp_improving_margin", .default = tunable_defaults.rfp_improving_margin },
    .{ .name = "rfp_worsening_margin", .default = tunable_defaults.rfp_worsening_margin },
    .{ .name = "rfp_cutnode_margin", .default = tunable_defaults.rfp_cutnode_margin },
    .{ .name = "aspiration_initial", .default = tunable_defaults.aspiration_initial },
    .{ .name = "aspiration_multiplier", .default = tunable_defaults.aspiration_multiplier },
    .{ .name = "lmr_quiet_base", .default = tunable_defaults.lmr_quiet_base },
    .{ .name = "lmr_noisy_base", .default = tunable_defaults.lmr_noisy_base },
    .{ .name = "lmr_quiet_log_mult", .default = tunable_defaults.lmr_quiet_log_mult },
    .{ .name = "lmr_noisy_log_mult", .default = tunable_defaults.lmr_noisy_log_mult },
    .{ .name = "lmr_quiet_depth_mult", .default = tunable_defaults.lmr_quiet_depth_mult },
    .{ .name = "lmr_noisy_depth_mult", .default = tunable_defaults.lmr_noisy_depth_mult },
    .{ .name = "lmr_quiet_legal_mult", .default = tunable_defaults.lmr_quiet_legal_mult },
    .{ .name = "lmr_noisy_legal_mult", .default = tunable_defaults.lmr_noisy_legal_mult },
    .{ .name = "lmr_pv_mult", .default = tunable_defaults.lmr_pv_mult },
    .{ .name = "lmr_cutnode_mult", .default = tunable_defaults.lmr_cutnode_mult },
    .{ .name = "lmr_improving_mult", .default = tunable_defaults.lmr_improving_mult },
    .{ .name = "lmr_quiet_history_mult", .default = tunable_defaults.lmr_quiet_history_mult },
    .{ .name = "lmr_noisy_history_mult", .default = tunable_defaults.lmr_noisy_history_mult },
    .{ .name = "lmr_corrhist_mult", .default = tunable_defaults.lmr_corrhist_mult },
    .{ .name = "lmr_ttmove_mult", .default = tunable_defaults.lmr_ttmove_mult },
    .{ .name = "nmp_base", .default = tunable_defaults.nmp_base },
    .{ .name = "nmp_mult", .default = tunable_defaults.nmp_mult },
    .{ .name = "nmp_eval_reduction_scale", .default = tunable_defaults.nmp_eval_reduction_scale },
    .{ .name = "nmp_eval_reduction_max", .default = tunable_defaults.nmp_eval_reduction_max },
    .{ .name = "fp_base", .default = tunable_defaults.fp_base },
    .{ .name = "fp_mult", .default = tunable_defaults.fp_mult },
    .{ .name = "qs_see_threshold", .default = tunable_defaults.qs_see_threshold },
    .{ .name = "see_quiet_pruning_mult", .default = tunable_defaults.see_quiet_pruning_mult },
    .{ .name = "see_noisy_pruning_mult", .default = tunable_defaults.see_noisy_pruning_mult },
    .{ .name = "razoring_margin", .default = tunable_defaults.razoring_margin },
    .{ .name = "history_pruning_mult", .default = tunable_defaults.history_pruning_mult },
    .{ .name = "qs_futility_margin", .default = tunable_defaults.qs_futility_margin },
    .{ .name = "corrhist_pawn_weight", .default = tunable_defaults.corrhist_pawn_weight },
    .{ .name = "corrhist_nonpawn_weight", .default = tunable_defaults.corrhist_nonpawn_weight },
    .{ .name = "corrhist_countermove_weight", .default = tunable_defaults.corrhist_countermove_weight },
    .{ .name = "corrhist_major_weight", .default = tunable_defaults.corrhist_major_weight },
    .{ .name = "corrhist_minor_weight", .default = tunable_defaults.corrhist_minor_weight },
    .{ .name = "lmp_legal_base", .default = tunable_defaults.lmp_legal_base },
    .{ .name = "lmp_standard_mult", .default = tunable_defaults.lmp_standard_mult },
    .{ .name = "lmp_improving_mult", .default = tunable_defaults.lmp_improving_mult },
    .{ .name = "nodetm_base", .default = tunable_defaults.nodetm_base },
    .{ .name = "nodetm_mult", .default = tunable_defaults.nodetm_mult },
    .{ .name = "soft_limit_base", .default = tunable_defaults.soft_limit_base },
    .{ .name = "soft_limit_incr", .default = tunable_defaults.soft_limit_incr },
    .{ .name = "hard_limit_base", .default = tunable_defaults.hard_limit_base },
    .{ .name = "singular_depth_limit", .default = tunable_defaults.singular_depth_limit },
    .{ .name = "singular_tt_depth_margin", .default = tunable_defaults.singular_tt_depth_margin },
    .{ .name = "singular_beta_mult", .default = tunable_defaults.singular_beta_mult },
    .{ .name = "singular_depth_mult", .default = tunable_defaults.singular_depth_mult },
    .{ .name = "singular_dext_margin", .default = tunable_defaults.singular_dext_margin },
};

pub const tunable_constants = if (do_tuning) struct {
    pub var quiet_history_bonus_mult = tunable_defaults.quiet_history_bonus_mult;
    pub var quiet_history_bonus_offs = tunable_defaults.quiet_history_bonus_offs;
    pub var quiet_history_bonus_max = tunable_defaults.quiet_history_bonus_max;
    pub var quiet_history_penalty_mult = tunable_defaults.quiet_history_penalty_mult;
    pub var quiet_history_penalty_offs = tunable_defaults.quiet_history_penalty_offs;
    pub var quiet_history_penalty_max = tunable_defaults.quiet_history_penalty_max;
    pub var cont_history_bonus_mult = tunable_defaults.cont_history_bonus_mult;
    pub var cont_history_bonus_offs = tunable_defaults.cont_history_bonus_offs;
    pub var cont_history_bonus_max = tunable_defaults.cont_history_bonus_max;
    pub var cont_history_penalty_mult = tunable_defaults.cont_history_penalty_mult;
    pub var cont_history_penalty_offs = tunable_defaults.cont_history_penalty_offs;
    pub var cont_history_penalty_max = tunable_defaults.cont_history_penalty_max;
    pub var noisy_history_bonus_mult = tunable_defaults.noisy_history_bonus_mult;
    pub var noisy_history_bonus_offs = tunable_defaults.noisy_history_bonus_offs;
    pub var noisy_history_bonus_max = tunable_defaults.noisy_history_bonus_max;
    pub var noisy_history_penalty_mult = tunable_defaults.noisy_history_penalty_mult;
    pub var noisy_history_penalty_offs = tunable_defaults.noisy_history_penalty_offs;
    pub var noisy_history_penalty_max = tunable_defaults.noisy_history_penalty_max;
    pub var rfp_base = tunable_defaults.rfp_base;
    pub var rfp_mult = tunable_defaults.rfp_mult;
    pub var rfp_improving_margin = tunable_defaults.rfp_improving_margin;
    pub var rfp_worsening_margin = tunable_defaults.rfp_worsening_margin;
    pub var rfp_cutnode_margin = tunable_defaults.rfp_cutnode_margin;
    pub var aspiration_initial = tunable_defaults.aspiration_initial;
    pub var aspiration_multiplier = tunable_defaults.aspiration_multiplier;
    pub var lmr_quiet_base = tunable_defaults.lmr_quiet_base;
    pub var lmr_noisy_base = tunable_defaults.lmr_noisy_base;
    pub var lmr_quiet_log_mult = tunable_defaults.lmr_quiet_log_mult;
    pub var lmr_noisy_log_mult = tunable_defaults.lmr_noisy_log_mult;
    pub var lmr_quiet_depth_mult = tunable_defaults.lmr_quiet_depth_mult;
    pub var lmr_noisy_depth_mult = tunable_defaults.lmr_noisy_depth_mult;
    pub var lmr_quiet_legal_mult = tunable_defaults.lmr_quiet_legal_mult;
    pub var lmr_noisy_legal_mult = tunable_defaults.lmr_noisy_legal_mult;
    pub var lmr_pv_mult = tunable_defaults.lmr_pv_mult;
    pub var lmr_cutnode_mult = tunable_defaults.lmr_cutnode_mult;
    pub var lmr_improving_mult = tunable_defaults.lmr_improving_mult;
    pub var lmr_quiet_history_mult = tunable_defaults.lmr_quiet_history_mult;
    pub var lmr_noisy_history_mult = tunable_defaults.lmr_noisy_history_mult;
    pub var lmr_corrhist_mult = tunable_defaults.lmr_corrhist_mult;
    pub var lmr_ttmove_mult = tunable_defaults.lmr_ttmove_mult;
    pub var nmp_base = tunable_defaults.nmp_base;
    pub var nmp_mult = tunable_defaults.nmp_mult;
    pub var nmp_eval_reduction_scale = tunable_defaults.nmp_eval_reduction_scale;
    pub var nmp_eval_reduction_max = tunable_defaults.nmp_eval_reduction_max;
    pub var fp_base = tunable_defaults.fp_base;
    pub var fp_mult = tunable_defaults.fp_mult;
    pub var qs_see_threshold = tunable_defaults.qs_see_threshold;
    pub var see_quiet_pruning_mult = tunable_defaults.see_quiet_pruning_mult;
    pub var see_noisy_pruning_mult = tunable_defaults.see_noisy_pruning_mult;
    pub var razoring_margin = tunable_defaults.razoring_margin;
    pub var history_pruning_mult = tunable_defaults.history_pruning_mult;
    pub var qs_futility_margin = tunable_defaults.qs_futility_margin;
    pub var corrhist_pawn_weight = tunable_defaults.corrhist_pawn_weight;
    pub var corrhist_nonpawn_weight = tunable_defaults.corrhist_nonpawn_weight;
    pub var corrhist_countermove_weight = tunable_defaults.corrhist_countermove_weight;
    pub var corrhist_major_weight = tunable_defaults.corrhist_major_weight;
    pub var corrhist_minor_weight = tunable_defaults.corrhist_minor_weight;
    pub var lmp_legal_base = tunable_defaults.lmp_legal_base;
    pub var lmp_standard_mult = tunable_defaults.lmp_standard_mult;
    pub var lmp_improving_mult = tunable_defaults.lmp_improving_mult;
    pub var nodetm_base = tunable_defaults.nodetm_base;
    pub var nodetm_mult = tunable_defaults.nodetm_mult;
    pub var soft_limit_base = tunable_defaults.soft_limit_base;
    pub var soft_limit_incr = tunable_defaults.soft_limit_incr;
    pub var hard_limit_base = tunable_defaults.hard_limit_base;
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
