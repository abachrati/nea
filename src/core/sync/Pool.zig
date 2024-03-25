const std = @import("std");
const mem = std.mem;

const foo = @import("foo");

allocator: mem.Allocator,

queue: foo.RingListUnmanaged(*Runnable) = .{},
threads: []std.Thread = &[_]std.Thread{},
is_running: bool = true,

mutex: std.Thread.Mutex = .{},
condition: std.Thread.Condition = .{},

pub const Runnable = struct {
    runFn: *const fn (*Runnable) void,
};

pub const Options = struct {
    allocator: mem.Allocator,

    thread_count: ?usize = null,
    thread_config: std.Thread.SpawnConfig = .{},
};

const Pool = @This();

pub fn init(self: *Pool, options: Options) !void {
    self.* = .{
        .allocator = options.allocator,
    };

    const thread_count = options.thread_count orelse try std.Thread.getCpuCount();
    const threads = try options.allocator.alloc(std.Thread, thread_count);
    errdefer options.allocator.free(threads);

    var spawned: usize = 0;
    errdefer self.joinCount(spawned); // Kill and cleanup spawned threads.

    for (threads) |*thread| {
        thread.* = try std.Thread.spawn(options.thread_config, worker, .{self});
        spawned += 1;
    }

    self.threads = threads;
}

pub fn initAlloc(options: Options) !*Pool {
    const self = options.allocator.create(Pool);
    try self.init(options);
    return self;
}

pub fn deinit(self: *Pool) void {
    self.join(); // Wait for threads to end, and join them.
    self.allocator.free(self.threads);
    self.queue.deinit(self.allocator);
}

pub fn join(self: *Pool) void {
    return self.joinCount(self.threads.len);
}

pub fn spawn(self: *Pool, comptime func: anytype, args: anytype) !void {
    const Args = @TypeOf(args);
    const Closure = struct {
        args: Args,
        pool: *Pool,

        runnable: Runnable = .{ .runFn = run },

        const Closure = @This();

        fn run(runnable: *Runnable) void {
            const closure = @fieldParentPtr(Closure, "runnable", runnable);

            @call(.auto, func, closure.args);

            // The pool's allocator is protected by the mutex.
            {
                const mutex = &closure.pool.mutex;
                mutex.lock();
                defer mutex.unlock();

                closure.pool.allocator.destroy(closure);
            }
        }
    };

    {
        self.mutex.lock();
        defer self.mutex.unlock();

        const closure = try self.allocator.create(Closure);
        closure.* = .{
            .args = args,
            .pool = self,
        };

        try self.queue.pushBack(self.allocator, &closure.runnable);
    }

    self.condition.signal();
}

fn worker(pool: *Pool) void {
    pool.mutex.lock();
    defer pool.mutex.unlock();

    while (true) {
        if (pool.queue.popFrontOrNull()) |runnable| {
            pool.mutex.unlock(); // Unlock mutex while doing work.
            defer pool.mutex.lock();

            runnable.runFn(runnable);
        }

        if (pool.is_running) {
            pool.condition.wait(&pool.mutex);
        } else {
            break;
        }
    }
}

fn joinCount(self: *Pool, count: usize) void {
    {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.is_running = false;
    }

    self.condition.broadcast();

    for (self.threads[0..count]) |thread| {
        thread.join();
    }
}
