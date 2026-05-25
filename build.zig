const std = @import("std");

const build_net = @import("build/net.zig");
const build_release = @import("build/release.zig");
const build_tuning = @import("build/tuning.zig");
const EvalMode = @import("src/eval_mode.zig").EvalMode;

const BASE_VERSION = "2.0";
const DEFAULT_NET_PATH = "pawnocchio-nets/networks/pretrained.nnue";

fn gitShortHash(b: *std.Build) ?[]const u8 {
    var exit_code: u8 = undefined;
    const argv = if (b.build_root.path) |build_root_path|
        &[_][]const u8{ "git", "-C", build_root_path, "rev-parse", "--short=7", "HEAD" }
    else
        &[_][]const u8{ "git", "rev-parse", "--short=7", "HEAD" };
    const stdout = b.runAllowFail(argv, &exit_code, .ignore) catch return null;
    const short_sha = std.mem.trim(u8, stdout, &std.ascii.whitespace);
    if (short_sha.len == 0) {
        return null;
    }
    return short_sha;
}

fn defaultVersion(b: *std.Build) []const u8 {
    if (gitShortHash(b)) |short_sha| {
        return b.fmt("{s}-dev-{s}", .{ BASE_VERSION, short_sha });
    }
    return BASE_VERSION ++ "-dev";
}

const ExecutableOptions = struct {
    name: []const u8,
    version: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    eval_mode: EvalMode,
    link_mode: ?std.builtin.LinkMode = null,
    emit_symbols: bool = false,
    use_tbs: bool = true,
    use_numa: bool = false,
    tools_only: bool = false,
};

const Inputs = struct {
    generated_files: *std.Build.Step.WriteFile,
    tuning_generated_file: std.Build.LazyPath,
    input: build_net.Input,
};

fn prepareInputs(
    b: *std.Build,
    transform_tool: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    eval_mode: EvalMode,
    net_override: ?std.Build.LazyPath,
) !Inputs {
    if (eval_mode != .nnue and net_override != null) {
        std.log.err("cannot set net when eval mode is not nnue\n", .{});
        return error.IncompatibleFlags;
    }

    const generated_files = b.addWriteFiles();
    const tuning_generated_file = try build_tuning.prepareGeneratedTuning(b, generated_files);
    const input: build_net.Input = if (eval_mode == .nnue)
        try build_net.prepareNet(
            b,
            transform_tool,
            target.result.cpu,
            net_override orelse b.path(DEFAULT_NET_PATH),
        )
    else
        .hce;
    return .{
        .generated_files = generated_files,
        .tuning_generated_file = tuning_generated_file,
        .input = input,
    };
}

fn configureArtifact(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    options: ExecutableOptions,
    inputs: Inputs,
) void {
    build_net.configureArtifact(
        b,
        artifact,
        build_net.addOptions(
            b,
            options.version,
            options.use_tbs,
            options.use_numa,
            options.tools_only,
            options.eval_mode,
            inputs.input,
        ),
        inputs.input,
        inputs.generated_files,
        inputs.tuning_generated_file,
    );
}

fn addExecutable(
    b: *std.Build,
    options: ExecutableOptions,
    inputs: Inputs,
) !*std.Build.Step.Compile {
    const minimal_executable = switch (options.optimize) {
        .ReleaseFast, .ReleaseSmall => true,
        .Debug, .ReleaseSafe => false,
    } and !options.emit_symbols;

    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = options.target,
            .optimize = options.optimize,
            .omit_frame_pointer = minimal_executable,
            .strip = minimal_executable,
            .link_libc = options.target.result.os.tag == .windows or options.use_tbs or options.use_numa,
        }),
        .use_llvm = true,
        .linkage = options.link_mode,
    });
    configureArtifact(b, exe, options, inputs);
    if (options.use_numa) {
        exe.root_module.linkSystemLibrary("numa", .{});
    }
    if (options.use_tbs) {
        exe.root_module.addCSourceFile(.{
            .file = b.path("src/Pyrrhic/tbprobe.c"),
            .flags = &.{
                "-O3",
            },
            .language = .c,
        });
        exe.root_module.addIncludePath(b.path("src/Pyrrhic/"));
    }

    return exe;
}

fn addBuildStep(
    b: *std.Build,
    step_name: []const u8,
    description: []const u8,
    version: []const u8,
    transform_tool: *std.Build.Step.Compile,
    config: build_release.Config,
    tools_only: bool,
    use_numa: bool,
) !void {
    const step = b.step(step_name, description);
    for (config.specs) |spec| {
        const target = try spec.resolveTarget(b);
        const inputs = try prepareInputs(b, transform_tool, target, config.eval_mode, null);
        const exe = try addExecutable(b, .{
            .name = spec.name(b, version),
            .version = version,
            .target = target,
            .optimize = config.optimize,
            .eval_mode = config.eval_mode,
            .link_mode = spec.link_mode,
            .use_numa = use_numa,
            .tools_only = tools_only or config.tools_only,
        }, inputs);
        const install_artifact = b.addInstallArtifact(exe, .{});
        step.dependOn(&install_artifact.step);
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const name = b.option([]const u8, "name", "change the binary name") orelse "pawnocchio";
    const version = b.option([]const u8, "version_string", "set executable version string") orelse defaultVersion(b);
    const eval_mode = b.option(EvalMode, "eval", "which evaluator to use") orelse .nnue;
    const net_override = b.option(std.Build.LazyPath, "net", "use this net");
    const link_mode = b.option(std.builtin.LinkMode, "link_mode", "set linkage mode");
    const emit_symbols = b.option(bool, "emit_symbols", "keep debug symbols") orelse false;
    const use_tbs = b.option(bool, "use_tbs", "enable tablebases") orelse true;
    const use_numa = b.option(bool, "use_numa", "link to libnuma for NUMA aware resource management") orelse false;
    const tools_only = b.option(bool, "tools_only", "disable UCI, datagen, bench, and genfens to minimize tool binaries") orelse false;
    if (use_numa and target.result.os.tag != .linux) {
        std.log.err("build cannot use numa on non linux targets\n", .{});
        return error.IncompatibleFlags;
    }
    const transform_tool = build_net.addTransformTool(b);
    const inputs = try prepareInputs(b, transform_tool, target, eval_mode, net_override);

    const exe = try addExecutable(b, .{
        .name = name,
        .version = version,
        .target = target,
        .optimize = optimize,
        .eval_mode = eval_mode,
        .link_mode = link_mode,
        .emit_symbols = emit_symbols,
        .use_tbs = use_tbs,
        .use_numa = use_numa,
        .tools_only = tools_only,
    }, inputs);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "run pawnocchio");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = use_numa,
        }),
        .use_llvm = true,
    });
    configureArtifact(b, unit_tests, .{
        .name = "test",
        .version = version,
        .target = target,
        .optimize = optimize,
        .eval_mode = eval_mode,
        .use_tbs = false,
        .use_numa = use_numa,
        .tools_only = tools_only,
    }, inputs);
    if (use_numa) {
        unit_tests.root_module.linkSystemLibrary("numa", .{});
    }
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const check_step = b.step("check", "check if project compiles");
    check_step.dependOn(&exe.step);

    try addBuildStep(b, "tool_builds", "build tool artifacts", version, transform_tool, build_release.TOOLS, tools_only, use_numa);
    try addBuildStep(b, "release_builds", "build release artifacts", version, transform_tool, build_release.RELEASE, tools_only, use_numa);
}
