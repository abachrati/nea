const std = @import("std");
const heap = std.heap;
const log = std.log;

const core = @import("core/lib.zig");

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const properties = try core.Properties.load(gpa.allocator(), "server.properties");
    defer properties.deinit();

    var server = try core.Server.init(.{
        .allocator = gpa.allocator(),
        .properties = properties,
    });
    defer server.deinit();

    log.info("Server starting on {}", .{server.address});

    // Currently the server starts up forever. The main runloop needs to be implemented.
    try server.startup();

    log.info("Done!", .{});
}
