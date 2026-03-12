const std = @import("std");
const builtin = @import("builtin");

const Eval = @import("src/evaluation.zig").Eval;
const nnue_arch = @import("src/nnue_arch.zig");
const Weights = nnue_arch.Weights;

const EvalInput = union(enum) {
    hce,
    nnue: struct {
        identifier: []const u8,
        file: std.Build.LazyPath,
    },
};

fn selectNet(
    b: *std.Build,
    net_override: ?std.Build.LazyPath,
    default_net_path: []const u8,
) std.Build.LazyPath {
    return net_override orelse b.path(default_net_path);
}

fn readNet(path: []const u8, allocator: std.mem.Allocator) !*Weights {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const from_file: *Weights = try allocator.create(Weights);
    _ = try file.readAll(std.mem.asBytes(from_file));

    return from_file;
}

fn prepareNet(
    b: *std.Build,
    cpu: std.Target.Cpu,
    allocator: std.mem.Allocator,
    net_lp: std.Build.LazyPath,
    write_files: *std.Build.Step.WriteFile,
) !EvalInput {
    const net_weights = try readNet(net_lp.getPath(b), allocator);
    defer allocator.destroy(net_weights);
    nnue_arch.permuteNet(cpu, net_weights);

    return .{ .nnue = .{
        .identifier = net_lp.basename(b, null),
        .file = write_files.add("net", std.mem.asBytes(net_weights)),
    } };
}

fn buildOptions(
    b: *std.Build,
    use_tbs: bool,
    eval_mode: Eval,
    eval_input: EvalInput,
) *std.Build.Step.Options {
    const options = b.addOptions();
    options.addOption(bool, "use_tbs", use_tbs);
    options.addOption([]const u8, "eval", @tagName(eval_mode));
    options.addOption([]const u8, "eval_identifier", switch (eval_input) {
        .hce => "hce",
        .nnue => |nnue| nnue.identifier,
    });
    return options;
}

fn configureArtifact(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    build_options: *std.Build.Step.Options,
    eval_input: EvalInput,
    permuted_net_writing_step: *std.Build.Step.WriteFile,
) void {
    switch (eval_input) {
        .hce => {},
        .nnue => |nnue| artifact.root_module.addImport("net", b.createModule(.{ .root_source_file = nnue.file })),
    }
    artifact.root_module.addOptions("build_options", build_options);
    artifact.step.dependOn(&permuted_net_writing_step.step);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const name = b.option([]const u8, "name", "change the binary name") orelse "pawnocchio";
    const eval_mode = b.option(Eval, "eval", "which evaluator to use") orelse .nnue;
    const default_net_path = "pawnocchio-nets/networks/mixed_data_chonked5.nnue";

    const net_override = b.option(std.Build.LazyPath, "net", "use this net");
    if (eval_mode == .hce and net_override != null) {
        std.log.err("build cannot set both -Deval=hce and -Dnet\n", .{});
        return error.IncompatibleFlags;
    }
    const permuted_net_writing_step = b.addWriteFiles();
    const eval_input: EvalInput = if (eval_mode == .hce)
        .hce
    else
        try prepareNet(
            b,
            target.result.cpu,
            b.allocator,
            selectNet(b, net_override, default_net_path),
            permuted_net_writing_step,
        );
    const dynamic = b.option(bool, "dynamic", "build dynamic") orelse false;
    const static = b.option(bool, "static", "build static") orelse false;
    if (static and dynamic) {
        std.log.err("build cannot be both dynamic and static!\n", .{});
        return error.IncompatibleFlags;
    }
    const linkage_mode: ?std.builtin.LinkMode = if (dynamic)
        .dynamic
    else if (static)
        .static
    else
        null;
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
    configureArtifact(b, exe, buildOptions(b, use_tbs, eval_mode, eval_input), eval_input, permuted_net_writing_step);
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
    configureArtifact(b, unit_tests, buildOptions(b, false, eval_mode, eval_input), eval_input, permuted_net_writing_step);
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const check_step = b.step("check", "Check if project compiles");
    check_step.dependOn(&exe.step);
}
