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

const IS_WINDOWS = @import("builtin").os.tag == .windows;

const windows = std.os.windows;

extern "kernel32" fn CreateFileMappingA(
    hFile: windows.HANDLE,
    lpFileMappingAttributes: ?*windows.SECURITY_ATTRIBUTES,
    flProtect: windows.DWORD,
    dwMaximumSizeHigh: windows.DWORD,
    dwMaximumSizeLow: windows.DWORD,
    lpName: ?windows.LPCSTR,
) callconv(.winapi) ?windows.HANDLE;

extern "kernel32" fn MapViewOfFile(
    hFileMappingObject: windows.HANDLE,
    dwDesiredAccess: windows.DWORD,
    dwFileOffsetHigh: windows.DWORD,
    dwFileOffsetLow: windows.DWORD,
    dwNumberOfBytesToMap: windows.SIZE_T,
) callconv(.winapi) ?windows.LPVOID;

extern "kernel32" fn UnmapViewOfFile(lpBaseAddress: windows.LPCVOID) callconv(.winapi) windows.BOOL;

const CloseHandle = windows.CloseHandle;

const Mapping = if (IS_WINDOWS) windows.HANDLE else void;

data: []align(4096) const u8,
file_mapping: Mapping,

const Self = @This();

pub fn init(file: std.fs.File) !Self {
    const len = (try file.stat()).size;
    if (IS_WINDOWS) {
        const file_mapping = CreateFileMappingA(file.handle, null, windows.PAGE_READONLY, 0, 0, null) orelse return error.FileMapFailed;
        const READ = 4;
        const raw_ptr = MapViewOfFile(file_mapping, READ, 0, 0, len) orelse return error.MapViewFailed;
        const ptr: [*]align(4096) const u8 = @ptrCast(@alignCast(raw_ptr));

        return .{
            .data = ptr[0..len],
            .file_mapping = file_mapping,
        };
    } else {
        return .{
            .data = try std.posix.mmap(null, len, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, file.handle, 0),
            .file_mapping = void{},
        };
    }
}

pub fn deinit(self: *const Self) void {
    if (IS_WINDOWS) {
        _ = CloseHandle(self.file_mapping);
        _ = UnmapViewOfFile(self.data.ptr);
    } else {
        std.posix.munmap(self.data);
    }
}
