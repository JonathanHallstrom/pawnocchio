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
    pub const quiet_history_bonus_mult: i32 = 471;
    pub const quiet_history_bonus_offs: i32 = 441;
    pub const quiet_history_bonus_max: i32 = 3509;
    pub const quiet_history_penalty_mult: i32 = 207;
    pub const quiet_history_penalty_offs: i32 = 340;
    pub const quiet_history_penalty_max: i32 = 1187;
    pub const pawn_history_bonus_mult: i32 = 453;
    pub const pawn_history_bonus_offs: i32 = 423;
    pub const pawn_history_bonus_max: i32 = 2491;
    pub const pawn_history_penalty_mult: i32 = 264;
    pub const pawn_history_penalty_offs: i32 = 326;
    pub const pawn_history_penalty_max: i32 = 1408;
    pub const cont_history_bonus_mult: i32 = 242;
    pub const cont_history_bonus_offs: i32 = 210;
    pub const cont_history_bonus_max: i32 = 3426;
    pub const cont_history_penalty_mult: i32 = 184;
    pub const cont_history_penalty_offs: i32 = 283;
    pub const cont_history_penalty_max: i32 = 1375;
    pub const noisy_history_bonus_mult: i32 = 270;
    pub const noisy_history_bonus_offs: i32 = 335;
    pub const noisy_history_bonus_max: i32 = 3285;
    pub const noisy_history_penalty_mult: i32 = 224;
    pub const noisy_history_penalty_offs: i32 = 219;
    pub const noisy_history_penalty_max: i32 = 2445;
    pub const high_eval_offs: i32 = 50;
    pub const quiet_ordering_weight: i32 = 1217;
    pub const quiet_pruning_weight: i32 = 899;
    pub const pawn_ordering_weight: i32 = 964;
    pub const pawn_pruning_weight: i32 = 538;
    pub const cont1_ordering_weight: i32 = 1170;
    pub const cont1_pruning_weight: i32 = 885;
    pub const cont2_ordering_weight: i32 = 949;
    pub const cont2_pruning_weight: i32 = 989;
    pub const cont4_ordering_weight: i32 = 868;
    pub const cont4_pruning_weight: i32 = 83;
    pub const noisy_ordering_weight: i32 = 1175;
    pub const noisy_pruning_weight: i32 = 1177;
    pub const rfp_base: i32 = 51;
    pub const rfp_mult: i32 = 39;
    pub const rfp_quad: i32 = 6;
    pub const rfp_improving_margin: i32 = 83;
    pub const rfp_worsening_margin: i32 = 15;
    pub const rfp_cutnode_margin: i32 = 19;
    pub const rfp_corrplexity_mult: i32 = 18;
    pub const aspiration_score_mult: i32 = 1115;
    pub const aspiration_initial: i32 = 10190;
    pub const aspiration_multiplier: i32 = 1144;
    pub const lmr_quiet_base: i32 = 3680;
    pub const lmr_noisy_base: i32 = 2156;
    pub const lmr_quiet_log_mult: i32 = 178;
    pub const lmr_noisy_log_mult: i32 = 222;
    pub const lmr_quiet_depth_mult: i32 = 924;
    pub const lmr_noisy_depth_mult: i32 = 729;
    pub const lmr_quiet_depth_offs: i32 = -108;
    pub const lmr_noisy_depth_offs: i32 = 213;
    pub const lmr_quiet_legal_mult: i32 = 1160;
    pub const lmr_noisy_legal_mult: i32 = 1113;
    pub const lmr_quiet_legal_offs: i32 = -19;
    pub const lmr_noisy_legal_offs: i32 = -137;
    pub const lmr_quiet_history_mult: i32 = 632;
    pub const lmr_noisy_history_mult: i32 = 896;
    pub const lmr_corrhist_mult: i32 = 6808;
    pub const lmr_dodeeper_margin: i32 = 56;
    pub const lmr_dodeeper_mult: i32 = 2;
    pub const nmp_margin_base: i32 = 250;
    pub const nmp_margin_mult: i32 = 25;
    pub const nmp_base: i32 = 56078;
    pub const nmp_mult: i32 = 1093;
    pub const nmp_eval_reduction_scale: i32 = 24;
    pub const nmp_eval_reduction_max: i32 = 30376;
    pub const nmp_history_mult: i32 = 512;
    pub const fp_depth_limit: i32 = 6144;
    pub const fp_base: i32 = 311;
    pub const fp_mult: i32 = 80;
    pub const fp_hist_mult: i32 = 125;
    pub const qs_see_threshold: i32 = -74;
    pub const see_quiet_pruning_mult: i32 = -79;
    pub const see_noisy_pruning_mult: i32 = -43;
    pub const razoring_mult: i32 = 209;
    pub const razoring_offs: i32 = 51;
    pub const razoring_easy_capture: i32 = 98;
    pub const history_pruning_depth_limit: i32 = 4095;
    pub const history_pruning_offs: i32 = 792;
    pub const history_pruning_mult: i32 = -2912;
    pub const qs_futility_margin: i32 = 134;
    pub const qs_hp_margin: i32 = -3627;
    pub const corrhist_pawn_weight: i32 = 761;
    pub const corrhist_nonpawn_weight: i32 = 879;
    pub const corrhist_countermove_weight: i32 = 765;
    pub const corrhist_major_weight: i32 = 957;
    pub const corrhist_minor_weight: i32 = 963;
    pub const lmp_standard_base: i32 = 3082;
    pub const lmp_improving_base: i32 = 3246;
    pub const lmp_standard_linear_mult: i32 = -38;
    pub const lmp_improving_linear_mult: i32 = 380;
    pub const lmp_standard_quadratic_mult: i32 = 220;
    pub const lmp_improving_quadratic_mult: i32 = 1205;
    pub const good_noisy_ordering_base: i32 = -14;
    pub const good_noisy_ordering_mult: i32 = 840;
    pub const see_pawn_pruning: i32 = 86;
    pub const see_knight_pruning: i32 = 231;
    pub const see_bishop_pruning: i32 = 313;
    pub const see_rook_pruning: i32 = 502;
    pub const see_queen_pruning: i32 = 965;
    pub const see_pawn_ordering: i32 = 93;
    pub const see_knight_ordering: i32 = 280;
    pub const see_bishop_ordering: i32 = 292;
    pub const see_rook_ordering: i32 = 640;
    pub const see_queen_ordering: i32 = 818;
    pub const mvv_mult: i32 = 588;
    pub const material_scaling_base: i32 = 9290;
    pub const material_scaling_pawn: i32 = 70;
    pub const material_scaling_knight: i32 = 366;
    pub const material_scaling_bishop: i32 = 421;
    pub const material_scaling_rook: i32 = 325;
    pub const material_scaling_queen: i32 = 871;
    pub const multicut_fail_medium: i32 = 113;
    pub const rfp_fail_medium: i32 = 503;
    pub const tt_fail_medium: i32 = 12;
    pub const qs_tt_fail_medium: i32 = 171;
    pub const standpat_fail_medium: i32 = 222;
    pub const nodetm_base: i32 = 1438;
    pub const nodetm_mult: i32 = 1194;
    pub const eval_stab_margin: i32 = 22;
    pub const eval_stab_base: i32 = 1349;
    pub const eval_stab_offs: i32 = 55;
    pub const move_stab_base: i32 = 1329;
    pub const move_stab_offs: i32 = 46;
    pub const soft_limit_base: i32 = 51;
    pub const soft_limit_incr: i32 = 782;
    pub const hard_limit_phase_mult: i32 = 108;
    pub const hard_limit_base: i32 = 234;
    pub const singular_beta_mult: i32 = 450;
    pub const singular_depth_mult: i32 = 591;
    pub const singular_depth_offs: i32 = 822;
    pub const singular_dext_margin: i32 = 15;
    pub const singular_dext_pv_margin: i32 = 22;
    pub const singular_text_margin: i32 = 81;
    pub const ttpick_depth_weight: i32 = 981;
    pub const ttpick_age_weight: i32 = 4180;
    pub const ttpick_pv_weight: i32 = 208;
    pub const ttpick_lower_weight: i32 = 286;
    pub const ttpick_upper_weight: i32 = 176;
    pub const ttpick_exact_weight: i32 = 7;
    pub const ttpick_move_weight: i32 = 41;
};

pub const tunables = [_]Tunable{
    .{ .name = "quiet_history_bonus_mult", .default = tunable_defaults.quiet_history_bonus_mult, .min = -10, .max = 1212, .c_end = 48 },
    .{ .name = "quiet_history_bonus_offs", .default = tunable_defaults.quiet_history_bonus_offs, .min = -10, .max = 960, .c_end = 38 },
    .{ .name = "quiet_history_bonus_max", .default = tunable_defaults.quiet_history_bonus_max, .min = -10, .max = 6650, .c_end = 265 },
    .{ .name = "quiet_history_penalty_mult", .default = tunable_defaults.quiet_history_penalty_mult, .min = -10, .max = 567, .c_end = 22 },
    .{ .name = "quiet_history_penalty_offs", .default = tunable_defaults.quiet_history_penalty_offs, .min = -10, .max = 822, .c_end = 32 },
    .{ .name = "quiet_history_penalty_max", .default = tunable_defaults.quiet_history_penalty_max, .min = -10, .max = 4145, .c_end = 165 },
    .{ .name = "pawn_history_bonus_mult", .default = tunable_defaults.pawn_history_bonus_mult, .min = -10, .max = 1212, .c_end = 48 },
    .{ .name = "pawn_history_bonus_offs", .default = tunable_defaults.pawn_history_bonus_offs, .min = -10, .max = 960, .c_end = 38 },
    .{ .name = "pawn_history_bonus_max", .default = tunable_defaults.pawn_history_bonus_max, .min = -10, .max = 6650, .c_end = 265 },
    .{ .name = "pawn_history_penalty_mult", .default = tunable_defaults.pawn_history_penalty_mult, .min = -10, .max = 567, .c_end = 22 },
    .{ .name = "pawn_history_penalty_offs", .default = tunable_defaults.pawn_history_penalty_offs, .min = -10, .max = 822, .c_end = 32 },
    .{ .name = "pawn_history_penalty_max", .default = tunable_defaults.pawn_history_penalty_max, .min = -10, .max = 4145, .c_end = 165 },
    .{ .name = "cont_history_bonus_mult", .default = tunable_defaults.cont_history_bonus_mult, .min = -10, .max = 1385, .c_end = 55 },
    .{ .name = "cont_history_bonus_offs", .default = tunable_defaults.cont_history_bonus_offs, .min = -10, .max = 800, .c_end = 31 },
    .{ .name = "cont_history_bonus_max", .default = tunable_defaults.cont_history_bonus_max, .min = -10, .max = 6430, .c_end = 256 },
    .{ .name = "cont_history_penalty_mult", .default = tunable_defaults.cont_history_penalty_mult, .min = -10, .max = 472, .c_end = 18 },
    .{ .name = "cont_history_penalty_offs", .default = tunable_defaults.cont_history_penalty_offs, .min = -10, .max = 650, .c_end = 25 },
    .{ .name = "cont_history_penalty_max", .default = tunable_defaults.cont_history_penalty_max, .min = -10, .max = 4610, .c_end = 184 },
    .{ .name = "noisy_history_bonus_mult", .default = tunable_defaults.noisy_history_bonus_mult, .min = -10, .max = 775, .c_end = 30 },
    .{ .name = "noisy_history_bonus_offs", .default = tunable_defaults.noisy_history_bonus_offs, .min = -10, .max = 1005, .c_end = 39 },
    .{ .name = "noisy_history_bonus_max", .default = tunable_defaults.noisy_history_bonus_max, .min = -10, .max = 6015, .c_end = 240 },
    .{ .name = "noisy_history_penalty_mult", .default = tunable_defaults.noisy_history_penalty_mult, .min = -10, .max = 530, .c_end = 20 },
    .{ .name = "noisy_history_penalty_offs", .default = tunable_defaults.noisy_history_penalty_offs, .min = -10, .max = 435, .c_end = 17 },
    .{ .name = "noisy_history_penalty_max", .default = tunable_defaults.noisy_history_penalty_max, .min = -10, .max = 4965, .c_end = 198 },
    .{ .name = "high_eval_offs", .default = tunable_defaults.high_eval_offs },
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
    .{ .name = "noisy_ordering_weight", .default = tunable_defaults.noisy_ordering_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "noisy_pruning_weight", .default = tunable_defaults.noisy_pruning_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "rfp_base", .default = tunable_defaults.rfp_base, .min = -10, .max = 100, .c_end = 5 },
    .{ .name = "rfp_mult", .default = tunable_defaults.rfp_mult, .min = -10, .max = 100 },
    .{ .name = "rfp_quad", .default = tunable_defaults.rfp_quad, .min = -10, .max = 30 },
    .{ .name = "rfp_improving_margin", .default = tunable_defaults.rfp_improving_margin, .min = -10, .max = 195, .c_end = 7 },
    .{ .name = "rfp_worsening_margin", .default = tunable_defaults.rfp_worsening_margin, .min = -10, .max = 45, .c_end = 1 },
    .{ .name = "rfp_cutnode_margin", .default = tunable_defaults.rfp_cutnode_margin, .min = -10, .max = 55, .c_end = 1 },
    .{ .name = "rfp_corrplexity_mult", .default = tunable_defaults.rfp_corrplexity_mult, .min = -10, .max = 60, .c_end = 2 },
    .{ .name = "aspiration_score_mult", .default = tunable_defaults.aspiration_score_mult, .min = 10, .max = 4096, .c_end = 32 },
    .{ .name = "aspiration_initial", .default = tunable_defaults.aspiration_initial, .min = 10, .max = 39450, .c_end = 1577 },
    .{ .name = "aspiration_multiplier", .default = tunable_defaults.aspiration_multiplier, .min = 1127, .max = 4015, .c_end = 160 },
    .{ .name = "lmr_quiet_base", .default = tunable_defaults.lmr_quiet_base, .min = -10, .max = 6772, .c_end = 270 },
    .{ .name = "lmr_noisy_base", .default = tunable_defaults.lmr_noisy_base, .min = -10, .max = 4412, .c_end = 176 },
    .{ .name = "lmr_quiet_log_mult", .default = tunable_defaults.lmr_quiet_log_mult, .min = -10, .max = 510, .c_end = 20 },
    .{ .name = "lmr_noisy_log_mult", .default = tunable_defaults.lmr_noisy_log_mult, .min = -10, .max = 547, .c_end = 21 },
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
    .{ .name = "nmp_margin_base", .default = tunable_defaults.nmp_margin_base, .min = -500, .max = 500, .c_end = 20 },
    .{ .name = "nmp_margin_mult", .default = tunable_defaults.nmp_margin_mult, .min = -100, .max = 100, .c_end = 5 },
    .{ .name = "nmp_base", .default = tunable_defaults.nmp_base, .min = -10, .max = 126747, .c_end = 5069 },
    .{ .name = "nmp_mult", .default = tunable_defaults.nmp_mult, .min = -10, .max = 2317, .c_end = 92 },
    .{ .name = "nmp_eval_reduction_scale", .default = tunable_defaults.nmp_eval_reduction_scale, .min = -10, .max = 97, .c_end = 3 },
    .{ .name = "nmp_eval_reduction_max", .default = tunable_defaults.nmp_eval_reduction_max, .min = -10, .max = 62215, .c_end = 2488 },
    .{ .name = "nmp_history_mult", .default = tunable_defaults.nmp_history_mult, .min = 0, .max = 1536, .c_end = 51 },
    .{ .name = "fp_depth_limit", .default = tunable_defaults.fp_depth_limit },
    .{ .name = "fp_base", .default = tunable_defaults.fp_base, .min = -10, .max = 747, .c_end = 29 },
    .{ .name = "fp_mult", .default = tunable_defaults.fp_mult, .min = -10, .max = 242, .c_end = 9 },
    .{ .name = "fp_hist_mult", .default = tunable_defaults.fp_hist_mult, .min = -10, .max = 512, .c_end = 16 },
    .{ .name = "qs_see_threshold", .default = tunable_defaults.qs_see_threshold, .min = -230, .max = 10, .c_end = 8 },
    .{ .name = "see_quiet_pruning_mult", .default = tunable_defaults.see_quiet_pruning_mult, .min = -185, .max = 10, .c_end = 7 },
    .{ .name = "see_noisy_pruning_mult", .default = tunable_defaults.see_noisy_pruning_mult, .min = -135, .max = 10, .c_end = 5 },
    .{ .name = "razoring_mult", .default = tunable_defaults.razoring_mult, .min = -10, .max = 572, .c_end = 22 },
    .{ .name = "razoring_offs", .default = tunable_defaults.razoring_offs, .min = -1024, .max = 1024, .c_end = 10 },
    .{ .name = "razoring_easy_capture", .default = tunable_defaults.razoring_easy_capture, .min = -1024, .max = 1024, .c_end = 10 },
    .{ .name = "history_pruning_depth_limit", .default = tunable_defaults.history_pruning_depth_limit },
    .{ .name = "history_pruning_offs", .default = tunable_defaults.history_pruning_offs, .min = -2048, .max = 1024, .c_end = 128 },
    .{ .name = "history_pruning_mult", .default = tunable_defaults.history_pruning_mult, .min = -7382, .max = 9, .c_end = 294 },
    .{ .name = "qs_futility_margin", .default = tunable_defaults.qs_futility_margin, .min = -10, .max = 305, .c_end = 11 },
    .{ .name = "qs_hp_margin", .default = tunable_defaults.qs_hp_margin, .min = -6000, .max = 0, .c_end = 400 },
    .{ .name = "corrhist_pawn_weight", .default = tunable_defaults.corrhist_pawn_weight, .min = -10, .max = 1825, .c_end = 72 },
    .{ .name = "corrhist_nonpawn_weight", .default = tunable_defaults.corrhist_nonpawn_weight, .min = -10, .max = 1500, .c_end = 59 },
    .{ .name = "corrhist_countermove_weight", .default = tunable_defaults.corrhist_countermove_weight, .min = -10, .max = 2875, .c_end = 114 },
    .{ .name = "corrhist_major_weight", .default = tunable_defaults.corrhist_major_weight, .min = -10, .max = 2952, .c_end = 117 },
    .{ .name = "corrhist_minor_weight", .default = tunable_defaults.corrhist_minor_weight, .min = -10, .max = 2315, .c_end = 92 },
    .{ .name = "lmp_standard_base", .default = tunable_defaults.lmp_standard_base, .min = 10, .max = 9345, .c_end = 200 },
    .{ .name = "lmp_improving_base", .default = tunable_defaults.lmp_improving_base, .min = 10, .max = 7580, .c_end = 200 },
    .{ .name = "lmp_standard_linear_mult", .default = tunable_defaults.lmp_standard_linear_mult, .min = -1024, .max = 1024, .c_end = 100 },
    .{ .name = "lmp_improving_linear_mult", .default = tunable_defaults.lmp_improving_linear_mult, .min = -1024, .max = 1024, .c_end = 100 },
    .{ .name = "lmp_standard_quadratic_mult", .default = tunable_defaults.lmp_standard_quadratic_mult, .min = -10, .max = 2177, .c_end = 100 },
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
    .{ .name = "nodetm_base", .default = tunable_defaults.nodetm_base, .min = 1024, .c_end = 80 },
    .{ .name = "nodetm_mult", .default = tunable_defaults.nodetm_mult, .min = 10, .c_end = 50 },
    .{ .name = "eval_stab_margin", .default = tunable_defaults.eval_stab_margin, .min = 1, .c_end = 1 },
    .{ .name = "eval_stab_base", .default = tunable_defaults.eval_stab_base, .min = 10, .c_end = 60 },
    .{ .name = "eval_stab_offs", .default = tunable_defaults.eval_stab_offs, .min = 10, .c_end = 2 },
    .{ .name = "move_stab_base", .default = tunable_defaults.move_stab_base, .min = 10, .c_end = 60 },
    .{ .name = "move_stab_offs", .default = tunable_defaults.move_stab_offs, .min = 10, .c_end = 2 },
    .{ .name = "soft_limit_base", .default = tunable_defaults.soft_limit_base, .min = 10, .c_end = 2 },
    .{ .name = "soft_limit_incr", .default = tunable_defaults.soft_limit_incr, .min = 10, .c_end = 30 },
    .{ .name = "hard_limit_phase_mult", .default = tunable_defaults.hard_limit_phase_mult, .min = 10, .c_end = 6 },
    .{ .name = "hard_limit_base", .default = tunable_defaults.hard_limit_base, .min = 10, .c_end = 10 },
    .{ .name = "singular_beta_mult", .default = tunable_defaults.singular_beta_mult, .min = 10, .max = 992, .c_end = 39 },
    .{ .name = "singular_depth_mult", .default = tunable_defaults.singular_depth_mult, .min = 10, .max = 1565, .c_end = 62 },
    .{ .name = "singular_depth_offs", .default = tunable_defaults.singular_depth_offs, .min = 10, .max = 1837, .c_end = 73 },
    .{ .name = "singular_dext_margin", .default = tunable_defaults.singular_dext_margin, .min = 0, .max = 50, .c_end = 1 },
    .{ .name = "singular_dext_pv_margin", .default = tunable_defaults.singular_dext_pv_margin, .min = 0, .max = 50, .c_end = 1 },
    .{ .name = "singular_text_margin", .default = tunable_defaults.singular_text_margin, .min = 0, .max = 200, .c_end = 5 },
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
    pub var noisy_ordering_weight = tunable_defaults.noisy_ordering_weight;
    pub var noisy_pruning_weight = tunable_defaults.noisy_pruning_weight;
    pub var rfp_base = tunable_defaults.rfp_base;
    pub var rfp_mult = tunable_defaults.rfp_mult;
    pub var rfp_quad = tunable_defaults.rfp_quad;
    pub var rfp_improving_margin = tunable_defaults.rfp_improving_margin;
    pub var rfp_worsening_margin = tunable_defaults.rfp_worsening_margin;
    pub var rfp_cutnode_margin = tunable_defaults.rfp_cutnode_margin;
    pub var rfp_corrplexity_mult = tunable_defaults.rfp_corrplexity_mult;
    pub var aspiration_score_mult = tunable_defaults.aspiration_score_mult;
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
    pub var lmr_quiet_history_mult = tunable_defaults.lmr_quiet_history_mult;
    pub var lmr_noisy_history_mult = tunable_defaults.lmr_noisy_history_mult;
    pub var lmr_corrhist_mult = tunable_defaults.lmr_corrhist_mult;
    pub var lmr_dodeeper_margin = tunable_defaults.lmr_dodeeper_margin;
    pub var lmr_dodeeper_mult = tunable_defaults.lmr_dodeeper_mult;
    pub var nmp_margin_base = tunable_defaults.nmp_margin_base;
    pub var nmp_margin_mult = tunable_defaults.nmp_margin_mult;
    pub var nmp_base = tunable_defaults.nmp_base;
    pub var nmp_mult = tunable_defaults.nmp_mult;
    pub var nmp_eval_reduction_scale = tunable_defaults.nmp_eval_reduction_scale;
    pub var nmp_eval_reduction_max = tunable_defaults.nmp_eval_reduction_max;
    pub var nmp_history_mult = tunable_defaults.nmp_history_mult;
    pub var fp_depth_limit = tunable_defaults.fp_depth_limit;
    pub var fp_base = tunable_defaults.fp_base;
    pub var fp_mult = tunable_defaults.fp_mult;
    pub var fp_hist_mult = tunable_defaults.fp_hist_mult;
    pub var qs_see_threshold = tunable_defaults.qs_see_threshold;
    pub var see_quiet_pruning_mult = tunable_defaults.see_quiet_pruning_mult;
    pub var see_noisy_pruning_mult = tunable_defaults.see_noisy_pruning_mult;
    pub var razoring_mult = tunable_defaults.razoring_mult;
    pub var razoring_offs = tunable_defaults.razoring_offs;
    pub var razoring_easy_capture = tunable_defaults.razoring_easy_capture;
    pub var history_pruning_depth_limit = tunable_defaults.history_pruning_depth_limit;
    pub var history_pruning_offs = tunable_defaults.history_pruning_offs;
    pub var history_pruning_mult = tunable_defaults.history_pruning_mult;
    pub var qs_futility_margin = tunable_defaults.qs_futility_margin;
    pub var qs_hp_margin = tunable_defaults.qs_hp_margin;
    pub var corrhist_pawn_weight = tunable_defaults.corrhist_pawn_weight;
    pub var corrhist_nonpawn_weight = tunable_defaults.corrhist_nonpawn_weight;
    pub var corrhist_countermove_weight = tunable_defaults.corrhist_countermove_weight;
    pub var corrhist_major_weight = tunable_defaults.corrhist_major_weight;
    pub var corrhist_minor_weight = tunable_defaults.corrhist_minor_weight;
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
    pub var singular_dext_pv_margin = tunable_defaults.singular_dext_pv_margin;
    pub var singular_text_margin = tunable_defaults.singular_text_margin;
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
        -1173,
        1439,
        -545,
        593,
        -1028,
        -48,
        -618,
        846,
    };
    pub const two: [N * (N - 1) / 2]i16 = .{
        -55,
        -150,
        68,
        -123,
        221,
        243,
        6,
        52,
        155,
        -129,
        -26,
        -104,
        131,
        -62,
        -153,
        32,
        143,
        204,
        -429,
        228,
        209,
        -233,
        61,
        -183,
        112,
        174,
        -137,
        20,
    };
    pub const three: [N * (N - 1) * (N - 2) / 6]i16 = .{
        249,
        168,
        -441,
        342,
        12,
        -101,
        -256,
        211,
        -69,
        -17,
        16,
        -378,
        66,
        289,
        -100,
        107,
        -30,
        181,
        -81,
        -297,
        -67,
        28,
        220,
        29,
        -132,
        69,
        -200,
        277,
        173,
        -144,
        -8,
        321,
        -76,
        178,
        172,
        -74,
        -59,
        -3,
        -93,
        20,
        -32,
        382,
        -70,
        -384,
        -51,
        88,
        2,
        -130,
        -339,
        408,
        -82,
        -259,
        -268,
        1,
        94,
        227,
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

pub const see_psqts: [6][64]i16 = .{
    .{
        0,   0,   0,   0,   0,   0,   0,    0,
        120, 112, 58,  170, 45,  144, -102, 65,
        39,  5,   -17, 7,   -44, 32,  93,   33,
        -27, 28,  -17, -10, -8,  56,  -35,  -49,
        -15, -9,  -25, 24,  21,  17,  8,    -11,
        -63, 7,   -12, -13, 9,   4,   -11,  34,
        -13, 9,   41,  29,  -10, 39,  135,  57,
        0,   0,   0,   0,   0,   0,   0,    0,
    },
    .{
        -196, -109, -14,  -14, 34,  -177, 53,  -202,
        -119, 41,   32,   42,  -8,  61,   -23, -20,
        -64,  87,   120,  117, 108, 49,   126, 70,
        -26,  -15,  64,   44,  3,   8,    55,  22,
        -60,  19,   -5,   45,  -29, 18,   -9,  49,
        8,    10,   68,   -58, -7,  89,   13,  29,
        80,   -6,   -41,  30,  26,  63,   -81, -12,
        -177, -28,  -104, -37, 109, -4,   -38, -1,
    },
    .{
        32,   43, -77, -45, 10,  -66, 144, -8,
        18,   41, 62,  -12, -39, 118, 18,  -46,
        -35,  23, 82,  -8,  47,  17,  24,  -17,
        -70,  -1, 41,  91,  15,  35,  -14, 63,
        -7,   19, 44,  120, -42, 26,  73,  86,
        -118, 19, 51,  -46, 70,  -6,  -34, 115,
        -74,  90, 67,  5,   20,  56,  114, -55,
        -64,  21, -26, 92,  -5,  39,  -18, -7,
    },
    .{
        40,  -16,  8,   22,  81,  -76, 1,   -13,
        25,  -10,  -82, 74,  100, 190, 16,  88,
        70,  27,   -8,  138, -18, 5,   130, 101,
        -96, 9,    62,  9,   -18, 114, 28,  66,
        -49, -41,  -60, -41, 50,  15,  -18, -24,
        -53, 28,   32,  -15, -86, -22, -72, 17,
        -30, -117, 51,  -17, 12,  55,  32,  -104,
        4,   -86,  -62, -39, 7,   46,  -89, -43,
    },
    .{
        6,    -47,  53,  -20, 53,   78,  92,   112,
        -79,  13,   41,  33,  20,   41,  46,   37,
        -202, -98,  -21, 18,  103,  79,  66,   179,
        -46,  -91,  1,   -48, -32,  10,  114,  -33,
        -14,  -82,  -56, 11,  33,   -10, 44,   -93,
        -91,  -108, -47, -37, -111, 52,  -10,  92,
        -28,  -23,  -31, -39, -6,   17,  -158, 120,
        -54,  -4,   -37, -60, 94,   83,  117,  82,
    },
    .{
        -52,  112, -36, 38,  -37, 14,   -12, 0,
        62,   -27, -58, -23, 17,  142,  -13, -61,
        -2,   -38, 59,  17,  118, -99,  44,  77,
        -82,  7,   -37, 47,  -93, 76,   -32, 31,
        97,   -10, -1,  -52, -39, 47,   -7,  -46,
        -25,  -45, -60, 34,  11,  63,   17,  54,
        65,   -13, -57, -60, -31, -153, 62,  -126,
        -137, 82,  97,  9,   -68, -38,  51,  13,
    },
};

comptime {
    std.debug.assert(std.meta.declarations(tunable_defaults).len == tunables.len);
    std.debug.assert(std.meta.declarations(tunable_constants).len == tunables.len);
}
