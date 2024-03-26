pub const codec = @import("codec.zig");
pub const v765 = @import("v765.zig");

/// The state of the client connection.
pub const State = enum {
    handshake,
    status,
    login,
    config,
    play,
};
