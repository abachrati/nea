const protocol = @import("../lib.zig");

/// Client->Server packets
pub const ClientPacket = union(enum(u8)) {
    pub const Type = @typeInfo(@This()).Union.tag_type.?;

    // zig fmt: off
    handshake: Handshake = 0x00,
    // zig fmt: on
};

pub const Handshake = struct {
    protocol: i32,
    address: []const u8,
    port: u16,
    next: protocol.State,
};

/// Server->Client packets
pub const ServerPacket = union(enum(u8)) {
    pub const Type = @typeInfo(@This()).Union.tag_type.?;

    // zig fmt: off
    // zig fmt: on
};
