const std = @import("std");
const root = @import("../root.zig");
const Board = root.Board;
const evaluation = root.evaluation;

pub const arch = @import("arch.zig");
const numa = root.numa;
const nnue_accumulator = @import("accumulator.zig");
const nnue_weights = @import("weights.zig");

pub const Accumulator = nnue_accumulator.Accumulator;
pub const AccumulatorHalf = nnue_accumulator.AccumulatorHalf;
pub const MirroringType = arch.inputs.MirroringType;
pub const feature = arch.inputs.featureWeight;
pub const featureIndex = arch.inputs.featureIndex;
pub const init = nnue_weights.init;
pub const deinit = nnue_weights.deinit;
pub const weightsForNode = nnue_weights.weightsForNode;

pub const Context = struct {
    weights: *const arch.Weights = undefined,
    input: arch.inputs.Context = undefined,

    pub fn initForThread(self: *Context, thread_idx: usize) void {
        const node: usize = if (root.numa.enabled) numa.nodeForThread(thread_idx) else 0;
        self.weights = weightsForNode(node);
        self.input.initRefreshCache(self.weights);
    }

    pub fn initRoot(self: *Context, board: *const Board) void {
        self.input.initRoot(board, self.weights);
    }

    pub fn prepareChild(self: *Context, child_ply: usize, child_board: *const Board) void {
        self.input.prepareChild(@intCast(child_ply), child_board);
    }

    pub fn handle(self: *Context, ply: usize) evaluation.Handle(arch.inputs.Handle) {
        return evaluation.wrapHandle(self.input.getHandle(@intCast(ply), self.weights));
    }
};

pub fn evalPosition(board: *const Board) i16 {
    const ctx = evaluation.globalCtx.lock();
    defer evaluation.globalCtx.release();
    ctx.initRoot(board);
    return ctx.handle(0).eval(board);
}
