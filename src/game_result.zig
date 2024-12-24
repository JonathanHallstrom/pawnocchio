const Side = @import("Side.zig");

pub const GameResult = enum {
    tie,
    white,
    black,

    pub fn from(turn: Side) GameResult {
        return switch (turn) {
            .white => .white,
            .black => .black,
        };
    }
};
