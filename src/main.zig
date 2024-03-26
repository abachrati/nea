const std = @import("std");
const time = std.time;
const heap = std.heap;
const log = std.log;

const Server = @import("core/Server.zig");
const Properties = @import("core/Properties.zig");

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    log.info("Loading '" ++ Properties.default_path ++ "'", .{});

    // Try and load server properties, using default values on failure.
    const properties = Properties.load(gpa.allocator(), Properties.default_path) catch |err| blk: {
        log.err("Error loading '" ++ Properties.default_path ++ "': {}", .{err});
        break :blk Properties.default;
    };

    // Try and save server properties.
    properties.save(Properties.default_path) catch |err|
        log.err("Error saving '" ++ Properties.default_path ++ "': {}", .{err});

    defer properties.deinit();

    // Initialize the server. This sets up the thread pool, and loads configs.
    var server = try Server.init(.{
        .allocator = gpa.allocator(),
        .properties = properties,
    });
    defer server.deinit();

    log.info("Server starting on {}", .{server.address});

    // Currently the server starts up forever. The main runloop needs to be implemented.
    try server.startup();

    log.info("Done!", .{});
}
