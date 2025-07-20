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
    pub const quiet_history_bonus_mult: i32 = 452;
    pub const quiet_history_bonus_offs: i32 = 435;
    pub const quiet_history_bonus_max: i32 = 2882;
    pub const quiet_history_penalty_mult: i32 = 204;
    pub const quiet_history_penalty_offs: i32 = 324;
    pub const quiet_history_penalty_max: i32 = 1555;
    pub const pawn_history_bonus_mult: i32 = 413;
    pub const pawn_history_bonus_offs: i32 = 397;
    pub const pawn_history_bonus_max: i32 = 2688;
    pub const pawn_history_penalty_mult: i32 = 231;
    pub const pawn_history_penalty_offs: i32 = 340;
    pub const pawn_history_penalty_max: i32 = 1609;
    pub const cont_history_bonus_mult: i32 = 469;
    pub const cont_history_bonus_offs: i32 = 231;
    pub const cont_history_bonus_max: i32 = 3079;
    pub const cont_history_penalty_mult: i32 = 210;
    pub const cont_history_penalty_offs: i32 = 259;
    pub const cont_history_penalty_max: i32 = 1986;
    pub const noisy_history_bonus_mult: i32 = 302;
    pub const noisy_history_bonus_offs: i32 = 360;
    pub const noisy_history_bonus_max: i32 = 2413;
    pub const noisy_history_penalty_mult: i32 = 226;
    pub const noisy_history_penalty_offs: i32 = 196;
    pub const noisy_history_penalty_max: i32 = 2372;
    pub const rfp_base: i32 = 42;
    pub const rfp_mult: i32 = 64;
    pub const rfp_improving_margin: i32 = 69;
    pub const rfp_worsening_margin: i32 = 15;
    pub const rfp_cutnode_margin: i32 = 18;
    pub const rfp_corrplexity_mult: i32 = 18;
    pub const aspiration_score_mult: i32 = 1068;
    pub const aspiration_initial: i32 = 9531;
    pub const aspiration_multiplier: i32 = 1278;
    pub const lmr_quiet_base: i32 = 3417;
    pub const lmr_noisy_base: i32 = 2053;
    pub const lmr_quiet_log_mult: i32 = 215;
    pub const lmr_noisy_log_mult: i32 = 232;
    pub const lmr_quiet_depth_mult: i32 = 808;
    pub const lmr_noisy_depth_mult: i32 = 792;
    pub const lmr_quiet_depth_offs: i32 = -116;
    pub const lmr_noisy_depth_offs: i32 = 153;
    pub const lmr_quiet_legal_mult: i32 = 939;
    pub const lmr_noisy_legal_mult: i32 = 972;
    pub const lmr_quiet_legal_offs: i32 = 51;
    pub const lmr_noisy_legal_offs: i32 = -121;
    pub const lmr_quiet_history_mult: i32 = 596;
    pub const lmr_noisy_history_mult: i32 = 1024;
    pub const lmr_corrhist_mult: i32 = 9221;
    pub const lmr_dodeeper_margin: i32 = 56;
    pub const nmp_base: i32 = 55914;
    pub const nmp_mult: i32 = 997;
    pub const nmp_eval_reduction_scale: i32 = 29;
    pub const nmp_eval_reduction_max: i32 = 29364;
    pub const fp_base: i32 = 304;
    pub const fp_mult: i32 = 79;
    pub const fp_hist_mult: i32 = 105;
    pub const qs_see_threshold: i32 = -80;
    pub const see_quiet_pruning_mult: i32 = -81;
    pub const see_noisy_pruning_mult: i32 = -52;
    pub const razoring_margin: i32 = 218;
    pub const history_pruning_offs: i32 = 655;
    pub const history_pruning_mult: i32 = -2653;
    pub const qs_futility_margin: i32 = 107;
    pub const corrhist_pawn_weight: i32 = 654;
    pub const corrhist_nonpawn_weight: i32 = 740;
    pub const corrhist_countermove_weight: i32 = 956;
    pub const corrhist_major_weight: i32 = 1187;
    pub const corrhist_minor_weight: i32 = 1059;
    pub const lmp_standard_base: i32 = 2505;
    pub const lmp_improving_base: i32 = 3528;
    pub const lmp_standard_linear_mult: i32 = -356;
    pub const lmp_improving_linear_mult: i32 = 229;
    pub const lmp_standard_quadratic_mult: i32 = 502;
    pub const lmp_improving_quadratic_mult: i32 = 1139;
    pub const good_noisy_ordering_base: i32 = 52;
    pub const good_noisy_ordering_mult: i32 = 863;
    pub const see_pawn_pruning: i32 = 78;
    pub const see_knight_pruning: i32 = 272;
    pub const see_bishop_pruning: i32 = 296;
    pub const see_rook_pruning: i32 = 509;
    pub const see_queen_pruning: i32 = 877;
    pub const see_pawn_ordering: i32 = 88;
    pub const see_knight_ordering: i32 = 291;
    pub const see_bishop_ordering: i32 = 279;
    pub const see_rook_ordering: i32 = 542;
    pub const see_queen_ordering: i32 = 869;
    pub const mvv_mult: i32 = 991;
    pub const material_scaling_base: i32 = 10124;
    pub const material_scaling_pawn: i32 = 16;
    pub const material_scaling_knight: i32 = 350;
    pub const material_scaling_bishop: i32 = 393;
    pub const material_scaling_rook: i32 = 392;
    pub const material_scaling_queen: i32 = 862;
    pub const multicut_fail_medium: i32 = 28;
    pub const rfp_fail_medium: i32 = 555;
    pub const tt_fail_medium: i32 = 7;
    pub const qs_tt_fail_medium: i32 = 2;
    pub const standpat_fail_medium: i32 = 24;
    pub const nodetm_base: i32 = 1510;
    pub const nodetm_mult: i32 = 1093;
    pub const eval_stab_margin: i32 = 21;
    pub const eval_stab_base: i32 = 1341;
    pub const eval_stab_offs: i32 = 56;
    pub const move_stab_base: i32 = 1279;
    pub const move_stab_offs: i32 = 45;
    pub const soft_limit_base: i32 = 48;
    pub const soft_limit_incr: i32 = 688;
    pub const hard_limit_phase_mult: i32 = 119;
    pub const hard_limit_base: i32 = 224;
    pub const singular_beta_mult: i32 = 461;
    pub const singular_depth_mult: i32 = 531;
    pub const singular_depth_offs: i32 = 825;
    pub const singular_dext_margin: i32 = 15;
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
    .{ .name = "rfp_base", .default = tunable_defaults.rfp_base, .min = -10, .max = 147, .c_end = 5 },
    .{ .name = "rfp_mult", .default = tunable_defaults.rfp_mult, .min = -10, .max = 145, .c_end = 5 },
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
    .{ .name = "nmp_base", .default = tunable_defaults.nmp_base, .min = -10, .max = 126747, .c_end = 5069 },
    .{ .name = "nmp_mult", .default = tunable_defaults.nmp_mult, .min = -10, .max = 2317, .c_end = 92 },
    .{ .name = "nmp_eval_reduction_scale", .default = tunable_defaults.nmp_eval_reduction_scale, .min = -10, .max = 97, .c_end = 3 },
    .{ .name = "nmp_eval_reduction_max", .default = tunable_defaults.nmp_eval_reduction_max, .min = -10, .max = 62215, .c_end = 2488 },
    .{ .name = "fp_base", .default = tunable_defaults.fp_base, .min = -10, .max = 747, .c_end = 29 },
    .{ .name = "fp_mult", .default = tunable_defaults.fp_mult, .min = -10, .max = 242, .c_end = 9 },
    .{ .name = "fp_hist_mult", .default = tunable_defaults.fp_hist_mult, .min = -10, .max = 512, .c_end = 16 },
    .{ .name = "qs_see_threshold", .default = tunable_defaults.qs_see_threshold, .min = -230, .max = 10, .c_end = 8 },
    .{ .name = "see_quiet_pruning_mult", .default = tunable_defaults.see_quiet_pruning_mult, .min = -185, .max = 10, .c_end = 7 },
    .{ .name = "see_noisy_pruning_mult", .default = tunable_defaults.see_noisy_pruning_mult, .min = -135, .max = 10, .c_end = 5 },
    .{ .name = "razoring_margin", .default = tunable_defaults.razoring_margin, .min = -10, .max = 572, .c_end = 22 },
    .{ .name = "history_pruning_offs", .default = tunable_defaults.history_pruning_offs, .min = -2048, .max = 1024, .c_end = 128 },
    .{ .name = "history_pruning_mult", .default = tunable_defaults.history_pruning_mult, .min = -7382, .max = 9, .c_end = 294 },
    .{ .name = "qs_futility_margin", .default = tunable_defaults.qs_futility_margin, .min = -10, .max = 305, .c_end = 11 },
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
    .{ .name = "multicut_fail_medium", .default = tunable_defaults.multicut_fail_medium, .min = 0, .max = 1024, .c_end = 32 },
    .{ .name = "rfp_fail_medium", .default = tunable_defaults.rfp_fail_medium, .min = 0, .max = 1024, .c_end = 32 },
    .{ .name = "tt_fail_medium", .default = tunable_defaults.tt_fail_medium, .min = 0, .max = 1024, .c_end = 32 },
    .{ .name = "qs_tt_fail_medium", .default = tunable_defaults.qs_tt_fail_medium, .min = 0, .max = 1024, .c_end = 32 },
    .{ .name = "standpat_fail_medium", .default = tunable_defaults.standpat_fail_medium, .min = 0, .max = 1024, .c_end = 32 },
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
    pub var rfp_base = tunable_defaults.rfp_base;
    pub var rfp_mult = tunable_defaults.rfp_mult;
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
    pub var nmp_base = tunable_defaults.nmp_base;
    pub var nmp_mult = tunable_defaults.nmp_mult;
    pub var nmp_eval_reduction_scale = tunable_defaults.nmp_eval_reduction_scale;
    pub var nmp_eval_reduction_max = tunable_defaults.nmp_eval_reduction_max;
    pub var fp_base = tunable_defaults.fp_base;
    pub var fp_mult = tunable_defaults.fp_mult;
    pub var fp_hist_mult = tunable_defaults.fp_hist_mult;
    pub var qs_see_threshold = tunable_defaults.qs_see_threshold;
    pub var see_quiet_pruning_mult = tunable_defaults.see_quiet_pruning_mult;
    pub var see_noisy_pruning_mult = tunable_defaults.see_noisy_pruning_mult;
    pub var razoring_margin = tunable_defaults.razoring_margin;
    pub var history_pruning_offs = tunable_defaults.history_pruning_offs;
    pub var history_pruning_mult = tunable_defaults.history_pruning_mult;
    pub var qs_futility_margin = tunable_defaults.qs_futility_margin;
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
} else tunable_defaults;

const factorized_lmr_defaults = struct {
    const N = 8;
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

    pub const one = [N]i32{
        -1150,
        1247,
        -551,
        691,
        -730,
        193,
        -1023,
        695,
    };
    pub const two: [N * (N - 1) / 2]i32 = .{
        6,
        -40,
        114,
        -130,
        153,
        90,
        51,
        97,
        147,
        -64,
        -112,
        163,
        151,
        -34,
        -18,
        232,
        174,
        0,
        -146,
        -61,
        -75,
        -76,
        134,
        204,
        5,
        55,
        -194,
        15,
    };
    pub const three: [N * (N - 1) * (N - 2) / 6]i32 = .{
        137,
        39,
        -83,
        240,
        133,
        3,
        -193,
        173,
        -57,
        -188,
        111,
        24,
        -136,
        75,
        43,
        -60,
        -34,
        7,
        -84,
        -112,
        -104,
        74,
        111,
        -28,
        -155,
        67,
        -176,
        269,
        234,
        -139,
        -45,
        -140,
        -103,
        72,
        47,
        10,
        -99,
        59,
        -91,
        -62,
        -84,
        -91,
        26,
        76,
        -232,
        31,
        -35,
        -100,
        -106,
        124,
        -159,
        97,
        -237,
        -18,
        -79,
        58,
    };
};

pub const factorized_lmr_params = struct {
    pub const min = -2048;
    pub const max = 2048;
    pub const c_end = 128;
};

pub const factorized_lmr = if (do_tuning) struct {
    pub var one = factorized_lmr_defaults.one;
    pub var two = factorized_lmr_defaults.two;
    pub var three = factorized_lmr_defaults.three;
} else factorized_lmr_defaults;

comptime {
    std.debug.assert(std.meta.declarations(tunable_defaults).len == tunables.len);
    std.debug.assert(std.meta.declarations(tunable_constants).len == tunables.len);
}
