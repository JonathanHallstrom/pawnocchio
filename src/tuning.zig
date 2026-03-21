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

pub const do_tuning = false;
pub const do_factorized_tuning = false;

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
    if (!do_tuning) {
        return;
    }
    inline for (tunables) |tunable| {
        @field(tunable_constants.*, tunable.name) = tunable.min;
    }
}
pub fn setMax() void {
    if (!do_tuning) {
        return;
    }
    inline for (tunables) |tunable| {
        @field(tunable_constants.*, tunable.name) = tunable.max;
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
        .quiet = @field(tunable_constants.*, prefix ++ "_quiet_weight"),
        .pawn = @field(tunable_constants.*, prefix ++ "_pawn_weight"),
        .cont1 = @field(tunable_constants.*, prefix ++ "_cont1_weight"),
        .cont2 = @field(tunable_constants.*, prefix ++ "_cont2_weight"),
        .cont4 = @field(tunable_constants.*, prefix ++ "_cont4_weight"),
    };
}

pub inline fn historyWeights(comptime prefix: []const u8) HistoryWeights {
    return .{
        .q = quietHistoryWeights(prefix),
        .n = @field(tunable_constants.*, prefix ++ "_noisy_weight"),
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
pub const tunable_defaults: TunableValues = tuning_generated.tunable_defaults;
pub const tunables = tuning_generated.tunables;

const tunable_constants_storage = if (do_tuning) struct {
    pub var value: TunableValues = tunable_defaults;
} else struct {
    pub const value: TunableValues = tunable_defaults;
};

pub const tunable_constants = &tunable_constants_storage.value;

pub const factorized_lmr = factorized.Family(.{
    .enabled = do_factorized_tuning,
    .spec = tuning_schema.schema.factorized_lmr.Factorized,
    .defaults = tuning_generated.factorized_lmr_defaults,
    .tunables = tuning_generated.factorized_lmr_tunables,
});

pub fn forEachTunable(
    comptime Context: type,
    ctx: *Context,
    comptime visit: fn (*Context, TunableParam) void,
) void {
    inline for (tunables) |tunable| {
        visit(ctx, .{
            .name = tunable.name,
            .default = tunable.default,
            .min = tunable.min,
            .max = tunable.max,
            .c_end = tunable.c_end,
            .current = @field(tunable_constants.*, tunable.name),
        });
    }

    if (factorized_lmr.enabled) {
        inline for (factorized_lmr.tunables) |tunable| {
            visit(ctx, .{
                .name = tunable.name,
                .default = tunable.default,
                .min = tunable.min,
                .max = tunable.max,
                .c_end = tunable.c_end,
                .current = factorized_lmr.get(tunable.order, tunable.index),
            });
        }
    }
}

pub fn trySetTunable(option_name: []const u8, value: i32) bool {
    if (do_tuning) {
        inline for (tunables) |tunable| {
            if (std.ascii.eqlIgnoreCase(tunable.name, option_name)) {
                @field(tunable_constants.*, tunable.name) = value;
                return true;
            }
        }
    }

    if (factorized_lmr.trySet(option_name, value)) {
        return true;
    }

    return false;
}
