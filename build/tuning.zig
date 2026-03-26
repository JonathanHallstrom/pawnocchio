const std = @import("std");

const tuning_schema = @import("../src/tuning/schema.zig");
const TuningSchema = @TypeOf(tuning_schema.SCHEMA);
const TuningSchemaField = std.meta.FieldEnum(TuningSchema);
const ResolvedTunables = std.EnumArray(TuningSchemaField, tuning_schema.Tunable);

fn FactorizedFamilyValues(comptime spec: tuning_schema.FactorizedTunable, comptime Value: type) type {
    comptime var fields: [spec.max_order]std.builtin.Type.StructField = undefined;
    inline for (0..spec.max_order) |order| {
        const field_type = [tuning_schema.factorizedInteractionCount(spec, order)]Value;
        fields[order] = .{
            .name = tuning_schema.factorizedOrderFieldName(order),
            .type = field_type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(field_type),
        };
    }
    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn initFactorizedFamilyValues(
    comptime spec: tuning_schema.FactorizedTunable,
    comptime Value: type,
    value: Value,
) FactorizedFamilyValues(spec, Value) {
    var family: FactorizedFamilyValues(spec, Value) = undefined;
    inline for (0..spec.max_order) |order| {
        @field(family, tuning_schema.factorizedOrderFieldName(order)) =
            [_]Value{value} ** tuning_schema.factorizedInteractionCount(spec, order);
    }
    return family;
}

fn getFactorizedFamilyValuePtr(
    family: anytype,
    comptime order: usize,
    comptime index: usize,
) @TypeOf(&@field(family.*, tuning_schema.factorizedOrderFieldName(order))[index]) {
    return &@field(family.*, tuning_schema.factorizedOrderFieldName(order))[index];
}

fn FactorizedResolvedType(comptime Value: type) type {
    comptime var field_count = 0;
    inline for (std.meta.fields(TuningSchema)) |field| {
        switch (@field(tuning_schema.SCHEMA, field.name)) {
            .Factorized => field_count += 1,
            else => {},
        }
    }

    comptime var fields: [field_count]std.builtin.Type.StructField = undefined;
    comptime var i = 0;
    inline for (std.meta.fields(TuningSchema)) |field| {
        switch (@field(tuning_schema.SCHEMA, field.name)) {
            .Factorized => |spec| {
                const field_type = FactorizedFamilyValues(spec, Value);
                fields[i] = .{
                    .name = field.name,
                    .type = field_type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field_type),
                };
                i += 1;
            },
            else => {},
        }
    }
    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn factorizedNameMaxLen(comptime family_name: []const u8, comptime spec: tuning_schema.FactorizedTunable) usize {
    comptime var len = family_name.len;
    inline for (spec.inputs) |input| {
        len += 1 + input.len;
    }
    return len;
}

fn writeFactorizedParamNameRec(
    buf: []u8,
    len: *usize,
    spec: tuning_schema.FactorizedTunable,
    choose_count: usize,
    start: usize,
    target_index: *usize,
) bool {
    if (choose_count == 0) {
        if (target_index.* == 0) {
            return true;
        }
        target_index.* -= 1;
        return false;
    }

    for (start..spec.inputs.len - choose_count + 1) |i| {
        const before = len.*;
        if (before != 0) {
            buf[len.*] = '_';
            len.* += 1;
        }
        @memcpy(buf[len.* .. len.* + spec.inputs[i].len], spec.inputs[i]);
        len.* += spec.inputs[i].len;
        if (writeFactorizedParamNameRec(buf, len, spec, choose_count - 1, i + 1, target_index)) {
            return true;
        }
        len.* = before;
    }

    return false;
}

fn factorizedParamNameInto(
    buf: []u8,
    comptime family_name: []const u8,
    comptime spec: tuning_schema.FactorizedTunable,
    comptime order: usize,
    comptime index: usize,
) []const u8 {
    @memcpy(buf[0..family_name.len], family_name);
    var len = family_name.len;
    var remaining_index = index;
    if (!writeFactorizedParamNameRec(buf, &len, spec, order + 1, 0, &remaining_index)) {
        @panic("invalid factorized interaction index");
    }
    return buf[0..len];
}

const ResolvedFactorizedTunables = FactorizedResolvedType(i32);
const ResolvedTuning = struct {
    tunables: ResolvedTunables,
    factorized: ResolvedFactorizedTunables,
};

fn initResolvedFactorizedTunables() ResolvedFactorizedTunables {
    var resolved: ResolvedFactorizedTunables = undefined;
    inline for (std.meta.fields(TuningSchema)) |field| {
        switch (@field(tuning_schema.SCHEMA, field.name)) {
            .Factorized => |spec| {
                @field(resolved, field.name) = initFactorizedFamilyValues(spec, i32, 0);
            },
            else => {},
        }
    }
    return resolved;
}

fn trySetFactorizedValue(resolved: *ResolvedFactorizedTunables, line_name: []const u8, value: i32) bool {
    inline for (std.meta.fields(TuningSchema)) |field| {
        switch (@field(tuning_schema.SCHEMA, field.name)) {
            .Factorized => |spec| {
                inline for (0..spec.max_order) |order| {
                    const count = comptime tuning_schema.factorizedInteractionCount(spec, order);
                    inline for (0..count) |index| {
                        var name_buf: [factorizedNameMaxLen(field.name, spec)]u8 = undefined;
                        const name = factorizedParamNameInto(&name_buf, field.name, spec, order, index);
                        if (std.ascii.eqlIgnoreCase(name, line_name)) {
                            getFactorizedFamilyValuePtr(&@field(resolved.*, field.name), order, index).* = value;
                            return true;
                        }
                    }
                }
            },
            else => {},
        }
    }

    return false;
}

fn resolveTuning(params_text: []const u8) !ResolvedTuning {
    @setEvalBranchQuota(1 << 24);
    var resolved = ResolvedTunables.initUndefined();
    inline for (std.meta.fields(TuningSchema)) |field| {
        resolved.set(
            @field(TuningSchemaField, field.name),
            @field(tuning_schema.SCHEMA, field.name),
        );
    }
    var resolved_factorized = initResolvedFactorizedTunables();

    var lines = std.mem.tokenizeScalar(u8, params_text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, &std.ascii.whitespace);
        if (line.len == 0 or line[0] == '#') {
            continue;
        }

        var parts = std.mem.tokenizeScalar(u8, line, ',');
        const line_name = std.mem.trim(u8, parts.next() orelse return error.InvalidParamsLine, &std.ascii.whitespace);
        const value_text = std.mem.trim(u8, parts.next() orelse return error.InvalidParamsLine, &std.ascii.whitespace);
        const value = try std.fmt.parseInt(i32, value_text, 10);

        if (std.meta.stringToEnum(TuningSchemaField, line_name)) |field| {
            switch (resolved.getPtr(field).*) {
                .Scalar => |*spec| {
                    spec.default = value;
                    continue;
                },
                .Factorized => {},
            }
        }
        if (!trySetFactorizedValue(&resolved_factorized, line_name, value)) {
            std.log.err("unknown tuning param '{s}' in defaults.txt", .{line_name});
            return error.UnknownTuningParam;
        }
    }

    var iter = resolved.iterator();
    while (iter.next()) |entry| {
        switch (entry.value.*) {
            .Scalar => |spec| {
                if (spec.default == null) {
                    std.log.err("missing value for param '{s}'", .{@tagName(entry.key)});
                    return error.MissingTuningParam;
                }
            },
            .Factorized => {},
        }
    }
    return .{
        .tunables = resolved,
        .factorized = resolved_factorized,
    };
}

fn emitGeneratedFactorizedDefaults(
    writer: anytype,
    resolved_factorized: ResolvedFactorizedTunables,
) !void {
    inline for (std.meta.fields(TuningSchema)) |field| {
        switch (@field(tuning_schema.SCHEMA, field.name)) {
            .Factorized => |spec| {
                const family = @field(resolved_factorized, field.name);

                try writer.print("pub const {s}_defaults = struct {{\n", .{field.name});
                inline for (0..spec.max_order) |order| {
                    const order_name = tuning_schema.factorizedOrderFieldName(order);
                    const count = comptime tuning_schema.factorizedInteractionCount(spec, order);
                    try writer.print("    @\"{s}\": [{}]i32,\n", .{ order_name, count });
                }
                try writer.writeAll("}{\n");

                inline for (0..spec.max_order) |order| {
                    const order_name = tuning_schema.factorizedOrderFieldName(order);
                    const count = comptime tuning_schema.factorizedInteractionCount(spec, order);
                    try writer.print("    .@\"{s}\" = .{{\n", .{order_name});
                    inline for (0..count) |index| {
                        try writer.print("        {},\n", .{getFactorizedFamilyValuePtr(&family, order, index).*});
                    }
                    try writer.writeAll("    },\n");
                }
                try writer.writeAll(
                    \\};
                    \\
                );
            },
            else => {},
        }
    }
}

fn emitGeneratedFactorizedTunables(
    writer: anytype,
    resolved_factorized: ResolvedFactorizedTunables,
) !void {
    try writer.writeAll(
        \\pub const FactorizedTunable = struct {
        \\    name: []const u8,
        \\    default: i32,
        \\    min: i32,
        \\    max: i32,
        \\    c_end: f64,
        \\    order: u8,
        \\    index: usize,
        \\};
        \\
    );

    inline for (std.meta.fields(TuningSchema)) |field| {
        switch (@field(tuning_schema.SCHEMA, field.name)) {
            .Factorized => |spec| {
                const family = @field(resolved_factorized, field.name);

                try writer.print("pub const {s}_tunables = [_]FactorizedTunable{{\n", .{field.name});
                inline for (0..spec.max_order) |order| {
                    const count = comptime tuning_schema.factorizedInteractionCount(spec, order);
                    inline for (0..count) |index| {
                        var name_buf: [factorizedNameMaxLen(field.name, spec)]u8 = undefined;
                        try writer.print(
                            "    .{{ .name = \"{s}\", .default = {}, .min = {}, .max = {}, .c_end = {d}, .order = {}, .index = {} }},\n",
                            .{
                                factorizedParamNameInto(&name_buf, field.name, spec, order, index),
                                getFactorizedFamilyValuePtr(&family, order, index).*,
                                spec.min,
                                spec.max,
                                spec.c_end,
                                order,
                                index,
                            },
                        );
                    }
                }
                try writer.writeAll(
                    \\};
                    \\
                );
            },
            else => {},
        }
    }
}

fn generateTuningSource(allocator: std.mem.Allocator, params_text: []const u8) ![]u8 {
    @setEvalBranchQuota(1 << 24);
    const resolved = try resolveTuning(params_text);
    var resolved_tunables = resolved.tunables;

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();

    try writer.writeAll(
        \\// generated by build.zig; do not edit manually.
        \\
        \\pub const Tunable = struct {
        \\    name: []const u8,
        \\    default: i32,
        \\    min: i32,
        \\    max: i32,
        \\    c_end: f64,
        \\};
        \\
    );

    try emitGeneratedFactorizedDefaults(writer, resolved.factorized);
    try emitGeneratedFactorizedTunables(writer, resolved.factorized);

    try writer.writeAll(
        \\pub const TunableValues = struct {
        \\
    );

    var resolved_it = resolved_tunables.iterator();
    while (resolved_it.next()) |entry| {
        switch (entry.value.*) {
            .Scalar => |spec| {
                try writer.print("    {s}: i32 = {},\n", .{ @tagName(entry.key), spec.default.? });
            },
            .Factorized => {},
        }
    }

    try writer.writeAll(
        \\};
        \\
        \\pub const tunable_defaults: TunableValues = .{};
        \\
        \\pub const tunables = [_]Tunable{
        \\
    );

    resolved_it = resolved_tunables.iterator();
    while (resolved_it.next()) |entry| {
        switch (entry.value.*) {
            .Scalar => |spec| {
                try writer.print(
                    "    .{{ .name = \"{s}\", .default = {}, .min = {}, .max = {}, .c_end = {d} }},\n",
                    .{
                        @tagName(entry.key),
                        spec.default.?,
                        entry.value.getMin(),
                        entry.value.getMax(),
                        entry.value.getCEnd(),
                    },
                );
            },
            .Factorized => {},
        }
    }

    try writer.writeAll(
        \\};
        \\
    );

    return out.toOwnedSlice();
}

pub fn prepareGeneratedTuning(
    b: *std.Build,
    generated_files: *std.Build.Step.WriteFile,
) !std.Build.LazyPath {
    const defaults_path = b.path("src/tuning/defaults.txt").getPath3(b, null);
    const params_text = defaults_path.root_dir.handle.readFileAlloc(
        b.allocator,
        defaults_path.sub_path,
        1 << 20,
    ) catch "";
    const source = try generateTuningSource(b.allocator, params_text);
    return generated_files.add("generated.zig", source);
}
