const std = @import("std");
const meta = std.meta;
const mem = std.mem;

const protocol = @import("lib.zig");

pub const Packet = union(enum) {
    client: ClientPacket,
    server: ServerPacket,

    pub fn init(allocator: mem.Allocator, value: anytype) !*Packet {
        const self = try allocator.create(Packet);
        self.* = Packet.from(value);
        return self;
    }

    pub fn deinit(self: *Packet, allocator: mem.Allocator) void {
        allocator.destroy(self);
    }

    /// Convert an underlying packet object to a `Packet` union
    pub fn from(value: anytype) Packet {
        inline for (meta.fields(Packet)) |origin| {
            inline for (meta.field(origin.type)) |state| {
                inline for (meta.fields(state.type)) |packet| {
                    if (packet.type == @TypeOf(value)) {
                        return @unionInit(
                            Packet,
                            origin.name,
                            @unionInit(
                                origin.type,
                                state.name,
                                @unionInit(
                                    state.type,
                                    packet.name,
                                    value,
                                ),
                            ),
                        );
                    }
                }
            }
        }

        @compileError("Invalid packet of type `" ++ @typeName(@TypeOf(value)) ++ "`");
    }
};

/// Client->Server packets
pub const ClientPacket = union(protocol.State) {
    // zig fmt: off
    handshake: handshake.ClientPacket,
    status:    status.ClientPacket,
    login:     login.ClientPacket,
    config:    config.ClientPacket,
    play:      play.ClientPacket,
    // zig fmt: on
};

/// Server->Client packets
pub const ServerPacket = union(protocol.State) {
    // zig fmt: off
    handshake: handshake.ServerPacket,
    status:    status.ServerPacket,
    login:     login.ServerPacket,
    config:    config.ServerPacket,
    play:      play.ServerPacket,
    // zig fmt: on
};

// zig fmt: off
pub const handshake = @import("packet/handshake.zig");
pub const status    = @import("packet/status.zig");
pub const login     = @import("packet/login.zig");
pub const config    = @import("packet/config.zig");
pub const play      = @import("packet/play.zig");
// zig fmt: on
