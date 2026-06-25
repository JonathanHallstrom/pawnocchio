const std = @import("std");
const nnue_arch = @import("nnue_arch");

fn usage() noreturn {
    std.process.fatal("usage: transform_net <target> <endian> <input> <output>", .{});
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.next() orelse unreachable;
    const target_name = args.next() orelse usage();
    const endian_name = args.next() orelse usage();
    const input_path = args.next() orelse usage();
    const output_path = args.next() orelse usage();
    if (args.next() != null) usage();

    const target_kind = nnue_arch.parseTarget(target_name) orelse {
        std.process.fatal("unknown net target '{s}'", .{target_name});
    };
    const endian = nnue_arch.parseEndian(endian_name) orelse {
        std.process.fatal("unknown endian '{s}'", .{endian_name});
    };

    var input = try std.Io.Dir.cwd().openFile(init.io, input_path, .{});
    defer input.close(init.io);

    const weights = try init.gpa.create(nnue_arch.Weights);
    defer init.gpa.destroy(weights);

    const weights_bytes = std.mem.asBytes(weights);
    const bytes_read = try input.readPositionalAll(init.io, weights_bytes, 0);
    if (bytes_read != weights_bytes.len) {
        std.process.fatal("short read from '{s}'", .{input_path});
    }

    nnue_arch.transformNetFor(target_kind, endian, weights);

    var output = try std.Io.Dir.cwd().createFile(init.io, output_path, .{ .truncate = true });
    defer output.close(init.io);
    try output.writeStreamingAll(init.io, weights_bytes);
}
