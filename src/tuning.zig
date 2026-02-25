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
pub const do_factorized_tuning = false;

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

inline fn histQ(
    terms: anytype,
    quiet: i32,
    pawn: i32,
    cont1: i32,
    cont2: i32,
    cont4: i32,
) i32 {
    return @divTrunc(
        terms.quiet * quiet +
            terms.pawn * pawn +
            terms.cont1 * cont1 +
            terms.cont2 * cont2 +
            terms.cont4 * cont4,
        1024,
    );
}

inline fn histN(terms: anytype, noisy: i32) i32 {
    return @divTrunc(terms.noisy * noisy, 1024);
}

pub inline fn rfpHistQ(terms: anytype) i32 {
    return histQ(
        terms,
        tunable_constants.rfp_hist_quiet_weight,
        tunable_constants.rfp_hist_pawn_weight,
        tunable_constants.rfp_hist_cont1_weight,
        tunable_constants.rfp_hist_cont2_weight,
        tunable_constants.rfp_hist_cont4_weight,
    );
}

pub inline fn rfpHistN(terms: anytype) i32 {
    return histN(terms, tunable_constants.rfp_hist_noisy_weight);
}

pub inline fn lmrDepthHistQ(terms: anytype) i32 {
    return histQ(
        terms,
        tunable_constants.lmr_depth_hist_quiet_weight,
        tunable_constants.lmr_depth_hist_pawn_weight,
        tunable_constants.lmr_depth_hist_cont1_weight,
        tunable_constants.lmr_depth_hist_cont2_weight,
        tunable_constants.lmr_depth_hist_cont4_weight,
    );
}

pub inline fn lmrDepthHistN(terms: anytype) i32 {
    return histN(terms, tunable_constants.lmr_depth_hist_noisy_weight);
}

pub inline fn lmrHistQ(terms: anytype) i32 {
    return histQ(
        terms,
        tunable_constants.lmr_hist_quiet_weight,
        tunable_constants.lmr_hist_pawn_weight,
        tunable_constants.lmr_hist_cont1_weight,
        tunable_constants.lmr_hist_cont2_weight,
        tunable_constants.lmr_hist_cont4_weight,
    );
}

pub inline fn lmrHistN(terms: anytype) i32 {
    return histN(terms, tunable_constants.lmr_hist_noisy_weight);
}

pub inline fn hpHistQ(terms: anytype) i32 {
    return histQ(
        terms,
        tunable_constants.hp_hist_quiet_weight,
        tunable_constants.hp_hist_pawn_weight,
        tunable_constants.hp_hist_cont1_weight,
        tunable_constants.hp_hist_cont2_weight,
        tunable_constants.hp_hist_cont4_weight,
    );
}

pub inline fn hpHistN(terms: anytype) i32 {
    return histN(terms, tunable_constants.hp_hist_noisy_weight);
}

pub inline fn fpHistQ(terms: anytype) i32 {
    return histQ(
        terms,
        tunable_constants.fp_hist_quiet_weight,
        tunable_constants.fp_hist_pawn_weight,
        tunable_constants.fp_hist_cont1_weight,
        tunable_constants.fp_hist_cont2_weight,
        tunable_constants.fp_hist_cont4_weight,
    );
}

pub inline fn ordHistQ(terms: anytype) i32 {
    return histQ(
        terms,
        tunable_constants.quiet_ordering_weight,
        tunable_constants.pawn_ordering_weight,
        tunable_constants.cont1_ordering_weight,
        tunable_constants.cont2_ordering_weight,
        tunable_constants.cont4_ordering_weight,
    );
}

const tunable_defaults = struct {
    pub const quiet_history_bonus_mult: i32 = 434;
    pub const quiet_history_bonus_offs: i32 = 489;
    pub const quiet_history_bonus_max: i32 = 3922;
    pub const quiet_history_penalty_mult: i32 = 249;
    pub const quiet_history_penalty_offs: i32 = 345;
    pub const quiet_history_penalty_max: i32 = 1146;
    pub const pawn_history_bonus_mult: i32 = 292;
    pub const pawn_history_bonus_offs: i32 = 292;
    pub const pawn_history_bonus_max: i32 = 2279;
    pub const pawn_history_penalty_mult: i32 = 347;
    pub const pawn_history_penalty_offs: i32 = 504;
    pub const pawn_history_penalty_max: i32 = 1792;
    pub const cont1_history_bonus_mult: i32 = 214;
    pub const cont1_history_bonus_offs: i32 = 163;
    pub const cont1_history_bonus_max: i32 = 3421;
    pub const cont1_history_penalty_mult: i32 = 183;
    pub const cont1_history_penalty_offs: i32 = 365;
    pub const cont1_history_penalty_max: i32 = 1525;
    pub const cont2_history_bonus_mult: i32 = 214;
    pub const cont2_history_bonus_offs: i32 = 163;
    pub const cont2_history_bonus_max: i32 = 3421;
    pub const cont2_history_penalty_mult: i32 = 183;
    pub const cont2_history_penalty_offs: i32 = 365;
    pub const cont2_history_penalty_max: i32 = 1525;
    pub const cont4_history_bonus_mult: i32 = 214;
    pub const cont4_history_bonus_offs: i32 = 163;
    pub const cont4_history_bonus_max: i32 = 3421;
    pub const cont4_history_penalty_mult: i32 = 183;
    pub const cont4_history_penalty_offs: i32 = 365;
    pub const cont4_history_penalty_max: i32 = 1525;
    pub const noisy_history_bonus_mult: i32 = 237;
    pub const noisy_history_bonus_offs: i32 = 279;
    pub const noisy_history_bonus_max: i32 = 3084;
    pub const noisy_history_penalty_mult: i32 = 203;
    pub const noisy_history_penalty_offs: i32 = 266;
    pub const noisy_history_penalty_max: i32 = 2845;
    pub const eval_hist_min: i32 = -97;
    pub const eval_hist_max: i32 = 82;
    pub const eval_hist_offs: i32 = 126;
    pub const eval_hist_mult: i32 = 1066;
    pub const high_eval_offs: i32 = 42;
    pub const faillow_mult: i32 = 2446;
    pub const quiet_ordering_weight: i32 = 1024;
    pub const quiet_pruning_weight: i32 = 403;
    pub const pawn_ordering_weight: i32 = 1010;
    pub const pawn_pruning_weight: i32 = 1027;
    pub const cont1_ordering_weight: i32 = 840;
    pub const cont1_pruning_weight: i32 = 749;
    pub const cont2_ordering_weight: i32 = 1046;
    pub const cont2_pruning_weight: i32 = 974;
    pub const cont4_ordering_weight: i32 = 557;
    pub const cont4_pruning_weight: i32 = 231;
    pub const rfp_min_margin: i32 = 21;
    pub const rfp_base: i32 = 47248;
    pub const rfp_mult: i32 = 34063;
    pub const rfp_quad: i32 = 6177;
    pub const rfp_improving_margin: i32 = 107;
    pub const rfp_easy_margin: i32 = -17;
    pub const rfp_improving_easy_margin: i32 = -101;
    pub const rfp_worsening_margin: i32 = 15;
    pub const rfp_cutnode_margin: i32 = 18;
    pub const rfp_corrplexity_mult: i32 = 15;
    pub const rfp_history_mult: i32 = 65;
    pub const rfp_noisy_history_mult: i32 = 38;
    pub const rfp_hist_quiet_weight: i32 = 403;
    pub const rfp_hist_pawn_weight: i32 = 1027;
    pub const rfp_hist_cont1_weight: i32 = 749;
    pub const rfp_hist_cont2_weight: i32 = 974;
    pub const rfp_hist_cont4_weight: i32 = 231;
    pub const rfp_hist_noisy_weight: i32 = 1024;
    pub const aspiration_score_mult: i32 = 1148;
    pub const aspiration_initial: i32 = 11314;
    pub const aspiration_multiplier: i32 = 1368;
    pub const failhigh_add: i32 = 1002;
    pub const failhigh_mult: i32 = 550;
    pub const failhigh_max: i32 = 4133;
    pub const lmr_quiet_base: i32 = 3910;
    pub const lmr_noisy_base: i32 = 2788;
    pub const lmr_quiet_depth_mult: i32 = 269;
    pub const lmr_noisy_depth_mult: i32 = 302;
    pub const lmr_quiet_depth_offs: i32 = -7;
    pub const lmr_noisy_depth_offs: i32 = -51;
    pub const lmr_quiet_legal_mult: i32 = 518;
    pub const lmr_noisy_legal_mult: i32 = 642;
    pub const lmr_quiet_legal_offs: i32 = 30;
    pub const lmr_noisy_legal_offs: i32 = -103;
    pub const lmr_quiet_history_mult: i32 = 891;
    pub const lmr_noisy_history_mult: i32 = 896;
    pub const lmr_depth_hist_quiet_weight: i32 = 403;
    pub const lmr_depth_hist_pawn_weight: i32 = 1027;
    pub const lmr_depth_hist_cont1_weight: i32 = 749;
    pub const lmr_depth_hist_cont2_weight: i32 = 974;
    pub const lmr_depth_hist_cont4_weight: i32 = 231;
    pub const lmr_depth_hist_noisy_weight: i32 = 1024;
    pub const lmr_hist_quiet_weight: i32 = 403;
    pub const lmr_hist_pawn_weight: i32 = 1027;
    pub const lmr_hist_cont1_weight: i32 = 749;
    pub const lmr_hist_cont2_weight: i32 = 974;
    pub const lmr_hist_cont4_weight: i32 = 231;
    pub const lmr_hist_noisy_weight: i32 = 1024;
    pub const lmr_corrhist_mult: i32 = 8219;
    pub const lmr_alpha_raise_mult: i32 = 1024;
    pub const lmr_ttpv_depth: i32 = 512;
    pub const lmr_ttpv_score: i32 = 512;
    pub const lmr_dodeeper_margin: i32 = 59457;
    pub const lmr_dodeeper_mult: i32 = 1997;
    pub const lmr_doshallower_margin: i32 = 1153;
    pub const lmr_doshallower_mult: i32 = 1153;
    pub const hindsight_ext_margin: i32 = 2801;
    pub const nmp_margin_base: i32 = 288;
    pub const nmp_margin_mult: i32 = 22;
    pub const nmp_base: i32 = 68037;
    pub const nmp_mult: i32 = 1185;
    pub const fp_depth_limit: i32 = 8249;
    pub const fp_base: i32 = 244;
    pub const fp_mult: i32 = 76;
    pub const fp_pv_base: i32 = 110;
    pub const fp_pv_mult: i32 = 26;
    pub const fp_improving: i32 = 64;
    pub const fp_hist_mult: i32 = 141;
    pub const fp_hist_quiet_weight: i32 = 403;
    pub const fp_hist_pawn_weight: i32 = 1027;
    pub const fp_hist_cont1_weight: i32 = 749;
    pub const fp_hist_cont2_weight: i32 = 974;
    pub const fp_hist_cont4_weight: i32 = 231;
    pub const fp_hist_noisy_weight: i32 = 1024;
    pub const bnfp_depth_limit: i32 = 8648;
    pub const bnfp_base: i32 = 158;
    pub const bnfp_mult: i32 = 75;
    pub const qs_see_threshold: i32 = -68;
    pub const see_quiet_pruning_offs: i32 = -43;
    pub const see_noisy_pruning_offs: i32 = -9;
    pub const see_quiet_pruning_mult: i32 = 9;
    pub const see_noisy_pruning_mult: i32 = 0;
    pub const see_quiet_pruning_quad: i32 = -35;
    pub const see_noisy_pruning_quad: i32 = -35;
    pub const see_pv_offs: i32 = 98;
    pub const razoring_offs: i32 = 46;
    pub const razoring_mult: i32 = 165;
    pub const razoring_quad: i32 = 95;
    pub const razoring_easy_capture: i32 = 106;
    pub const history_pruning_depth_limit: i32 = 3524;
    pub const history_pruning_offs: i32 = 957;
    pub const history_pruning_mult: i32 = -2548;
    pub const hp_hist_quiet_weight: i32 = 403;
    pub const hp_hist_pawn_weight: i32 = 1027;
    pub const hp_hist_cont1_weight: i32 = 749;
    pub const hp_hist_cont2_weight: i32 = 974;
    pub const hp_hist_cont4_weight: i32 = 231;
    pub const hp_hist_noisy_weight: i32 = 1024;
    pub const noisy_history_pruning_depth_limit: i32 = 3578;
    pub const noisy_history_pruning_offs: i32 = 897;
    pub const noisy_history_pruning_mult: i32 = -2835;
    pub const qs_futility_margin: i32 = 152;
    pub const qs_hp_margin: i32 = -3906;
    pub const corrhist_pawn_weight: i32 = 990;
    pub const corrhist_nonpawn_weight: i32 = 1113;
    pub const corrhist_countermove_weight: i32 = 779;
    pub const corrhist_followupmove_weight: i32 = 353;
    pub const corrhist_major_weight: i32 = 1146;
    pub const corrhist_minor_weight: i32 = 950;
    pub const corrhist_pawn_update_weight: i32 = 2701;
    pub const corrhist_nonpawn_update_weight: i32 = 1837;
    pub const corrhist_countermove_update_weight: i32 = 2225;
    pub const corrhist_followupmove_update_weight: i32 = 2113;
    pub const corrhist_major_update_weight: i32 = 1758;
    pub const corrhist_minor_update_weight: i32 = 2060;
    pub const lmp_standard_base: i32 = 4336;
    pub const lmp_improving_base: i32 = 5000;
    pub const lmp_standard_linear_mult: i32 = 127;
    pub const lmp_improving_linear_mult: i32 = 354;
    pub const lmp_standard_quadratic_mult: i32 = 150;
    pub const lmp_improving_quadratic_mult: i32 = 1127;
    pub const good_noisy_ordering_base: i32 = -40;
    pub const good_noisy_ordering_mult: i32 = 948;
    pub const see_pawn_pruning: i32 = 77;
    pub const see_knight_pruning: i32 = 214;
    pub const see_bishop_pruning: i32 = 321;
    pub const see_rook_pruning: i32 = 536;
    pub const see_queen_pruning: i32 = 1111;
    pub const see_pawn_ordering: i32 = 70;
    pub const see_knight_ordering: i32 = 266;
    pub const see_bishop_ordering: i32 = 241;
    pub const see_rook_ordering: i32 = 478;
    pub const see_queen_ordering: i32 = 722;
    pub const mvv_mult: i32 = 757;
    pub const material_scaling_base: i32 = 8731;
    pub const material_scaling_pawn: i32 = 105;
    pub const material_scaling_knight: i32 = 354;
    pub const material_scaling_bishop: i32 = 511;
    pub const material_scaling_rook: i32 = 281;
    pub const material_scaling_queen: i32 = 974;
    pub const rfp_fail_medium: i32 = 62;
    pub const tt_fail_medium: i32 = 11;
    pub const qs_tt_fail_medium: i32 = 181;
    pub const standpat_fail_medium: i32 = 290;
    pub const qs_fail_medium: i32 = 512;
    pub const nodetm_base: i32 = 1418;
    pub const nodetm_mult: i32 = 1178;
    pub const eval_stab_margin: i32 = 22;
    pub const eval_stab_base: i32 = 1397;
    pub const eval_stab_offs: i32 = 54;
    pub const eval_stab_lim: i32 = 846;
    pub const move_stab_base: i32 = 1405;
    pub const move_stab_offs: i32 = 47;
    pub const move_stab_lim: i32 = 947;
    pub const soft_limit_base: i32 = 53;
    pub const soft_limit_incr: i32 = 796;
    pub const hard_limit_phase_mult: i32 = 111;
    pub const hard_limit_base: i32 = 238;
    pub const singular_beta_mult: i32 = 491;
    pub const singular_beta_pv_mult: i32 = 529;
    pub const singular_beta_ttpv_mult: i32 = 465;
    pub const singular_depth_mult: i32 = 537;
    pub const singular_depth_offs: i32 = 924;
    pub const singular_dext_margin_quiet: i32 = 17;
    pub const singular_dext_margin_noisy: i32 = 15;
    pub const singular_dext_pv_margin: i32 = 23;
    pub const singular_text_margin_quiet: i32 = 74;
    pub const singular_text_margin_noisy: i32 = 81;
    pub const singular_text_pv_margin: i32 = 508;
    pub const ttpick_depth_weight: i32 = 819;
    pub const ttpick_age_weight: i32 = 4835;
    pub const ttpick_pv_weight: i32 = 287;
    pub const ttpick_lower_weight: i32 = 168;
    pub const ttpick_upper_weight: i32 = 324;
    pub const ttpick_exact_weight: i32 = 7;
    pub const ttpick_move_weight: i32 = 15;
    pub const voting_score_max: i32 = 1060;
    pub const voting_score_offset: i32 = 130;
    pub const voting_depth_offset: i32 = 129;
    pub const voting_offset: i32 = -41;
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
    .{ .name = "cont1_history_bonus_mult", .default = tunable_defaults.cont1_history_bonus_mult },
    .{ .name = "cont1_history_bonus_offs", .default = tunable_defaults.cont1_history_bonus_offs },
    .{ .name = "cont1_history_bonus_max", .default = tunable_defaults.cont1_history_bonus_max },
    .{ .name = "cont1_history_penalty_mult", .default = tunable_defaults.cont1_history_penalty_mult },
    .{ .name = "cont1_history_penalty_offs", .default = tunable_defaults.cont1_history_penalty_offs },
    .{ .name = "cont1_history_penalty_max", .default = tunable_defaults.cont1_history_penalty_max },
    .{ .name = "cont2_history_bonus_mult", .default = tunable_defaults.cont2_history_bonus_mult },
    .{ .name = "cont2_history_bonus_offs", .default = tunable_defaults.cont2_history_bonus_offs },
    .{ .name = "cont2_history_bonus_max", .default = tunable_defaults.cont2_history_bonus_max },
    .{ .name = "cont2_history_penalty_mult", .default = tunable_defaults.cont2_history_penalty_mult },
    .{ .name = "cont2_history_penalty_offs", .default = tunable_defaults.cont2_history_penalty_offs },
    .{ .name = "cont2_history_penalty_max", .default = tunable_defaults.cont2_history_penalty_max },
    .{ .name = "cont4_history_bonus_mult", .default = tunable_defaults.cont4_history_bonus_mult },
    .{ .name = "cont4_history_bonus_offs", .default = tunable_defaults.cont4_history_bonus_offs },
    .{ .name = "cont4_history_bonus_max", .default = tunable_defaults.cont4_history_bonus_max },
    .{ .name = "cont4_history_penalty_mult", .default = tunable_defaults.cont4_history_penalty_mult },
    .{ .name = "cont4_history_penalty_offs", .default = tunable_defaults.cont4_history_penalty_offs },
    .{ .name = "cont4_history_penalty_max", .default = tunable_defaults.cont4_history_penalty_max },
    .{ .name = "noisy_history_bonus_mult", .default = tunable_defaults.noisy_history_bonus_mult },
    .{ .name = "noisy_history_bonus_offs", .default = tunable_defaults.noisy_history_bonus_offs },
    .{ .name = "noisy_history_bonus_max", .default = tunable_defaults.noisy_history_bonus_max },
    .{ .name = "noisy_history_penalty_mult", .default = tunable_defaults.noisy_history_penalty_mult },
    .{ .name = "noisy_history_penalty_offs", .default = tunable_defaults.noisy_history_penalty_offs },
    .{ .name = "noisy_history_penalty_max", .default = tunable_defaults.noisy_history_penalty_max },
    .{ .name = "eval_hist_min", .default = tunable_defaults.eval_hist_min },
    .{ .name = "eval_hist_max", .default = tunable_defaults.eval_hist_max },
    .{ .name = "eval_hist_offs", .default = tunable_defaults.eval_hist_offs },
    .{ .name = "eval_hist_mult", .default = tunable_defaults.eval_hist_mult },
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
    .{ .name = "rfp_hist_quiet_weight", .default = tunable_defaults.rfp_hist_quiet_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "rfp_hist_pawn_weight", .default = tunable_defaults.rfp_hist_pawn_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "rfp_hist_cont1_weight", .default = tunable_defaults.rfp_hist_cont1_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "rfp_hist_cont2_weight", .default = tunable_defaults.rfp_hist_cont2_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "rfp_hist_cont4_weight", .default = tunable_defaults.rfp_hist_cont4_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "rfp_hist_noisy_weight", .default = tunable_defaults.rfp_hist_noisy_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "aspiration_score_mult", .default = tunable_defaults.aspiration_score_mult, .min = 10, .max = 4096, .c_end = 32 },
    .{ .name = "aspiration_initial", .default = tunable_defaults.aspiration_initial, .min = 10, .max = 39450, .c_end = 1577 },
    .{ .name = "aspiration_multiplier", .default = tunable_defaults.aspiration_multiplier, .min = 1127, .max = 4015, .c_end = 160 },
    .{ .name = "failhigh_add", .default = tunable_defaults.failhigh_add },
    .{ .name = "failhigh_mult", .default = tunable_defaults.failhigh_mult },
    .{ .name = "failhigh_max", .default = tunable_defaults.failhigh_max },
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
    .{ .name = "lmr_depth_hist_quiet_weight", .default = tunable_defaults.lmr_depth_hist_quiet_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_depth_hist_pawn_weight", .default = tunable_defaults.lmr_depth_hist_pawn_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_depth_hist_cont1_weight", .default = tunable_defaults.lmr_depth_hist_cont1_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_depth_hist_cont2_weight", .default = tunable_defaults.lmr_depth_hist_cont2_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_depth_hist_cont4_weight", .default = tunable_defaults.lmr_depth_hist_cont4_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_depth_hist_noisy_weight", .default = tunable_defaults.lmr_depth_hist_noisy_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_hist_quiet_weight", .default = tunable_defaults.lmr_hist_quiet_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_hist_pawn_weight", .default = tunable_defaults.lmr_hist_pawn_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_hist_cont1_weight", .default = tunable_defaults.lmr_hist_cont1_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_hist_cont2_weight", .default = tunable_defaults.lmr_hist_cont2_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_hist_cont4_weight", .default = tunable_defaults.lmr_hist_cont4_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_hist_noisy_weight", .default = tunable_defaults.lmr_hist_noisy_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "lmr_corrhist_mult", .default = tunable_defaults.lmr_corrhist_mult, .min = -10, .max = 23695, .c_end = 947 },
    .{ .name = "lmr_alpha_raise_mult", .default = tunable_defaults.lmr_alpha_raise_mult },
    .{ .name = "lmr_ttpv_depth", .default = tunable_defaults.lmr_ttpv_depth },
    .{ .name = "lmr_ttpv_score", .default = tunable_defaults.lmr_ttpv_score },
    .{ .name = "lmr_dodeeper_margin", .default = tunable_defaults.lmr_dodeeper_margin },
    .{ .name = "lmr_dodeeper_mult", .default = tunable_defaults.lmr_dodeeper_mult },
    .{ .name = "lmr_doshallower_margin", .default = tunable_defaults.lmr_doshallower_margin },
    .{ .name = "lmr_doshallower_mult", .default = tunable_defaults.lmr_doshallower_mult },
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
    .{ .name = "fp_improving", .default = tunable_defaults.fp_improving },
    .{ .name = "fp_hist_mult", .default = tunable_defaults.fp_hist_mult },
    .{ .name = "fp_hist_quiet_weight", .default = tunable_defaults.fp_hist_quiet_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "fp_hist_pawn_weight", .default = tunable_defaults.fp_hist_pawn_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "fp_hist_cont1_weight", .default = tunable_defaults.fp_hist_cont1_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "fp_hist_cont2_weight", .default = tunable_defaults.fp_hist_cont2_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "fp_hist_cont4_weight", .default = tunable_defaults.fp_hist_cont4_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "fp_hist_noisy_weight", .default = tunable_defaults.fp_hist_noisy_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "bnfp_depth_limit", .default = tunable_defaults.bnfp_depth_limit },
    .{ .name = "bnfp_base", .default = tunable_defaults.bnfp_base },
    .{ .name = "bnfp_mult", .default = tunable_defaults.bnfp_mult },
    .{ .name = "qs_see_threshold", .default = tunable_defaults.qs_see_threshold },
    .{ .name = "see_quiet_pruning_offs", .default = tunable_defaults.see_quiet_pruning_offs, .min = -100, .max = 100, .c_end = 20 },
    .{ .name = "see_noisy_pruning_offs", .default = tunable_defaults.see_noisy_pruning_offs, .min = -100, .max = 100, .c_end = 5 },
    .{ .name = "see_quiet_pruning_mult", .default = tunable_defaults.see_quiet_pruning_mult, .c_end = 5 },
    .{ .name = "see_noisy_pruning_mult", .default = tunable_defaults.see_noisy_pruning_mult, .c_end = 5 },
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
    .{ .name = "hp_hist_quiet_weight", .default = tunable_defaults.hp_hist_quiet_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "hp_hist_pawn_weight", .default = tunable_defaults.hp_hist_pawn_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "hp_hist_cont1_weight", .default = tunable_defaults.hp_hist_cont1_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "hp_hist_cont2_weight", .default = tunable_defaults.hp_hist_cont2_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "hp_hist_cont4_weight", .default = tunable_defaults.hp_hist_cont4_weight, .min = -2048, .max = 2048, .c_end = 128 },
    .{ .name = "hp_hist_noisy_weight", .default = tunable_defaults.hp_hist_noisy_weight, .min = -2048, .max = 2048, .c_end = 128 },
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
    .{ .name = "rfp_fail_medium", .default = tunable_defaults.rfp_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
    .{ .name = "tt_fail_medium", .default = tunable_defaults.tt_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
    .{ .name = "qs_tt_fail_medium", .default = tunable_defaults.qs_tt_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
    .{ .name = "standpat_fail_medium", .default = tunable_defaults.standpat_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
    .{ .name = "qs_fail_medium", .default = tunable_defaults.qs_fail_medium, .min = 0, .max = 1024, .c_end = 128 },
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
    .{ .name = "singular_dext_margin_quiet", .default = tunable_defaults.singular_dext_margin_quiet, .min = 0, .max = tunable_defaults.singular_dext_margin_quiet, .c_end = 1 },
    .{ .name = "singular_dext_margin_noisy", .default = tunable_defaults.singular_dext_margin_noisy, .min = 0, .max = tunable_defaults.singular_dext_margin_noisy, .c_end = 1 },
    .{ .name = "singular_dext_pv_margin", .default = tunable_defaults.singular_dext_pv_margin, .min = 0, .max = tunable_defaults.singular_dext_pv_margin, .c_end = 1 },
    .{ .name = "singular_text_margin_quiet", .default = tunable_defaults.singular_text_margin_quiet, .min = 0, .max = tunable_defaults.singular_text_margin_quiet, .c_end = 5 },
    .{ .name = "singular_text_margin_noisy", .default = tunable_defaults.singular_text_margin_noisy, .min = 0, .max = tunable_defaults.singular_text_margin_noisy, .c_end = 5 },
    .{ .name = "singular_text_pv_margin", .default = tunable_defaults.singular_text_pv_margin, .min = 0, .max = tunable_defaults.singular_text_pv_margin, .c_end = 25 },
    .{ .name = "ttpick_depth_weight", .default = tunable_defaults.ttpick_depth_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_age_weight", .default = tunable_defaults.ttpick_age_weight, .min = 0, .max = 8192, .c_end = 256 },
    .{ .name = "ttpick_pv_weight", .default = tunable_defaults.ttpick_pv_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_lower_weight", .default = tunable_defaults.ttpick_lower_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_upper_weight", .default = tunable_defaults.ttpick_upper_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_exact_weight", .default = tunable_defaults.ttpick_exact_weight, .min = 0, .max = 2048, .c_end = 128 },
    .{ .name = "ttpick_move_weight", .default = tunable_defaults.ttpick_move_weight, .min = 0, .max = 8192, .c_end = 256 },
    .{ .name = "voting_score_max", .default = tunable_defaults.voting_score_max },
    .{ .name = "voting_score_offset", .default = tunable_defaults.voting_score_offset },
    .{ .name = "voting_depth_offset", .default = tunable_defaults.voting_depth_offset },
    .{ .name = "voting_offset", .default = tunable_defaults.voting_offset, .min = -1000, .max = 1000, .c_end = 100 },
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
    pub var cont1_history_bonus_mult = tunable_defaults.cont1_history_bonus_mult;
    pub var cont1_history_bonus_offs = tunable_defaults.cont1_history_bonus_offs;
    pub var cont1_history_bonus_max = tunable_defaults.cont1_history_bonus_max;
    pub var cont1_history_penalty_mult = tunable_defaults.cont1_history_penalty_mult;
    pub var cont1_history_penalty_offs = tunable_defaults.cont1_history_penalty_offs;
    pub var cont1_history_penalty_max = tunable_defaults.cont1_history_penalty_max;
    pub var cont2_history_bonus_mult = tunable_defaults.cont2_history_bonus_mult;
    pub var cont2_history_bonus_offs = tunable_defaults.cont2_history_bonus_offs;
    pub var cont2_history_bonus_max = tunable_defaults.cont2_history_bonus_max;
    pub var cont2_history_penalty_mult = tunable_defaults.cont2_history_penalty_mult;
    pub var cont2_history_penalty_offs = tunable_defaults.cont2_history_penalty_offs;
    pub var cont2_history_penalty_max = tunable_defaults.cont2_history_penalty_max;
    pub var cont4_history_bonus_mult = tunable_defaults.cont4_history_bonus_mult;
    pub var cont4_history_bonus_offs = tunable_defaults.cont4_history_bonus_offs;
    pub var cont4_history_bonus_max = tunable_defaults.cont4_history_bonus_max;
    pub var cont4_history_penalty_mult = tunable_defaults.cont4_history_penalty_mult;
    pub var cont4_history_penalty_offs = tunable_defaults.cont4_history_penalty_offs;
    pub var cont4_history_penalty_max = tunable_defaults.cont4_history_penalty_max;
    pub var noisy_history_bonus_mult = tunable_defaults.noisy_history_bonus_mult;
    pub var noisy_history_bonus_offs = tunable_defaults.noisy_history_bonus_offs;
    pub var noisy_history_bonus_max = tunable_defaults.noisy_history_bonus_max;
    pub var noisy_history_penalty_mult = tunable_defaults.noisy_history_penalty_mult;
    pub var noisy_history_penalty_offs = tunable_defaults.noisy_history_penalty_offs;
    pub var eval_hist_min = tunable_defaults.eval_hist_min;
    pub var eval_hist_max = tunable_defaults.eval_hist_max;
    pub var eval_hist_offs = tunable_defaults.eval_hist_offs;
    pub var eval_hist_mult = tunable_defaults.eval_hist_mult;
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
    pub var rfp_hist_quiet_weight = tunable_defaults.rfp_hist_quiet_weight;
    pub var rfp_hist_pawn_weight = tunable_defaults.rfp_hist_pawn_weight;
    pub var rfp_hist_cont1_weight = tunable_defaults.rfp_hist_cont1_weight;
    pub var rfp_hist_cont2_weight = tunable_defaults.rfp_hist_cont2_weight;
    pub var rfp_hist_cont4_weight = tunable_defaults.rfp_hist_cont4_weight;
    pub var rfp_hist_noisy_weight = tunable_defaults.rfp_hist_noisy_weight;
    pub var aspiration_score_mult = tunable_defaults.aspiration_score_mult;
    pub var aspiration_initial = tunable_defaults.aspiration_initial;
    pub var aspiration_multiplier = tunable_defaults.aspiration_multiplier;
    pub var failhigh_add = tunable_defaults.failhigh_add;
    pub var failhigh_mult = tunable_defaults.failhigh_mult;
    pub var failhigh_max = tunable_defaults.failhigh_max;
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
    pub var lmr_depth_hist_quiet_weight = tunable_defaults.lmr_depth_hist_quiet_weight;
    pub var lmr_depth_hist_pawn_weight = tunable_defaults.lmr_depth_hist_pawn_weight;
    pub var lmr_depth_hist_cont1_weight = tunable_defaults.lmr_depth_hist_cont1_weight;
    pub var lmr_depth_hist_cont2_weight = tunable_defaults.lmr_depth_hist_cont2_weight;
    pub var lmr_depth_hist_cont4_weight = tunable_defaults.lmr_depth_hist_cont4_weight;
    pub var lmr_depth_hist_noisy_weight = tunable_defaults.lmr_depth_hist_noisy_weight;
    pub var lmr_hist_quiet_weight = tunable_defaults.lmr_hist_quiet_weight;
    pub var lmr_hist_pawn_weight = tunable_defaults.lmr_hist_pawn_weight;
    pub var lmr_hist_cont1_weight = tunable_defaults.lmr_hist_cont1_weight;
    pub var lmr_hist_cont2_weight = tunable_defaults.lmr_hist_cont2_weight;
    pub var lmr_hist_cont4_weight = tunable_defaults.lmr_hist_cont4_weight;
    pub var lmr_hist_noisy_weight = tunable_defaults.lmr_hist_noisy_weight;
    pub var lmr_corrhist_mult = tunable_defaults.lmr_corrhist_mult;
    pub var lmr_alpha_raise_mult = tunable_defaults.lmr_alpha_raise_mult;
    pub var lmr_ttpv_depth = tunable_defaults.lmr_ttpv_depth;
    pub var lmr_ttpv_score = tunable_defaults.lmr_ttpv_score;
    pub var lmr_dodeeper_margin = tunable_defaults.lmr_dodeeper_margin;
    pub var lmr_dodeeper_mult = tunable_defaults.lmr_dodeeper_mult;
    pub var lmr_doshallower_margin = tunable_defaults.lmr_doshallower_margin;
    pub var lmr_doshallower_mult = tunable_defaults.lmr_doshallower_mult;
    pub var hindsight_ext_margin = tunable_defaults.hindsight_ext_margin;
    pub var nmp_margin_base = tunable_defaults.nmp_margin_base;
    pub var nmp_margin_mult = tunable_defaults.nmp_margin_mult;
    pub var nmp_base = tunable_defaults.nmp_base;
    pub var nmp_mult = tunable_defaults.nmp_mult;
    pub var fp_depth_limit = tunable_defaults.fp_depth_limit;
    pub var fp_base = tunable_defaults.fp_base;
    pub var fp_mult = tunable_defaults.fp_mult;
    pub var fp_pv_base = tunable_defaults.fp_pv_base;
    pub var fp_pv_mult = tunable_defaults.fp_pv_mult;
    pub var fp_improving = tunable_defaults.fp_improving;
    pub var fp_hist_mult = tunable_defaults.fp_hist_mult;
    pub var fp_hist_quiet_weight = tunable_defaults.fp_hist_quiet_weight;
    pub var fp_hist_pawn_weight = tunable_defaults.fp_hist_pawn_weight;
    pub var fp_hist_cont1_weight = tunable_defaults.fp_hist_cont1_weight;
    pub var fp_hist_cont2_weight = tunable_defaults.fp_hist_cont2_weight;
    pub var fp_hist_cont4_weight = tunable_defaults.fp_hist_cont4_weight;
    pub var fp_hist_noisy_weight = tunable_defaults.fp_hist_noisy_weight;
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
    pub var hp_hist_quiet_weight = tunable_defaults.hp_hist_quiet_weight;
    pub var hp_hist_pawn_weight = tunable_defaults.hp_hist_pawn_weight;
    pub var hp_hist_cont1_weight = tunable_defaults.hp_hist_cont1_weight;
    pub var hp_hist_cont2_weight = tunable_defaults.hp_hist_cont2_weight;
    pub var hp_hist_cont4_weight = tunable_defaults.hp_hist_cont4_weight;
    pub var hp_hist_noisy_weight = tunable_defaults.hp_hist_noisy_weight;
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
    pub var rfp_fail_medium = tunable_defaults.rfp_fail_medium;
    pub var tt_fail_medium = tunable_defaults.tt_fail_medium;
    pub var qs_tt_fail_medium = tunable_defaults.qs_tt_fail_medium;
    pub var standpat_fail_medium = tunable_defaults.standpat_fail_medium;
    pub var qs_fail_medium = tunable_defaults.qs_fail_medium;
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
    pub var voting_score_max = tunable_defaults.voting_score_max;
    pub var voting_score_offset = tunable_defaults.voting_score_offset;
    pub var voting_depth_offset = tunable_defaults.voting_depth_offset;
    pub var voting_offset = tunable_defaults.voting_offset;
} else tunable_defaults;

const factorized_lmr_defaults = struct {
    pub const N = 9;
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
        -1032,
        1588,
        -338,
        184,
        -979,
        -242,
        -827,
        763,
        592,
    };
    pub const two: [N * (N - 1) / 2]i32 = .{
        421,
        -71,
        640,
        43,
        458,
        -75,
        334,
        -158,
        125,
        497,
        -177,
        31,
        -73,
        460,
        119,
        -159,
        40,
        104,
        -44,
        516,
        158,
        -489,
        273,
        294,
        -271,
        69,
        -103,
        -354,
        232,
        -21,
        -248,
        -111,
        40,
        338,
        -74,
        -86,
    };
    pub const three: [N * (N - 1) * (N - 2) / 6]i32 = .{
        127,
        188,
        -504,
        210,
        -89,
        88,
        -6,
        -447,
        -229,
        -300,
        -72,
        108,
        -3,
        -431,
        111,
        295,
        -212,
        -129,
        -185,
        110,
        -12,
        -51,
        71,
        -161,
        28,
        -5,
        -11,
        -27,
        -45,
        392,
        -19,
        -61,
        204,
        -53,
        -267,
        -85,
        379,
        297,
        -151,
        -36,
        154,
        -197,
        -67,
        284,
        199,
        210,
        -163,
        -67,
        109,
        -19,
        -268,
        -77,
        18,
        -50,
        36,
        239,
        -26,
        2,
        -420,
        -36,
        67,
        -212,
        -43,
        -25,
        205,
        -84,
        -257,
        111,
        262,
        -304,
        -109,
        -237,
        -230,
        -192,
        -249,
        324,
        -52,
        -17,
        28,
        -100,
        415,
        233,
        -143,
        219,
    };
};

pub const factorized_lmr_params = struct {
    pub const min = -2048;
    pub const max = 2048;
    pub const c_end = 128;
};

pub const factorized_lmr = if (do_factorized_tuning) struct {
    pub const N = factorized_lmr_defaults.N;
    pub var one = factorized_lmr_defaults.one;
    pub var two = factorized_lmr_defaults.two;
    pub var three = factorized_lmr_defaults.three;
} else factorized_lmr_defaults;

comptime {
    std.debug.assert(std.meta.declarations(tunable_defaults).len == tunables.len);
    std.debug.assert(std.meta.declarations(tunable_constants).len == tunables.len);
}
