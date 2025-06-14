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
const llvm_name = cpu.model.llvm_name orelse "";
const is_zen1 = std.mem.eql(u8, "znver1", llvm_name);
const is_zen2 = std.mem.eql(u8, "znver2", llvm_name);
const use_pext = std.Target.x86.featureSetHas(cpu.model.features, .bmi2) and !(is_zen1 or is_zen2);
pub const attack_impl = if (use_pext)
    @import("pext.zig")
else
    @import("magics.zig");
pub const AttackEntry = attack_impl.AttackEntry;
pub const init = attack_impl.init;
pub const getBishopAttacks = attack_impl.getBishopAttacks;
pub const getRookAttacks = attack_impl.getRookAttacks;
