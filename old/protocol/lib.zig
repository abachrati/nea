pub const version = 765;

pub const State = enum {
    handshake,
    status,
    login,
    config,
    play,
};

// zig fmt: off
pub const codec  = @import("codec.zig");
pub const packet = @import("packet.zig");
// zig fmt: on
