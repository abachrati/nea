const std = @import("std");
const heap = std.heap;
const time = std.time;
const mem = std.mem;
const net = std.net;
const log = std.log;

const core = @import("core/lib.zig");

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    log.info("Starting Basalt server", .{});

    const properties = try core.Properties.load(gpa.allocator(), "server.properties");
    defer properties.deinit();
}
