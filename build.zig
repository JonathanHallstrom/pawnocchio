const std = @import("std");

fn copyNetwork(net: []const u8) !void {
    var should_close = true;
    var nets_directory = std.fs.cwd().openDir("pawnocchio-nets/networks/", .{}) catch |e| switch (e) {
        error.FileNotFound => blk: {
            should_close = false;
            break :blk std.fs.cwd();
        },
        else => return e,
    };
    defer if (should_close) nets_directory.close();

    std.fs.cwd().makeDir("src/networks/") catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    var src_networks = try std.fs.cwd().openDir("src/networks/", .{});
    defer src_networks.close();

    nets_directory.copyFile(net, src_networks, "net.nnue", .{}) catch |e| switch (e) {
        error.FileNotFound => std.debug.panic("{s} was not found!\n", .{net}),
        else => return e,
    };
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    const name = b.option([]const u8, "name", "Change the name of the binary") orelse "pawnocchio";
    const net = b.option([]const u8, "net", "Change the net to be used") orelse "net17_04_768_400_8_mirrored_2.nnue";
    copyNetwork(net) catch |e| std.debug.panic("copying neural net failed with error: {}\n", .{e});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // const bench = b.addExecutable(.{
    //     .name = "pawnocchio_perft_bench",
    //     .root_source_file = b.path("src/perft_bench.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    const check_step = b.step("check", "Check if project compiles");
    // check_step.dependOn(&bench.step);
    check_step.dependOn(&exe.step);

    // const bench_step = b.step("bench", "Benchmark move generation");
    // b.installArtifact(bench);
    // const bench_cmd = b.addRunArtifact(bench);
    // bench_cmd.step.dependOn(&bench.step);
    // bench_step.dependOn(&bench_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    if (b.args) |args| {
        run_cmd.addArgs(args);
        // bench_cmd.addArgs(args);
    }

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
