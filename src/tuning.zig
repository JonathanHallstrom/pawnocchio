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
        if (self.c_end) |m| {
            return m;
        }
        const d: f64 = @floatFromInt(@abs(self.default));
        return @max(0.5, d / 10);
    }
};

pub fn setMin() void {
    if (!do_tuning) {
        return;
    }
    inline for (tunables) |tunable| {
        @field(tunable_constants, tunable.name) = tunable.getMin();
    }
}
pub fn setMax() void {
    if (!do_tuning) {
        return;
    }
    inline for (tunables) |tunable| {
        @field(tunable_constants, tunable.name) = tunable.getMax();
    }
}

const tunable_defaults = struct {
    pub const quiet_history_bonus_mult: i32 = 474;
    pub const quiet_history_bonus_offs: i32 = 507;
    pub const quiet_history_bonus_max: i32 = 3462;
    pub const quiet_history_penalty_mult: i32 = 222;
    pub const quiet_history_penalty_offs: i32 = 311;
    pub const quiet_history_penalty_max: i32 = 1154;
    pub const pawn_history_bonus_mult: i32 = 385;
    pub const pawn_history_bonus_offs: i32 = 365;
    pub const pawn_history_bonus_max: i32 = 2420;
    pub const pawn_history_penalty_mult: i32 = 304;
    pub const pawn_history_penalty_offs: i32 = 386;
    pub const pawn_history_penalty_max: i32 = 1488;
    pub const cont_history_bonus_mult: i32 = 190;
    pub const cont_history_bonus_offs: i32 = 168;
    pub const cont_history_bonus_max: i32 = 3463;
    pub const cont_history_penalty_mult: i32 = 186;
    pub const cont_history_penalty_offs: i32 = 333;
    pub const cont_history_penalty_max: i32 = 1209;
    pub const noisy_history_bonus_mult: i32 = 284;
    pub const noisy_history_bonus_offs: i32 = 279;
    pub const noisy_history_bonus_max: i32 = 2948;
    pub const noisy_history_penalty_mult: i32 = 211;
    pub const noisy_history_penalty_offs: i32 = 205;
    pub const noisy_history_penalty_max: i32 = 2596;
    pub const high_eval_offs: i32 = 50;
    pub const faillow_mult: i32 = 2222;
    pub const quiet_ordering_weight: i32 = 1238;
    pub const quiet_pruning_weight: i32 = 837;
    pub const pawn_ordering_weight: i32 = 924;
    pub const pawn_pruning_weight: i32 = 711;
    pub const cont1_ordering_weight: i32 = 1237;
    pub const cont1_pruning_weight: i32 = 866;
    pub const cont2_ordering_weight: i32 = 1126;
    pub const cont2_pruning_weight: i32 = 1005;
    pub const cont4_ordering_weight: i32 = 1053;
    pub const cont4_pruning_weight: i32 = 139;
    pub const rfp_min_margin: i32 = 23;
    pub const rfp_base: i32 = 49056;
    pub const rfp_mult: i32 = 40340;
    pub const rfp_quad: i32 = 6451;
    pub const rfp_improving_margin: i32 = 80;
    pub const rfp_easy_margin: i32 = 0;
    pub const rfp_improving_easy_margin: i32 = -84;
    pub const rfp_worsening_margin: i32 = 14;
    pub const rfp_cutnode_margin: i32 = 18;
    pub const rfp_corrplexity_mult: i32 = 17;
    pub const rfp_history_mult: i32 = 49;
    pub const rfp_noisy_history_mult: i32 = 38;
    pub const aspiration_score_mult: i32 = 1118;
    pub const aspiration_initial: i32 = 10170;
    pub const aspiration_multiplier: i32 = 1249;
    pub const lmr_quiet_base: i32 = 3592;
    pub const lmr_noisy_base: i32 = 2277;
    pub const lmr_quiet_depth_mult: i32 = 367;
    pub const lmr_noisy_depth_mult: i32 = 312;
    pub const lmr_quiet_depth_offs: i32 = -52;
    pub const lmr_noisy_depth_offs: i32 = 57;
    pub const lmr_quiet_legal_mult: i32 = 532;
    pub const lmr_noisy_legal_mult: i32 = 512;
    pub const lmr_quiet_legal_offs: i32 = -15;
    pub const lmr_noisy_legal_offs: i32 = -43;
    pub const lmr_quiet_history_mult: i32 = 640;
    pub const lmr_noisy_history_mult: i32 = 1003;
    pub const lmr_corrhist_mult: i32 = 7015;
    pub const lmr_dodeeper_margin: i32 = 56;
    pub const lmr_dodeeper_mult: i32 = 2;
    pub const lmr_doshallower_margin: i32 = 1;
    pub const hindsight_ext_margin: i32 = 2954;
    pub const nmp_margin_base: i32 = 258;
    pub const nmp_margin_mult: i32 = 24;
    pub const nmp_base: i32 = 66220;
    pub const nmp_mult: i32 = 1190;
    pub const fp_depth_limit: i32 = 8571;
    pub const fp_base: i32 = 282;
    pub const fp_mult: i32 = 70;
    pub const fp_pv_base: i32 = 94;
    pub const fp_pv_mult: i32 = 31;
    pub const fp_hist_mult: i32 = 141;
    pub const bnfp_depth_limit: i32 = 8386;
    pub const bnfp_base: i32 = 180;
    pub const bnfp_mult: i32 = 81;
    pub const qs_see_threshold: i32 = -74;
    pub const see_quiet_pruning_offs: i32 = -47;
    pub const see_noisy_pruning_offs: i32 = 1;
    pub const see_quiet_pruning_mult: i32 = 1;
    pub const see_noisy_pruning_mult: i32 = 0;
    pub const see_quiet_pruning_quad: i32 = -34;
    pub const see_noisy_pruning_quad: i32 = -41;
    pub const see_pv_offs: i32 = 97;
    pub const razoring_offs: i32 = 52;
    pub const razoring_mult: i32 = 231;
    pub const razoring_quad: i32 = 100;
    pub const razoring_easy_capture: i32 = 107;
    pub const history_pruning_depth_limit: i32 = 3994;
    pub const history_pruning_offs: i32 = 835;
    pub const history_pruning_mult: i32 = -3014;
    pub const noisy_history_pruning_depth_limit: i32 = 3964;
    pub const noisy_history_pruning_offs: i32 = 792;
    pub const noisy_history_pruning_mult: i32 = -2928;
    pub const qs_futility_margin: i32 = 141;
    pub const qs_hp_margin: i32 = -3654;
    pub const corrhist_pawn_weight: i32 = 815;
    pub const corrhist_nonpawn_weight: i32 = 912;
    pub const corrhist_countermove_weight: i32 = 717;
    pub const corrhist_followupmove_weight: i32 = 520;
    pub const corrhist_major_weight: i32 = 1012;
    pub const corrhist_minor_weight: i32 = 971;
    pub const corrhist_pawn_update_weight: i32 = 2267;
    pub const corrhist_nonpawn_update_weight: i32 = 1957;
    pub const corrhist_countermove_update_weight: i32 = 2091;
    pub const corrhist_followupmove_update_weight: i32 = 1885;
    pub const corrhist_major_update_weight: i32 = 1962;
    pub const corrhist_minor_update_weight: i32 = 2046;
    pub const lmp_standard_base: i32 = 4423;
    pub const lmp_improving_base: i32 = 4649;
    pub const lmp_standard_linear_mult: i32 = 15;
    pub const lmp_improving_linear_mult: i32 = 367;
    pub const lmp_standard_quadratic_mult: i32 = 117;
    pub const lmp_improving_quadratic_mult: i32 = 1256;
    pub const good_noisy_ordering_base: i32 = 2;
    pub const good_noisy_ordering_mult: i32 = 877;
    pub const see_pawn_pruning: i32 = 85;
    pub const see_knight_pruning: i32 = 210;
    pub const see_bishop_pruning: i32 = 316;
    pub const see_rook_pruning: i32 = 554;
    pub const see_queen_pruning: i32 = 929;
    pub const see_pawn_ordering: i32 = 85;
    pub const see_knight_ordering: i32 = 244;
    pub const see_bishop_ordering: i32 = 306;
    pub const see_rook_ordering: i32 = 543;
    pub const see_queen_ordering: i32 = 820;
    pub const mvv_mult: i32 = 680;
    pub const material_scaling_base: i32 = 9363;
    pub const material_scaling_pawn: i32 = 80;
    pub const material_scaling_knight: i32 = 333;
    pub const material_scaling_bishop: i32 = 454;
    pub const material_scaling_rook: i32 = 267;
    pub const material_scaling_queen: i32 = 1020;
    pub const multicut_fail_medium: i32 = 139;
    pub const rfp_fail_medium: i32 = 359;
    pub const tt_fail_medium: i32 = 8;
    pub const qs_tt_fail_medium: i32 = 240;
    pub const standpat_fail_medium: i32 = 129;
    pub const nodetm_base: i32 = 1433;
    pub const nodetm_mult: i32 = 1177;
    pub const eval_stab_margin: i32 = 22;
    pub const eval_stab_base: i32 = 1360;
    pub const eval_stab_offs: i32 = 55;
    pub const eval_stab_lim: i32 = 879;
    pub const move_stab_base: i32 = 1327;
    pub const move_stab_offs: i32 = 46;
    pub const move_stab_lim: i32 = 958;
    pub const soft_limit_base: i32 = 52;
    pub const soft_limit_incr: i32 = 779;
    pub const hard_limit_phase_mult: i32 = 111;
    pub const hard_limit_base: i32 = 229;
    pub const singular_beta_mult: i32 = 414;
    pub const singular_beta_pv_mult: i32 = 432;
    pub const singular_beta_ttpv_mult: i32 = 382;
    pub const singular_depth_mult: i32 = 543;
    pub const singular_depth_offs: i32 = 780;
    pub const singular_dext_margin_quiet: i32 = 17;
    pub const singular_dext_margin_noisy: i32 = 15;
    pub const singular_dext_pv_margin: i32 = 23;
    pub const singular_text_margin_quiet: i32 = 81;
    pub const singular_text_margin_noisy: i32 = 85;
    pub const singular_text_pv_margin: i32 = 503;
    pub const ttpick_depth_weight: i32 = 926;
    pub const ttpick_age_weight: i32 = 4413;
    pub const ttpick_pv_weight: i32 = 356;
    pub const ttpick_lower_weight: i32 = 344;
    pub const ttpick_upper_weight: i32 = 202;
    pub const ttpick_exact_weight: i32 = 51;
    pub const ttpick_move_weight: i32 = 426;
};

pub const tunables = [_]Tunable{
    .{ .name = "quiet_history_bonus_mult", .default = tunable_defaults.quiet_history_bonus_mult },
    .{ .name = "quiet_history_bonus_offs", .default = tunable_defaults.quiet_history_bonus_offs },
    .{ .name = "quiet_history_bonus_max", .default = tunable_defaults.quiet_history_bonus_max },
    .{ .name = "quiet_history_penalty_mult", .default = tunable_defaults.quiet_history_penalty_mult },
    .{ .name = "quiet_history_penalty_offs", .default = tunable_defaults.quiet_history_penalty_offs },
    .{ .name = "quiet_history_penalty_max", .default = tunable_defaults.quiet_history_penalty_max },
    .{ .name = "pawn_history_bonus_mult", .default = tunable_defaults.pawn_history_bonus_mult },
    .{ .name = "pawn_history_bonus_offs", .default = tunable_defaults.pawn_history_bonus_offs },
    .{ .name = "pawn_history_bonus_max", .default = tunable_defaults.pawn_history_bonus_max },
    .{ .name = "pawn_history_penalty_mult", .default = tunable_defaults.pawn_history_penalty_mult },
    .{ .name = "pawn_history_penalty_offs", .default = tunable_defaults.pawn_history_penalty_offs },
    .{ .name = "pawn_history_penalty_max", .default = tunable_defaults.pawn_history_penalty_max },
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
    .{ .name = "high_eval_offs", .default = tunable_defaults.high_eval_offs },
    .{ .name = "faillow_mult", .default = tunable_defaults.faillow_mult },
    .{ .name = "quiet_ordering_weight", .default = tunable_defaults.quiet_ordering_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "quiet_pruning_weight", .default = tunable_defaults.quiet_pruning_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "pawn_ordering_weight", .default = tunable_defaults.pawn_ordering_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "pawn_pruning_weight", .default = tunable_defaults.pawn_pruning_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "cont1_ordering_weight", .default = tunable_defaults.cont1_ordering_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "cont1_pruning_weight", .default = tunable_defaults.cont1_pruning_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "cont2_ordering_weight", .default = tunable_defaults.cont2_ordering_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "cont2_pruning_weight", .default = tunable_defaults.cont2_pruning_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "cont4_ordering_weight", .default = tunable_defaults.cont4_ordering_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "cont4_pruning_weight", .default = tunable_defaults.cont4_pruning_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "rfp_min_margin", .default = tunable_defaults.rfp_min_margin },
    .{ .name = "rfp_base", .default = tunable_defaults.rfp_base },
    .{ .name = "rfp_mult", .default = tunable_defaults.rfp_mult },
    .{ .name = "rfp_quad", .default = tunable_defaults.rfp_quad, .c_end = @as(f64, tunable_defaults.rfp_quad) / 20 },
    .{ .name = "rfp_improving_margin", .default = tunable_defaults.rfp_improving_margin },
    .{ .name = "rfp_easy_margin", .default = tunable_defaults.rfp_easy_margin, .min = -50, .max = 50, .c_end = 5 },
    .{ .name = "rfp_improving_easy_margin", .default = tunable_defaults.rfp_improving_easy_margin },
    .{ .name = "rfp_worsening_margin", .default = tunable_defaults.rfp_worsening_margin, .min = -10, .max = 45, .c_end = 1 },
    .{ .name = "rfp_cutnode_margin", .default = tunable_defaults.rfp_cutnode_margin, .min = -10, .max = 55, .c_end = 1 },
    .{ .name = "rfp_corrplexity_mult", .default = tunable_defaults.rfp_corrplexity_mult, .min = -10, .max = 60, .c_end = 2 },
    .{ .name = "rfp_history_mult", .default = tunable_defaults.rfp_history_mult },
    .{ .name = "rfp_noisy_history_mult", .default = tunable_defaults.rfp_noisy_history_mult },
    .{ .name = "aspiration_score_mult", .default = tunable_defaults.aspiration_score_mult, .min = 10, .max = 4096, .c_end = 32 },
    .{ .name = "aspiration_initial", .default = tunable_defaults.aspiration_initial, .min = 10, .max = 39450, .c_end = 1577 },
    .{ .name = "aspiration_multiplier", .default = tunable_defaults.aspiration_multiplier, .min = 1127, .max = 4015, .c_end = 160 },
    .{ .name = "lmr_quiet_base", .default = tunable_defaults.lmr_quiet_base, .min = -10, .max = 6772, .c_end = 270 },
    .{ .name = "lmr_noisy_base", .default = tunable_defaults.lmr_noisy_base, .min = -10, .max = 4412, .c_end = 176 },
    .{ .name = "lmr_quiet_depth_mult", .default = tunable_defaults.lmr_quiet_depth_mult, .min = -10, .max = 1895, .c_end = 75 },
    .{ .name = "lmr_noisy_depth_mult", .default = tunable_defaults.lmr_noisy_depth_mult, .min = -10, .max = 2132, .c_end = 84 },
    .{ .name = "lmr_quiet_depth_offs", .default = tunable_defaults.lmr_quiet_depth_offs, .min = -1024, .max = 1024, .c_end = 32 },
    .{ .name = "lmr_noisy_depth_offs", .default = tunable_defaults.lmr_noisy_depth_offs, .min = -1024, .max = 1024, .c_end = 32 },
    .{ .name = "lmr_quiet_legal_mult", .default = tunable_defaults.lmr_quiet_legal_mult, .min = -10, .max = 2302, .c_end = 91 },
    .{ .name = "lmr_noisy_legal_mult", .default = tunable_defaults.lmr_noisy_legal_mult, .min = -10, .max = 2357, .c_end = 93 },
    .{ .name = "lmr_quiet_legal_offs", .default = tunable_defaults.lmr_quiet_legal_offs, .min = -1024, .max = 1024, .c_end = 32 },
    .{ .name = "lmr_noisy_legal_offs", .default = tunable_defaults.lmr_noisy_legal_offs, .min = -1024, .max = 1024, .c_end = 32 },
    .{ .name = "lmr_quiet_history_mult", .default = tunable_defaults.lmr_quiet_history_mult, .min = -10, .max = 1975, .c_end = 78 },
    .{ .name = "lmr_noisy_history_mult", .default = tunable_defaults.lmr_noisy_history_mult, .min = -10, .max = 2470, .c_end = 98 },
    .{ .name = "lmr_corrhist_mult", .default = tunable_defaults.lmr_corrhist_mult, .min = -10, .max = 23695, .c_end = 947 },
    .{ .name = "lmr_dodeeper_margin", .default = tunable_defaults.lmr_dodeeper_margin, .min = -10, .max = 140, .c_end = 5 },
    .{ .name = "lmr_dodeeper_mult", .default = tunable_defaults.lmr_dodeeper_mult, .min = 0, .max = 10, .c_end = 0.5 },
    .{ .name = "lmr_doshallower_margin", .default = tunable_defaults.lmr_doshallower_margin, .min = -50, .max = 50, .c_end = 3 },
    .{ .name = "hindsight_ext_margin", .default = tunable_defaults.hindsight_ext_margin },
    .{ .name = "nmp_margin_base", .default = tunable_defaults.nmp_margin_base },
    .{ .name = "nmp_margin_mult", .default = tunable_defaults.nmp_margin_mult },
    .{ .name = "nmp_base", .default = tunable_defaults.nmp_base },
    .{ .name = "nmp_mult", .default = tunable_defaults.nmp_mult },
    .{ .name = "fp_depth_limit", .default = tunable_defaults.fp_depth_limit },
    .{ .name = "fp_base", .default = tunable_defaults.fp_base },
    .{ .name = "fp_mult", .default = tunable_defaults.fp_mult },
    .{ .name = "fp_pv_base", .default = tunable_defaults.fp_pv_base },
    .{ .name = "fp_pv_mult", .default = tunable_defaults.fp_pv_mult },
    .{ .name = "fp_hist_mult", .default = tunable_defaults.fp_hist_mult },
    .{ .name = "bnfp_depth_limit", .default = tunable_defaults.bnfp_depth_limit },
    .{ .name = "bnfp_base", .default = tunable_defaults.bnfp_base },
    .{ .name = "bnfp_mult", .default = tunable_defaults.bnfp_mult },
    .{ .name = "qs_see_threshold", .default = tunable_defaults.qs_see_threshold },
    .{ .name = "see_quiet_pruning_offs", .default = tunable_defaults.see_quiet_pruning_offs, .min = -100, .max = 100, .c_end = 20 },
    .{ .name = "see_noisy_pruning_offs", .default = tunable_defaults.see_noisy_pruning_offs, .min = -100, .max = 100, .c_end = 5 },
    .{ .name = "see_quiet_pruning_mult", .default = tunable_defaults.see_quiet_pruning_mult },
    .{ .name = "see_noisy_pruning_mult", .default = tunable_defaults.see_noisy_pruning_mult },
    .{ .name = "see_quiet_pruning_quad", .default = tunable_defaults.see_quiet_pruning_quad },
    .{ .name = "see_noisy_pruning_quad", .default = tunable_defaults.see_noisy_pruning_quad },
    .{ .name = "see_pv_offs", .default = tunable_defaults.see_pv_offs },
    .{ .name = "razoring_offs", .default = tunable_defaults.razoring_offs },
    .{ .name = "razoring_mult", .default = tunable_defaults.razoring_mult },
    .{ .name = "razoring_quad", .default = tunable_defaults.razoring_quad },
    .{ .name = "razoring_easy_capture", .default = tunable_defaults.razoring_easy_capture, .min = -1024, .max = 1024, .c_end = 10 },
    .{ .name = "history_pruning_depth_limit", .default = tunable_defaults.history_pruning_depth_limit },
    .{ .name = "history_pruning_offs", .default = tunable_defaults.history_pruning_offs, .min = -2048, .max = 1024, .c_end = 128 },
    .{ .name = "history_pruning_mult", .default = tunable_defaults.history_pruning_mult, .min = -7382, .max = 9, .c_end = 294 },
    .{ .name = "noisy_history_pruning_depth_limit", .default = tunable_defaults.noisy_history_pruning_depth_limit },
    .{ .name = "noisy_history_pruning_offs", .default = tunable_defaults.noisy_history_pruning_offs, .min = -2048, .max = 1024, .c_end = 128 },
    .{ .name = "noisy_history_pruning_mult", .default = tunable_defaults.noisy_history_pruning_mult, .min = -7382, .max = 9, .c_end = 294 },
    .{ .name = "qs_futility_margin", .default = tunable_defaults.qs_futility_margin, .min = -10, .max = 305, .c_end = 11 },
    .{ .name = "qs_hp_margin", .default = tunable_defaults.qs_hp_margin, .min = -6000, .max = 0, .c_end = 400 },
    .{ .name = "corrhist_pawn_weight", .default = tunable_defaults.corrhist_pawn_weight, .min = -10, .max = 1825, .c_end = 72 },
    .{ .name = "corrhist_nonpawn_weight", .default = tunable_defaults.corrhist_nonpawn_weight, .min = -10, .max = 1500, .c_end = 59 },
    .{ .name = "corrhist_countermove_weight", .default = tunable_defaults.corrhist_countermove_weight, .min = -10, .max = 2875, .c_end = 114 },
    .{ .name = "corrhist_followupmove_weight", .default = tunable_defaults.corrhist_followupmove_weight, .min = -10, .max = 2875, .c_end = 114 },
    .{ .name = "corrhist_major_weight", .default = tunable_defaults.corrhist_major_weight, .min = -10, .max = 2952, .c_end = 117 },
    .{ .name = "corrhist_minor_weight", .default = tunable_defaults.corrhist_minor_weight, .min = -10, .max = 2315, .c_end = 92 },
    .{ .name = "corrhist_pawn_update_weight", .default = tunable_defaults.corrhist_pawn_update_weight },
    .{ .name = "corrhist_nonpawn_update_weight", .default = tunable_defaults.corrhist_nonpawn_update_weight },
    .{ .name = "corrhist_countermove_update_weight", .default = tunable_defaults.corrhist_countermove_update_weight },
    .{ .name = "corrhist_followupmove_update_weight", .default = tunable_defaults.corrhist_followupmove_update_weight },
    .{ .name = "corrhist_major_update_weight", .default = tunable_defaults.corrhist_major_update_weight },
    .{ .name = "corrhist_minor_update_weight", .default = tunable_defaults.corrhist_minor_update_weight },
    .{ .name = "lmp_standard_base", .default = tunable_defaults.lmp_standard_base, .min = 10, .max = 9345, .c_end = 300 },
    .{ .name = "lmp_improving_base", .default = tunable_defaults.lmp_improving_base, .min = 10, .max = 7580, .c_end = 300 },
    .{ .name = "lmp_standard_linear_mult", .default = tunable_defaults.lmp_standard_linear_mult, .min = -1024, .max = 1024, .c_end = 50 },
    .{ .name = "lmp_improving_linear_mult", .default = tunable_defaults.lmp_improving_linear_mult, .min = -1024, .max = 1024, .c_end = 50 },
    .{ .name = "lmp_standard_quadratic_mult", .default = tunable_defaults.lmp_standard_quadratic_mult, .min = -10, .max = 2177, .c_end = 40 },
    .{ .name = "lmp_improving_quadratic_mult", .default = tunable_defaults.lmp_improving_quadratic_mult, .min = -10, .max = 2717, .c_end = 100 },
    .{ .name = "good_noisy_ordering_base", .default = tunable_defaults.good_noisy_ordering_base, .min = -2048, .max = 2048, .c_end = 32 },
    .{ .name = "good_noisy_ordering_mult", .default = tunable_defaults.good_noisy_ordering_mult, .min = -10, .max = 2570, .c_end = 102 },
    .{ .name = "see_pawn_pruning", .default = tunable_defaults.see_pawn_pruning, .min = 10, .max = 215, .c_end = 8 },
    .{ .name = "see_knight_pruning", .default = tunable_defaults.see_knight_pruning, .min = 10, .max = 792, .c_end = 31 },
    .{ .name = "see_bishop_pruning", .default = tunable_defaults.see_bishop_pruning, .min = 10, .max = 737, .c_end = 29 },
    .{ .name = "see_rook_pruning", .default = tunable_defaults.see_rook_pruning, .min = 10, .max = 1355, .c_end = 53 },
    .{ .name = "see_queen_pruning", .default = tunable_defaults.see_queen_pruning, .min = 10, .max = 2110, .c_end = 84 },
    .{ .name = "see_pawn_ordering", .default = tunable_defaults.see_pawn_ordering, .min = 10, .max = 215, .c_end = 8 },
    .{ .name = "see_knight_ordering", .default = tunable_defaults.see_knight_ordering, .min = 10, .max = 792, .c_end = 31 },
    .{ .name = "see_bishop_ordering", .default = tunable_defaults.see_bishop_ordering, .min = 10, .max = 737, .c_end = 29 },
    .{ .name = "see_rook_ordering", .default = tunable_defaults.see_rook_ordering, .min = 10, .max = 1355, .c_end = 53 },
    .{ .name = "see_queen_ordering", .default = tunable_defaults.see_queen_ordering, .min = 10, .max = 2110, .c_end = 84 },
    .{ .name = "mvv_mult", .default = tunable_defaults.mvv_mult, .min = 1, .max = 2048, .c_end = 128 },
    .{ .name = "material_scaling_base", .default = tunable_defaults.material_scaling_base, .min = 10, .max = 23110, .c_end = 924 },
    .{ .name = "material_scaling_pawn", .default = tunable_defaults.material_scaling_pawn, .min = 0, .max = 200, .c_end = 15 },
    .{ .name = "material_scaling_knight", .default = tunable_defaults.material_scaling_knight, .min = 10, .max = 885, .c_end = 35 },
    .{ .name = "material_scaling_bishop", .default = tunable_defaults.material_scaling_bishop, .min = 10, .max = 1007, .c_end = 39 },
    .{ .name = "material_scaling_rook", .default = tunable_defaults.material_scaling_rook, .min = 10, .max = 1360, .c_end = 54 },
    .{ .name = "material_scaling_queen", .default = tunable_defaults.material_scaling_queen, .min = 10, .max = 2495, .c_end = 99 },
    .{ .name = "multicut_fail_medium", .default = tunable_defaults.multicut_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
    .{ .name = "rfp_fail_medium", .default = tunable_defaults.rfp_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
    .{ .name = "tt_fail_medium", .default = tunable_defaults.tt_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
    .{ .name = "qs_tt_fail_medium", .default = tunable_defaults.qs_tt_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
    .{ .name = "standpat_fail_medium", .default = tunable_defaults.standpat_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
    .{ .name = "nodetm_base", .default = tunable_defaults.nodetm_base, .min = 1024, .c_end = 40 },
    .{ .name = "nodetm_mult", .default = tunable_defaults.nodetm_mult, .min = 10, .c_end = 25 },
    .{ .name = "eval_stab_margin", .default = tunable_defaults.eval_stab_margin, .min = 1, .c_end = 0.5 },
    .{ .name = "eval_stab_base", .default = tunable_defaults.eval_stab_base, .min = 10, .c_end = 30 },
    .{ .name = "eval_stab_offs", .default = tunable_defaults.eval_stab_offs, .min = 10, .c_end = 1 },
    .{ .name = "eval_stab_lim", .default = tunable_defaults.eval_stab_lim, .min = 10, .c_end = 20 },
    .{ .name = "move_stab_base", .default = tunable_defaults.move_stab_base, .min = 10, .c_end = 30 },
    .{ .name = "move_stab_offs", .default = tunable_defaults.move_stab_offs, .min = 10, .c_end = 1 },
    .{ .name = "move_stab_lim", .default = tunable_defaults.move_stab_lim, .min = 10, .c_end = 20 },
    .{ .name = "soft_limit_base", .default = tunable_defaults.soft_limit_base, .min = 10, .c_end = 1 },
    .{ .name = "soft_limit_incr", .default = tunable_defaults.soft_limit_incr, .min = 10, .c_end = 15 },
    .{ .name = "hard_limit_phase_mult", .default = tunable_defaults.hard_limit_phase_mult, .min = 10, .c_end = 3 },
    .{ .name = "hard_limit_base", .default = tunable_defaults.hard_limit_base, .min = 10, .c_end = 5 },
    .{ .name = "singular_beta_mult", .default = tunable_defaults.singular_beta_mult, .min = 10, .max = 992, .c_end = 39 },
    .{ .name = "singular_beta_pv_mult", .default = tunable_defaults.singular_beta_pv_mult, .min = 10, .max = 992, .c_end = 39 },
    .{ .name = "singular_beta_ttpv_mult", .default = tunable_defaults.singular_beta_ttpv_mult, .min = 10, .max = 992, .c_end = 39 },
    .{ .name = "singular_depth_mult", .default = tunable_defaults.singular_depth_mult, .min = 10, .max = 1565, .c_end = 62 },
    .{ .name = "singular_depth_offs", .default = tunable_defaults.singular_depth_offs, .min = 10, .max = 1837, .c_end = 73 },
    .{ .name = "singular_dext_margin_quiet", .default = tunable_defaults.singular_dext_margin_quiet, .min = 0, .max = 50, .c_end = 1 },
    .{ .name = "singular_dext_margin_noisy", .default = tunable_defaults.singular_dext_margin_noisy, .min = 0, .max = 50, .c_end = 1 },
    .{ .name = "singular_dext_pv_margin", .default = tunable_defaults.singular_dext_pv_margin, .min = 0, .max = 50, .c_end = 1 },
    .{ .name = "singular_text_margin_quiet", .default = tunable_defaults.singular_text_margin_quiet, .min = 0, .max = 200, .c_end = 5 },
    .{ .name = "singular_text_margin_noisy", .default = tunable_defaults.singular_text_margin_noisy, .min = 0, .max = 200, .c_end = 5 },
    .{ .name = "singular_text_pv_margin", .default = tunable_defaults.singular_text_pv_margin, .min = 0, .max = 1000, .c_end = 25 },
    .{ .name = "ttpick_depth_weight", .default = tunable_defaults.ttpick_depth_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_age_weight", .default = tunable_defaults.ttpick_age_weight, .min = 0, .max = 8192, .c_end = 256 },
    .{ .name = "ttpick_pv_weight", .default = tunable_defaults.ttpick_pv_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_lower_weight", .default = tunable_defaults.ttpick_lower_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_upper_weight", .default = tunable_defaults.ttpick_upper_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_exact_weight", .default = tunable_defaults.ttpick_exact_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_move_weight", .default = tunable_defaults.ttpick_move_weight, .min = 0, .max = 8192, .c_end = 256 },
};

pub const tunable_constants = if (do_tuning) struct {
    pub var quiet_history_bonus_mult = tunable_defaults.quiet_history_bonus_mult;
    pub var quiet_history_bonus_offs = tunable_defaults.quiet_history_bonus_offs;
    pub var quiet_history_bonus_max = tunable_defaults.quiet_history_bonus_max;
    pub var quiet_history_penalty_mult = tunable_defaults.quiet_history_penalty_mult;
    pub var quiet_history_penalty_offs = tunable_defaults.quiet_history_penalty_offs;
    pub var quiet_history_penalty_max = tunable_defaults.quiet_history_penalty_max;
    pub var pawn_history_bonus_mult = tunable_defaults.pawn_history_bonus_mult;
    pub var pawn_history_bonus_offs = tunable_defaults.pawn_history_bonus_offs;
    pub var pawn_history_bonus_max = tunable_defaults.pawn_history_bonus_max;
    pub var pawn_history_penalty_mult = tunable_defaults.pawn_history_penalty_mult;
    pub var pawn_history_penalty_offs = tunable_defaults.pawn_history_penalty_offs;
    pub var pawn_history_penalty_max = tunable_defaults.pawn_history_penalty_max;
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
    pub var high_eval_offs = tunable_defaults.high_eval_offs;
    pub var faillow_mult = tunable_defaults.faillow_mult;
    pub var quiet_ordering_weight = tunable_defaults.quiet_ordering_weight;
    pub var quiet_pruning_weight = tunable_defaults.quiet_pruning_weight;
    pub var pawn_ordering_weight = tunable_defaults.pawn_ordering_weight;
    pub var pawn_pruning_weight = tunable_defaults.pawn_pruning_weight;
    pub var cont1_ordering_weight = tunable_defaults.cont1_ordering_weight;
    pub var cont1_pruning_weight = tunable_defaults.cont1_pruning_weight;
    pub var cont2_ordering_weight = tunable_defaults.cont2_ordering_weight;
    pub var cont2_pruning_weight = tunable_defaults.cont2_pruning_weight;
    pub var cont4_ordering_weight = tunable_defaults.cont4_ordering_weight;
    pub var cont4_pruning_weight = tunable_defaults.cont4_pruning_weight;
    pub var rfp_min_margin = tunable_defaults.rfp_min_margin;
    pub var rfp_base = tunable_defaults.rfp_base;
    pub var rfp_mult = tunable_defaults.rfp_mult;
    pub var rfp_quad = tunable_defaults.rfp_quad;
    pub var rfp_improving_margin = tunable_defaults.rfp_improving_margin;
    pub var rfp_easy_margin = tunable_defaults.rfp_easy_margin;
    pub var rfp_improving_easy_margin = tunable_defaults.rfp_improving_easy_margin;
    pub var rfp_worsening_margin = tunable_defaults.rfp_worsening_margin;
    pub var rfp_cutnode_margin = tunable_defaults.rfp_cutnode_margin;
    pub var rfp_corrplexity_mult = tunable_defaults.rfp_corrplexity_mult;
    pub var rfp_history_mult = tunable_defaults.rfp_history_mult;
    pub var rfp_noisy_history_mult = tunable_defaults.rfp_noisy_history_mult;
    pub var aspiration_score_mult = tunable_defaults.aspiration_score_mult;
    pub var aspiration_initial = tunable_defaults.aspiration_initial;
    pub var aspiration_multiplier = tunable_defaults.aspiration_multiplier;
    pub var lmr_quiet_base = tunable_defaults.lmr_quiet_base;
    pub var lmr_noisy_base = tunable_defaults.lmr_noisy_base;
    pub var lmr_quiet_depth_mult = tunable_defaults.lmr_quiet_depth_mult;
    pub var lmr_noisy_depth_mult = tunable_defaults.lmr_noisy_depth_mult;
    pub var lmr_quiet_depth_offs = tunable_defaults.lmr_quiet_depth_offs;
    pub var lmr_noisy_depth_offs = tunable_defaults.lmr_noisy_depth_offs;
    pub var lmr_quiet_legal_mult = tunable_defaults.lmr_quiet_legal_mult;
    pub var lmr_noisy_legal_mult = tunable_defaults.lmr_noisy_legal_mult;
    pub var lmr_quiet_legal_offs = tunable_defaults.lmr_quiet_legal_offs;
    pub var lmr_noisy_legal_offs = tunable_defaults.lmr_noisy_legal_offs;
    pub var lmr_quiet_history_mult = tunable_defaults.lmr_quiet_history_mult;
    pub var lmr_noisy_history_mult = tunable_defaults.lmr_noisy_history_mult;
    pub var lmr_corrhist_mult = tunable_defaults.lmr_corrhist_mult;
    pub var lmr_dodeeper_margin = tunable_defaults.lmr_dodeeper_margin;
    pub var lmr_dodeeper_mult = tunable_defaults.lmr_dodeeper_mult;
    pub var lmr_doshallower_margin = tunable_defaults.lmr_doshallower_margin;
    pub var hindsight_ext_margin = tunable_defaults.hindsight_ext_margin;
    pub var nmp_margin_base = tunable_defaults.nmp_margin_base;
    pub var nmp_margin_mult = tunable_defaults.nmp_margin_mult;
    pub var nmp_base = tunable_defaults.nmp_base;
    pub var nmp_mult = tunable_defaults.nmp_mult;
    pub var fp_depth_limit = tunable_defaults.fp_depth_limit;
    pub var fp_pv_base = tunable_defaults.fp_pv_base;
    pub var fp_pv_mult = tunable_defaults.fp_pv_mult;
    pub var fp_base = tunable_defaults.fp_base;
    pub var fp_mult = tunable_defaults.fp_mult;
    pub var fp_hist_mult = tunable_defaults.fp_hist_mult;
    pub var bnfp_depth_limit = tunable_defaults.bnfp_depth_limit;
    pub var bnfp_base = tunable_defaults.bnfp_base;
    pub var bnfp_mult = tunable_defaults.bnfp_mult;
    pub var qs_see_threshold = tunable_defaults.qs_see_threshold;
    pub var see_quiet_pruning_offs = tunable_defaults.see_quiet_pruning_offs;
    pub var see_noisy_pruning_offs = tunable_defaults.see_noisy_pruning_offs;
    pub var see_quiet_pruning_mult = tunable_defaults.see_quiet_pruning_mult;
    pub var see_noisy_pruning_mult = tunable_defaults.see_noisy_pruning_mult;
    pub var see_quiet_pruning_quad = tunable_defaults.see_quiet_pruning_quad;
    pub var see_noisy_pruning_quad = tunable_defaults.see_noisy_pruning_quad;
    pub var see_pv_offs = tunable_defaults.see_pv_offs;
    pub var razoring_offs = tunable_defaults.razoring_offs;
    pub var razoring_mult = tunable_defaults.razoring_mult;
    pub var razoring_quad = tunable_defaults.razoring_quad;
    pub var razoring_easy_capture = tunable_defaults.razoring_easy_capture;
    pub var history_pruning_depth_limit = tunable_defaults.history_pruning_depth_limit;
    pub var history_pruning_offs = tunable_defaults.history_pruning_offs;
    pub var history_pruning_mult = tunable_defaults.history_pruning_mult;
    pub var noisy_history_pruning_depth_limit = tunable_defaults.noisy_history_pruning_depth_limit;
    pub var noisy_history_pruning_offs = tunable_defaults.noisy_history_pruning_offs;
    pub var noisy_history_pruning_mult = tunable_defaults.noisy_history_pruning_mult;
    pub var qs_futility_margin = tunable_defaults.qs_futility_margin;
    pub var qs_hp_margin = tunable_defaults.qs_hp_margin;
    pub var corrhist_pawn_weight = tunable_defaults.corrhist_pawn_weight;
    pub var corrhist_nonpawn_weight = tunable_defaults.corrhist_nonpawn_weight;
    pub var corrhist_countermove_weight = tunable_defaults.corrhist_countermove_weight;
    pub var corrhist_followupmove_weight = tunable_defaults.corrhist_followupmove_weight;
    pub var corrhist_major_weight = tunable_defaults.corrhist_major_weight;
    pub var corrhist_minor_weight = tunable_defaults.corrhist_minor_weight;
    pub var corrhist_pawn_update_weight = tunable_defaults.corrhist_pawn_update_weight;
    pub var corrhist_nonpawn_update_weight = tunable_defaults.corrhist_nonpawn_update_weight;
    pub var corrhist_countermove_update_weight = tunable_defaults.corrhist_countermove_update_weight;
    pub var corrhist_followupmove_update_weight = tunable_defaults.corrhist_followupmove_update_weight;
    pub var corrhist_major_update_weight = tunable_defaults.corrhist_major_update_weight;
    pub var corrhist_minor_update_weight = tunable_defaults.corrhist_minor_update_weight;
    pub var lmp_standard_base = tunable_defaults.lmp_standard_base;
    pub var lmp_improving_base = tunable_defaults.lmp_improving_base;
    pub var lmp_standard_linear_mult = tunable_defaults.lmp_standard_linear_mult;
    pub var lmp_improving_linear_mult = tunable_defaults.lmp_improving_linear_mult;
    pub var lmp_standard_quadratic_mult = tunable_defaults.lmp_standard_quadratic_mult;
    pub var lmp_improving_quadratic_mult = tunable_defaults.lmp_improving_quadratic_mult;
    pub var good_noisy_ordering_base = tunable_defaults.good_noisy_ordering_base;
    pub var good_noisy_ordering_mult = tunable_defaults.good_noisy_ordering_mult;
    pub var see_pawn_pruning = tunable_defaults.see_pawn_pruning;
    pub var see_knight_pruning = tunable_defaults.see_knight_pruning;
    pub var see_bishop_pruning = tunable_defaults.see_bishop_pruning;
    pub var see_rook_pruning = tunable_defaults.see_rook_pruning;
    pub var see_queen_pruning = tunable_defaults.see_queen_pruning;
    pub var see_pawn_ordering = tunable_defaults.see_pawn_ordering;
    pub var see_knight_ordering = tunable_defaults.see_knight_ordering;
    pub var see_bishop_ordering = tunable_defaults.see_bishop_ordering;
    pub var see_rook_ordering = tunable_defaults.see_rook_ordering;
    pub var see_queen_ordering = tunable_defaults.see_queen_ordering;
    pub var mvv_mult = tunable_defaults.mvv_mult;
    pub var material_scaling_base = tunable_defaults.material_scaling_base;
    pub var material_scaling_pawn = tunable_defaults.material_scaling_pawn;
    pub var material_scaling_knight = tunable_defaults.material_scaling_knight;
    pub var material_scaling_bishop = tunable_defaults.material_scaling_bishop;
    pub var material_scaling_rook = tunable_defaults.material_scaling_rook;
    pub var material_scaling_queen = tunable_defaults.material_scaling_queen;
    pub var multicut_fail_medium = tunable_defaults.multicut_fail_medium;
    pub var rfp_fail_medium = tunable_defaults.rfp_fail_medium;
    pub var tt_fail_medium = tunable_defaults.tt_fail_medium;
    pub var qs_tt_fail_medium = tunable_defaults.qs_tt_fail_medium;
    pub var standpat_fail_medium = tunable_defaults.standpat_fail_medium;
    pub var nodetm_base = tunable_defaults.nodetm_base;
    pub var nodetm_mult = tunable_defaults.nodetm_mult;
    pub var eval_stab_margin = tunable_defaults.eval_stab_margin;
    pub var eval_stab_base = tunable_defaults.eval_stab_base;
    pub var eval_stab_offs = tunable_defaults.eval_stab_offs;
    pub var eval_stab_lim = tunable_defaults.eval_stab_lim;
    pub var move_stab_base = tunable_defaults.move_stab_base;
    pub var move_stab_offs = tunable_defaults.move_stab_offs;
    pub var move_stab_lim = tunable_defaults.move_stab_lim;
    pub var soft_limit_base = tunable_defaults.soft_limit_base;
    pub var soft_limit_incr = tunable_defaults.soft_limit_incr;
    pub var hard_limit_phase_mult = tunable_defaults.hard_limit_phase_mult;
    pub var hard_limit_base = tunable_defaults.hard_limit_base;
    pub var singular_beta_mult = tunable_defaults.singular_beta_mult;
    pub var singular_beta_pv_mult = tunable_defaults.singular_beta_pv_mult;
    pub var singular_beta_ttpv_mult = tunable_defaults.singular_beta_ttpv_mult;
    pub var singular_depth_mult = tunable_defaults.singular_depth_mult;
    pub var singular_depth_offs = tunable_defaults.singular_depth_offs;
    pub var singular_dext_margin_quiet = tunable_defaults.singular_dext_margin_quiet;
    pub var singular_dext_margin_noisy = tunable_defaults.singular_dext_margin_noisy;
    pub var singular_dext_pv_margin = tunable_defaults.singular_dext_pv_margin;
    pub var singular_text_margin_quiet = tunable_defaults.singular_text_margin_quiet;
    pub var singular_text_margin_noisy = tunable_defaults.singular_text_margin_noisy;
    pub var singular_text_pv_margin = tunable_defaults.singular_text_pv_margin;
    pub var ttpick_depth_weight = tunable_defaults.ttpick_depth_weight;
    pub var ttpick_age_weight = tunable_defaults.ttpick_age_weight;
    pub var ttpick_pv_weight = tunable_defaults.ttpick_pv_weight;
    pub var ttpick_lower_weight = tunable_defaults.ttpick_lower_weight;
    pub var ttpick_upper_weight = tunable_defaults.ttpick_upper_weight;
    pub var ttpick_exact_weight = tunable_defaults.ttpick_exact_weight;
    pub var ttpick_move_weight = tunable_defaults.ttpick_move_weight;
} else tunable_defaults;

const factorized_lmr_defaults = struct {
    pub const N = 8;
    pub fn biggerTables(comptime amount: usize) void {
        comptime var two_idx_old = 0;
        comptime var three_idx_old = 0;
        comptime var two_idx = 0;
        comptime var three_idx = 0;
        comptime var one_out: []const u8 = "";
        comptime var two_out: []const u8 = "";
        comptime var three_out: []const u8 = "";
        inline for (0..N + amount) |i| {
            inline for (i + 1..N + amount) |j| {
                inline for (j + 1..N + amount) |k| {
                    if (i < N and j < N and k < N) {
                        three_out = three_out ++ std.fmt.comptimePrint("{},\n", .{three[three_idx_old]});
                        three_idx_old += 1;
                    } else {
                        three_out = three_out ++ std.fmt.comptimePrint("0,\n", .{});
                    }
                    three_idx += 1;
                }
                if (i < N and j < N) {
                    two_out = two_out ++ std.fmt.comptimePrint("{},\n", .{two[two_idx_old]});
                    two_idx_old += 1;
                } else {
                    two_out = two_out ++ std.fmt.comptimePrint("0,\n", .{});
                }
                two_idx += 1;
            }
            if (i < N) {
                one_out = one_out ++ std.fmt.comptimePrint("{},\n", .{one[i]});
            } else {
                one_out = one_out ++ std.fmt.comptimePrint("0,\n", .{});
            }
        }
        std.debug.print(
            \\pub const one = [N]i32{{
            \\{s}}};
            \\pub const two: [N * (N - 1) / 2]i32 = .{{
            \\{s}}};
            \\pub const three: [N * (N - 1) * (N - 2) / 6]i32 = .{{
            \\{s}}};
            \\
        , .{ one_out, two_out, three_out });
    }

    pub const one = [N]i16{
        -1079,
        1528,
        -414,
        559,
        -1107,
        40,
        -714,
        773,
    };
    pub const two: [N * (N - 1) / 2]i16 = .{
        -16,
        -33,
        277,
        -149,
        226,
        292,
        50,
        164,
        201,
        -411,
        121,
        -87,
        239,
        -201,
        -60,
        47,
        114,
        375,
        -459,
        303,
        206,
        -383,
        135,
        -396,
        80,
        90,
        -199,
        94,
    };
    pub const three: [N * (N - 1) * (N - 2) / 6]i16 = .{
        208,
        119,
        -540,
        420,
        3,
        -35,
        -259,
        57,
        -20,
        -4,
        167,
        -524,
        100,
        198,
        -145,
        14,
        -79,
        172,
        -13,
        -333,
        -27,
        -121,
        257,
        -38,
        -168,
        127,
        -361,
        153,
        208,
        35,
        92,
        256,
        -230,
        268,
        244,
        54,
        -9,
        -32,
        -27,
        114,
        -40,
        205,
        2,
        -479,
        -19,
        -9,
        -2,
        16,
        -194,
        431,
        -100,
        -342,
        -370,
        148,
        4,
        205,
    };
};

pub const factorized_lmr_params = struct {
    pub const min = -2048;
    pub const max = 2048;
    pub const c_end = 128;
};

pub const factorized_lmr = if (do_tuning) struct {
    pub const N = factorized_lmr_defaults.N;
    pub var one = factorized_lmr_defaults.one;
    pub var two = factorized_lmr_defaults.two;
    pub var three = factorized_lmr_defaults.three;
} else factorized_lmr_defaults;

comptime {
    std.debug.assert(std.meta.declarations(tunable_defaults).len == tunables.len);
    std.debug.assert(std.meta.declarations(tunable_constants).len == tunables.len);
}
