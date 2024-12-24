pub const Side = enum(u8) {
    black,
    white,

    pub fn flipped(self: Side) Side {
        return if (self == .white) .black else .white;
    }
};
