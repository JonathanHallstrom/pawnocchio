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
    pub const quiet_history_bonus_mult: i32 = 406;
    pub const quiet_history_bonus_offs: i32 = 322;
    pub const quiet_history_bonus_max: i32 = 2614;
    pub const quiet_history_penalty_mult: i32 = 217;
    pub const quiet_history_penalty_offs: i32 = 287;
    pub const quiet_history_penalty_max: i32 = 1831;
    pub const cont_history_bonus_mult: i32 = 447;
    pub const cont_history_bonus_offs: i32 = 298;
    pub const cont_history_bonus_max: i32 = 2871;
    pub const cont_history_penalty_mult: i32 = 234;
    pub const cont_history_penalty_offs: i32 = 278;
    pub const cont_history_penalty_max: i32 = 1879;
    pub const noisy_history_bonus_mult: i32 = 406;
    pub const noisy_history_bonus_offs: i32 = 345;
    pub const noisy_history_bonus_max: i32 = 2367;
    pub const noisy_history_penalty_mult: i32 = 220;
    pub const noisy_history_penalty_offs: i32 = 225;
    pub const noisy_history_penalty_max: i32 = 1918;
    pub const rfp_base: i32 = 61;
    pub const rfp_mult: i32 = 59;
    pub const rfp_improving_margin: i32 = 60;
    pub const rfp_worsening_margin: i32 = 12;
    pub const rfp_cutnode_margin: i32 = 19;
    pub const aspiration_initial: i32 = 15360;
    pub const aspiration_multiplier: i32 = 2213;
    pub const lmr_quiet_base: i32 = 2355;
    pub const lmr_noisy_base: i32 = 2268;
    pub const lmr_quiet_log_mult: i32 = 215;
    pub const lmr_noisy_log_mult: i32 = 230;
    pub const lmr_quiet_depth_mult: i32 = 847;
    pub const lmr_noisy_depth_mult: i32 = 909;
    pub const lmr_quiet_depth_offs: i32 = 0;
    pub const lmr_noisy_depth_offs: i32 = 0;
    pub const lmr_quiet_legal_mult: i32 = 938;
    pub const lmr_noisy_legal_mult: i32 = 901;
    pub const lmr_quiet_legal_offs: i32 = 0;
    pub const lmr_noisy_legal_offs: i32 = 0;
    pub const lmr_pv_mult: i32 = 1319;
    pub const lmr_cutnode_mult: i32 = 1019;
    pub const lmr_improving_mult: i32 = 1022;
    pub const lmr_quiet_history_mult: i32 = 946;
    pub const lmr_noisy_history_mult: i32 = 1079;
    pub const lmr_corrhist_mult: i32 = 12362;
    pub const lmr_ttmove_mult: i32 = 534;
    pub const lmr_dodeeper_margin: i32 = 60;
    pub const nmp_base: i32 = 45963;
    pub const nmp_mult: i32 = 1110;
    pub const nmp_eval_reduction_scale: i32 = 32;
    pub const nmp_eval_reduction_max: i32 = 23564;
    pub const fp_base: i32 = 269;
    pub const fp_mult: i32 = 107;
    pub const qs_see_threshold: i32 = -92;
    pub const see_quiet_pruning_mult: i32 = -62;
    pub const see_noisy_pruning_mult: i32 = -43;
    pub const razoring_margin: i32 = 188;
    pub const history_pruning_mult: i32 = -2509;
    pub const qs_futility_margin: i32 = 107;
    pub const corrhist_pawn_weight: i32 = 1006;
    pub const corrhist_nonpawn_weight: i32 = 549;
    pub const corrhist_countermove_weight: i32 = 1105;
    pub const corrhist_major_weight: i32 = 1087;
    pub const corrhist_minor_weight: i32 = 980;
    pub const lmp_standard_base: i32 = -3396;
    pub const lmp_improving_base: i32 = -3396;
    pub const lmp_standard_mult: i32 = 989;
    pub const lmp_improving_mult: i32 = 969;
    pub const see_pawn: i32 = 93;
    pub const see_knight: i32 = 308;
    pub const see_bishop: i32 = 346;
    pub const see_rook: i32 = 521;
    pub const see_queen: i32 = 994;
    pub const nodetm_base: i32 = 1713;
    pub const nodetm_mult: i32 = 950;
    pub const eval_stab_base: i32 = 1200;
    pub const eval_stab_offs: i32 = 50;
    pub const move_stab_base: i32 = 1200;
    pub const move_stab_offs: i32 = 50;
    pub const soft_limit_base: i32 = 53;
    pub const soft_limit_incr: i32 = 572;
    pub const hard_limit_phase_mult: i32 = 128;
    pub const hard_limit_base: i32 = 190;
    pub const singular_beta_mult: i32 = 16;
    pub const singular_depth_mult: i32 = 19;
    pub const singular_dext_margin: i32 = 13;
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
    .{ .name = "see_pawn", .default = tunable_defaults.see_pawn },
    .{ .name = "see_knight", .default = tunable_defaults.see_knight },
    .{ .name = "see_bishop", .default = tunable_defaults.see_bishop },
    .{ .name = "see_rook", .default = tunable_defaults.see_rook },
    .{ .name = "see_queen", .default = tunable_defaults.see_queen },
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
    pub var see_pawn = tunable_defaults.see_pawn;
    pub var see_knight = tunable_defaults.see_knight;
    pub var see_bishop = tunable_defaults.see_bishop;
    pub var see_rook = tunable_defaults.see_rook;
    pub var see_queen = tunable_defaults.see_queen;
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
    pub var singular_dext_margin = tunable_defaults.singular_dext_margin;
} else tunable_defaults;

comptime {
    std.debug.assert(std.meta.declarations(tunable_defaults).len == tunables.len);
    std.debug.assert(std.meta.declarations(tunable_constants).len == tunables.len);
}
