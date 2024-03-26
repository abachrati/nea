const std = @import("std");
const heap = std.heap;
const json = std.json;
const fmt = std.fmt;
const mem = std.mem;
const net = std.net;
const log = std.log;

const codec = @import("net/codec.zig");
const v765 = @import("net/v765.zig");

const Server = @import("Server.zig");

/// The state of the client connection.
pub const State = enum {
    handshake,
    status,
    login,
    config,
    play,
};

server: *Server,

stream: net.Stream,
address: net.Address,

arena: heap.ArenaAllocator,

state: State = .handshake,

uuid: ?codec.Uuid = null,
name: ?[]const u8 = null,

const Client = @This();

pub fn init(
    allocator: mem.Allocator,
    server: *Server,
    connection: net.StreamServer.Connection,
) !*Client {
    const self = try allocator.create(Client);

    self.* = .{
        .server = server,
        .stream = connection.stream,
        .address = connection.address,
        .arena = heap.ArenaAllocator.init(allocator),
    };

    return self;
}

pub fn deinit(self: *Client) void {
    self.stream.close();
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self);
}

/// Read and handle a packet from the client.
pub fn tick(self: *Client) !void {
    const arena = &self.arena;
    const allocator = arena.allocator();

    switch (self.state) {
        .handshake => {
            switch (try v765.handshake.read(arena, self.stream.reader())) {
                .handshake => |pkt| self.state = @enumFromInt(@intFromEnum(pkt.next)),
                .legacy => return error.LegacyClient,
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
                            .max = self.server.properties.@"max-players",
                            .online = 0,
                        },
                        .description = .{
                            .text = self.server.properties.motd,
                        },
                        // Sending a malformed favicon is safe.
                        .favicon = self.server.favicon orelse "",
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

                    return error.Disconnected;
                },
            }
        },
        .login => {
            switch (try v765.login.read(arena, self.stream.reader())) {
                .login_start => |pkt| {
                    self.name = try self.arena.child_allocator.dupe(u8, pkt.name);

                    self.uuid = codec.Uuid.initV3(self.name.?);

                    try v765.login.write(.{
                        .login_success = .{
                            .uuid = self.uuid.?,
                            .username = self.name.?,
                            .properties = {},
                        },
                    }, self.stream.writer());
                },
                .login_acknowledged => {
                    self.state = .config;
                },
                else => {},
            }
        },
        else => {
            return self.disconnect("Unimplemented");
        },
    }
}

/// Blocking. Handle packets from client until able to login, then register with server.
pub fn login(self: *Client) !void {
    while (self.state != .config) {
        self.tick() catch |err| return switch (err) {
            error.Disconnected, error.LegacyClient => {},
            else => err,
        };
    }

    log.info("`{s}` ({any}) joined the game.", .{ self.name.?, self.uuid.? });

    {
        const mutex = &self.server.clients.mutex;
        mutex.lock();
        defer mutex.unlock();

        try self.server.clients.map.put(self.server.allocator, self.uuid.?, self);
    }
}

/// Blocking. Handle packets from client until in an appropriate state to disconnect.
pub fn disconnect(self: *Client, reason: []const u8) anyerror!void {
    const arena = &self.arena;
    const allocator = arena.allocator();

    defer self.deinit();

    if (self.uuid) |uuid| {
        const mutex = &self.server.clients.mutex;
        mutex.lock();
        defer mutex.unlock();

        log.info("`{s}` was disconnected ({s})", .{ self.name.?, reason });

        _ = self.server.clients.map.remove(uuid);
    }

    while (true) {
        switch (self.state) {
            .login => {
                return v765.login.write(.{
                    .disconnect = .{
                        .reason = try fmt.allocPrint(allocator, "{{\"text\":\"{s}\"}}", .{reason}),
                    },
                }, self.stream.writer());
            },
            .config => {
                return v765.config.write(.{
                    .disconnect = .{
                        .reason = try fmt.allocPrint(allocator, "{{\"text\":\"{s}\"}}", .{reason}),
                    },
                }, self.stream.writer());
            },

            else => {
                self.tick() catch |err| return switch (err) {
                    error.Disconnected, error.LegacyClient => {},
                    else => err,
                };
            },
        }
    }
}
