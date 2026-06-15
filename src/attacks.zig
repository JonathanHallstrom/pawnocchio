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

const simd = @import("simd.zig");
pub const attack_impl = if (simd.HAS_PEXT)
    @import("pext.zig")
else
    @import("magics.zig");
pub const AttackEntry = attack_impl.AttackEntry;
pub const init = attack_impl.init;
pub const bishopAttacks = attack_impl.getBishopAttacks;
pub const rookAttacks = attack_impl.getRookAttacks;

pub inline fn queenAttacks(square: anytype, blockers: u64) u64 {
    return bishopAttacks(square, blockers) | rookAttacks(square, blockers);
}
