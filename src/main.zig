const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const net = std.net;
const log = std.log;

const core = @import("core/core.zig");

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    log.info("Starting Basalt server", .{});

    const properties = core.Properties.load(gpa.allocator(), "server.properties") catch blk: {
        log.err("Failed to load server properties", .{});
        break :blk .{};
    };
    _ = properties;
}
