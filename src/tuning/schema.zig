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

pub const ScalarTunable = struct {
    default: ?i32 = null, // read from OB spsa output if not specified
    min: ?i32 = null,
    max: ?i32 = null,
    c_end: ?f64 = null,

    fn margin(self: ScalarTunable) i32 {
        const default = self.default orelse 0;
        return 10 + (default * std.math.sign(default) >> 1);
    }

    pub fn getMin(self: ScalarTunable) i32 {
        if (self.min) |m| {
            return m;
        }
        const default = self.default orelse 0;
        if (default > 0) {
            return 0;
        }
        if (default < 0) {
            return default - self.margin();
        }
        std.debug.panic("0 default tunables must define an explicit min", .{});
    }

    pub fn getMax(self: ScalarTunable) i32 {
        if (self.max) |m| {
            return m;
        }
        const default = self.default orelse 0;
        if (default > 0) {
            return default + self.margin();
        }
        if (default < 0) {
            return 0;
        }
        std.debug.panic("0 default tunables must define an explicit max", .{});
    }

    pub fn getCEnd(self: ScalarTunable) f64 {
        if (self.c_end) |m| {
            return m;
        }
        const range: f64 = @floatFromInt(self.getMax() - self.getMin());
        return range / 20.0;
    }
};

pub const Literal = struct {
    name: []const u8,
    negated: bool = false,
};

pub const Constraint = struct {
    lhs: Literal,
    rhs: Literal,
};

fn asLiteral(value: anytype) Literal {
    const T = @TypeOf(value);
    return switch (T) {
        Literal => value,
        else => switch (@typeInfo(T)) {
            .pointer, .array => .{ .name = value },
            else => @compileError("expected a string-like value, Literal, or *const Literal"),
        },
    };
}

pub fn not(comptime name: []const u8) Literal {
    return .{ .name = name, .negated = true };
}

pub fn implies(lhs: anytype, rhs: anytype) Constraint {
    return .{
        .lhs = asLiteral(lhs),
        .rhs = asLiteral(rhs),
    };
}

pub const FactorizedTunable = struct {
    inputs: []const []const u8,
    constraints: []const Constraint = &.{},
    max_order: usize,
    min: i32,
    max: i32,
    c_end: f64,

    pub fn getMin(self: FactorizedTunable) i32 {
        return self.min;
    }

    pub fn getMax(self: FactorizedTunable) i32 {
        return self.max;
    }

    pub fn getCEnd(self: FactorizedTunable) f64 {
        return self.c_end;
    }
};

pub const Tunable = union(enum) {
    Scalar: ScalarTunable,
    Factorized: FactorizedTunable,

    pub fn getMin(self: Tunable) i32 {
        return switch (self) {
            inline else => |underlying| underlying.getMin(),
        };
    }

    pub fn getMax(self: Tunable) i32 {
        return switch (self) {
            inline else => |underlying| underlying.getMax(),
        };
    }

    pub fn getCEnd(self: Tunable) f64 {
        return switch (self) {
            inline else => |underlying| underlying.getCEnd(),
        };
    }
};

pub fn scalar(spec: ScalarTunable) Tunable {
    return .{ .Scalar = spec };
}

pub fn factorized(spec: FactorizedTunable) Tunable {
    return .{ .Factorized = spec };
}

pub fn factorizedOrderFieldName(comptime order: usize) [:0]const u8 {
    @setEvalBranchQuota(1 << 20);
    const name = std.fmt.comptimePrint("{d}", .{order + 1});
    return name[0..name.len :0];
}

pub fn factorizedInputIndex(spec: FactorizedTunable, name: []const u8) usize {
    for (spec.inputs, 0..) |input, i| {
        if (std.mem.eql(u8, input, name)) {
            return i;
        }
    }
    std.debug.panic("unknown factorized input '{s}'", .{name});
}

fn choose(n: usize, k: usize) usize {
    var result: usize = 1;
    for (0..@min(k, n - k)) |i| {
        result = result * (n - i) / (i + 1);
    }
    return result;
}

pub inline fn factorizedInteractionCount(spec: FactorizedTunable, order: usize) usize {
    return choose(spec.inputs.len, order + 1);
}

pub const SCHEMA = .{
    .factorized_lmr = factorized(.{
        .inputs = &.{
            "pv",
            "cutnode",
            "improving",
            "ttmove",
            "ttpv",
            "quiet",
            "givescheck",
            "root",
            "2failhighs",
        },
        .constraints = &.{
            implies("pv", "ttpv"),
            implies("pv", not("cutnode")),
            implies("cutnode", not("pv")),
            implies("root", "pv"),
        },
        .max_order = 3,
        .min = -2048,
        .max = 2048,
        .c_end = 128,
    }),

    .quiet_bonus_mult = scalar(.{}),
    .quiet_bonus_offs = scalar(.{}),
    .quiet_bonus_max = scalar(.{}),
    .quiet_penalty_mult = scalar(.{}),
    .quiet_penalty_offs = scalar(.{}),
    .quiet_penalty_max = scalar(.{}),

    .pawn_bonus_mult = scalar(.{}),
    .pawn_bonus_offs = scalar(.{}),
    .pawn_bonus_max = scalar(.{}),
    .pawn_penalty_mult = scalar(.{}),
    .pawn_penalty_offs = scalar(.{}),
    .pawn_penalty_max = scalar(.{}),

    .cont1_bonus_mult = scalar(.{}),
    .cont1_bonus_offs = scalar(.{}),
    .cont1_bonus_max = scalar(.{}),
    .cont1_penalty_mult = scalar(.{}),
    .cont1_penalty_offs = scalar(.{}),
    .cont1_penalty_max = scalar(.{}),

    .cont2_bonus_mult = scalar(.{}),
    .cont2_bonus_offs = scalar(.{}),
    .cont2_bonus_max = scalar(.{}),
    .cont2_penalty_mult = scalar(.{}),
    .cont2_penalty_offs = scalar(.{}),
    .cont2_penalty_max = scalar(.{}),

    .cont4_bonus_mult = scalar(.{}),
    .cont4_bonus_offs = scalar(.{}),
    .cont4_bonus_max = scalar(.{}),
    .cont4_penalty_mult = scalar(.{}),
    .cont4_penalty_offs = scalar(.{}),
    .cont4_penalty_max = scalar(.{}),

    .noisy_bonus_mult = scalar(.{}),
    .noisy_bonus_offs = scalar(.{}),
    .noisy_bonus_max = scalar(.{}),
    .noisy_penalty_mult = scalar(.{}),
    .noisy_penalty_offs = scalar(.{}),
    .noisy_penalty_max = scalar(.{}),

    .eval_hist_min = scalar(.{}),
    .eval_hist_max = scalar(.{}),
    .eval_hist_offs = scalar(.{}),
    .eval_hist_mult = scalar(.{}),
    .high_eval_offs = scalar(.{}),
    .faillow_mult = scalar(.{}),

    .ord_quiet_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ord_pawn_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ord_cont1_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ord_cont2_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ord_cont4_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ord_direct_check_bonus = scalar(.{ .min = 0, .max = 8192, .c_end = 256 }),
    .ord_from_danger_pawn_bonus = scalar(.{ .min = 0, .max = 16384, .c_end = 512 }),
    .ord_from_danger_knight_bonus = scalar(.{ .min = 0, .max = 16384, .c_end = 512 }),
    .ord_from_danger_bishop_bonus = scalar(.{ .min = 0, .max = 16384, .c_end = 512 }),
    .ord_from_danger_rook_bonus = scalar(.{ .min = 0, .max = 16384, .c_end = 512 }),
    .ord_from_danger_queen_bonus = scalar(.{ .min = 0, .max = 16384, .c_end = 512 }),
    .ord_from_danger_king_bonus = scalar(.{ .min = 0, .max = 16384, .c_end = 512 }),
    .ord_to_danger_pawn_penalty = scalar(.{ .min = 0, .max = 8192, .c_end = 256 }),
    .ord_to_danger_knight_penalty = scalar(.{ .min = 0, .max = 8192, .c_end = 256 }),
    .ord_to_danger_bishop_penalty = scalar(.{ .min = 0, .max = 8192, .c_end = 256 }),
    .ord_to_danger_rook_penalty = scalar(.{ .min = 0, .max = 8192, .c_end = 256 }),
    .ord_to_danger_queen_penalty = scalar(.{ .min = 0, .max = 8192, .c_end = 256 }),

    .rfp_hist_quiet_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .rfp_hist_pawn_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .rfp_hist_cont1_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .rfp_hist_cont2_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .rfp_hist_cont4_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .rfp_hist_noisy_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),

    .lmr_depth_hist_quiet_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_depth_hist_pawn_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_depth_hist_cont1_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_depth_hist_cont2_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_depth_hist_cont4_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_depth_hist_noisy_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),

    .lmr_hist_quiet_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_hist_pawn_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_hist_cont1_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_hist_cont2_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_hist_cont4_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .lmr_hist_noisy_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),

    .fp_hist_quiet_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .fp_hist_pawn_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .fp_hist_cont1_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .fp_hist_cont2_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .fp_hist_cont4_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),

    .hp_hist_quiet_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .hp_hist_pawn_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .hp_hist_cont1_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .hp_hist_cont2_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .hp_hist_cont4_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .hp_hist_noisy_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),

    .rfp_min_margin = scalar(.{}),
    .rfp_base = scalar(.{}),
    .rfp_mult = scalar(.{}),
    .rfp_quad = scalar(.{}),
    .rfp_improving_margin = scalar(.{}),
    .rfp_easy_margin = scalar(.{ .min = -50, .max = 50, .c_end = 5 }),
    .rfp_improving_easy_margin = scalar(.{}),
    .rfp_worsening_margin = scalar(.{ .min = -10, .max = 45, .c_end = 1 }),
    .rfp_cutnode_margin = scalar(.{ .min = -10, .max = 55, .c_end = 1 }),
    .rfp_corrplexity_mult = scalar(.{ .min = -10, .max = 60, .c_end = 2 }),
    .rfp_history_mult = scalar(.{}),
    .rfp_noisy_history_mult = scalar(.{}),

    .aspiration_score_mult = scalar(.{ .min = 10, .max = 4096, .c_end = 32 }),
    .aspiration_initial = scalar(.{ .min = 10, .max = 39450, .c_end = 1577 }),
    .aspiration_multiplier = scalar(.{ .min = 1127, .max = 4015, .c_end = 160 }),
    .failhigh_add = scalar(.{}),
    .failhigh_mult = scalar(.{}),
    .failhigh_max = scalar(.{}),

    .lmr_quiet_base = scalar(.{ .min = -10, .max = 6772, .c_end = 270 }),
    .lmr_noisy_base = scalar(.{ .min = -10, .max = 4412, .c_end = 176 }),
    .lmr_quiet_depth_mult = scalar(.{ .min = -10, .max = 1895, .c_end = 75 }),
    .lmr_noisy_depth_mult = scalar(.{ .min = -10, .max = 2132, .c_end = 84 }),
    .lmr_quiet_depth_offs = scalar(.{ .min = -1024, .max = 1024, .c_end = 32 }),
    .lmr_noisy_depth_offs = scalar(.{ .min = -1024, .max = 1024, .c_end = 32 }),
    .lmr_quiet_legal_mult = scalar(.{ .min = -10, .max = 2302, .c_end = 91 }),
    .lmr_noisy_legal_mult = scalar(.{ .min = -10, .max = 2357, .c_end = 93 }),
    .lmr_quiet_legal_offs = scalar(.{ .min = -1024, .max = 1024, .c_end = 32 }),
    .lmr_noisy_legal_offs = scalar(.{ .min = -1024, .max = 1024, .c_end = 32 }),
    .lmr_quiet_history_mult = scalar(.{ .min = -10, .max = 1975, .c_end = 78 }),
    .lmr_noisy_history_mult = scalar(.{ .min = -10, .max = 2470, .c_end = 98 }),

    .lmr_corrhist_mult = scalar(.{ .min = -10, .max = 23695, .c_end = 947 }),
    .lmr_alpha_raise_mult = scalar(.{}),
    .lmr_ttpv_depth = scalar(.{}),
    .lmr_ttpv_score = scalar(.{}),
    .lmr_dodeeper_margin = scalar(.{}),
    .lmr_dodeeper_mult = scalar(.{}),
    .lmr_do_even_deeper_margin = scalar(.{}),
    .lmr_doshallower_margin = scalar(.{}),
    .lmr_doshallower_mult = scalar(.{}),

    .hindsight_ext_margin = scalar(.{}),
    .nmp_margin_base = scalar(.{}),
    .nmp_margin_mult = scalar(.{}),
    .nmp_base = scalar(.{}),
    .nmp_mult = scalar(.{}),

    .probcut_margin = scalar(.{}),
    .probcut_improving_margin = scalar(.{}),
    .probcut_see_mult = scalar(.{}),

    .fp_depth_limit = scalar(.{}),
    .fp_base = scalar(.{}),
    .fp_mult = scalar(.{}),
    .fp_pv_base = scalar(.{}),
    .fp_pv_mult = scalar(.{}),
    .fp_improving = scalar(.{}),
    .fp_hist_mult = scalar(.{}),

    .bnfp_depth_limit = scalar(.{}),
    .bnfp_base = scalar(.{}),
    .bnfp_mult = scalar(.{}),
    .bnfp_captured = scalar(.{}),

    .see_quiet_pruning_offs = scalar(.{ .min = -100, .max = 100, .c_end = 20 }),
    .see_noisy_pruning_offs = scalar(.{ .min = -100, .max = 100, .c_end = 5 }),
    .see_quiet_pruning_mult = scalar(.{ .c_end = 5, .min = -20, .max = 20 }),
    .see_noisy_pruning_mult = scalar(.{ .c_end = 5, .min = -20, .max = 20 }),
    .see_quiet_pruning_quad = scalar(.{}),
    .see_noisy_pruning_quad = scalar(.{}),
    .see_pv_offs = scalar(.{}),

    .razoring_offs = scalar(.{}),
    .razoring_mult = scalar(.{}),
    .razoring_quad = scalar(.{}),
    .razoring_easy_capture = scalar(.{ .min = -1024, .max = 1024, .c_end = 10 }),

    .history_pruning_depth_limit = scalar(.{}),
    .history_pruning_offs = scalar(.{}),
    .history_pruning_mult = scalar(.{}),

    .noisy_history_pruning_depth_limit = scalar(.{}),
    .noisy_history_pruning_offs = scalar(.{}),
    .noisy_history_pruning_mult = scalar(.{}),

    .qs_futility_margin = scalar(.{}),
    .qs_hp_margin = scalar(.{}),
    .qs_see_threshold = scalar(.{}),
    .qs_alpha_eval_diff_mult = scalar(.{ .default = 128, .min = -1024, .max = 1024, .c_end = 64 }),

    .corrhist_pawn_weight = scalar(.{}),
    .corrhist_nonpawn_weight = scalar(.{}),
    .corrhist_prev_weight = scalar(.{}),
    .corrhist_followup_weight = scalar(.{}),
    .corrhist_major_weight = scalar(.{}),
    .corrhist_minor_weight = scalar(.{}),
    .corrhist_pawn_update_weight = scalar(.{}),
    .corrhist_nonpawn_update_weight = scalar(.{}),
    .corrhist_prev_update_weight = scalar(.{}),
    .corrhist_followup_update_weight = scalar(.{}),
    .corrhist_major_update_weight = scalar(.{}),
    .corrhist_minor_update_weight = scalar(.{}),

    .lmp_standard_base = scalar(.{ .min = 10, .max = 9345, .c_end = 300 }),
    .lmp_improving_base = scalar(.{ .min = 10, .max = 7580, .c_end = 300 }),
    .lmp_standard_linear_mult = scalar(.{ .min = -1024, .max = 1024, .c_end = 50 }),
    .lmp_improving_linear_mult = scalar(.{ .min = -1024, .max = 1024, .c_end = 50 }),
    .lmp_standard_quadratic_mult = scalar(.{ .min = -10, .max = 2177, .c_end = 40 }),
    .lmp_improving_quadratic_mult = scalar(.{ .min = -10, .max = 2717, .c_end = 100 }),
    .lmp_direct_check_bonus = scalar(.{ .default = 1024, .min = 0, .max = 4096, .c_end = 128 }),

    .good_noisy_ordering_base = scalar(.{ .min = -2048, .max = 2048, .c_end = 32 }),
    .good_noisy_ordering_mult = scalar(.{ .min = -10, .max = 2570, .c_end = 102 }),

    .mvv_mult = scalar(.{ .min = 1, .max = 2048, .c_end = 128 }),

    .see_pawn_pruning = scalar(.{}),
    .see_knight_pruning = scalar(.{}),
    .see_bishop_pruning = scalar(.{}),
    .see_rook_pruning = scalar(.{}),
    .see_queen_pruning = scalar(.{}),
    .see_pawn_ordering = scalar(.{}),
    .see_knight_ordering = scalar(.{}),
    .see_bishop_ordering = scalar(.{}),
    .see_rook_ordering = scalar(.{}),
    .see_queen_ordering = scalar(.{}),

    .material_scaling_base = scalar(.{}),
    .material_scaling_pawn = scalar(.{}),
    .material_scaling_knight = scalar(.{}),
    .material_scaling_bishop = scalar(.{}),
    .material_scaling_rook = scalar(.{}),
    .material_scaling_queen = scalar(.{}),

    .rfp_fail_medium = scalar(.{ .min = 0, .max = 1024, .c_end = 128 }),
    .tt_fail_medium = scalar(.{ .min = 0, .max = 1024, .c_end = 128 }),
    .qs_tt_fail_medium = scalar(.{ .min = 0, .max = 1024, .c_end = 128 }),
    .standpat_fail_medium = scalar(.{ .min = 0, .max = 1024, .c_end = 128 }),
    .qs_fail_medium = scalar(.{ .min = 0, .max = 1024, .c_end = 128 }),
    .probcut_fail_medium = scalar(.{ .min = 0, .max = 1024, .c_end = 128 }),
    .nodetm_base = scalar(.{ .min = 1024, .c_end = 40 }),
    .nodetm_mult = scalar(.{ .min = 10, .c_end = 25 }),

    .eval_stab_margin = scalar(.{ .min = 1, .c_end = 0.5 }),
    .eval_stab_base = scalar(.{ .min = 10, .c_end = 30 }),
    .eval_stab_offs = scalar(.{ .min = 10, .c_end = 2.5 }),
    .eval_stab_lim = scalar(.{ .min = 10, .c_end = 20 }),
    .move_stab_base = scalar(.{ .min = 10, .c_end = 30 }),
    .move_stab_offs = scalar(.{ .min = 10, .c_end = 2.5 }),
    .move_stab_lim = scalar(.{ .min = 10, .c_end = 20 }),
    .soft_limit_base = scalar(.{ .min = 10, .c_end = 2.5 }),
    .soft_limit_incr = scalar(.{ .min = 10, .c_end = 15 }),
    .hard_limit_phase_mult = scalar(.{ .min = 10, .c_end = 3 }),
    .hard_limit_base = scalar(.{ .min = 10, .c_end = 5 }),

    .singular_beta_mult = scalar(.{ .min = 10, .max = 992, .c_end = 39 }),
    .singular_beta_pv_mult = scalar(.{ .min = 10, .max = 992, .c_end = 39 }),
    .singular_beta_ttpv_mult = scalar(.{ .min = 10, .max = 992, .c_end = 39 }),
    .singular_depth_mult = scalar(.{ .min = 10, .max = 1565, .c_end = 62 }),
    .singular_depth_offs = scalar(.{ .min = 10, .max = 1837, .c_end = 73 }),
    .singular_dext_margin_quiet = scalar(.{ .min = 0, .max = 16, .c_end = 1 }),
    .singular_dext_margin_noisy = scalar(.{ .min = 0, .max = 14, .c_end = 1 }),
    .singular_dext_pv_margin = scalar(.{ .min = 0, .max = 22, .c_end = 1 }),
    .singular_text_margin_quiet = scalar(.{ .min = 0, .max = 70, .c_end = 5 }),
    .singular_text_margin_noisy = scalar(.{ .min = 0, .max = 76, .c_end = 5 }),
    .singular_text_pv_margin = scalar(.{ .min = 0, .max = 507, .c_end = 25 }),

    .ttpick_depth_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ttpick_age_weight = scalar(.{ .min = 0, .max = 8192, .c_end = 256 }),
    .ttpick_pv_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ttpick_lower_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ttpick_upper_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ttpick_exact_weight = scalar(.{ .min = 0, .max = 2048, .c_end = 128 }),
    .ttpick_move_weight = scalar(.{ .min = 0, .max = 8192, .c_end = 256 }),

    .voting_score_max = scalar(.{}),
    .voting_score_offset = scalar(.{}),
    .voting_depth_offset = scalar(.{}),
    .voting_offset = scalar(.{ .min = -1000, .max = 1000, .c_end = 100 }),
};
