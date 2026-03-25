const std = @import("std");

const build_net = @import("build/net.zig");
const build_tuning = @import("build/tuning.zig");
const EvalMode = @import("src/eval_mode.zig").EvalMode;

const base_version = "2.0";

fn gitShortHash(b: *std.Build) ?[]const u8 {
    var exit_code: u8 = undefined;
    const argv = if (b.build_root.path) |build_root_path|
        &[_][]const u8{ "git", "-C", build_root_path, "rev-parse", "--short=7", "HEAD" }
    else
        &[_][]const u8{ "git", "rev-parse", "--short=7", "HEAD" };
    const stdout = b.runAllowFail(argv, &exit_code, .Ignore) catch return null;
    const short_sha = std.mem.trim(u8, stdout, &std.ascii.whitespace);
    if (short_sha.len == 0) {
        return null;
    }
    return short_sha;
}

fn defaultVersionString(b: *std.Build) []const u8 {
    if (gitShortHash(b)) |short_sha| {
        return b.fmt("{s}-dev-{s}", .{ base_version, short_sha });
    }
    return b.fmt("{s}-dev", .{base_version});
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const name = b.option([]const u8, "name", "change the binary name") orelse "pawnocchio";
    const version_string = b.option([]const u8, "version_string", "set executable version string") orelse defaultVersionString(b);
    const eval_mode = b.option(EvalMode, "eval", "which evaluator to use") orelse .nnue;
    const default_net_path = "pawnocchio-nets/networks/mixed_data_chonked5.nnue";

    const net_override = b.option(std.Build.LazyPath, "net", "use this net");
    if (eval_mode == .hce and net_override != null) {
        std.log.err("build cannot set both -Deval=hce and -Dnet\n", .{});
        return error.IncompatibleFlags;
    }
    const generated_files = b.addWriteFiles();
    const tuning_generated_file = try build_tuning.prepareGeneratedTuning(b, generated_files);
    const eval_input: build_net.EvalInput = if (eval_mode == .hce)
        .hce
    else
        try build_net.prepareNet(
            b,
            target.result.cpu,
            b.allocator,
            build_net.selectNet(b, net_override, default_net_path),
            generated_files,
        );
    const linkage_mode = b.option(std.builtin.LinkMode, "link_mode", "set linkage mode");
    const emit_symbols = b.option(bool, "emit_symbols", "keep debug symbols") orelse false;
    const use_tbs = b.option(bool, "use_tbs", "enable tablebases") orelse true;
    const minimal_executable = switch (optimize) {
        .ReleaseFast, .ReleaseSmall => true,
        .Debug, .ReleaseSafe => false,
    } and !emit_symbols;

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .omit_frame_pointer = minimal_executable,
            .strip = minimal_executable,
            .link_libc = target.result.os.tag == .windows or use_tbs,
        }),
        .use_llvm = true,
        .linkage = linkage_mode,
    });
    build_net.configureArtifact(b, exe, build_net.buildOptions(b, version_string, use_tbs, eval_mode, eval_input), eval_input, generated_files, tuning_generated_file);
    if (use_tbs) {
        exe.addCSourceFile(.{
            .file = b.path("src/Pyrrhic/tbprobe.c"),
            .flags = &.{
                "-fno-sanitize=undefined",
                "-O3",
            },
            .language = .c,
        });
        exe.addIncludePath(b.path("src/Pyrrhic/"));
    }
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
        }),
        .use_llvm = true,
    });
    build_net.configureArtifact(b, unit_tests, build_net.buildOptions(b, version_string, false, eval_mode, eval_input), eval_input, generated_files, tuning_generated_file);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const check_step = b.step("check", "Check if project compiles");
    check_step.dependOn(&exe.step);
}
