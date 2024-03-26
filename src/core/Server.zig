const std = @import("std");
const heap = std.heap;
const time = std.time;
const mem = std.mem;
const net = std.net;
const log = std.log;

const bnet = @import("net/lib.zig");
const v765 = bnet.v765;

const sync = @import("sync/lib.zig");
const util = @import("util/lib.zig");

const io_mode = .evented;

const Client = @import("Client.zig");
const Properties = @import("Properties.zig");

allocator: mem.Allocator,

properties: *const Properties,

address: net.Address,
socket: net.StreamServer,
pool: *sync.Pool,

/// Only the main thread is allowed to mutate this.
status: Status = .starting,

pub const Status = enum { starting, running, stopping };

const Server = @This();

const Options = struct {
    allocator: mem.Allocator,
    /// Server properties
    properties: *const Properties,
    /// Number of threads for the server to run on. If `null` the system's CPU count - 1 is used.
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

    const pool = try sync.Pool.init(.{
        .allocator = allocator,
        .n_thread = options.n_thread orelse
            try std.Thread.getCpuCount() - 1, // Reserve 1 CPU for main thread.
    });

    return .{
        .allocator = allocator,
        .properties = properties,
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
    return Client.init(self.allocator, try self.socket.accept());
}

pub fn startup(self: *Server) !void {
    try self.socket.listen(self.address);
    try self.pool.add(startupHandler, .{self});

    // Sleep the thread forever (nothing can trigger the condition variable)
    {
        var mutex = std.Thread.Mutex{};
        var condition = std.Thread.Condition{};

        mutex.lock();
        defer mutex.unlock();

        condition.wait(&mutex);
    }

    self.status = .running;
}

/// Handler for incoming connections while the server is starting up.
fn startupHandler(server: *Server) void {
    while (server.status == .starting) {
        const client = server.accept() catch continue;
        defer client.deinit();
        client.disconnect("Server is starting.") catch continue;
    }
}
