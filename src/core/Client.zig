const std = @import("std");
const heap = std.heap;
const json = std.json;
const fmt = std.fmt;
const mem = std.mem;
const net = std.net;

const bnet = @import("net/lib.zig");
const v765 = bnet.v765;

/// The state of the client connection.
pub const State = enum {
    handshake,
    status,
    login,
    config,
    play,
};

stream: net.Stream,
address: net.Address,

arena: heap.ArenaAllocator,

state: State = .handshake,

const Client = @This();

pub fn init(allocator: mem.Allocator, connection: net.StreamServer.Connection) !*Client {
    const self = try allocator.create(Client);

    self.* = .{
        .stream = connection.stream,
        .address = connection.address,
        .arena = heap.ArenaAllocator.init(allocator),
    };

    return self;
}

pub fn deinit(self: *Client) void {
    self.stream.close();
}

/// Read and handle a packet from the client.
pub fn tick(self: *Client) !void {
    _ = self; // autofix
}

/// Blocking. Handle packets from client until in an appropriate state to disconnect.
/// Also applicable for Server List Ping, where `reason` is displayed as the MOTD.
pub fn disconnect(self: *Client, reason: []const u8) !void {
    const arena = &self.arena;
    const allocator = arena.allocator();

    while (true) {
        defer _ = arena.reset(.retain_capacity);

        switch (self.state) {
            .handshake => {
                switch (try v765.handshake.read(arena, self.stream.reader())) {
                    .handshake => |pkt| self.state = @enumFromInt(@intFromEnum(pkt.next)),
                    .legacy => break,
                }
            },
            .status => {
                switch (try v765.status.read(arena, self.stream.reader())) {
                    .status_request => {
                        const response = .{
                            .version = .{
                                .name = "1.20.4",
                                .protocol = 765,
                            },
                            .players = .{
                                .max = 0,
                                .online = 0,
                            },
                            .description = .{
                                .text = reason,
                            },
                        };

                        try v765.status.write(.{
                            .status_response = .{
                                .response = try json.stringifyAlloc(allocator, response, .{}),
                            },
                        }, self.stream.writer());
                    },
                    .ping_request => |pkt| {
                        try v765.status.write(.{
                            .ping_response = .{ .payload = pkt.payload },
                        }, self.stream.writer());

                        break;
                    },
                }
            },
            .login => {
                try v765.login.write(.{
                    .disconnect = .{
                        .reason = try fmt.allocPrint(allocator, "{{\"text\":\"{s}\"}}", .{reason}),
                    },
                }, self.stream.writer());

                break;
            },

            else => unreachable,
        }
    }
}
