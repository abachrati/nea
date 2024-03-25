//! A thread pool for concurrent execution of tasks. Adapted from `std.Thread.Pool`.

const std = @import("std");
const mem = std.mem;

const RingListUnmanaged = @import("ring_list.zig").RingListUnmanaged;

allocator: mem.Allocator,

queue: RingListUnmanaged(Task) = .{},
threads: []std.Thread = &[_]std.Thread{},
is_running: bool = true,

mutex: std.Thread.Mutex = .{},
condition: std.Thread.Condition = .{},

const Task = struct {
    args: *anyopaque,
    taskFn: *const fn (*Pool, *anyopaque) void,
};

const Pool = @This();

pub const Options = struct {
    allocator: mem.Allocator,
    /// Number of threads to spawn. If `null`, the system's CPU count is used.
    n_thread: ?usize = null,
};

/// Initialize a new pool, and spawn worker threads.
pub fn init(options: Options) !*Pool {
    const self = try options.allocator.create(Pool);

    self.* = .{
        .allocator = options.allocator,
    };

    const n_thread = options.n_thread orelse try std.Thread.getCpuCount();

    const threads = try options.allocator.alloc(std.Thread, n_thread);
    errdefer options.allocator.free(threads);

    for (threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, worker, .{self});
        errdefer self.join(i); // Kill and cleanup spawned threads.
    }

    self.threads = threads;

    return self;
}

/// Does not ensure all work in the queue is complete. Blocks until worker threads complete their
/// current task.
pub fn deinit(self: *Pool) void {
    self.join(self.threads.len); // Wait for threads to end, and join them.
    self.allocator.free(self.threads);
    self.queue.deinit(self.allocator);
    self.allocator.destroy(self);
}

/// Add a new task to the back of the task queue.
pub fn add(self: *Pool, comptime function: anytype, args: anytype) !void {
    const Args = @TypeOf(args);

    if (@typeInfo(Args) != .Struct)
        @compileError("`args` must be a tuple of arguments, not `" ++ @typeName(Args) ++ "`");

    {
        self.mutex.lock();
        defer self.mutex.unlock();

        // `args` must be copied to the heap, since the job will outlive this function's stack
        // frame.
        const copy = try self.allocator.create(Args);
        errdefer self.allocator.destroy(copy);

        copy.* = args;

        try self.queue.pushBack(self.allocator, .{
            .args = copy,
            .taskFn = taskFn(function, Args),
        });
    }

    self.condition.signal();
}

/// Block the caller thread until all work is complete / threads to become idle.
pub fn wait(self: *Pool) void {
    _ = self; // autofix
    @compileError("TODO: implement");
}

fn worker(pool: *Pool) void {
    pool.mutex.lock();
    defer pool.mutex.unlock();

    while (true) {
        if (pool.queue.popFrontOrNull()) |job| {
            pool.mutex.unlock(); // Unlock pool while doing work.
            defer pool.mutex.lock();

            job.taskFn(pool, job.args);
        }

        if (pool.is_running) {
            pool.condition.wait(&pool.mutex); // Unlocks pool while waiting.
        } else {
            break;
        }
    }
}

/// Join the first `n` threads in the pool. Helps with error cleanup.
fn join(self: *Pool, n: usize) void {
    {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.is_running = false;
    }

    self.condition.broadcast();

    for (self.threads[0..n]) |thread| {
        thread.join();
    }
}

/// Generic job caller for any function and args.
fn taskFn(comptime function: anytype, comptime Args: type) fn (*Pool, *anyopaque) void {
    return struct {
        fn task(pool: *Pool, context: *anyopaque) void {
            const args: *Args = @ptrCast(@alignCast(context));

            @call(.auto, function, args.*);

            // The pool's allocator is protected by the mutex.
            {
                const mutex = &pool.mutex;
                mutex.lock();
                defer mutex.unlock();

                pool.allocator.destroy(args);
            }
        }
    }.task;
}
