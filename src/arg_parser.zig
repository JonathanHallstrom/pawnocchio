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
const ComptimeArrayList = @import("comptime_array_list.zig").ComptimeArrayList;
const edit_distance = @import("edit_distance.zig");

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
    text: ?[]const u8 = null,
    default_text: ?[]const u8 = null,
};

pub const Suggestion = struct {
    name: []const u8,
    cost: usize,
};

pub const Options = struct {
    allow_implied: bool = false,
    default_int_type: type = i32,
    default_float_type: type = f64,
    option_suggest_base: usize = 80,
    option_suggest_extra: usize = 10,
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
    const spec_is_type = @TypeOf(spec_or_type) == type;
    const RawSpecType = if (spec_is_type) spec_or_type else @TypeOf(spec_or_type);
    const required_mask = comptime blk: {
        var mask = ComptimeArrayList(bool){};
        for (std.meta.fields(RawSpecType)) |field| {
            mask.append(spec_is_type and field.default_value_ptr == null);
        }
        break :blk mask.items;
    };
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
    required_mask: []const bool,
) Error!@TypeOf(spec) {
    const Spec = @TypeOf(spec);

    var parsed = spec;
    var consumed_implied = false;
    var seen: [std.meta.fields(Spec).len]bool = .{false} ** std.meta.fields(Spec).len;

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            const option = arg[2..];
            const equals_idx = std.mem.indexOfScalar(u8, option, '=');
            const option_name = option[0 .. equals_idx orelse option.len];
            const inline_value = if (equals_idx) |idx| option[idx + 1 ..] else null;
            if (std.mem.eql(u8, option_name, "help")) {
                return error.HelpRequested;
            }

            const field_idx = try setNamedOption(Spec, &parsed, option_name, inline_value, args, &seen);
            seen[field_idx] = true;
            continue;
        }

        if (!options.allow_implied or consumed_implied) {
            return error.UnexpectedPositional;
        }

        const field_idx = try setImpliedPositional(Spec, &parsed, arg, &seen);
        seen[field_idx] = true;
        consumed_implied = true;
    }

    for (required_mask, 0..) |is_required, i| {
        if (is_required and !seen[i]) {
            return error.MissingRequiredOption;
        }
    }

    return parsed;
}

pub fn requiredUsage(comptime spec_or_type: anytype, comptime options: Options) []const []const u8 {
    if (@TypeOf(spec_or_type) != type) {
        return &.{};
    }

    return comptime blk: {
        const Spec = ParsedType(spec_or_type, options);
        const RawSpecType = spec_or_type;
        const raw_fields = std.meta.fields(RawSpecType);
        const implied_index = firstImpliedFieldIndex(Spec, options);

        var result = ComptimeArrayList([]const u8){};
        for (raw_fields, 0..) |field, i| {
            if (field.default_value_ptr != null) continue;
            const value_name = value_name_blk: {
                var out: [field.name.len]u8 = undefined;
                _ = std.ascii.upperString(&out, field.name);
                break :value_name_blk out;
            };
            const part = usageDescriptionForField(options, field.name) orelse if (implied_index != null and implied_index.? == i)
                std.fmt.comptimePrint("--{s} <{s}> or <{s}> (positional)", .{ field.name, value_name[0..], value_name[0..] })
            else
                std.fmt.comptimePrint("--{s}", .{field.name});
            result.append(part);
        }
        break :blk result.items;
    };
}

pub fn fullUsage(comptime spec_or_type: anytype, comptime options: Options) []const []const u8 {
    const Spec = ParsedType(spec_or_type, options);

    const spec_is_type = @TypeOf(spec_or_type) == type;
    const RawSpecType = if (spec_is_type) spec_or_type else @TypeOf(spec_or_type);
    const raw_fields = std.meta.fields(RawSpecType);
    const spec_fields = std.meta.fields(Spec);
    const required_mask = comptime blk: {
        var mask: [raw_fields.len]bool = .{false} ** raw_fields.len;
        for (raw_fields, 0..) |field, i| {
            mask[i] = spec_is_type and field.default_value_ptr == null;
        }
        break :blk mask;
    };
    const implied_index = comptime firstImpliedFieldIndex(Spec, options);

    return comptime blk: {
        var base_parts = ComptimeArrayList([]const u8){};
        var type_parts = ComptimeArrayList([]const u8){};
        var default_parts = ComptimeArrayList(?[]const u8){};
        var max_base_len: usize = 0;
        var max_type_len: usize = 0;

        for (raw_fields, 0..) |field, i| {
            const spec_field = spec_fields[i];
            const value_name = value_name_blk: {
                var out: [field.name.len]u8 = undefined;
                _ = std.ascii.upperString(&out, field.name);
                break :value_name_blk out;
            };
            const custom_part = usageDescriptionForField(options, field.name);
            const custom_default = usageDefaultTextForField(options, field.name);
            const type_hint = typeHintText(spec_field.type);
            const part = custom_part orelse if (implied_index != null and implied_index.? == i and spec_field.type != bool)
                std.fmt.comptimePrint("--{s} <{s}> or <{s}> (positional)", .{ field.name, value_name[0..], value_name[0..] })
            else if (spec_field.type == bool)
                std.fmt.comptimePrint("--{s}", .{field.name})
            else
                std.fmt.comptimePrint("--{s} <{s}>", .{ field.name, value_name[0..] });

            const base = if (required_mask[i])
                part ++ " [required]"
            else
                part;
            if (base.len > max_base_len) {
                max_base_len = base.len;
            }
            if (type_hint.len > max_type_len) {
                max_type_len = type_hint.len;
            }

            const auto_default = defaultTextFor(spec_or_type, spec_is_type, field);
            const default_text = chooseDefaultText(custom_default, auto_default);

            base_parts.append(base);
            type_parts.append(type_hint);
            default_parts.append(default_text);
        }

        var result = ComptimeArrayList([]const u8){};
        for (0..base_parts.items.len) |i| {
            const base = base_parts.items[i];
            const type_hint = type_parts.items[i];
            const type_padding = " " ** (max_type_len - type_hint.len);
            const suffix = if (default_parts.items[i]) |default_text|
                std.fmt.comptimePrint("({s}{s} default: {s})", .{ type_hint, type_padding, default_text })
            else
                std.fmt.comptimePrint("({s})", .{type_hint});
            const base_padding = " " ** (max_base_len - base.len + 1);
            result.append(std.fmt.comptimePrint("{s}{s}{s}", .{ base, base_padding, suffix }));
        }
        break :blk result.items;
    };
}

fn defaultTextFor(comptime spec_or_type: anytype, comptime spec_is_type: bool, comptime field: anytype) ?[]const u8 {
    if (!spec_is_type) {
        return defaultValueText(@field(spec_or_type, field.name));
    }
    if (field.default_value_ptr == null) {
        return null;
    }

    const DefaultPtr = *const field.type;
    const default_value = @as(DefaultPtr, @ptrCast(@alignCast(field.default_value_ptr.?))).*;
    return defaultValueText(default_value);
}

fn chooseDefaultText(custom_default: ?[]const u8, auto_default: ?[]const u8) ?[]const u8 {
    if (custom_default) |text| {
        return text;
    }
    if (auto_default) |text| {
        return if (std.mem.eql(u8, text, "null")) null else text;
    }
    return null;
}

pub fn suggestOption(
    comptime spec_or_type: anytype,
    comptime options: Options,
    option_name: []const u8,
) ?[]const u8 {
    const suggestion = suggestOptionWithCost(spec_or_type, options, option_name) orelse return null;
    return suggestion.name;
}

pub fn suggestOptionWithCost(
    comptime spec_or_type: anytype,
    comptime options: Options,
    option_name: []const u8,
) ?Suggestion {
    const Spec = ParsedType(spec_or_type, options);
    const Field = std.meta.FieldEnum(Spec);
    const lookup = edit_distance.matchEnum(Field, option_name, options.option_suggest_base, options.option_suggest_extra) orelse return null;
    return switch (lookup) {
        .match => |field| .{ .name = @tagName(field), .cost = 0 },
        .closest => |closest| .{ .name = @tagName(closest.tag), .cost = closest.cost },
    };
}

fn usageDescriptionForField(comptime options: Options, comptime field_name: []const u8) ?[]const u8 {
    for (options.usage_descriptions) |usage_description| {
        if (std.mem.eql(u8, usage_description.field, field_name)) {
            return usage_description.text;
        }
    }
    return null;
}

fn usageDefaultTextForField(comptime options: Options, comptime field_name: []const u8) ?[]const u8 {
    for (options.usage_descriptions) |usage_description| {
        if (std.mem.eql(u8, usage_description.field, field_name)) {
            return usage_description.default_text;
        }
    }
    return null;
}

fn defaultValueText(comptime value: anytype) []const u8 {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .bool => if (value) "true" else "false",
        .int, .float => std.fmt.comptimePrint("{}", .{value}),
        .@"enum" => @tagName(value),
        .optional => if (value) |inner|
            defaultValueText(inner)
        else
            "null",
        .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8)
            value
        else
            std.fmt.comptimePrint("{any}", .{value}),
        else => std.fmt.comptimePrint("{any}", .{value}),
    };
}

fn enumTagList(comptime T: type) []const u8 {
    const fields = @typeInfo(T).@"enum".fields;
    var result = ComptimeArrayList(u8){};
    inline for (fields, 0..) |field, i| {
        if (i != 0) {
            result.append('|');
        }
        result.appendSlice(field.name);
    }
    return result.items;
}

fn typeHintText(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => "integer",
        .float => "float",
        .bool => "bool",
        .@"enum" => std.fmt.comptimePrint("enum({s})", .{enumTagList(T)}),
        .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8)
            "string"
        else
            @typeName(T),
        .optional => |opt| std.fmt.comptimePrint("?{s}", .{typeHintText(opt.child)}),
        else => @typeName(T),
    };
}

fn NormalizedSpecType(comptime RawSpec: type, comptime options: Options) type {
    const raw_info = @typeInfo(RawSpec);
    if (raw_info != .@"struct") {
        @compileError("arg_parser.parse expects a struct (type or instance) as spec");
    }

    const raw_fields = std.meta.fields(RawSpec);
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

fn initSpecDefaults(comptime RawSpec: type, comptime Spec: type) Spec {
    const raw_fields = std.meta.fields(RawSpec);
    const spec_fields = std.meta.fields(Spec);
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
    inline for (std.meta.fields(Out)) |field| {
        @field(out, field.name) = coerceValue(field.type, @field(spec, field.name));
    }
    return out;
}

fn coerceValue(comptime To: type, value: anytype) To {
    const From = @TypeOf(value);
    if (To == From) {
        return value;
    }

    return switch (@typeInfo(To)) {
        .int => @as(To, @intCast(value)),
        .float => switch (@typeInfo(From)) {
            .int, .comptime_int => @floatFromInt(value),
            else => @floatCast(value),
        },
        .optional => |opt| blk: {
            if (@typeInfo(From) == .optional) {
                if (value) |inner| {
                    break :blk coerceValue(opt.child, inner);
                }
                break :blk null;
            }
            break :blk coerceValue(opt.child, value);
        },
        else => value,
    };
}

fn firstImpliedFieldIndex(comptime Spec: type, comptime options: Options) ?usize {
    if (!options.allow_implied) {
        return null;
    }
    inline for (std.meta.fields(Spec), 0..) |field, i| {
        if (field.type != bool) {
            return i;
        }
    }
    return null;
}

fn setNamedOption(
    comptime Spec: type,
    parsed: *Spec,
    option_name: []const u8,
    inline_value: ?[]const u8,
    args: anytype,
    seen: *const [std.meta.fields(Spec).len]bool,
) Error!usize {
    const Field = std.meta.FieldEnum(Spec);
    const field = std.meta.stringToEnum(Field, option_name) orelse return error.UnknownOption;
    const i = @intFromEnum(field);
    if (seen[i]) {
        return error.OptionAlreadySet;
    }

    return switch (field) {
        inline else => |field_tag| {
            const field_name = @tagName(field_tag);
            const FieldType = @FieldType(Spec, field_name);
            if (FieldType == bool) {
                @field(parsed.*, field_name) = if (inline_value) |value|
                    try parseValue(bool, value)
                else
                    true;
                return i;
            }

            const value = inline_value orelse (args.next() orelse return error.MissingOptionValue);
            @field(parsed.*, field_name) = try parseValue(FieldType, value);
            return i;
        },
    };
}

fn setImpliedPositional(
    comptime Spec: type,
    parsed: *Spec,
    value: []const u8,
    seen: *const [std.meta.fields(Spec).len]bool,
) Error!usize {
    inline for (std.meta.fields(Spec), 0..) |field, i| {
        if (field.type != bool) {
            if (seen[i]) {
                return error.OptionAlreadySet;
            }
            @field(parsed.*, field.name) = try parseValue(field.type, value);
            return i;
        }
    }
    return error.UnexpectedPositional;
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
    try std.testing.expectEqual(@as(usize, 2), default_usage.len);
    try std.testing.expectEqualStrings("--input <INPUT> or <INPUT> (positional)", default_usage[0]);
    try std.testing.expectEqualStrings("--tb-path", default_usage[1]);

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
    try std.testing.expectEqual(@as(usize, 2), custom_usage.len);
    try std.testing.expectEqualStrings("<INPUT>", custom_usage[0]);
    try std.testing.expectEqualStrings("--tb-path <PATH>", custom_usage[1]);
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
    try std.testing.expectEqual(@as(usize, 3), usage.len);
    try std.testing.expectEqualStrings("--input <INPUT> or <INPUT> (positional) [required] (string)", usage[0]);
    try std.testing.expect(std.mem.endsWith(u8, usage[1], "(?string)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, usage[2], 1, "default: false"));
    const col0 = std.mem.lastIndexOfScalar(u8, usage[0], '(').?;
    const col1 = std.mem.lastIndexOfScalar(u8, usage[1], '(').?;
    const col2 = std.mem.lastIndexOfScalar(u8, usage[2], '(').?;
    try std.testing.expectEqual(col0, col1);
    try std.testing.expectEqual(col0, col2);
    try std.testing.expect(std.mem.indexOf(u8, usage[1], "default:") == null);
}

test "full usage appends type/default for custom descriptions and aligns suffixes" {
    const usage = fullUsage(
        struct {
            input: []const u8,
            output: ?[]const u8 = null,
        },
        .{
            .allow_implied = false,
            .usage_descriptions = &.{
                .{ .field = "input", .text = "--input <INPUT>" },
            },
        },
    );
    try std.testing.expectEqual(@as(usize, 2), usage.len);
    try std.testing.expect(std.mem.endsWith(u8, usage[0], "(string)"));
    try std.testing.expect(std.mem.endsWith(u8, usage[1], "(?string)"));
    const col0 = std.mem.lastIndexOfScalar(u8, usage[0], '(').?;
    const col1 = std.mem.lastIndexOfScalar(u8, usage[1], '(').?;
    try std.testing.expectEqual(col0, col1);
}

test "full usage uses default_text override from usage description" {
    const usage = fullUsage(
        struct {
            output: ?[]const u8 = null,
        },
        .{
            .usage_descriptions = &.{
                .{ .field = "output", .default_text = "<INPUT>.vf" },
            },
        },
    );
    try std.testing.expectEqual(@as(usize, 1), usage.len);
    try std.testing.expectEqualStrings("--output <OUTPUT> (?string, default: <INPUT>.vf)", usage[0]);
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
        .{ .@"white-relative" = true },
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

test "option suggestion returns close match and respects threshold" {
    const suggestion = suggestOption(
        struct {
            @"allow-overwrite": bool = false,
            @"tb-path": ?[]const u8 = null,
        },
        .{},
        "allow-overwrit",
    );
    try std.testing.expectEqualStrings("allow-overwrite", suggestion.?);

    try std.testing.expectEqual(
        @as(?[]const u8, null),
        suggestOption(
            struct { @"allow-overwrite": bool = false },
            .{ .option_suggest_base = 0, .option_suggest_extra = 0 },
            "allow-overwrit",
        ),
    );
}

test "option suggestion supports prefix matches gated by percent" {
    try std.testing.expectEqualStrings(
        "allow-overwrite",
        suggestOption(
            struct {
                @"allow-overwrite": bool = false,
                @"tb-path": ?[]const u8 = null,
            },
            .{},
            "allow-ov",
        ).?,
    );

    try std.testing.expectEqual(
        @as(?[]const u8, null),
        suggestOption(
            struct { @"allow-overwrite": bool = false },
            .{ .option_suggest_base = 0, .option_suggest_extra = 0 },
            "allow-ov",
        ),
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
