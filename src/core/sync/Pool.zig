const std = @import("std");
const mem = std.mem;

allocator: mem.Allocator,

mutex: std.Thread.Mutex = .{},
threads: []std.Thread,

const Options = struct {
    allocator: mem.Allocator,
    thread_count: ?usize = null,
};

const Self = @This();

pub fn init(self: *Self, options: Options) !void {
    self.* = .{
        .allocator = options.allocator,
        .threads = &[_]std.Thread{},
    };

    const count = options.thread_count orelse try std.Thread.getCpuCount();
    const threads = try self.allocator.alloc(std.Thread, count);
    errdefer self.allocator.free(threads);

    var spawned: usize = 0;
    errdefer for (self.threads[0..spawned]) |thread| thread.join();

    for (self.threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, worker, .{self});
        spawned += 1;
    }

    self.threads = threads;
}

pub fn deinit(self: *Self) void {
    _ = self; // autofix
}

fn worker(self: *Self) void {
    _ = self; // autofix
}
