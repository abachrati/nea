const std = @import("std");
const heap = std.heap;
const time = std.time;
const mem = std.mem;
const net = std.net;
const log = std.log;

const core = @import("core/lib.zig");
const sync = core.sync;

fn greeter(num: usize) void {
    log.info("Hello, {}", .{num});
    time.sleep(time.ns_per_s);
}

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    log.info("Starting Basalt server", .{});

    const properties = try core.Properties.load(gpa.allocator(), "server.properties");
    defer properties.deinit();

    var pool: sync.Pool = undefined;
    try pool.init(.{ .allocator = gpa.allocator() });
    defer pool.deinit();

    try pool.spawn(greeter, .{1});
    try pool.spawn(greeter, .{2});
    try pool.spawn(greeter, .{3});
    try pool.spawn(greeter, .{4});
    try pool.spawn(greeter, .{5});
    try pool.spawn(greeter, .{6});
    try pool.spawn(greeter, .{7});
}
