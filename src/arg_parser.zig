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
    text: ?[]const u8 = null,
    default_text: ?[]const u8 = null,
};

pub const Suggestion = struct {
    name: []const u8,
    cost: usize,
};

pub fn Options(comptime spec_or_type: anytype) type {
    const Spec = SpecType(spec_or_type);
    if (@typeInfo(Spec) != .@"struct") {
        @compileError("arg_parser spec must be a struct");
    }
    return struct {
        allow_implied: bool = false,
        default_int_type: type = i32,
        default_float_type: type = f64,
        option_suggest_base: usize = 80,
        option_suggest_extra: usize = 10,
        usage_descriptions: OptionalFields(Spec, UsageDescription) = .{},
        bare_values: OptionalFields(Spec, null) = .{},
    };
}

fn SpecType(comptime spec_or_type: anytype) type {
    return if (@TypeOf(spec_or_type) == type) spec_or_type else @TypeOf(spec_or_type);
}

fn OptionalFields(comptime Spec: type, comptime Value: ?type) type {
    const spec_info = @typeInfo(Spec).@"struct";
    var field_types: [spec_info.field_names.len]type = undefined;
    var field_attrs: [spec_info.field_names.len]std.lang.Type.Struct.FieldAttributes = undefined;
    for (spec_info.field_types, 0..) |field_type, i| {
        field_types[i] = ?(Value orelse field_type);
        field_attrs[i] = .{ .default_value_ptr = @ptrCast(&@as(field_types[i], null)) };
    }
    return @Struct(.auto, null, spec_info.field_names, &field_types, &field_attrs);
}

pub fn ParsedType(comptime spec_or_type: anytype, comptime options: Options(spec_or_type)) type {
    return NormalizedSpecType(SpecType(spec_or_type), options);
}

pub inline fn parse(
    args: anytype,
    comptime spec_or_type: anytype,
    comptime options: Options(spec_or_type),
    allocator: std.mem.Allocator,
) (Error || error{OutOfMemory})!ParsedType(spec_or_type, options) {
    const ArgType = std.meta.Child(@TypeOf(args));
    comptime if (!(@hasDecl(ArgType, "next") or @hasField(ArgType, "next"))) {
        @compileError(
            \\expected args to be an iterator with a "next" member
        );
    };

    const Spec = ParsedType(spec_or_type, options);
    const spec_is_type = @TypeOf(spec_or_type) == type;
    const RawSpecType = SpecType(spec_or_type);
    const required_mask = comptime blk: {
        var mask = ComptimeArrayList(bool){};
        for (@typeInfo(RawSpecType).@"struct".field_attrs) |field_attrs| {
            mask.append(spec_is_type and field_attrs.default_value_ptr == null);
        }
        break :blk mask.items;
    };
    const spec: Spec = if (spec_is_type)
        initSpecDefaults(RawSpecType, Spec)
    else
        normalizeSpecValue(Spec, spec_or_type);
    return parseImpl(args, spec, options, required_mask, allocator);
}

fn parseImpl(
    args: anytype,
    spec: anytype,
    comptime options: anytype,
    required_mask: []const bool,
    allocator: std.mem.Allocator,
) (Error || error{OutOfMemory})!@TypeOf(spec) {
    const Spec = @TypeOf(spec);
    const spec_info = @typeInfo(Spec).@"struct";

    var parsed = spec;
    var consumed_implied = false;
    var seen: [spec_info.field_names.len]bool = @splat(false);
    var pending: ?[]const u8 = null;

    var scratch: [spec_info.field_names.len]std.ArrayList([]const u8) = @splat(.empty);
    defer for (&scratch) |*s| s.deinit(allocator);

    while (pending orelse args.next()) |arg| {
        pending = null;
        if (std.mem.startsWith(u8, arg, "--")) {
            const option = arg[2..];
            const equals_idx = std.mem.findScalar(u8, option, '=');
            const option_name = option[0 .. equals_idx orelse option.len];
            const inline_value = if (equals_idx) |idx| option[idx + 1 ..] else null;
            if (std.mem.eql(u8, option_name, "help")) {
                return error.HelpRequested;
            }

            var list_field_idx: ?usize = null;
            inline for (spec_info.field_names, spec_info.field_types, 0..) |field_name, field_type, i| {
                if (comptime field_type == []const []const u8) {
                    if (std.mem.eql(u8, field_name, option_name)) {
                        list_field_idx = i;
                    }
                }
            }
            if (list_field_idx) |list_idx| {
                seen[list_idx] = true;
                if (inline_value) |val| {
                    try scratch[list_idx].append(allocator, val);
                } else {
                    while (args.next()) |val| {
                        if (std.mem.startsWith(u8, val, "--")) {
                            pending = val;
                            break;
                        }
                        try scratch[list_idx].append(allocator, val);
                    }
                }
                continue;
            }

            const field_idx = try setNamedOption(Spec, options, &parsed, option_name, inline_value, args, &seen);
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

    inline for (spec_info.field_types, 0..) |field_type, i| {
        if (required_mask[i]) {
            const missing = if (comptime field_type == []const []const u8)
                scratch[i].items.len == 0
            else
                !seen[i];
            if (missing) return error.MissingRequiredOption;
        }
    }

    var transferred: usize = 0;
    errdefer {
        inline for (spec_info.field_names, spec_info.field_types, 0..) |field_name, field_type, i| {
            if (comptime field_type == []const []const u8) {
                if (i < transferred) allocator.free(@field(parsed, field_name));
            }
        }
    }
    inline for (spec_info.field_names, spec_info.field_types, 0..) |field_name, field_type, i| {
        if (comptime field_type == []const []const u8) {
            @field(parsed, field_name) = try scratch[i].toOwnedSlice(allocator);
            transferred = i + 1;
        }
    }

    return parsed;
}

pub fn requiredUsage(comptime spec_or_type: anytype, comptime options: Options(spec_or_type)) []const []const u8 {
    if (@TypeOf(spec_or_type) != type) {
        return &.{};
    }

    return comptime blk: {
        const Spec = ParsedType(spec_or_type, options);
        const RawSpecType = spec_or_type;
        const raw_info = @typeInfo(RawSpecType).@"struct";
        const implied_index = firstImpliedFieldIndex(Spec, options);

        var result = ComptimeArrayList([]const u8){};
        for (raw_info.field_names, raw_info.field_attrs, 0..) |field_name, field_attrs, i| {
            if (field_attrs.default_value_ptr != null) continue;
            const value_name = value_name_blk: {
                var out: [field_name.len]u8 = undefined;
                _ = std.ascii.upperString(&out, field_name);
                break :value_name_blk out;
            };
            const usage: UsageDescription = @field(options.usage_descriptions, field_name) orelse .{};
            const part = usage.text orelse if (implied_index != null and implied_index.? == i)
                std.fmt.comptimePrint("--{s} <{s}> or <{s}> (positional)", .{ field_name, value_name[0..], value_name[0..] })
            else
                std.fmt.comptimePrint("--{s}", .{field_name});
            result.append(part);
        }
        break :blk result.items;
    };
}

pub fn fullUsage(comptime spec_or_type: anytype, comptime options: Options(spec_or_type)) []const []const u8 {
    const Spec = ParsedType(spec_or_type, options);

    const spec_is_type = @TypeOf(spec_or_type) == type;
    const RawSpecType = SpecType(spec_or_type);
    const raw_info = @typeInfo(RawSpecType).@"struct";
    const spec_info = @typeInfo(Spec).@"struct";
    const implied_index = comptime firstImpliedFieldIndex(Spec, options);

    return comptime blk: {
        var base_parts = ComptimeArrayList([]const u8){};
        var type_parts = ComptimeArrayList([]const u8){};
        var default_parts = ComptimeArrayList(?[]const u8){};
        var max_base_len: usize = 0;
        var max_type_len: usize = 0;

        for (raw_info.field_names, raw_info.field_types, raw_info.field_attrs, 0..) |field_name, field_type, field_attrs, i| {
            const spec_field_type = spec_info.field_types[i];
            const value_name = value_name_blk: {
                var out: [field_name.len]u8 = undefined;
                _ = std.ascii.upperString(&out, field_name);
                break :value_name_blk out;
            };
            const usage: UsageDescription = @field(options.usage_descriptions, field_name) orelse .{};
            const type_hint = typeHintText(spec_field_type);
            const part = usage.text orelse if (spec_field_type == []const []const u8)
                std.fmt.comptimePrint("--{s} <{s}>...", .{ field_name, value_name[0..] })
            else if (implied_index != null and implied_index.? == i)
                std.fmt.comptimePrint("--{s} <{s}> or <{s}> (positional)", .{ field_name, value_name[0..], value_name[0..] })
            else if (spec_field_type == bool)
                std.fmt.comptimePrint("--{s}", .{field_name})
            else if (@field(options.bare_values, field_name) != null)
                std.fmt.comptimePrint("--{s}[=<{s}>]", .{ field_name, value_name[0..] })
            else
                std.fmt.comptimePrint("--{s} <{s}>", .{ field_name, value_name[0..] });

            const base = if (spec_is_type and field_attrs.default_value_ptr == null)
                part ++ " [required]"
            else
                part;
            if (base.len > max_base_len) {
                max_base_len = base.len;
            }
            if (type_hint.len > max_type_len) {
                max_type_len = type_hint.len;
            }

            const auto_default = if (!spec_is_type)
                defaultValueText(@field(spec_or_type, field_name))
            else if (field_attrs.defaultValue(field_type)) |value|
                defaultValueText(value)
            else
                null;
            const default_text = usage.default_text orelse auto_default;

            base_parts.append(base);
            type_parts.append(type_hint);
            default_parts.append(default_text);
        }

        var result = ComptimeArrayList([]const u8){};
        for (0..base_parts.items.len) |i| {
            const base = base_parts.items[i];
            const type_hint = type_parts.items[i];
            const type_padding: [max_type_len - type_hint.len]u8 = @splat(' ');
            const suffix = if (default_parts.items[i]) |default_text|
                std.fmt.comptimePrint("({s},{s} default: {s})", .{ type_hint, type_padding, default_text })
            else
                std.fmt.comptimePrint("({s})", .{type_hint});
            const base_padding: [max_base_len - base.len + 1]u8 = @splat(' ');
            result.append(std.fmt.comptimePrint("{s}{s}{s}", .{ base, base_padding, suffix }));
        }
        break :blk result.items;
    };
}

pub fn suggestOption(
    comptime spec_or_type: anytype,
    comptime options: Options(spec_or_type),
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

fn defaultValueText(comptime value: anytype) ?[]const u8 {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .bool => if (value) "true" else "false",
        .int, .float => std.fmt.comptimePrint("{}", .{value}),
        .@"enum" => @tagName(value),
        .optional => if (value) |inner|
            defaultValueText(inner)
        else
            null,
        .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8)
            value
        else
            std.fmt.comptimePrint("{any}", .{value}),
        else => std.fmt.comptimePrint("{any}", .{value}),
    };
}

fn fieldNameList(comptime T: type) []const u8 {
    var result = ComptimeArrayList(u8){};
    switch (@typeInfo(T)) {
        inline .@"enum", .@"union" => |info| {
            inline for (info.field_names, 0..) |field_name, i| {
                if (i != 0) {
                    result.append('|');
                }
                result.appendSlice(field_name);
                if (@hasField(@TypeOf(info), "field_types") and info.field_types[i] != void) {
                    result.appendSlice(std.fmt.comptimePrint("({s})", .{@typeName(info.field_types[i])}));
                }
            }
        },
        else => @compileError("expected enum or union type, found '" ++ @typeName(T) ++ "'"),
    }
    return result.items;
}

fn typeHintText(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => "integer",
        .float => "float",
        .bool => "bool",
        .pointer => |ptr| blk: {
            if (ptr.size == .slice and ptr.child == u8) break :blk "string";
            if (ptr.size == .slice) {
                const inner = @typeInfo(ptr.child);
                if (inner == .pointer and inner.pointer.size == .slice and inner.pointer.child == u8) {
                    break :blk "string...";
                }
            }
            break :blk @typeName(T);
        },
        .optional => |opt| std.fmt.comptimePrint("?{s}", .{typeHintText(opt.child)}),
        inline .@"enum", .@"union" => std.fmt.comptimePrint("enum({s})", .{fieldNameList(T)}),
        else => @typeName(T),
    };
}

fn NormalizedSpecType(comptime RawSpec: type, comptime options: anytype) type {
    const raw_struct = @typeInfo(RawSpec).@"struct";
    comptime var field_types: [raw_struct.field_names.len]type = undefined;
    comptime var field_attrs: [raw_struct.field_names.len]std.lang.Type.Struct.FieldAttributes = undefined;

    inline for (raw_struct.field_types, raw_struct.field_attrs, 0..) |raw_field_type, raw_field_attrs, i| {
        field_types[i] = NormalizedFieldType(raw_field_type, options);
        field_attrs[i] = .{ .@"align" = raw_field_attrs.@"align" };
    }

    if (raw_struct.is_tuple) {
        return @Tuple(&field_types);
    }

    return @Struct(raw_struct.layout, null, raw_struct.field_names, &field_types, &field_attrs);
}

fn NormalizedFieldType(comptime T: type, comptime options: anytype) type {
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
        .optional => |opt| ?NormalizedFieldType(opt.child, options),
        else => T,
    };
}

fn initSpecDefaults(comptime RawSpec: type, comptime Spec: type) Spec {
    const raw_info = @typeInfo(RawSpec).@"struct";
    const spec_info = @typeInfo(Spec).@"struct";
    var spec: Spec = undefined;
    inline for (raw_info.field_types, raw_info.field_attrs, 0..) |raw_field_type, raw_field_attrs, i| {
        const spec_field_name = spec_info.field_names[i];
        const spec_field_type = spec_info.field_types[i];
        if (raw_field_attrs.defaultValue(raw_field_type)) |default_value| {
            @field(spec, spec_field_name) = coerceValue(spec_field_type, default_value);
        } else if (spec_field_type == []const []const u8) {
            @field(spec, spec_field_name) = &.{};
        } else {
            @field(spec, spec_field_name) = undefined;
        }
    }
    return spec;
}

fn normalizeSpecValue(comptime Out: type, spec: anytype) Out {
    const In = @TypeOf(spec);
    if (In == Out) {
        return spec;
    }

    const out_info = @typeInfo(Out).@"struct";
    var out: Out = undefined;
    inline for (out_info.field_names, out_info.field_types) |field_name, field_type| {
        @field(out, field_name) = coerceValue(field_type, @field(spec, field_name));
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

fn firstImpliedFieldIndex(comptime Spec: type, comptime options: anytype) ?usize {
    if (!options.allow_implied) {
        return null;
    }
    inline for (@typeInfo(Spec).@"struct".field_types, 0..) |field_type, i| {
        if (field_type != bool) {
            return i;
        }
    }
    return null;
}

fn setNamedOption(
    comptime Spec: type,
    comptime options: anytype,
    parsed: *Spec,
    option_name: []const u8,
    inline_value: ?[]const u8,
    args: anytype,
    seen: *const [@typeInfo(Spec).@"struct".field_names.len]bool,
) Error!usize {
    const Field = std.meta.FieldEnum(Spec);
    const field = std.meta.stringToEnum(Field, option_name) orelse return error.UnknownOption;
    const i = @backingInt(field);
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
            if (FieldType == []const []const u8) {
                unreachable; // list fields are intercepted in parseImpl before setNamedOption
            }
            if (comptime @field(options.bare_values, field_name)) |bare| {
                @field(parsed.*, field_name) = if (inline_value) |value| try parseValue(FieldType, value) else bare;
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
    seen: *const [@typeInfo(Spec).@"struct".field_names.len]bool,
) Error!usize {
    const spec_info = @typeInfo(Spec).@"struct";
    inline for (spec_info.field_names, spec_info.field_types, 0..) |field_name, field_type, i| {
        if (field_type != bool) {
            if (seen[i]) {
                return error.OptionAlreadySet;
            }
            @field(parsed.*, field_name) = try parseValue(field_type, value);
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
        .@"union" => |u| blk: {
            const Tag: type = u.tag_type orelse @compileError("untagged unions are not supported");
            comptime var non_void_field: ?struct { tag: Tag, tp: type } = null;
            inline for (u.field_names, u.field_types) |field_name, field_type| {
                if (field_type != void) {
                    if (non_void_field != null) {
                        @compileError("only one value field is supported");
                    }
                    non_void_field = .{
                        .tag = comptime std.meta.stringToEnum(Tag, field_name).?,
                        .tp = field_type,
                    };
                }
            }

            inline for (u.field_names, u.field_types) |field_name, field_type| {
                if (field_type == void and std.mem.eql(u8, value, field_name)) break :blk @unionInit(T, field_name, {});
            }

            break :blk if (non_void_field) |nv|
                @unionInit(T, @tagName(nv.tag), try parseValue(nv.tp, value))
            else
                error.InvalidValue;
        },
        else => @compileError("unsupported arg parser field type"),
    };
}
