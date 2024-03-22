const std = @import("std");
const mem = std.mem;

const RingArrayUnmanaged = @import("../misc/ring_array.zig").RingArrayUnmanaged;

pub fn Queue(comptime T: type) type {
    return struct {
        allocator: mem.Allocator,

        items: RingArrayUnmanaged(T) = .{},
        mutex: std.Thread.Mutex = .{},

        const Self = @This();

        pub fn init(allocator: mem.Allocator) !Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        pub fn send(self: *Self, item: T) !void {
            _ = self; // autofix
            _ = item; // autofix
        }

        pub fn trySend(self: *Self, item: T) !void {
            _ = self; // autofix
            _ = item; // autofix
        }

        pub fn receive(self: *Self) !T {
            _ = self; // autofix
        }

        pub fn tryReceive(self: *Self) !?T {
            _ = self; // autofix
        }
    };
}
