const std = @import("std");
const builtin = @import("builtin");
const root = @import("../root.zig");
const arch = @import("arch.zig");
const numa = root.numa;

const build_options = @import("build_options");
const use_numa = build_options.use_numa and builtin.os.tag == .linux and builtin.link_libc;

const net = @embedFile("net");
const verbatim_backing: [net.len:0]u8 align(64) = net.*;

pub var verbatim_weights: *const arch.Weights = @ptrCast(&verbatim_backing);
var weights_by_node: numa.PerNode(arch.Weights) = .{};

pub export fn setWeights(w: *const arch.Weights) void {
    verbatim_weights = w;
}

pub fn init() !void {
    if (!use_numa) {
        return;
    }

    try weights_by_node.allocCopyToAll(verbatim_weights);
}

pub fn deinit() void {
    if (!use_numa) {
        return;
    }

    weights_by_node.deinit();
}

pub fn weightsForNode(node: usize) *const arch.Weights {
    if (!use_numa) {
        return verbatim_weights;
    }

    std.debug.assert(numa.isActive());
    return weights_by_node.getConst(node) orelse unreachable;
}
