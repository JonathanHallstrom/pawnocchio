const std = @import("std");

pub const Error = error{
    HelpRequested,
    InvalidValue,
    MissingOptionValue,
    MissingRequiredOption,
    OptionAlreadySet,
    UnknownOption,
    UnexpectedPositional,
};

pub const UsageDescription = struct {
    field: []const u8,
    text: []const u8,
};

pub const Options = struct {
    allow_implied: bool = false,
    default_int_type: type = i32,
    default_float_type: type = f64,
    usage_descriptions: []const UsageDescription = &.{},
};

pub fn ParsedType(comptime spec_or_type: anytype, comptime options: Options) type {
    const RawSpecType = if (@TypeOf(spec_or_type) == type) spec_or_type else @TypeOf(spec_or_type);
    return NormalizedSpecType(RawSpecType, options);
}

pub inline fn parse(
    args: anytype,
    comptime spec_or_type: anytype,
    comptime options: Options,
) Error!ParsedType(spec_or_type, options) {
    const ArgType = std.meta.Child(@TypeOf(args));
    comptime if (!(@hasDecl(ArgType, "next") or @hasField(ArgType, "next"))) {
        @compileError(
            \\expected args to be an iterator with a "next" member
        );
    };

    const Spec = ParsedType(spec_or_type, options);
    comptime validateUsageDescriptions(Spec, options);
    const spec_is_type = @TypeOf(spec_or_type) == type;
    const RawSpecType = if (spec_is_type) spec_or_type else @TypeOf(spec_or_type);
    const required_mask = RequiredFieldMask(RawSpecType, spec_is_type);
    const spec: Spec = if (spec_is_type)
        initSpecDefaults(RawSpecType, Spec)
    else
        normalizeSpecValue(Spec, spec_or_type);
    return parseImpl(args, spec, options, required_mask);
}

fn parseImpl(
    args: anytype,
    spec: anytype,
    comptime options: Options,
    required_mask: [@typeInfo(@TypeOf(spec)).@"struct".fields.len]bool,
) Error!@TypeOf(spec) {
    const Spec = @TypeOf(spec);

    var parsed = spec;
    var consumed_implied = false;
    var seen: [@typeInfo(Spec).@"struct".fields.len]bool = .{false} ** @typeInfo(Spec).@"struct".fields.len;

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            const option = arg[2..];
            const equals_idx = std.mem.indexOfScalar(u8, option, '=');
            const option_name = option[0 .. equals_idx orelse option.len];
            const inline_value = if (equals_idx) |idx| option[idx + 1 ..] else null;
            if (std.ascii.eqlIgnoreCase(option_name, "help")) {
                return error.HelpRequested;
            }

            if (try setNamedOption(Spec, &parsed, option_name, inline_value, args, &seen)) |field_idx| {
                seen[field_idx] = true;
            } else {
                return error.UnknownOption;
            }
            continue;
        }
        if (!options.allow_implied) {
            return error.UnexpectedPositional;
        }
        if (consumed_implied) {
            return error.UnexpectedPositional;
        }

        if (try setImpliedPositional(Spec, &parsed, arg, &seen)) |field_idx| {
            seen[field_idx] = true;
        } else {
            return error.UnexpectedPositional;
        }
        consumed_implied = true;
    }

    for (required_mask, 0..) |is_required, i| {
        if (is_required and !seen[i]) {
            return error.MissingRequiredOption;
        }
    }

    return parsed;
}

pub fn requiredUsage(comptime spec_or_type: anytype, comptime options: Options) []const u8 {
    if (@TypeOf(spec_or_type) != type) {
        return "";
    }

    const Spec = ParsedType(spec_or_type, options);
    comptime validateUsageDescriptions(Spec, options);

    const RawSpecType = spec_or_type;
    const raw_fields = @typeInfo(RawSpecType).@"struct".fields;
    const implied_index = comptime firstImpliedFieldIndex(Spec, options);

    comptime var usage: []const u8 = "";
    comptime var first = true;
    inline for (raw_fields, 0..) |field, i| {
        if (comptime field.default_value_ptr != null) continue;
        const value_name = comptime fieldValueName(field.name);

        const part = comptime (usageDescriptionForField(options, field.name) orelse if (implied_index != null and implied_index.? == i)
            std.fmt.comptimePrint("--{s} <{s}> or <{s}> (positional)", .{ field.name, value_name[0..], value_name[0..] })
        else
            std.fmt.comptimePrint("--{s}", .{field.name}));

        if (first) {
            usage = part;
            first = false;
        } else {
            usage = usage ++ "\n" ++ part;
        }
    }
    return usage;
}

pub fn fullUsage(comptime spec_or_type: anytype, comptime options: Options) []const u8 {
    const Spec = ParsedType(spec_or_type, options);
    comptime validateUsageDescriptions(Spec, options);

    const spec_is_type = @TypeOf(spec_or_type) == type;
    const RawSpecType = if (spec_is_type) spec_or_type else @TypeOf(spec_or_type);
    const raw_fields = @typeInfo(RawSpecType).@"struct".fields;
    const spec_fields = @typeInfo(Spec).@"struct".fields;
    const required_mask = comptime RequiredFieldMask(RawSpecType, spec_is_type);
    const implied_index = comptime firstImpliedFieldIndex(Spec, options);

    comptime var usage: []const u8 = "";
    comptime var first = true;
    inline for (raw_fields, 0..) |field, i| {
        const spec_field = spec_fields[i];
        const value_name = comptime fieldValueName(field.name);
        const part = comptime (usageDescriptionForField(options, field.name) orelse if (implied_index != null and implied_index.? == i and isImpliedFieldType(spec_field.type))
            std.fmt.comptimePrint("--{s} <{s}> or <{s}> (positional)", .{ field.name, value_name[0..], value_name[0..] })
        else if (spec_field.type == bool)
            std.fmt.comptimePrint("--{s}", .{field.name})
        else
            std.fmt.comptimePrint("--{s} <{s}>", .{ field.name, value_name[0..] }));

        const line = comptime if (required_mask[i])
            part ++ " [required]"
        else
            part;

        if (first) {
            usage = line;
            first = false;
        } else {
            usage = usage ++ "\n" ++ line;
        }
    }
    return usage;
}

fn fieldValueName(comptime field_name: []const u8) [field_name.len]u8 {
    comptime var out: [field_name.len]u8 = undefined;
    _ = std.ascii.upperString(&out, field_name);
    return out;
}

fn usageDescriptionForField(comptime options: Options, comptime field_name: []const u8) ?[]const u8 {
    for (options.usage_descriptions) |usage_description| {
        if (std.mem.eql(u8, usage_description.field, field_name)) {
            return usage_description.text;
        }
    }
    return null;
}

fn validateUsageDescriptions(comptime Spec: type, comptime options: Options) void {
    comptime {
        for (options.usage_descriptions, 0..) |usage_description, i| {
            if (std.meta.fieldIndex(Spec, usage_description.field) == null) {
                @compileError(std.fmt.comptimePrint(
                    "usage_descriptions field '{s}' not found in spec",
                    .{usage_description.field},
                ));
            }
            for (options.usage_descriptions[i + 1 ..]) |other| {
                if (std.mem.eql(u8, usage_description.field, other.field)) {
                    @compileError(std.fmt.comptimePrint(
                        "usage_descriptions has duplicate field '{s}'",
                        .{usage_description.field},
                    ));
                }
            }
        }
    }
}

fn NormalizedSpecType(comptime RawSpec: type, comptime options: Options) type {
    const raw_info = @typeInfo(RawSpec);
    if (raw_info != .@"struct") {
        @compileError("arg_parser.parse expects a struct (type or instance) as spec");
    }

    const raw_fields = raw_info.@"struct".fields;
    comptime var fields: [raw_fields.len]std.builtin.Type.StructField = undefined;
    inline for (raw_fields, 0..) |field, i| {
        const field_type = NormalizedFieldType(field.type, options);
        fields[i] = .{
            .name = field.name,
            .type = field_type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = field.alignment,
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = raw_info.@"struct".layout,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = raw_info.@"struct".is_tuple,
    } });
}

fn NormalizedFieldType(comptime T: type, comptime options: Options) type {
    return switch (@typeInfo(T)) {
        .comptime_int => options.default_int_type,
        .comptime_float => options.default_float_type,
        .pointer => |ptr| blk: {
            if (ptr.size == .one) {
                switch (@typeInfo(ptr.child)) {
                    .array => |arr| if (arr.child == u8) {
                        break :blk []const u8;
                    },
                    else => {},
                }
            }
            break :blk T;
        },
        .optional => |opt| @Type(.{ .optional = .{
            .child = NormalizedFieldType(opt.child, options),
        } }),
        else => T,
    };
}

fn RequiredFieldMask(comptime RawSpec: type, comptime spec_is_type: bool) [@typeInfo(RawSpec).@"struct".fields.len]bool {
    const raw_fields = @typeInfo(RawSpec).@"struct".fields;
    comptime var mask: [raw_fields.len]bool = .{false} ** raw_fields.len;
    inline for (raw_fields, 0..) |field, i| {
        mask[i] = spec_is_type and field.default_value_ptr == null;
    }
    return mask;
}

fn initSpecDefaults(comptime RawSpec: type, comptime Spec: type) Spec {
    const raw_fields = @typeInfo(RawSpec).@"struct".fields;
    const spec_fields = @typeInfo(Spec).@"struct".fields;
    comptime {
        if (raw_fields.len != spec_fields.len) {
            @compileError("normalized spec field mismatch");
        }
    }

    var spec: Spec = undefined;
    inline for (raw_fields, 0..) |raw_field, i| {
        const spec_field = spec_fields[i];
        if (raw_field.default_value_ptr) |default_ptr| {
            const DefaultPtr = *const raw_field.type;
            const default_value = @as(DefaultPtr, @ptrCast(@alignCast(default_ptr))).*;
            @field(spec, spec_field.name) = coerceValue(spec_field.type, default_value);
        } else {
            @field(spec, spec_field.name) = undefined;
        }
    }
    return spec;
}

fn normalizeSpecValue(comptime Out: type, spec: anytype) Out {
    const In = @TypeOf(spec);
    if (In == Out) {
        return spec;
    }

    var out: Out = undefined;
    inline for (@typeInfo(Out).@"struct".fields) |field| {
        @field(out, field.name) = coerceValue(field.type, @field(spec, field.name));
    }
    return out;
}

fn coerceValue(comptime To: type, value: anytype) To {
    const From = @TypeOf(value);
    if (To == From) {
        return value;
    }

    if (comptime isByteSliceType(To)) {
        const byte_slice = coerceToByteSlice(value);
        return @as(To, byte_slice);
    }

    return switch (@typeInfo(To)) {
        .int => @as(To, @intCast(value)),
        .float => switch (@typeInfo(From)) {
            .int, .comptime_int => @as(To, @floatFromInt(value)),
            else => @as(To, @floatCast(value)),
        },
        .optional => |opt| blk: {
            if (@typeInfo(From) == .optional) {
                if (value) |inner| {
                    break :blk @as(To, coerceValue(opt.child, inner));
                }
                break :blk null;
            }
            break :blk @as(To, coerceValue(opt.child, value));
        },
        else => @as(To, value),
    };
}

fn firstImpliedFieldIndex(comptime Spec: type, comptime options: Options) ?usize {
    if (!options.allow_implied) {
        return null;
    }
    const fields = @typeInfo(Spec).@"struct".fields;
    inline for (fields, 0..) |field, i| {
        if (isImpliedFieldType(field.type)) {
            return i;
        }
    }
    return null;
}

fn isByteSliceType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.size == .slice and ptr.child == u8,
        else => false,
    };
}

fn coerceToByteSlice(value: anytype) []const u8 {
    const From = @TypeOf(value);
    return switch (@typeInfo(From)) {
        .pointer => |ptr| switch (ptr.size) {
            .slice => value,
            .one => switch (@typeInfo(ptr.child)) {
                .array => |arr| blk: {
                    if (arr.child != u8) {
                        @compileError("cannot coerce non-u8 array pointer to []const u8");
                    }
                    break :blk value[0..arr.len];
                },
                else => @compileError("cannot coerce pointer type to []const u8"),
            },
            else => @compileError("cannot coerce pointer type to []const u8"),
        },
        else => @compileError("cannot coerce type to []const u8"),
    };
}

fn setNamedOption(
    comptime Spec: type,
    parsed: *Spec,
    option_name: []const u8,
    inline_value: ?[]const u8,
    args: anytype,
    seen: *const [@typeInfo(Spec).@"struct".fields.len]bool,
) Error!?usize {
    const fields = @typeInfo(Spec).@"struct".fields;
    inline for (fields, 0..) |field, i| {
        if (std.ascii.eqlIgnoreCase(option_name, field.name)) {
            if (seen[i]) {
                return error.OptionAlreadySet;
            }
            if (field.type == bool) {
                @field(parsed.*, field.name) = if (inline_value) |value|
                    try parseValue(bool, value)
                else
                    true;
                return i;
            }

            const value = inline_value orelse (args.next() orelse return error.MissingOptionValue);
            @field(parsed.*, field.name) = try parseValue(field.type, value);
            return i;
        }
    }
    return null;
}

fn setImpliedPositional(
    comptime Spec: type,
    parsed: *Spec,
    value: []const u8,
    seen: *const [@typeInfo(Spec).@"struct".fields.len]bool,
) Error!?usize {
    const fields = @typeInfo(Spec).@"struct".fields;
    inline for (fields, 0..) |field, i| {
        if (isImpliedFieldType(field.type)) {
            if (seen[i]) {
                return error.OptionAlreadySet;
            }
            @field(parsed.*, field.name) = try parseValue(field.type, value);
            return i;
        }
    }
    return null;
}

fn isImpliedFieldType(comptime T: type) bool {
    return T != bool;
}

fn parseValue(comptime T: type, value: []const u8) Error!T {
    return switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(T, value, 10) catch error.InvalidValue,
        .float => std.fmt.parseFloat(T, value) catch error.InvalidValue,
        .bool => if (std.ascii.eqlIgnoreCase(value, "true"))
            true
        else if (std.ascii.eqlIgnoreCase(value, "false"))
            false
        else
            error.InvalidValue,
        .@"enum" => std.meta.stringToEnum(T, value) orelse error.InvalidValue,
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8) {
                break :blk value;
            }
            @compileError("unsupported pointer type in arg parser spec");
        },
        .optional => |opt| @as(T, try parseValue(opt.child, value)),
        else => @compileError("unsupported arg parser field type"),
    };
}

const SliceIterator = struct {
    args: []const []const u8,
    index: usize = 0,

    fn next(self: *SliceIterator) ?[]const u8 {
        if (self.index >= self.args.len) return null;
        defer self.index += 1;
        return self.args[self.index];
    }
};

fn parseArgs(
    comptime spec_or_type: anytype,
    comptime options: Options,
    args: []const []const u8,
) Error!ParsedType(spec_or_type, options) {
    var iter = SliceIterator{ .args = args };
    return parse(&iter, spec_or_type, options);
}

fn expectParseError(
    expected: anyerror,
    comptime spec_or_type: anytype,
    comptime options: Options,
    args: []const []const u8,
) !void {
    try std.testing.expectError(expected, parseArgs(spec_or_type, options, args));
}

test "allow_implied defaults to false" {
    try expectParseError(error.UnexpectedPositional, .{ .depth = 13 }, .{}, &.{"42"});
}

test "parse accepts spec type and instance" {
    const typed = try parseArgs(
        struct { depth: i32 = 13 },
        .{ .allow_implied = true },
        &.{"42"},
    );
    try std.testing.expectEqual(@as(i32, 42), typed.depth);

    const instance = try parseArgs(
        .{ .depth = 13 },
        .{ .allow_implied = true },
        &.{"42"},
    );
    try std.testing.expectEqual(@as(i32, 42), instance.depth);
    try std.testing.expect(@TypeOf(instance.depth) == i32);
}

test "required field in type must be provided" {
    try expectParseError(
        error.MissingRequiredOption,
        struct { input: []const u8 },
        .{ .allow_implied = true },
        &.{},
    );
}

test "required usage strings are formatted correctly" {
    const default_usage = requiredUsage(
        struct {
            input: []const u8,
            @"tb-path": []const u8,
            approximate: bool = false,
        },
        .{ .allow_implied = true },
    );
    try std.testing.expectEqualStrings("--input <INPUT> or <INPUT> (positional)\n--tb-path", default_usage);

    const custom_usage = requiredUsage(
        struct {
            input: []const u8,
            @"tb-path": []const u8,
            approximate: bool = false,
        },
        .{
            .allow_implied = true,
            .usage_descriptions = &.{
                .{ .field = "input", .text = "<INPUT>" },
                .{ .field = "tb-path", .text = "--tb-path <PATH>" },
            },
        },
    );
    try std.testing.expectEqualStrings("<INPUT>\n--tb-path <PATH>", custom_usage);
}

test "required positional can satisfy required field" {
    const parsed = try parseArgs(
        struct { input: []const u8 },
        .{ .allow_implied = true },
        &.{"in.epd"},
    );
    try std.testing.expectEqualStrings("in.epd", parsed.input);
}

test "help option returns help requested error" {
    try expectParseError(
        error.HelpRequested,
        struct { input: []const u8 },
        .{ .allow_implied = true },
        &.{"--help"},
    );
}

test "full usage includes required and optional fields" {
    const usage = fullUsage(
        struct {
            input: []const u8,
            output: ?[]const u8 = null,
            @"allow-overwrite": bool = false,
        },
        .{ .allow_implied = true },
    );
    try std.testing.expectEqualStrings(
        "--input <INPUT> or <INPUT> (positional) [required]\n--output <OUTPUT>\n--allow-overwrite",
        usage,
    );
}

test "implied parsing supports provided and default values" {
    const provided = try parseArgs(.{ .depth = 13 }, .{ .allow_implied = true }, &.{"42"});
    try std.testing.expectEqual(@as(i32, 42), provided.depth);

    const omitted = try parseArgs(.{ .depth = 13 }, .{ .allow_implied = true }, &.{});
    try std.testing.expectEqual(@as(i32, 13), omitted.depth);
}

test "default numeric and string type inference works" {
    const float_parsed = try parseArgs(.{ .temp = 1.25 }, .{ .allow_implied = true }, &.{"2.5"});
    try std.testing.expect(@TypeOf(float_parsed.temp) == f64);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), float_parsed.temp, 0.000001);

    const string_parsed = try parseArgs(.{ .input = "" }, .{ .allow_implied = true }, &.{"in.epd"});
    try std.testing.expectEqualStrings("in.epd", string_parsed.input);
    try std.testing.expect(@TypeOf(string_parsed.input) == []const u8);
}

test "boolean flags support bare and inline forms" {
    const bare = try parseArgs(
        struct {
            @"skip-broken-games": bool = false,
            @"white-relative": bool = false,
        },
        .{},
        &.{"--white-relative"},
    );
    try std.testing.expectEqual(false, bare.@"skip-broken-games");
    try std.testing.expectEqual(true, bare.@"white-relative");

    const inline_false = try parseArgs(
        struct {
            @"white-relative": bool = true,
        },
        .{},
        &.{"--white-relative=false"},
    );
    try std.testing.expectEqual(false, inline_false.@"white-relative");
}

test "mixed implied positional and named options" {
    const parsed = try parseArgs(
        struct {
            input: []const u8 = "",
            @"skip-broken-games": bool = false,
        },
        .{ .allow_implied = true },
        &.{ "in.epd", "--skip-broken-games" },
    );
    try std.testing.expectEqualStrings("in.epd", parsed.input);
    try std.testing.expectEqual(true, parsed.@"skip-broken-games");
}

test "options with values support split and inline forms" {
    const cases = [_][]const []const u8{
        &.{ "--tb-path", "/tb", "data.vf" },
        &.{ "--tb-path=/tb", "data.vf" },
    };

    for (cases) |args| {
        const parsed = try parseArgs(
            struct {
                input: []const u8 = "",
                @"tb-path": ?[]const u8 = null,
            },
            .{ .allow_implied = true },
            args,
        );
        try std.testing.expectEqualStrings("data.vf", parsed.input);
        try std.testing.expectEqualStrings("/tb", parsed.@"tb-path".?);
    }
}

test "unknown options return an error" {
    try expectParseError(
        error.UnknownOption,
        .{ .white_relative = false },
        .{},
        &.{"--nope=1"},
    );
    try expectParseError(
        error.UnknownOption,
        .{ .white_relative = false },
        .{},
        &.{"--nope"},
    );
}

test "setting the same option twice returns error" {
    try expectParseError(
        error.OptionAlreadySet,
        .{ .depth = @as(i32, 11) },
        .{},
        &.{ "--depth", "12", "--depth=13" },
    );
}

test "mixing named and positional for the same field returns error" {
    try expectParseError(
        error.OptionAlreadySet,
        struct { input: []const u8 = "" },
        .{ .allow_implied = true },
        &.{ "--input", "in.epd", "other.epd" },
    );
}

test "setting bool flag twice returns error" {
    try expectParseError(
        error.OptionAlreadySet,
        struct { @"white-relative": bool = false },
        .{},
        &.{ "--white-relative", "--white-relative" },
    );
}

test "missing option value returns error" {
    try expectParseError(
        error.MissingOptionValue,
        struct { path: ?[]const u8 = null }{},
        .{},
        &.{"--path"},
    );
}

test "extra positional arguments are rejected" {
    try expectParseError(
        error.UnexpectedPositional,
        struct { input: []const u8 = "" }{},
        .{ .allow_implied = true },
        &.{ "in.epd", "extra" },
    );
    try expectParseError(
        error.UnexpectedPositional,
        struct {
            input: []const u8 = "",
            output: ?[]const u8 = null,
        }{},
        .{ .allow_implied = true },
        &.{ "in.epd", "out.vf" },
    );
}

test "invalid integer value returns error" {
    try expectParseError(
        error.InvalidValue,
        .{ .depth = @as(i32, 11) },
        .{ .allow_implied = true },
        &.{"abc"},
    );
}
