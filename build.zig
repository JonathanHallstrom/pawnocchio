const std = @import("std");
const builtin = @import("builtin");

const nnue_arch = @import("src/nnue_arch.zig");
const Weights = nnue_arch.Weights;

fn readNet(path: []const u8, allocator: std.mem.Allocator) !*Weights {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const from_file: *Weights = try allocator.create(Weights);
    _ = try file.readAll(std.mem.asBytes(from_file));

    return from_file;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    if (!target.result.cpu.has(.x86, .avx512f)) {
        return error.AVX512_ONLY;
    }
    const optimize = b.standardOptimizeOption(.{});
    const name = b.option([]const u8, "name", "Change the name of the binary") orelse "pawnocchio";

    const net_name = "mixed_data_dualact.nnue";

    const net = b.option([]const u8, "net", "Change the net to be used") orelse blk: {
        break :blk "pawnocchio-nets/networks/" ++ net_name;
    };

    const net_weights = try readNet(net, b.allocator);
    defer b.allocator.destroy(net_weights);
    nnue_arch.permuteNet(target.result.cpu, net_weights);
    const permuted_net_writing_step = b.addWriteFiles();
    const permuted_net_path = permuted_net_writing_step.add("net", std.mem.asBytes(net_weights));

    const net_module = b.createModule(.{ .root_source_file = permuted_net_path });

    const dynamic = b.option(bool, "dynamic", "build a dynamic executable") orelse false;
    const static = b.option(bool, "static", "build a static executable") orelse false;
    if (static and dynamic) {
        std.log.err("build cannot be both dynamic and static!\n", .{});
        return error.IncompatibleFlags;
    }
    var linkage_mode: ?std.builtin.LinkMode = null;
    if (dynamic) {
        linkage_mode = .dynamic;
    }
    if (static) {
        linkage_mode = .static;
    }
    const emit_symbols = b.option(bool, "emit_symbols", "force debug symbols not to be stripped") orelse false;
    const use_tbs = b.option(bool, "use_tbs", "whether to enable tablebases") orelse true;
    const minimal_executable = switch (optimize) {
        .ReleaseFast, .ReleaseSmall => true,
        .Debug, .ReleaseSafe => false,
    } and !emit_symbols;

    var net_abs_buf: [4096]u8 = undefined;
    const net_absolute = try std.fs.cwd().realpath(net, &net_abs_buf);

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
    exe.root_module.addImport("net", net_module);
    exe.step.dependOn(&permuted_net_writing_step.step);

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "use_tbs", use_tbs);
    exe_options.addOption([]const u8, "net_name", net_name);
    exe_options.addOption([]const u8, "net_path", net_absolute);
    exe.root_module.addOptions("build_options", exe_options);
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
    const test_options = b.addOptions();
    test_options.addOption(bool, "use_tbs", false);
    test_options.addOption([]const u8, "net_path", net);

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe_unit_tests.root_module.addImport("net", net_module);
    exe_unit_tests.root_module.addOptions("build_options", test_options);
    exe_unit_tests.step.dependOn(&permuted_net_writing_step.step);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib_unit_tests.root_module.addImport("net", net_module);
    lib_unit_tests.root_module.addOptions("build_options", test_options);
    lib_unit_tests.step.dependOn(&permuted_net_writing_step.step);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_lib_unit_tests.step);

    const check_step = b.step("check", "Check if project compiles");
    check_step.dependOn(&exe.step);
}
