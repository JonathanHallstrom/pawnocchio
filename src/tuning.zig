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
const factorized = @import("tuning/factorized.zig");
const tuning_schema = @import("tuning/schema.zig");
const tuning_generated = @import("tuning_generated");

pub const DO_TUNING = false;
pub const DO_FACTORIZED_TUNING = true;

pub const Tunable = tuning_generated.Tunable;
pub const FactorizedTunable = tuning_generated.FactorizedTunable;

pub const TunableParam = struct {
    name: []const u8,
    default: i32,
    min: i32,
    max: i32,
    c_end: f64,
    current: i32,
};

pub fn setMin() void {
    if (!DO_TUNING) {
        return;
    }
    inline for (TUNABLES) |tunable| {
        @field(TUNABLE_CONSTANTS.*, tunable.name) = tunable.min;
    }
}
pub fn setMax() void {
    if (!DO_TUNING) {
        return;
    }
    inline for (TUNABLES) |tunable| {
        @field(TUNABLE_CONSTANTS.*, tunable.name) = tunable.max;
    }
}

const QuietHistoryWeights = struct {
    quiet: i32,
    pawn: i32,
    cont1: i32,
    cont2: i32,
    cont4: i32,
};

pub const HistoryWeights = struct {
    q: QuietHistoryWeights,
    n: i32,
};

pub inline fn quietHistoryWeights(comptime prefix: []const u8) QuietHistoryWeights {
    return .{
        .quiet = @field(TUNABLE_CONSTANTS.*, prefix ++ "_quiet_weight"),
        .pawn = @field(TUNABLE_CONSTANTS.*, prefix ++ "_pawn_weight"),
        .cont1 = @field(TUNABLE_CONSTANTS.*, prefix ++ "_cont1_weight"),
        .cont2 = @field(TUNABLE_CONSTANTS.*, prefix ++ "_cont2_weight"),
        .cont4 = @field(TUNABLE_CONSTANTS.*, prefix ++ "_cont4_weight"),
    };
}

pub inline fn historyWeights(comptime prefix: []const u8) HistoryWeights {
    return .{
        .q = quietHistoryWeights(prefix),
        .n = @field(TUNABLE_CONSTANTS.*, prefix ++ "_noisy_weight"),
    };
}

pub inline fn histQ(terms: anytype, weights: QuietHistoryWeights) i32 {
    return @divTrunc(
        terms.quiet * weights.quiet +
            terms.pawn * weights.pawn +
            terms.cont1 * weights.cont1 +
            terms.cont2 * weights.cont2 +
            terms.cont4 * weights.cont4,
        1024,
    );
}

pub inline fn histN(terms: anytype, weight: i32) i32 {
    return @divTrunc(terms.noisy * weight, 1024);
}

pub const TunableValues = tuning_generated.TunableValues;
pub const TUNABLE_DEFAULTS: TunableValues = tuning_generated.tunable_defaults;
pub const TUNABLES = tuning_generated.tunables;

const TUNABLE_CONSTANTS_STORAGE = if (DO_TUNING) struct {
    pub var value: TunableValues = TUNABLE_DEFAULTS;
} else struct {
    pub const value: TunableValues = TUNABLE_DEFAULTS;
};

pub const TUNABLE_CONSTANTS = &TUNABLE_CONSTANTS_STORAGE.value;

pub const FACTORIZED_LMR = factorized.Family(.{
    .enabled = DO_FACTORIZED_TUNING,
    .spec = tuning_schema.SCHEMA.factorized_lmr.Factorized,
    .defaults = tuning_generated.factorized_lmr_defaults,
    .tunables = tuning_generated.factorized_lmr_tunables,
});
pub const FACTORIZED_LMP = factorized.Family(.{
    .enabled = DO_FACTORIZED_TUNING,
    .spec = tuning_schema.SCHEMA.factorized_lmp.Factorized,
    .defaults = tuning_generated.factorized_lmp_defaults,
    .tunables = tuning_generated.factorized_lmp_tunables,
});

pub fn forEachTunable(
    comptime Context: type,
    ctx: *Context,
    comptime visit: fn (*Context, TunableParam) void,
) void {
    inline for (TUNABLES) |tunable| {
        visit(ctx, .{
            .name = tunable.name,
            .default = tunable.default,
            .min = tunable.min,
            .max = tunable.max,
            .c_end = tunable.c_end,
            .current = @field(TUNABLE_CONSTANTS.*, tunable.name),
        });
    }

    if (FACTORIZED_LMR.enabled) {
        inline for (FACTORIZED_LMR.tunables) |tunable| {
            visit(ctx, .{
                .name = tunable.name,
                .default = tunable.default,
                .min = tunable.min,
                .max = tunable.max,
                .c_end = tunable.c_end,
                .current = FACTORIZED_LMR.get(tunable.order, tunable.index),
            });
        }
    }

    if (FACTORIZED_LMP.enabled) {
        inline for (FACTORIZED_LMP.tunables) |tunable| {
            visit(ctx, .{
                .name = tunable.name,
                .default = tunable.default,
                .min = tunable.min,
                .max = tunable.max,
                .c_end = tunable.c_end,
                .current = FACTORIZED_LMP.get(tunable.order, tunable.index),
            });
        }
    }
}

pub fn trySetTunable(option_name: []const u8, value: i32) bool {
    if (DO_TUNING) {
        inline for (TUNABLES) |tunable| {
            if (std.ascii.eqlIgnoreCase(tunable.name, option_name)) {
                @field(TUNABLE_CONSTANTS.*, tunable.name) = value;
                return true;
            }
        }
    }

    if (FACTORIZED_LMR.trySet(option_name, value)) {
        return true;
    }

    if (FACTORIZED_LMP.trySet(option_name, value)) {
        return true;
    }

    return false;
}
