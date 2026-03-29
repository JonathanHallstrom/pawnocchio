const std = @import("std");

const EvalMode = @import("../src/eval_mode.zig").EvalMode;
const nnue_arch = @import("../src/nnue_arch.zig");

pub const Input = union(enum) {
    hce,
    nnue: struct {
        identifier: []const u8,
        file: std.Build.LazyPath,
    },
};

pub fn addTransformTool(b: *std.Build) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "transform-net",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/transform_net.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    exe.root_module.addImport("nnue_arch", b.createModule(.{
        .root_source_file = b.path("src/nnue_arch.zig"),
    }));
    return exe;
}

pub fn prepareNet(
    b: *std.Build,
    transform_tool: *std.Build.Step.Compile,
    cpu: std.Target.Cpu,
    net_path: std.Build.LazyPath,
) !Input {
    const run = b.addRunArtifact(transform_tool);
    run.addArgs(&.{
        @tagName(nnue_arch.target(cpu)),
        @tagName(cpu.arch.endian()),
    });
    run.addFileArg(net_path);

    return .{ .nnue = .{
        .identifier = net_path.basename(b, null),
        .file = run.addOutputFileArg("net"),
    } };
}

pub fn addOptions(
    b: *std.Build,
    version: []const u8,
    use_tbs: bool,
    use_numa: bool,
    tools_only: bool,
    eval_mode: EvalMode,
    input: Input,
) *std.Build.Step.Options {
    const options = b.addOptions();
    options.addOption([]const u8, "version_string", version);
    options.addOption(bool, "use_tbs", use_tbs);
    options.addOption(bool, "use_numa", use_numa);
    options.addOption(bool, "tools_only", tools_only);
    options.addOption([]const u8, "eval", @tagName(eval_mode));
    options.addOption([]const u8, "eval_identifier", switch (input) {
        .hce => "hce",
        .nnue => |nnue| nnue.identifier,
    });
    return options;
}

pub fn configureArtifact(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    options: *std.Build.Step.Options,
    input: Input,
    generated_files: *std.Build.Step.WriteFile,
    tuning_generated_file: std.Build.LazyPath,
) void {
    switch (input) {
        .hce => {},
        .nnue => |nnue| artifact.root_module.addImport("net", b.createModule(.{ .root_source_file = nnue.file })),
    }
    artifact.root_module.addImport("tuning_generated", b.createModule(.{ .root_source_file = tuning_generated_file }));
    artifact.root_module.addOptions("build_options", options);
    artifact.step.dependOn(&generated_files.step);
}
