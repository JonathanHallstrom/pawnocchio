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
const DynamicReader = root.dynamic_reader.DynamicReader;
const DynamicGameView = root.dynamic_reader.DynamicGameView;
const FileFormat = root.dataformat.FileFormat;
fn pgnReaderNext(ptr: *anyopaque) !?DynamicGameView {
    const reader: *root.pgn.ScoredPlyReader = @ptrCast(@alignCast(ptr));
    return try reader.toDynamic().next();
}

fn pgnReaderDeinit(ptr: *anyopaque) void {
    const reader: *root.pgn.ScoredPlyReader = @ptrCast(@alignCast(ptr));
    reader.deinit();
}

pub const OwningReader = struct {
    inner: DynamicReader,
    allocator: std.mem.Allocator,
    concrete_backing: []align(64) u8,

    pub fn init(format: FileFormat, reader: *std.Io.Reader, allocator: std.mem.Allocator) !OwningReader {
        const size: usize = switch (format) {
            .pgn => @sizeOf(root.pgn.ScoredPlyReader),
            .viriformat => @sizeOf(root.viriformat.ScoredPlyReader),
        };

        const alignment = comptime std.mem.Alignment.fromByteUnits(64);
        const backing = try allocator.alignedAlloc(u8, alignment, size);
        errdefer allocator.free(backing);

        const inner = switch (format) {
            .pgn => blk: {
                const r: *root.pgn.ScoredPlyReader = @ptrCast(@alignCast(backing.ptr));
                r.* = root.pgn.scoredPlyReader(reader, allocator);
                break :blk r.toDynamic();
            },
            .viriformat => blk: {
                const r: *root.viriformat.ScoredPlyReader = @ptrCast(@alignCast(backing.ptr));
                r.* = root.viriformat.scoredPlyReader(reader, allocator);
                break :blk r.toDynamic();
            },
        };

        return .{
            .inner = inner,
            .allocator = allocator,
            .concrete_backing = backing,
        };
    }

    pub fn next(self: *OwningReader) !?DynamicGameView {
        return try self.inner.next();
    }

    pub fn deinit(self: *OwningReader) void {
        self.inner.deinit();
        self.allocator.free(self.concrete_backing);
    }
};
