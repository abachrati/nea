/// Client->Server packets
pub const ClientPacket = union(enum(u8)) {
    pub const Type = @typeInfo(@This()).Union.tag_type.?;

    // zig fmt: off
    status_request: StatusRequest = 0x00,
    ping_request:   PingRequest   = 0x01,
    // zig fmt: on
};

pub const StatusRequest = struct {};

pub const PingRequest = struct {
    data: i64,
};

/// Server->Client packets
pub const ServerPacket = union(enum(u8)) {
    pub const Type = @typeInfo(@This()).Union.tag_type.?;

    // zig fmt: off
    status_response: StatusResponse = 0x00,
    ping_response:   PingResponse   = 0x01,
    // zig fmt: on
};

pub const StatusResponse = struct {
    response: []const u8,
};

pub const PingResponse = struct {
    data: i64,
};
