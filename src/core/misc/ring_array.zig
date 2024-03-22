const std = @import("std");
const mem = std.mem;

/// A growable RingArray of items in memory. Items are not necessarily continuous in memory, instead
/// wrapping around within an internal buffer. Allows for O(1) push and pop on either end.
pub fn RingArray(comptime T: type) type {
    return struct {
        allocator: mem.Allocator,

        head: usize = 0,
        len: usize = 0,

        items: []T = &[_]T{},

        const Self = @This();

        pub fn init(allocator: mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Initialize a RingArray with the given capacity. The resulting capacity will be `num`
        /// exactly.
        pub fn initCapacity(allocator: mem.Allocator, num: usize) !Self {
            var self = Self.init(allocator);
            try self.ensureTotalCapacityPrecise(num);
            return self;
        }

        pub fn deinit(self: *Self) void {
            if (self.items.len > 0) {
                self.allocator.free(self.items);
            }
        }

        /// Grows the list so that it can store at least `unused` additional items.
        pub fn ensureUnusedCapacity(self: *Self, unused: usize) !void {
            return self.ensureTotalCapacity(self.capacity() + unused);
        }

        /// Grows the list so that it can store at least `total` total items.
        pub fn ensureTotalCapacity(self: *Self, total: usize) !void {
            const new_capacity = growCapacity(self.capacity(), total);
            return self.ensureTotalCapacityPrecise(new_capacity);
        }

        /// Grows the list so that it can store exactly `total` total items.
        pub fn ensureTotalCapacityPrecise(self: *Self, total: usize) !void {
            if (total <= self.capacity()) return;
            const items = try self.allocator.alloc(T, total);

            const first, const last = self.asSlices();

            // Copy items into the new array, making them contiguous
            @memcpy(items[0..first.len], first);
            @memcpy(items[first.len..][0..last.len], last);

            self.allocator.free(self.items);

            self.items = items;
            self.head = 0;
        }

        /// Pushes an item to the back of the list, growing if required.
        pub fn pushBack(self: *Self, item: T) !void {
            if (self.len == self.capacity()) try self.ensureUnusedCapacity(1);
            self.pushBackAssumeCapacity(item);
        }

        /// Pushes an item to the front of the list, growing if required.
        pub fn pushFront(self: *Self, item: T) !void {
            if (self.len == self.capacity()) try self.ensureUnusedCapacity(1);
            self.pushFrontAssumeCapacity(item);
        }

        pub usingnamespace RingArrayMethods(T, Self);
    };
}

/// A growable RingArrayUnmanaged of items in memory. Items are not necessarily continuous in
/// memory, instead wrapping around within an internal buffer.  Allows for O(1) push and pop on
/// either end. The same allocator must be used throughout the list's lifetime.
pub fn RingArrayUnmanaged(comptime T: type) type {
    return struct {
        head: usize = 0,
        len: usize = 0,

        items: []T = &[_]T{},

        const Self = @This();

        /// Initialize a RingArray with the given capacity. The resulting capacity will be `num`
        /// exactly.
        pub fn initCapacity(allocator: mem.Allocator, num: usize) !Self {
            var self = Self{};
            try self.ensureTotalCapacityPrecise(allocator, num);
            return self;
        }

        pub fn deinit(self: *Self, allocator: mem.Allocator) void {
            if (self.items.len > 0) {
                allocator.free(self.items);
            }
        }

        /// Grows the list so that it can store at least `unused` additional items.
        pub fn ensureUnusedCapacity(self: *Self, allocator: mem.Allocator, unused: usize) !void {
            return self.ensureTotalCapacity(allocator, self.capacity() + unused);
        }

        /// Grows the list so that it can store at least `total` total items.
        pub fn ensureTotalCapacity(self: *Self, allocator: mem.Allocator, total: usize) !void {
            const new_capacity = growCapacity(self.capacity(), total);
            return self.ensureTotalCapacityPrecise(allocator, new_capacity);
        }

        /// Grows the list so that it can store exactly `total` total items.
        pub fn ensureTotalCapacityPrecise(
            self: *Self,
            allocator: mem.Allocator,
            total: usize,
        ) !void {
            if (total <= self.items.len) return;
            const items = try allocator.alloc(T, total);

            const first, const last = self.asSlices();

            @memcpy(items[0..first.len], first);
            @memcpy(items[first.len..][0..last.len], last);

            allocator.free(self.items);

            self.items = items;
            self.head = 0;
        }

        /// Pushes an item to the back of the list, growing if required.
        pub fn pushBack(self: *Self, allocator: mem.Allocator, item: T) !void {
            if (self.len >= self.capacity()) try self.ensureUnusedCapacity(allocator, 1);
            self.pushBackAssumeCapacity(item);
        }

        /// Pushes an item to the front of the list, growing if required.
        pub fn pushFront(self: *Self, allocator: mem.Allocator, item: T) !void {
            if (self.len >= self.capacity()) try self.ensureUnusedCapacity(allocator, 1);
            self.pushFrontAssumeCapacity(item);
        }

        pub usingnamespace RingArrayMethods(T, Self);
    };
}

/// Methods shared between RingArray implementations.
fn RingArrayMethods(comptime T: type, comptime Self: type) type {
    return struct {
        pub inline fn capacity(self: *const Self) usize {
            return self.items.len;
        }

        /// Returns a pair of slices which contain, in order, the contents of the array.
        pub inline fn asSlices(self: *Self) struct { []T, []T } {
            const head_end = @min(self.head + self.len, self.items.len);
            const tail_end = self.head + self.len -| self.items.len;

            return .{ self.items[self.head..head_end], self.items[0..tail_end] };
        }

        /// Pushes an item to the back of the list. If the RingArray is full, clobbers the front
        /// item.
        pub fn pushBackAssumeCapacity(self: *Self, item: T) void {
            const tail = (self.head + self.len) % self.items.len;
            self.items[tail] = item;

            self.len += 1;
        }

        /// Pushes an item to the front of the list. If the RingArray is full, clobbers the back
        /// item.
        pub fn pushFrontAssumeCapacity(self: *Self, item: T) void {
            self.head = (self.head + self.items.len - 1) % self.items.len;
            self.items[self.head] = item;
            self.len += 1;
        }

        /// Pops an item from the back of the array. Invalidates pointers to the popped item.
        pub fn popBack(self: *Self) ?T {
            if (self.len == 0) return null;

            const tail = (self.head + self.len) % self.items.len;
            self.len -= 1;

            return self.items[tail];
        }

        /// Pops an item from the front of the array. Invalidates pointers to the popped item.
        pub fn popFront(self: *Self) ?T {
            if (self.len == 0) return null;

            const head = self.head;
            self.head = (self.head + 1) % self.items.len;
            self.len -= 1;

            return self.items[head];
        }

        /// Returns an item pointer from the index into the array. Pointers are invalidated if the
        /// list is resized.
        pub fn get(self: *Self, index: usize) ?*T {
            if (index > self.len - 1) return null;
            return &self.items[(self.head + index) % self.items.len];
        }

        /// Sets the item at `index` to `item`. `index` must not be larger than `len - 1`.
        pub fn set(self: *Self, index: usize, item: T) !void {
            if (index > self.len - 1) return error.OutOfBounds;
            self.items[(self.head + index) % self.items.len] = item;
        }

        pub const Iterator = struct {
            context: *Self,
            index: usize = 0,

            pub fn next(self: *Iterator) ?*T {
                const item = self.context.get(self.index) orelse return null;
                self.index += 1;
                return item;
            }

            pub fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        /// Returns an iterator over the items in the array. Modifying the list invalidates the
        /// iterator.
        pub fn iterator(self: *Self) Iterator {
            return .{ .context = self };
        }
    };
}

/// Called when memory growth is necessary. Returns a capacity larger than
/// minimum that grows super-linearly. Taken from `std.ArrayList`.
fn growCapacity(current: usize, minimum: usize) usize {
    var new = current;
    while (true) {
        new +|= new / 2 + 8;
        if (new >= minimum)
            return new;
    }
}
