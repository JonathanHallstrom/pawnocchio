const std = @import("std");
const tuning_schema = @import("schema.zig");

inline fn getValue(
    comptime spec: tuning_schema.FactorizedTunable,
    values: anytype,
    order: u8,
    index: usize,
) i32 {
    inline for (0..spec.max_order) |order_idx| {
        if (order == order_idx) {
            return @field(values, tuning_schema.factorizedOrderFieldName(order_idx))[index];
        }
    }
    unreachable;
}

fn setValue(
    comptime spec: tuning_schema.FactorizedTunable,
    values: anytype,
    order: u8,
    index: usize,
    value: i32,
) void {
    inline for (0..spec.max_order) |order_idx| {
        if (order == order_idx) {
            @field(values.*, tuning_schema.factorizedOrderFieldName(order_idx))[index] = value;
            return;
        }
    }
    unreachable;
}

pub fn Family(comptime cfg: anytype) type {
    const Values = @TypeOf(cfg.defaults);
    const Tunables = @TypeOf(cfg.tunables);
    const family_spec = cfg.spec;
    const family_enabled = cfg.enabled;

    return struct {
        pub const enabled = family_enabled;
        pub const spec = family_spec;
        pub const input_count = spec.inputs.len;
        pub const defaults: Values = cfg.defaults;
        pub const tunables: Tunables = cfg.tunables;

        const storage = if (enabled) struct {
            pub var value: Values = defaults;
        } else struct {
            pub const value: Values = defaults;
        };

        pub const values = &storage.value;

        pub inline fn get(order: u8, index: usize) i32 {
            return getValue(spec, values.*, order, index);
        }

        pub inline fn set(order: u8, index: usize, value: i32) void {
            if (!enabled) unreachable;
            setValue(spec, &storage.value, order, index, value);
        }

        pub inline fn trySet(option_name: []const u8, value: i32) bool {
            if (!enabled) {
                return false;
            }

            inline for (tunables) |tunable| {
                if (std.ascii.eqlIgnoreCase(tunable.name, option_name)) {
                    set(tunable.order, tunable.index, value);
                    return true;
                }
            }
            return false;
        }
    };
}
