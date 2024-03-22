const std = @import("std");
const mem = std.mem;
const net = std.net;

// TODO: Move into seperate file
/// The default host to bind to if `properties.server-ip` is empty.
const DEFAULT_HOST = "0.0.0.0";

pub const Properties = @import("Properties.zig");

pub const Server = struct {
    allocator: mem.Allocator,
    properties: *Properties,

    address: net.Address,
    server: net.Server,

    const Options = struct {
        allocator: mem.Allocator,
        properties: *Properties,
        address: ?net.Address = null,
    };

    pub fn init(options: Options) !Server {
        const address = options.address orelse blk: {
            var host = options.properties.@"server-ip";
            if (host.len == 0) host = DEFAULT_HOST;
            const port = options.properties.@"server-port";

            break :blk try net.Address.resolveIp(host, port);
        };

        const self = .{
            .allocator = options.allocator,
            .properties = options.properties,
            .address = address,
            .server = try address.listen(.{
                .reuse_address = true,
                // .force_nonblocking = true,
            }),
        };

        return self;
    }

    pub fn deinit(self: *Server) void {
        self.* = undefined;
    }

    pub fn run(self: *Server) !void {
        while (true) {
            const conn = self.server.accept() catch continue;
            try conn.stream.writeAll("Hello, World!\n");
        }
    }
};
