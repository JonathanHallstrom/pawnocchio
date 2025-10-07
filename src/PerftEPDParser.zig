// pawnocchio, UCI chess engine
// Copyright (C) 2025 Jonathan Hallström
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const root = @import("root.zig");

const PerftEPDParser = @This();
const Allocator = std.mem.Allocator;

file: std.fs.File,
allocator: Allocator,
buf: [4096]u8 = undefined,
reader: ?std.fs.File.Reader = null,

pub fn init(name: []const u8, alloc: Allocator) !PerftEPDParser {
    const file = try std.fs.cwd().openFile(name, .{});
    return .{
        .file = file,
        .allocator = alloc,
    };
}

pub fn deinit(self: PerftEPDParser) void {
    self.file.close();
}

pub const NodeCount = struct {
    nodes: u64,
    depth: i32,
};

pub const PerftPosition = struct {
    fen: []const u8,
    node_counts: root.BoundedArray(NodeCount, 128) = .{},
    allocator: Allocator,

    pub fn deinit(self: PerftPosition) void {
        self.allocator.free(self.fen);
    }
};

pub fn next(self: *PerftEPDParser) !?PerftPosition {
    if (self.reader == null) {
        self.reader = self.file.reader(&self.buf);
    }

    var w = std.Io.Writer.Allocating.init(self.allocator);
    defer w.deinit();

    _ = try self.reader.?.interface.streamDelimiter(&w.writer, '\n');
    const read = w.written();
    var iter = std.mem.tokenizeSequence(u8, read, ";D");
    var res: PerftPosition = .{
        .fen = try self.allocator.dupe(u8, iter.next() orelse return null),
        .allocator = self.allocator,
    };
    errdefer self.allocator.free(res.fen);
    while (iter.next()) |part| {
        const stripped = std.mem.trim(u8, part, &std.ascii.whitespace);
        const depth_end = std.mem.indexOfScalar(u8, stripped, ' ') orelse 0;
        const depth = try std.fmt.parseInt(u31, stripped[0..depth_end], 10);
        const nodes = try std.fmt.parseInt(
            u64,
            std.mem.trim(u8, stripped[depth_end..], &std.ascii.whitespace),
            10,
        );
        try res.node_counts.append(.{
            .depth = @intCast(depth),
            .nodes = nodes,
        });
    }
    return res;
}
