const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const name = b.option([]const u8, "name", "Change the name of the binary") orelse "pawnocchio";
    const runtime_net = b.option(bool, "runtime_net", "whether to exclude the binary from the binary") orelse false;
    const net = b.option([]const u8, "net", "Change the net to be used") orelse blk: {
        if (runtime_net) {
            std.debug.print("When using a runtime net you need to give an absolute path to the network\n", .{});
            return error.NoAbsoluteNetPathWithRuntimeNet;
        }
        break :blk "pawnocchio-nets/networks/net22_1280_take6.nnue";
    };

    const use_tbs = true;
    const minimal_executable = switch (optimize) {
        .ReleaseFast, .ReleaseSmall => true,
        .Debug, .ReleaseSafe => false,
    };
    const net_module = b.createModule(
        .{
            .root_source_file = std.Build.LazyPath{
                .cwd_relative = net, // OB passes the path as an absolute path so this is is the only way
            },
        },
    );

    const exe = b.addExecutable(.{
        .name = name,
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
        .omit_frame_pointer = minimal_executable,
        .strip = minimal_executable,
        .link_libc = target.result.os.tag == .windows or use_tbs,
    });
    const exe_options = b.addOptions();
    exe_options.addOption(bool, "use_tbs", use_tbs);
    exe_options.addOption(bool, "runtime_net", runtime_net);
    exe_options.addOption([]const u8, "net_path", net);
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
    exe.root_module.addImport("net", net_module);
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
    test_options.addOption(bool, "runtime_net", runtime_net);
    test_options.addOption([]const u8, "net_path", net);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("net", net_module);
    exe_unit_tests.root_module.addOptions("build_options", test_options);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("net", net_module);
    lib_unit_tests.root_module.addOptions("build_options", test_options);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_lib_unit_tests.step);

    const check_step = b.step("check", "Check if project compiles");
    check_step.dependOn(&exe.step);
}
