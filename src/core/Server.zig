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
/// TODO: Could probably reuse this for shutdown aswell.
fn startupHandler(server: *Server) void {
    while (server.status == .starting) {
        startupHandlerInner(server) catch |err| std.log.err("{}", .{err});
    }
}

/// Pool tasks cannot return an error, so we simply ignore them in `startupHandler`.
fn startupHandlerInner(server: *Server) !void {
    if (server.socket.accept()) |conn| {
        defer conn.stream.close();

        var state: bnet.State = .handshake;
        var arena = heap.ArenaAllocator.init(server.allocator);

        while (true) {
            switch (state) {
                .handshake => {
                    switch (try v765.handshake.read(&arena, conn.stream.reader())) {
                        .handshake => |pkt| {
                            state = switch (pkt.next) {
                                .status => .status,
                                .login => .login,
                            };
                        },
                        .legacy => break, // Terminate the connection for legacy clients.
                    }
                },
                .status => {
                    switch (try v765.status.read(&arena, conn.stream.reader())) {
                        .status_request => {
                            const response =
                                \\ {
                                \\     "version": {
                                \\         "name": "1.20.4",
                                \\         "protocol": 765
                                \\     },
                                \\     "players": {
                                \\         "max": 0,
                                \\         "online": 0
                                \\     },
                                \\     "description": {
                                \\         "text": "Server is starting."
                                \\     }
                                \\ }
                            ;

                            try v765.status.write(.{
                                .status_response = .{
                                    .response = response,
                                },
                            }, conn.stream.writer());
                        },
                        .ping_request => |pkt| {
                            try v765.status.write(.{
                                .ping_response = .{
                                    .payload = pkt.payload,
                                },
                            }, conn.stream.writer());

                            break; // No packets follow clientbound Ping Response.
                        },
                    }
                },
                .login => {
                    try v765.login.write(.{
                        .disconnect = .{
                            .reason = "{\"text\":\"Server is starting.\"}",
                        },
                    }, conn.stream.writer());

                    break; // No packets follow clientbound Disconnect.
                },
                else => unreachable,
            }
        }
    } else |_| {}
}
