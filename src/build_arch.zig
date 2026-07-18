const arch = @import("nnue/arch.zig");
pub const Weights = arch.Weights;
pub const Target = arch.Target;
pub const target = arch.target;
pub const parseTarget = arch.parseTarget;
pub const parseEndian = arch.parseEndian;
pub const transformNetFor = arch.transformNetFor;
pub const loadUnquantized = arch.loadUnquantized;
