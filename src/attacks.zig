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
pub const attack_impl = if (std.Target.x86.featureSetHas(@import("builtin").cpu.model.features, .bmi2))
    @import("pext.zig")
else
    @import("magics.zig");
pub const AttackEntry = attack_impl.AttackEntry;
pub const init = attack_impl.init;
pub const getBishopAttacks = attack_impl.getBishopAttacks;
pub const getRookAttacks = attack_impl.getRookAttacks;
