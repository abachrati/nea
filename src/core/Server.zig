const std = @import("std");
const time = std.time;
const mem = std.mem;
const net = std.net;
const log = std.log;

const bnet = @import("net/lib.zig");
const sync = @import("sync/lib.zig");
const util = @import("util/lib.zig");

const io_mode = .evented;

const Properties = @import("Properties.zig");

allocator: mem.Allocator,

properties: *const Properties,

address: net.Address,
socket: net.StreamServer,
pool: *sync.Pool,

/// Only the main thread is allowed to mutate this.
status: Status = .starting,

const Status = enum { starting, running, stopping };

const Server = @This();

const Options = struct {
    allocator: mem.Allocator,

    properties: ?*const Properties = null,
    /// Number of threads for the server to run on. If `null` the system's CPU count - 1 is used.
    n_thread: ?usize = null,
    /// Address to bind server to. If `null`, address is resolved from `properties.server-ip` and
    /// `properties.server-port`.
    address: ?net.Address = null,
};

pub fn init(options: Options) !Server {
    const allocator = options.allocator;
    const properties = options.properties orelse Properties.default;

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

pub fn startup(self: *Server) !void {
    try self.socket.listen(self.address);
    try self.pool.add(startupHandler, .{self});

    std.time.sleep(std.time.ns_per_s * 10);
    self.status = .running;
}

fn startupHandler(server: *Server) void {
    while (server.status == .starting) {}
}
