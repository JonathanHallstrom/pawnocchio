pub const Side = enum(u1) {
    white,
    black,

    pub fn flipped(self: Side) Side {
        return if (self == .white) .black else .white;
    }

    pub fn mult(self: Side, other: Side) Side {
        return if (self == .white) other else other.flipped();
    }

    pub fn toInt(self: Side) u1 {
        return @intFromEnum(self);
    }
};
