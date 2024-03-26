const std = @import("std");
const heap = std.heap;
const time = std.time;
const mem = std.mem;
const net = std.net;
const log = std.log;

const codec = @import("net/codec.zig");
const v765 = @import("net/v765.zig");
const util = @import("util/lib.zig");

const Pool = @import("sync/Pool.zig");
const Client = @import("Client.zig");
const Properties = @import("Properties.zig");

allocator: mem.Allocator,

properties: *const Properties,
favicon: ?[]const u8,

address: net.Address,
socket: net.StreamServer,
pool: *Pool,

clients: Clients = .{},

/// Only the main thread is allowed to mutate this.
status: Status = .starting,

pub const Status = enum { starting, running, stopping };

pub const Clients = struct {
    mutex: std.Thread.Mutex = .{},
    map: std.AutoHashMapUnmanaged(codec.Uuid, *Client) = .{},
};

const Server = @This();

const Options = struct {
    allocator: mem.Allocator,
    /// Server properties.
    properties: *const Properties,
    /// Server favicon png, encoded in base64.
    favicon: ?[]const u8 = null,
    /// Number of threads for the server to spawn. If `null` the system's CPU count - 1 is used.
    n_thread: ?usize = null,
    /// Address to bind server to. If `null`, address is resolved from `properties.server-ip` and
    /// `properties.server-port`.
    address: ?net.Address = null,
};

/// Sets up the thread pool, and loads options/properties.
pub fn init(options: Options) !Server {
    const allocator = options.allocator;
    const properties = options.properties;

    const address = options.address orelse try net.Address.resolveIp(
        util.maybeEmpty(properties.@"server-ip") orelse "0.0.0.0",
        properties.@"server-port",
    );

    const socket = net.StreamServer.init(.{ .reuse_address = true });

    const pool = try Pool.init(.{
        .allocator = allocator,
        .n_thread = options.n_thread orelse
            try std.Thread.getCpuCount() - 1, // Reserve 1 CPU for main thread.
    });

    return .{
        .allocator = allocator,
        .properties = properties,
        .favicon = options.favicon,
        .address = address,
        .socket = socket,
        .pool = pool,
    };
}

pub fn deinit(self: *Server) void {
    self.socket.deinit();
    self.pool.deinit();
}

pub fn accept(self: *Server) !*Client {
    return Client.init(self.allocator, self, try self.socket.accept());
}

pub fn startup(self: *Server) !void {
    try self.socket.listen(self.address);

    // Lets not bother starting the `startupHandler`, since there is nothing we need to wait on,
    // try self.pool.add(startupHandler, .{self});

    self.status = .running;
}

/// Handler which disconnects all incoming clients while the server is starting up.
fn startupHandler(server: *Server) void {
    // BUG: Zig 0.11.0 doesn't have non-blocking streams, so this will disconnect the first client
    //      who connects after startup completes.
    while (server.status == .starting) {
        const client = server.accept() catch continue;
        client.disconnect("Server is starting!") catch continue;
    }
}

pub fn tick(self: *Server) !void {
    {
        self.clients.mutex.lock();
        defer self.clients.mutex.unlock();

        var iter = self.clients.map.valueIterator();
        while (iter.next()) |client| {
            try self.pool.add(tickClient, .{client.*});
        }
    }
}

fn tickClient(client: *Client) void {
    client.tick() catch {};
}
