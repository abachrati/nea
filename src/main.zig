const std = @import("std");
const heap = std.heap;
const log = std.log;

const core = @import("core/lib.zig");

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var server = try core.Server.init(.{
        .allocator = gpa.allocator(),
        .n_thread = 3,
    });
    defer server.deinit();

    log.info("Server starting on {}", .{server.address});

    try server.startup();

    log.info("Done!", .{});

    while (server.status == .running) {}
}
