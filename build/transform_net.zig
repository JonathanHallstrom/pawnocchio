const std = @import("std");
const nnue_arch = @import("nnue_arch");

fn usage() noreturn {
    std.process.fatal("usage: transform_net <target> <endian> <input> <output>", .{});
}

pub fn main() !void {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
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

    var input = try std.fs.cwd().openFile(input_path, .{});
    defer input.close();

    const weights = try std.heap.page_allocator.create(nnue_arch.Weights);
    defer std.heap.page_allocator.destroy(weights);

    const weights_bytes = std.mem.asBytes(weights);
    const bytes_read = try input.readAll(weights_bytes);
    if (bytes_read != weights_bytes.len) {
        std.process.fatal("short read from '{s}'", .{input_path});
    }

    nnue_arch.transformNetFor(target_kind, endian, weights);

    var output = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer output.close();
    try output.writeAll(weights_bytes);
}
