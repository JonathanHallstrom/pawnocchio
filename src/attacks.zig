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
const cpu = @import("builtin").cpu;
const LLVM_NAME = cpu.model.llvm_name orelse "";
const USE_PEXT = std.Target.x86.featureSetHas(cpu.model.features, .bmi2) and
    !std.mem.eql(u8, "znver1", LLVM_NAME) and
    !std.mem.eql(u8, "znver2", LLVM_NAME);
pub const attack_impl = if (USE_PEXT)
    @import("pext.zig")
else
    @import("magics.zig");
pub const AttackEntry = attack_impl.AttackEntry;
pub const init = attack_impl.init;
pub const bishopAttacks = attack_impl.getBishopAttacks;
pub const rookAttacks = attack_impl.getRookAttacks;
