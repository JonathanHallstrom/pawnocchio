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

io: std.Io,
file: std.Io.File,
buf: [4096]u8 = undefined,
reader: ?std.Io.File.Reader = null,

pub fn init(io: std.Io, name: []const u8) !PerftEPDParser {
    const file = try std.Io.Dir.cwd().openFile(io, name, .{});
    return .{
        .io = io,
        .file = file,
    };
}

pub fn deinit(self: PerftEPDParser) void {
    self.file.close(self.io);
}

pub const NodeCount = struct {
    nodes: u64,
    depth: i32,
};

pub const PerftPosition = struct {
    fen: []const u8,
    node_counts: root.BoundedArray(NodeCount, 128) = .{},
};

pub fn next(self: *PerftEPDParser) !?PerftPosition {
    if (self.reader == null) {
        self.reader = self.file.readerStreaming(self.io, &self.buf);
    }

    const read = while (true) {
        const line = (try self.reader.?.interface.takeDelimiter('\n')) orelse return null;
        if (std.mem.trim(u8, line, &std.ascii.whitespace).len != 0) break line;
    };
    var iter = std.mem.tokenizeSequence(u8, read, ";D");
    var res: PerftPosition = .{
        .fen = iter.next() orelse return null,
    };
    while (iter.next()) |part| {
        const stripped = std.mem.trim(u8, part, &std.ascii.whitespace);
        const depth_end = std.mem.findScalar(u8, stripped, ' ') orelse 0;
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
