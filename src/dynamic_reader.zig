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
const Board = root.Board;
const WDL = root.WDL;
const dataformat = root.dataformat;
const ScoredMove = dataformat.ScoredMove;
const FileFormat = dataformat.FileFormat;

pub const DynamicGameView = struct {
    initial_board: *const Board,
    outcome: WDL,
    moves: []const ScoredMove,
};

pub const DynamicReader = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        next: *const fn (*anyopaque) anyerror!?DynamicGameView,
        deinit: *const fn (*anyopaque) void,
    };

    pub fn next(self: *DynamicReader) !?DynamicGameView {
        return try self.vtable.next(self.ptr);
    }

    pub fn deinit(self: *DynamicReader) void {
        self.vtable.deinit(self.ptr);
    }
};
