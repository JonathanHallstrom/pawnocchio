const std = @import("std");
const EvalMode = @import("../src/eval_mode.zig").EvalMode;

pub const Config = struct {
    specs: []const Spec,
    eval_mode: EvalMode,
    optimize: std.builtin.OptimizeMode,
    tools_only: bool,
};

pub const Spec = struct {
    target: []const u8,
    suffix: []const u8,
    cpu: ?[]const u8 = null,
    link_mode: std.builtin.LinkMode = .static,

    pub fn name(self: Spec, b: *std.Build, version: []const u8) []const u8 {
        return b.fmt("pawnocchio-{s}-{s}", .{ version, self.suffix });
    }

    pub fn resolveTarget(self: Spec, b: *std.Build) !std.Build.ResolvedTarget {
        return b.resolveTargetQuery(try std.Target.Query.parse(.{
            .arch_os_abi = self.target,
            .cpu_features = self.cpu,
        }));
    }
};

const RELEASE_SPECS = [_]Spec{
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64" },
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64_v2", .cpu = "x86_64_v2" },
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64_v3", .cpu = "x86_64_v3" },
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64_v4", .cpu = "x86_64_v4" },
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64_znver1", .cpu = "znver1" },
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64_znver2", .cpu = "znver2" },
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64_znver3", .cpu = "znver3" },
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64_znver4", .cpu = "znver4" },
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64_znver5", .cpu = "znver5" },
    .{ .target = "aarch64-windows", .suffix = "windows-aarch64" },
    .{ .target = "aarch64-windows", .suffix = "windows-aarch64-dotprod", .cpu = "baseline+dotprod" },
    .{ .target = "aarch64-windows", .suffix = "windows-aarch64-modern", .cpu = "baseline+dotprod+i8mm" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64_v2", .cpu = "x86_64_v2" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64_v3", .cpu = "x86_64_v3" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64_v4", .cpu = "x86_64_v4" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64_znver1", .cpu = "znver1" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64_znver2", .cpu = "znver2" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64_znver3", .cpu = "znver3" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64_znver4", .cpu = "znver4" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64_znver5", .cpu = "znver5" },
    .{ .target = "aarch64-linux", .suffix = "linux-aarch64" },
    .{ .target = "aarch64-linux", .suffix = "linux-aarch64-dotprod", .cpu = "baseline+dotprod" },
    .{ .target = "aarch64-linux", .suffix = "linux-aarch64-modern", .cpu = "baseline+dotprod+i8mm" },
    .{ .target = "x86_64-macos", .suffix = "macos-x86_64", .link_mode = .dynamic },
    .{ .target = "x86_64-macos", .suffix = "macos-x86_64_v2", .cpu = "x86_64_v2", .link_mode = .dynamic },
    .{ .target = "aarch64-macos", .suffix = "macos-aarch64-apple_m1", .cpu = "apple_m1", .link_mode = .dynamic },
};

const TOOLS_SPECS = [_]Spec{
    .{ .target = "x86_64-windows", .suffix = "windows-x86_64-tools" },
    .{ .target = "aarch64-windows", .suffix = "windows-aarch64-tools" },
    .{ .target = "x86_64-linux", .suffix = "linux-x86_64-tools" },
    .{ .target = "aarch64-linux", .suffix = "linux-aarch64-tools" },
    .{ .target = "x86_64-macos", .suffix = "macos-x86_64-tools", .link_mode = .dynamic },
    .{ .target = "aarch64-macos", .suffix = "macos-aarch64-tools", .link_mode = .dynamic },
};

pub const RELEASE = Config{
    .specs = &RELEASE_SPECS,
    .eval_mode = .nnue,
    .optimize = .ReleaseFast,
    .tools_only = false,
};

pub const TOOLS = Config{
    .specs = &TOOLS_SPECS,
    .eval_mode = .hce,
    .optimize = .ReleaseSmall,
    .tools_only = true,
};
