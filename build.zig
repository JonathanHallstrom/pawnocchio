const std = @import("std");

const build_release = @import("build/release.zig");
const build_tuning = @import("build/tuning.zig");
const EvalMode = @import("src/eval_mode.zig").EvalMode;

const BASE_VERSION = "3.0";
const DEFAULT_NET_PATH = "pp_big11.nnue";

fn gitShortHash(b: *std.Build) ?[]const u8 {
    b.graph.poisonCache();
    const build_root_path = b.root.joinString(b.allocator, "") catch @panic("OOM");
    const argv = &[_][]const u8{ "git", "-C", build_root_path, "rev-parse", "--short=7", "HEAD" };
    const stdout = switch (b.runFallible(argv, .{ .stderr_behavior = .ignore })) {
        .success => |stdout| stdout,
        .spawn_failed, .bad_exit_code, .crashed => return null,
    };
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
    optimize: std.lang.Optimize,
    eval_mode: EvalMode,
    link_mode: ?std.lang.LinkMode = null,
    emit_symbols: bool = false,
    use_tbs: bool = true,
    use_numa: bool = false,
    tools_only: bool = false,
};

const Inputs = struct {
    tuning_generated_file: std.Build.LazyPath,
    net: ?std.Build.LazyPath,
};

fn prepareInputs(
    b: *std.Build,
    eval_mode: EvalMode,
    net_override: ?std.Build.LazyPath,
) !Inputs {
    if (eval_mode != .nnue and net_override != null) {
        std.log.err("cannot set net when eval mode is not nnue", .{});
        return error.IncompatibleFlags;
    }

    const net: ?std.Build.LazyPath = if (eval_mode == .nnue)
        net_override orelse b.path(DEFAULT_NET_PATH)
    else
        null;
    return .{
        .tuning_generated_file = try build_tuning.prepareGeneratedTuning(b),
        .net = net,
    };
}

fn lazyPathBasename(lazy_path: std.Build.LazyPath) []const u8 {
    const basename = std.Io.Dir.path.basename(switch (lazy_path) {
        .src_path => |src_path| src_path.sub_path,
        .cwd_relative => |cwd_relative| cwd_relative,
        .dependency => |dependency| dependency.sub_path,
        .relative => |relative| relative.sub_path,
        .generated => "",
    });
    if (basename.len == 0) {
        std.process.fatal("net path has no filename: '{f}'", .{lazy_path});
    }
    return basename;
}

fn configureArtifact(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    options: ExecutableOptions,
    inputs: Inputs,
) void {
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version_string", options.version);
    build_options.addOption(bool, "use_tbs", options.use_tbs);
    build_options.addOption(bool, "use_numa", options.use_numa);
    build_options.addOption(bool, "tools_only", options.tools_only);
    build_options.addOption([]const u8, "eval", @tagName(options.eval_mode));
    build_options.addOption([]const u8, "eval_identifier", if (inputs.net) |net| lazyPathBasename(net) else "hce");
    if (inputs.net) |net| artifact.root_module.addImport("net", b.createModule(.{ .root_source_file = net }));
    artifact.root_module.addImport("tuning_generated", b.createModule(.{ .root_source_file = inputs.tuning_generated_file }));
    artifact.root_module.addOptions("build_options", build_options);
}

fn addExecutable(
    b: *std.Build,
    options: ExecutableOptions,
    inputs: Inputs,
) !*std.Build.Step.Compile {
    const minimal_executable = switch (options.optimize) {
        .fast, .small => true,
        .debug, .safe => false,
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
            .no_builtin = true,
        }),
        .use_llvm = true,
        .linkage = options.link_mode,
    });
    configureArtifact(b, exe, options, inputs);
    if (options.use_numa) {
        exe.root_module.linkSystemLibrary("numa", .{});
    }
    if (options.use_tbs) {
        const tbprobe = b.addTranslateC(.{
            .root_source_file = b.path("src/Pyrrhic/tbprobe.h"),
            .target = options.target,
            .optimize = options.optimize,
        });
        exe.root_module.addImport("tbprobe", tbprobe.createModule());
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
    config: build_release.Config,
    tools_only: bool,
    use_numa: bool,
) !void {
    const step = b.step(step_name, description);
    const inputs = try prepareInputs(b, config.eval_mode, null);
    for (config.specs) |spec| {
        const target = try spec.resolveTarget(b);
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
    const link_mode = b.option(std.lang.LinkMode, "link_mode", "set linkage mode");
    const emit_symbols = b.option(bool, "emit_symbols", "keep debug symbols") orelse false;
    const use_tbs = b.option(bool, "use_tbs", "enable tablebases") orelse true;
    const use_numa = b.option(bool, "use_numa", "link to libnuma for NUMA aware resource management") orelse false;
    const tools_only = b.option(bool, "tools_only", "disable UCI, datagen, bench, and genfens to minimize tool binaries") orelse false;
    if (use_numa and target.result.os.tag != .linux) {
        std.log.err("build cannot use numa on non linux targets", .{});
        return error.IncompatibleFlags;
    }
    const inputs = try prepareInputs(b, eval_mode, net_override);

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

    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "run pawnocchio");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = use_numa,
            .no_builtin = true,
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

    try addBuildStep(b, "tool_builds", "build tool artifacts", version, build_release.TOOLS, tools_only, use_numa);
    try addBuildStep(b, "release_builds", "build release artifacts", version, build_release.RELEASE, tools_only, use_numa);
}
