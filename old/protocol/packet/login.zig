/// Client->Server packets
pub const ClientPacket = union(enum(u8)) {
    pub const Type = @typeInfo(@This()).Union.tag_type.?;

    // zig fmt: off
    // zig fmt: on
};

/// Server->Client packets
pub const ServerPacket = union(enum(u8)) {
    pub const Type = @typeInfo(@This()).Union.tag_type.?;

    // zig fmt: off
    // zig fmt: on
};
