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
        return @max(0.5, d / 10);
    }
};

const tunable_defaults = struct {
    pub const quiet_history_bonus_mult: i32 = 480;
    pub const quiet_history_bonus_offs: i32 = 376;
    pub const quiet_history_bonus_max: i32 = 2834;
    pub const quiet_history_penalty_mult: i32 = 219;
    pub const quiet_history_penalty_offs: i32 = 321;
    pub const quiet_history_penalty_max: i32 = 1638;
    pub const cont_history_bonus_mult: i32 = 515;
    pub const cont_history_bonus_offs: i32 = 321;
    pub const cont_history_bonus_max: i32 = 2661;
    pub const cont_history_penalty_mult: i32 = 185;
    pub const cont_history_penalty_offs: i32 = 257;
    pub const cont_history_penalty_max: i32 = 1784;
    pub const noisy_history_bonus_mult: i32 = 312;
    pub const noisy_history_bonus_offs: i32 = 408;
    pub const noisy_history_bonus_max: i32 = 2377;
    pub const noisy_history_penalty_mult: i32 = 208;
    pub const noisy_history_penalty_offs: i32 = 171;
    pub const noisy_history_penalty_max: i32 = 1998;
    pub const rfp_base: i32 = 52;
    pub const rfp_mult: i32 = 57;
    pub const rfp_improving_margin: i32 = 74;
    pub const rfp_worsening_margin: i32 = 15;
    pub const rfp_cutnode_margin: i32 = 18;
    pub const rfp_corrplexity_mult: i32 = 21;
    pub const aspiration_initial: i32 = 14402;
    pub const aspiration_multiplier: i32 = 1580;
    pub const lmr_quiet_base: i32 = 2756;
    pub const lmr_noisy_base: i32 = 1755;
    pub const lmr_quiet_log_mult: i32 = 190;
    pub const lmr_noisy_log_mult: i32 = 217;
    pub const lmr_quiet_depth_mult: i32 = 793;
    pub const lmr_noisy_depth_mult: i32 = 801;
    pub const lmr_quiet_depth_offs: i32 = -149;
    pub const lmr_noisy_depth_offs: i32 = 250;
    pub const lmr_quiet_legal_mult: i32 = 908;
    pub const lmr_noisy_legal_mult: i32 = 951;
    pub const lmr_quiet_legal_offs: i32 = 212;
    pub const lmr_noisy_legal_offs: i32 = 2;
    pub const lmr_pv_mult: i32 = 1161;
    pub const lmr_cutnode_mult: i32 = 1096;
    pub const lmr_improving_mult: i32 = 870;
    pub const lmr_quiet_history_mult: i32 = 741;
    pub const lmr_noisy_history_mult: i32 = 1029;
    pub const lmr_corrhist_mult: i32 = 9595;
    pub const lmr_ttmove_mult: i32 = 655;
    pub const lmr_ttpv_mult: i32 = 539;
    pub const lmr_dodeeper_margin: i32 = 53;
    pub const nmp_base: i32 = 50816;
    pub const nmp_mult: i32 = 873;
    pub const nmp_eval_reduction_scale: i32 = 33;
    pub const nmp_eval_reduction_max: i32 = 24628;
    pub const fp_base: i32 = 281;
    pub const fp_mult: i32 = 95;
    pub const qs_see_threshold: i32 = -84;
    pub const see_quiet_pruning_mult: i32 = -71;
    pub const see_noisy_pruning_mult: i32 = -50;
    pub const razoring_margin: i32 = 223;
    pub const history_pruning_mult: i32 = -2927;
    pub const qs_futility_margin: i32 = 111;
    pub const corrhist_pawn_weight: i32 = 744;
    pub const corrhist_nonpawn_weight: i32 = 625;
    pub const corrhist_countermove_weight: i32 = 1143;
    pub const corrhist_major_weight: i32 = 1255;
    pub const corrhist_minor_weight: i32 = 1013;
    pub const lmp_standard_base: i32 = -3688;
    pub const lmp_improving_base: i32 = -3025;
    pub const lmp_standard_mult: i32 = 848;
    pub const lmp_improving_mult: i32 = 1108;
    pub const good_noisy_ordering_base: i32 = 19;
    pub const good_noisy_ordering_mult: i32 = 1017;
    pub const brunocut_failhigh_gamma: i32 = 483;
    pub const brunocut_failhigh_delta: i32 = 261;
    pub const see_pawn: i32 = 85;
    pub const see_knight: i32 = 315;
    pub const see_bishop: i32 = 305;
    pub const see_rook: i32 = 538;
    pub const see_queen: i32 = 885;
    pub const material_scaling_base: i32 = 9033;
    pub const material_scaling_pawn: i32 = 5;
    pub const material_scaling_knight: i32 = 348;
    pub const material_scaling_bishop: i32 = 401;
    pub const material_scaling_rook: i32 = 559;
    pub const material_scaling_queen: i32 = 981;
    pub const nodetm_base: i32 = 1594;
    pub const nodetm_mult: i32 = 1037;
    pub const eval_stab_base: i32 = 1249;
    pub const eval_stab_offs: i32 = 55;
    pub const move_stab_base: i32 = 1288;
    pub const move_stab_offs: i32 = 46;
    pub const soft_limit_base: i32 = 52;
    pub const soft_limit_incr: i32 = 599;
    pub const hard_limit_phase_mult: i32 = 122;
    pub const hard_limit_base: i32 = 205;
    pub const singular_beta_mult: i32 = 399;
    pub const singular_depth_mult: i32 = 585;
    pub const singular_depth_offs: i32 = 720;
    pub const singular_dext_margin: i32 = 15;
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
    .{ .name = "rfp_corrplexity_mult", .default = tunable_defaults.rfp_corrplexity_mult },
    .{ .name = "aspiration_initial", .default = tunable_defaults.aspiration_initial },
    .{ .name = "aspiration_multiplier", .default = tunable_defaults.aspiration_multiplier },
    .{ .name = "lmr_quiet_base", .default = tunable_defaults.lmr_quiet_base },
    .{ .name = "lmr_noisy_base", .default = tunable_defaults.lmr_noisy_base },
    .{ .name = "lmr_quiet_log_mult", .default = tunable_defaults.lmr_quiet_log_mult },
    .{ .name = "lmr_noisy_log_mult", .default = tunable_defaults.lmr_noisy_log_mult },
    .{ .name = "lmr_quiet_depth_mult", .default = tunable_defaults.lmr_quiet_depth_mult },
    .{ .name = "lmr_noisy_depth_mult", .default = tunable_defaults.lmr_noisy_depth_mult },
    .{ .name = "lmr_quiet_depth_offs", .default = tunable_defaults.lmr_quiet_depth_offs, .min = -1024, .max = 1024, .c_end = 128 },
    .{ .name = "lmr_noisy_depth_offs", .default = tunable_defaults.lmr_noisy_depth_offs, .min = -1024, .max = 1024, .c_end = 128 },
    .{ .name = "lmr_quiet_legal_mult", .default = tunable_defaults.lmr_quiet_legal_mult },
    .{ .name = "lmr_noisy_legal_mult", .default = tunable_defaults.lmr_noisy_legal_mult },
    .{ .name = "lmr_quiet_legal_offs", .default = tunable_defaults.lmr_quiet_legal_offs, .min = -1024, .max = 1024, .c_end = 128 },
    .{ .name = "lmr_noisy_legal_offs", .default = tunable_defaults.lmr_noisy_legal_offs, .min = -1024, .max = 1024, .c_end = 128 },
    .{ .name = "lmr_pv_mult", .default = tunable_defaults.lmr_pv_mult },
    .{ .name = "lmr_cutnode_mult", .default = tunable_defaults.lmr_cutnode_mult },
    .{ .name = "lmr_improving_mult", .default = tunable_defaults.lmr_improving_mult },
    .{ .name = "lmr_quiet_history_mult", .default = tunable_defaults.lmr_quiet_history_mult },
    .{ .name = "lmr_noisy_history_mult", .default = tunable_defaults.lmr_noisy_history_mult },
    .{ .name = "lmr_corrhist_mult", .default = tunable_defaults.lmr_corrhist_mult },
    .{ .name = "lmr_ttmove_mult", .default = tunable_defaults.lmr_ttmove_mult },
    .{ .name = "lmr_ttpv_mult", .default = tunable_defaults.lmr_ttpv_mult },
    .{ .name = "lmr_dodeeper_margin", .default = tunable_defaults.lmr_dodeeper_margin },
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
    .{ .name = "lmp_standard_base", .default = tunable_defaults.lmp_standard_base },
    .{ .name = "lmp_improving_base", .default = tunable_defaults.lmp_improving_base },
    .{ .name = "lmp_standard_mult", .default = tunable_defaults.lmp_standard_mult },
    .{ .name = "lmp_improving_mult", .default = tunable_defaults.lmp_improving_mult },
    .{ .name = "good_noisy_ordering_base", .default = tunable_defaults.good_noisy_ordering_base, .min = -2048, .max = 2048, .c_end = 256 },
    .{ .name = "good_noisy_ordering_mult", .default = tunable_defaults.good_noisy_ordering_mult },
    .{ .name = "brunocut_failhigh_gamma", .default = tunable_defaults.brunocut_failhigh_gamma },
    .{ .name = "brunocut_failhigh_delta", .default = tunable_defaults.brunocut_failhigh_delta },
    .{ .name = "see_pawn", .default = tunable_defaults.see_pawn },
    .{ .name = "see_knight", .default = tunable_defaults.see_knight },
    .{ .name = "see_bishop", .default = tunable_defaults.see_bishop },
    .{ .name = "see_rook", .default = tunable_defaults.see_rook },
    .{ .name = "see_queen", .default = tunable_defaults.see_queen },
    .{ .name = "material_scaling_base", .default = tunable_defaults.material_scaling_base },
    .{ .name = "material_scaling_pawn", .default = tunable_defaults.material_scaling_pawn, .min = -100, .max = 200, .c_end = 15 },
    .{ .name = "material_scaling_knight", .default = tunable_defaults.material_scaling_knight },
    .{ .name = "material_scaling_bishop", .default = tunable_defaults.material_scaling_bishop },
    .{ .name = "material_scaling_rook", .default = tunable_defaults.material_scaling_rook },
    .{ .name = "material_scaling_queen", .default = tunable_defaults.material_scaling_queen },
    .{ .name = "nodetm_base", .default = tunable_defaults.nodetm_base, .c_end = 80 },
    .{ .name = "nodetm_mult", .default = tunable_defaults.nodetm_mult, .c_end = 50 },
    .{ .name = "eval_stab_base", .default = tunable_defaults.eval_stab_base, .c_end = 60 },
    .{ .name = "eval_stab_offs", .default = tunable_defaults.eval_stab_offs, .c_end = 2 },
    .{ .name = "move_stab_base", .default = tunable_defaults.move_stab_base, .c_end = 60 },
    .{ .name = "move_stab_offs", .default = tunable_defaults.move_stab_offs, .c_end = 2 },
    .{ .name = "soft_limit_base", .default = tunable_defaults.soft_limit_base, .c_end = 2 },
    .{ .name = "soft_limit_incr", .default = tunable_defaults.soft_limit_incr, .c_end = 30 },
    .{ .name = "hard_limit_phase_mult", .default = tunable_defaults.hard_limit_phase_mult, .c_end = 6 },
    .{ .name = "hard_limit_base", .default = tunable_defaults.hard_limit_base, .c_end = 10 },
    .{ .name = "singular_beta_mult", .default = tunable_defaults.singular_beta_mult },
    .{ .name = "singular_depth_mult", .default = tunable_defaults.singular_depth_mult },
    .{ .name = "singular_depth_offs", .default = tunable_defaults.singular_depth_offs },
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
    pub var rfp_corrplexity_mult = tunable_defaults.rfp_corrplexity_mult;
    pub var aspiration_initial = tunable_defaults.aspiration_initial;
    pub var aspiration_multiplier = tunable_defaults.aspiration_multiplier;
    pub var lmr_quiet_base = tunable_defaults.lmr_quiet_base;
    pub var lmr_noisy_base = tunable_defaults.lmr_noisy_base;
    pub var lmr_quiet_log_mult = tunable_defaults.lmr_quiet_log_mult;
    pub var lmr_noisy_log_mult = tunable_defaults.lmr_noisy_log_mult;
    pub var lmr_quiet_depth_mult = tunable_defaults.lmr_quiet_depth_mult;
    pub var lmr_noisy_depth_mult = tunable_defaults.lmr_noisy_depth_mult;
    pub var lmr_quiet_depth_offs = tunable_defaults.lmr_quiet_depth_offs;
    pub var lmr_noisy_depth_offs = tunable_defaults.lmr_noisy_depth_offs;
    pub var lmr_quiet_legal_mult = tunable_defaults.lmr_quiet_legal_mult;
    pub var lmr_noisy_legal_mult = tunable_defaults.lmr_noisy_legal_mult;
    pub var lmr_quiet_legal_offs = tunable_defaults.lmr_quiet_legal_offs;
    pub var lmr_noisy_legal_offs = tunable_defaults.lmr_noisy_legal_offs;
    pub var lmr_pv_mult = tunable_defaults.lmr_pv_mult;
    pub var lmr_cutnode_mult = tunable_defaults.lmr_cutnode_mult;
    pub var lmr_improving_mult = tunable_defaults.lmr_improving_mult;
    pub var lmr_quiet_history_mult = tunable_defaults.lmr_quiet_history_mult;
    pub var lmr_noisy_history_mult = tunable_defaults.lmr_noisy_history_mult;
    pub var lmr_corrhist_mult = tunable_defaults.lmr_corrhist_mult;
    pub var lmr_ttmove_mult = tunable_defaults.lmr_ttmove_mult;
    pub var lmr_ttpv_mult = tunable_defaults.lmr_ttpv_mult;
    pub var lmr_dodeeper_margin = tunable_defaults.lmr_dodeeper_margin;
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
    pub var lmp_standard_base = tunable_defaults.lmp_standard_base;
    pub var lmp_improving_base = tunable_defaults.lmp_improving_base;
    pub var lmp_standard_mult = tunable_defaults.lmp_standard_mult;
    pub var lmp_improving_mult = tunable_defaults.lmp_improving_mult;
    pub var good_noisy_ordering_base = tunable_defaults.good_noisy_ordering_base;
    pub var good_noisy_ordering_mult = tunable_defaults.good_noisy_ordering_mult;
    pub var brunocut_failhigh_gamma = tunable_defaults.brunocut_failhigh_gamma;
    pub var brunocut_failhigh_delta = tunable_defaults.brunocut_failhigh_delta;
    pub var see_pawn = tunable_defaults.see_pawn;
    pub var see_knight = tunable_defaults.see_knight;
    pub var see_bishop = tunable_defaults.see_bishop;
    pub var see_rook = tunable_defaults.see_rook;
    pub var see_queen = tunable_defaults.see_queen;
    pub var material_scaling_base = tunable_defaults.material_scaling_base;
    pub var material_scaling_pawn = tunable_defaults.material_scaling_pawn;
    pub var material_scaling_knight = tunable_defaults.material_scaling_knight;
    pub var material_scaling_bishop = tunable_defaults.material_scaling_bishop;
    pub var material_scaling_rook = tunable_defaults.material_scaling_rook;
    pub var material_scaling_queen = tunable_defaults.material_scaling_queen;
    pub var nodetm_base = tunable_defaults.nodetm_base;
    pub var nodetm_mult = tunable_defaults.nodetm_mult;
    pub var eval_stab_base = tunable_defaults.eval_stab_base;
    pub var eval_stab_offs = tunable_defaults.eval_stab_offs;
    pub var move_stab_base = tunable_defaults.move_stab_base;
    pub var move_stab_offs = tunable_defaults.move_stab_offs;
    pub var soft_limit_base = tunable_defaults.soft_limit_base;
    pub var soft_limit_incr = tunable_defaults.soft_limit_incr;
    pub var hard_limit_phase_mult = tunable_defaults.hard_limit_phase_mult;
    pub var hard_limit_base = tunable_defaults.hard_limit_base;
    pub var singular_beta_mult = tunable_defaults.singular_beta_mult;
    pub var singular_depth_mult = tunable_defaults.singular_depth_mult;
    pub var singular_depth_offs = tunable_defaults.singular_depth_offs;
    pub var singular_dext_margin = tunable_defaults.singular_dext_margin;
} else tunable_defaults;

comptime {
    std.debug.assert(std.meta.declarations(tunable_defaults).len == tunables.len);
    std.debug.assert(std.meta.declarations(tunable_constants).len == tunables.len);
}
