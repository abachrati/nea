const std = @import("std");
const heap = std.heap;
const meta = std.meta;
const io = std.io;

const codec = @import("codec.zig");
const util = @import("../util/lib.zig");

const ArenaAllocator = heap.ArenaAllocator;

pub const handshake = struct {
    pub const Serverbound = union(enum) {
        pub const Handshake = struct {
            version: i32,
            address: []u8,
            port: u16,
            next: State,

            pub const State = enum(u2) { status = 1, login = 2 };
        };

        handshake: Handshake,
        legacy,
    };

    pub const Clientbound = union(enum) {};

    pub fn read(arena: *ArenaAllocator, reader: anytype) !Serverbound {
        const length = try codec.VarInt.read(reader);

        if (length == 0xfe)
            return .legacy;

        var limited = io.limitedReader(reader, try util.cast(u64, length));
        errdefer reader.skipBytes(limited.bytes_left, .{}) catch {};

        return switch (try codec.VarInt.read(limited.reader())) {
            0x00 => .{
                .handshake = .{
                    .version = try codec.VarInt.read(limited.reader()),
                    .address = try codec.String.read(arena.allocator(), limited.reader()),
                    .port = try limited.reader().readInt(u16, .Big),
                    .next = try meta.intToEnum(
                        Serverbound.Handshake.State,
                        try codec.VarInt.read(limited.reader()),
                    ),
                },
            },
            else => error.Unknown,
        };
    }

    pub fn write(packet: Clientbound, _: anytype) !void {
        switch (packet) {}
    }
};

pub const status = struct {
    pub const Serverbound = union(enum) {
        pub const PingRequest = struct {
            payload: i64,
        };

        status_request,
        ping_request: PingRequest,
    };

    pub const Clientbound = union(enum) {
        pub const StatusResponse = struct {
            response: []const u8,
        };

        pub const PingResponse = struct {
            payload: i64,
        };

        status_response: StatusResponse,
        ping_response: PingResponse,
    };

    pub fn read(_: *ArenaAllocator, reader: anytype) !Serverbound {
        const length = try codec.VarInt.read(reader);

        var limited = io.limitedReader(reader, try util.cast(u64, length));
        errdefer reader.skipBytes(limited.bytes_left, .{}) catch {};

        return switch (try codec.VarInt.read(limited.reader())) {
            0x00 => .status_request,
            0x01 => .{
                .ping_request = .{
                    .payload = try limited.reader().readInt(i64, .Big),
                },
            },
            else => error.Unknown,
        };
    }

    pub fn write(packet: Clientbound, writer: anytype) !void {
        switch (packet) {
            .status_response => |pkt| {
                const length = codec.VarInt.size(0x00) + try codec.String.size(pkt.response);

                try codec.VarInt.write(try util.cast(i32, length), writer);
                try codec.VarInt.write(0x00, writer);
                try codec.String.write(pkt.response, writer);
            },
            .ping_response => |pkt| {
                const length = codec.VarInt.size(0x01) + @sizeOf(i64);

                try codec.VarInt.write(try util.cast(i32, length), writer);
                try codec.VarInt.write(0x01, writer);
                try writer.writeInt(i64, pkt.payload, .Big);
            },
        }
    }
};

pub const login = struct {
    pub const Serverbound = union(enum) {
        pub const LoginStart = struct {
            name: []const u8,
            uuid: codec.Uuid,
        };

        pub const EncryptionResponse = struct {
            secret: []const u8,
            token: []const u8,
        };

        pub const LoginPluginResponse = struct {
            message_id: i32,
            data: ?[]const u8,
        };

        login_start: LoginStart,
        encryption_response: EncryptionResponse,
        login_plugin_response: LoginPluginResponse,
        login_acknowledged,
    };

    pub const Clientbound = union(enum) {
        pub const Disconnect = struct {
            reason: []const u8,
        };

        pub const EncryptionRequest = struct {
            server_id: []const u8,
            public_key: []const u8,
            token: []const u8,
        };

        pub const LoginSuccess = struct {
            uuid: codec.Uuid,
            username: []const u8,
            properties: void,
        };

        pub const SetCompression = struct {
            threshold: i32,
        };

        pub const LoginPluginRequest = struct {
            message_id: i32,
            channel: []const u8,
            data: []const u8,
        };

        disconnect: Disconnect,
        encryption_request: EncryptionRequest,
        login_success: LoginSuccess,
        set_compression: SetCompression,
        login_plugin_request: LoginPluginRequest,
    };

    pub fn read(arena: *ArenaAllocator, reader: anytype) !Serverbound {
        const length = try codec.VarInt.read(reader);

        var limited = io.limitedReader(reader, try util.cast(u64, length));
        errdefer reader.skipBytes(limited.bytes_left, .{}) catch {};

        return switch (try codec.VarInt.read(limited.reader())) {
            0x00 => .{
                .login_start = .{
                    .name = try codec.String.read(arena.allocator(), limited.reader()),
                    .uuid = try codec.Uuid.read(limited.reader()),
                },
            },
            0x01 => .{
                .encryption_response = .{
                    .secret = try codec.String.read(arena.allocator(), limited.reader()),
                    .token = try codec.String.read(arena.allocator(), limited.reader()),
                },
            },
            0x02 => .{
                .login_plugin_response = .{
                    .message_id = try codec.VarInt.read(limited.reader()),
                    .data = if (try limited.reader().readByte() != 0)
                        try limited.reader().readAllAlloc(arena.allocator(), 1048576)
                    else
                        null,
                },
            },
            0x03 => .login_acknowledged,
            else => error.Unknown,
        };
    }

    pub fn write(packet: Clientbound, writer: anytype) !void {
        switch (packet) {
            .disconnect => |pkt| {
                const length = codec.VarInt.size(0x00) + try codec.String.size(pkt.reason);

                try codec.VarInt.write(try util.cast(i32, length), writer);
                try codec.VarInt.write(0x00, writer);
                try codec.String.write(pkt.reason, writer);
            },
            .encryption_request => |pkt| {
                const length = codec.VarInt.size(0x01) +
                    try codec.String.size(pkt.server_id) +
                    try codec.String.size(pkt.public_key) +
                    try codec.String.size(pkt.token);

                try codec.VarInt.write(try util.cast(i32, length), writer);
                try codec.VarInt.write(0x01, writer);
                try codec.String.write(pkt.server_id, writer);
                try codec.String.write(pkt.public_key, writer);
                try codec.String.write(pkt.token, writer);
            },
            .login_success => |pkt| {
                const length = codec.VarInt.size(0x02) +
                    codec.Uuid.size(pkt.uuid) +
                    try codec.String.size(pkt.username) +
                    codec.VarInt.size(0);

                try codec.VarInt.write(try util.cast(i32, length), writer);
                try codec.VarInt.write(0x02, writer);
                try codec.Uuid.write(pkt.uuid, writer);
                try codec.String.write(pkt.username, writer);
                try codec.VarInt.write(0, writer);
            },
            .set_compression => |pkt| {
                const length = codec.VarInt.size(0x03) + codec.VarInt.size(pkt.threshold);

                try codec.VarInt.write(try util.cast(i32, length), writer);
                try codec.VarInt.write(0x03, writer);
                try codec.VarInt.write(pkt.threshold, writer);
            },
            .login_plugin_request => |pkt| {
                const length = codec.VarInt.size(0x04) +
                    codec.VarInt.size(pkt.message_id) +
                    try codec.String.size(pkt.channel) +
                    pkt.data.len;

                try codec.VarInt.write(try util.cast(i32, length), writer);
                try codec.VarInt.write(0x04, writer);
                try codec.VarInt.write(pkt.message_id, writer);
                try codec.String.write(pkt.channel, writer);
                try writer.writeAll(pkt.data);
            },
        }
    }
};

pub const config = struct {
    pub const Serverbound = union(enum) {};

    pub const Clientbound = union(enum) {
        pub const Disconnect = struct {
            reason: []const u8,
        };

        disconnect: Disconnect,
    };

    pub fn read(_: *ArenaAllocator, reader: anytype) !Serverbound {
        const length = try codec.VarInt.read(reader);

        var limited = io.limitedReader(reader, try util.cast(u64, length));
        errdefer reader.skipBytes(limited.bytes_left, .{}) catch {};

        return switch (try codec.VarInt.read(limited.reader())) {
            else => error.Unknown,
        };
    }

    pub fn write(packet: Clientbound, writer: anytype) !void {
        switch (packet) {
            .disconnect => |pkt| {
                const length = codec.VarInt.size(0x01) + try codec.String.size(pkt.reason);

                try codec.VarInt.write(try util.cast(i32, length), writer);
                try codec.VarInt.write(0x01, writer);
                try codec.String.write(pkt.reason, writer);
            },
        }
    }
};

pub const play = struct {
    pub const Serverbound = union(enum) {};

    pub const Clientbound = union(enum) {};

    pub fn read(_: *ArenaAllocator, reader: anytype) !Serverbound {
        const length = try codec.VarInt.read(reader);

        var limited = io.limitedReader(reader, try util.cast(u64, length));
        errdefer reader.skipBytes(limited.bytes_left, .{});

        return switch (try codec.VarInt.read(limited.reader())) {
            else => error.Unknown,
        };
    }

    pub fn write(packet: Clientbound, _: anytype) !void {
        switch (packet) {}
    }
};
