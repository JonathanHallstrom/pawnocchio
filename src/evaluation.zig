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
const build_options = @import("build_options");
const EvalMode = @import("eval_mode.zig").EvalMode;

const root = @import("root.zig");
const Board = root.Board;

pub const EVAL_MODE: EvalMode = std.meta.stringToEnum(EvalMode, build_options.eval).?;
pub const eval_mode: EvalMode = EVAL_MODE;
const impl = switch (EVAL_MODE) {
    .hce => @import("hce.zig"),
    .material => @import("material_eval.zig"),
    .nnue => root.nnue,
};

const material = @import("material_eval.zig");

pub const Context = impl.Context;

pub const globalCtx = struct {
    var ctx: Context = undefined;
    var initialised: bool = false;
    var mutex: std.atomic.Mutex = .unlocked;

    pub fn lock() *Context {
        while (!mutex.tryLock()) std.atomic.spinLoopHint();
        if (!initialised) {
            initialised = true;
            ctx.initForThread(0);
        }
        return &ctx;
    }

    pub fn release() void {
        mutex.unlock();
    }
};

pub fn Handle(comptime T: type) type {
    return struct {
        inner: T,

        const Self = @This();
        const Child = switch (@typeInfo(T)) {
            .pointer => |ptr| ptr.child,
            else => T,
        };

        inline fn hasMethod(comptime name: []const u8) bool {
            comptime return T != void and @hasDecl(Child, name);
        }

        pub inline fn addSub(self: Self, add: root.PSQTFeature, sub: root.PSQTFeature) void {
            if (hasMethod("addSub")) return self.inner.addSub(add, sub);

            if (hasMethod("add") and hasMethod("sub")) {
                self.inner.add(add);
                self.inner.sub(sub);
            }
        }

        pub inline fn addSubSub(self: Self, add: root.PSQTFeature, sub1: root.PSQTFeature, sub2: root.PSQTFeature) void {
            if (hasMethod("addSubSub")) return self.inner.addSubSub(add, sub1, sub2);

            if (hasMethod("add") and hasMethod("sub")) {
                self.inner.add(add);
                self.inner.sub(sub1);
                self.inner.sub(sub2);
            }
        }

        pub inline fn addAddSubSub(self: Self, add1: root.PSQTFeature, add2: root.PSQTFeature, sub1: root.PSQTFeature, sub2: root.PSQTFeature) void {
            if (hasMethod("addAddSubSub")) return self.inner.addAddSubSub(add1, add2, sub1, sub2);

            if (hasMethod("add") and hasMethod("sub")) {
                self.inner.add(add1);
                self.inner.sub(sub1);
                self.inner.add(add2);
                self.inner.sub(sub2);
            }
        }

        pub inline fn threatOnChange(self: Self, board: *const Board, piece: root.ColouredPieceType, sq: root.Square, comptime is_add: bool) void {
            if (comptime hasMethod("threatOnChange")) self.inner.threatOnChange(board, piece, sq, is_add);
        }

        pub inline fn threatOnMove(self: Self, board: *const Board, old_piece: root.ColouredPieceType, src: root.Square, new_piece: root.ColouredPieceType, dst: root.Square) void {
            if (comptime hasMethod("threatOnMove")) self.inner.threatOnMove(board, old_piece, src, new_piece, dst);
        }

        pub inline fn threatOnMutate(self: Self, board: *const Board, old_piece: root.ColouredPieceType, new_piece: root.ColouredPieceType, sq: root.Square) void {
            if (comptime hasMethod("threatOnMutate")) self.inner.threatOnMutate(board, old_piece, new_piece, sq);
        }

        pub inline fn eval(self: Self, board: *const Board) i16 {
            if (hasMethod("eval")) return self.inner.eval(board);
            return 0;
        }
    };
}

pub inline fn wrapHandle(inner: anytype) Handle(@TypeOf(inner)) {
    return .{ .inner = inner };
}

pub const NullHandle = Handle(void);

pub inline fn noHandle() NullHandle {
    return .{ .inner = void{} };
}

pub fn evalPosition(board: *const Board) i16 {
    return impl.evalPosition(board);
}

pub fn evalFen(fen: []const u8) !i16 {
    return evalPosition(&try Board.parseFen(fen, true));
}

pub const INF_SCORE: i16 = 32767;
pub const CHECKMATE_SCORE: i16 = 32000;
pub const HIGHEST_NON_MATE_SCORE = CHECKMATE_SCORE - root.SEARCH_MAX_PLY - 1;
pub const TB_WIN_SCORE: i16 = 30000;
pub const HIGHEST_NON_TB_SCORE = TB_WIN_SCORE - root.SEARCH_MAX_PLY - 1;
pub const WIN_SCORE: i16 = 29000;

pub fn clampScore(score: anytype) i16 {
    return @intCast(std.math.clamp(score, -(WIN_SCORE - 1), WIN_SCORE - 1));
}

pub fn scoreToTt(score: i16, ply: u8) i16 {
    if (score < -WIN_SCORE) {
        return score -% @as(i16, @intCast(ply));
    }
    if (score > WIN_SCORE) {
        return score +% @as(i16, @intCast(ply));
    }
    return score;
}

pub fn scoreFromTt(score: i16, ply: u8) i16 {
    if (score < -WIN_SCORE) {
        return score +% @as(i16, @intCast(ply));
    }
    if (score > WIN_SCORE) {
        return score -% @as(i16, @intCast(ply));
    }
    return score;
}

pub fn checkTTBound(score: i16, alpha: i32, beta: i32, tp: root.ScoreType) bool {
    return switch (tp) {
        .none => false,
        .lower => score >= beta,
        .upper => score <= alpha,
        .exact => true,
    };
}

pub fn matedIn(plies: u16) i16 {
    return -CHECKMATE_SCORE + @as(i16, @intCast(plies));
}

pub fn tbWin(plies: u8) i16 {
    return TB_WIN_SCORE - plies;
}

pub fn tbLoss(plies: u8) i16 {
    return -TB_WIN_SCORE + plies;
}

pub fn isMateScore(score: i32) bool {
    return @abs(score) > HIGHEST_NON_MATE_SCORE;
}

pub fn isTBScore(score: i32) bool {
    return @abs(score) > HIGHEST_NON_TB_SCORE;
}

pub fn formatScore(score: i16) root.BoundedArray(u8, 15) {
    var print_buf: [15]u8 = undefined;
    var res: root.BoundedArray(u8, 15) = .{};
    if (isMateScore(score)) {
        const plies_to_mate = if (score > 0) CHECKMATE_SCORE - score else CHECKMATE_SCORE + score;
        const moves_to_mate = @divTrunc(plies_to_mate + 1, 2);
        res.appendSliceAssumeCapacity("mate ");
        if (score < 0)
            res.appendAssumeCapacity('-');
        res.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{moves_to_mate}) catch unreachable);
    } else {
        res.appendSliceAssumeCapacity("cp ");
        res.appendSliceAssumeCapacity(std.fmt.bufPrint(&print_buf, "{}", .{score}) catch unreachable);
    }
    return res;
}
