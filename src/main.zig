const std = @import("std");
const time = std.time;
const heap = std.heap;
const log = std.log;

const util = @import("core/util/lib.zig");
const Server = @import("core/Server.zig");
const Properties = @import("core/Properties.zig");

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const start = time.microTimestamp();

    log.info("Loading '" ++ Properties.properties_path ++ "'", .{});

    // Try and load server properties, using default values on failure.
    const properties = Properties.load(gpa.allocator(), Properties.properties_path) catch |err| blk: {
        log.err("Error loading '" ++ Properties.properties_path ++ "': {}", .{err});
        break :blk Properties.default;
    };

    // Try and save server properties.
    properties.save(Properties.properties_path) catch |err|
        log.err("Error saving '" ++ Properties.properties_path ++ "': {}", .{err});

    defer properties.deinit();

    // Try and load favicon.
    const favicon = util.loadFavicon(gpa.allocator(), util.favicon_path) catch null;
    defer if (favicon) |fav| gpa.allocator().free(fav);

    // Initialize the server. This sets up the thread pool, and loads configs.
    var server = try Server.init(.{
        .allocator = gpa.allocator(),
        .properties = properties,
        .favicon = favicon,
    });
    defer server.deinit();

    log.info("Server starting on {}", .{server.address});

    try server.startup();
    const end = time.microTimestamp();

    log.info("Done ({}ms)!", .{end - start});

    while (true) {
        const client = server.accept() catch continue;
        client.login() catch continue;

        server.tick() catch break;
    }
}
