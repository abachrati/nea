const std = @import("std");
const debug = std.debug;
const math = std.math;
const mem = std.mem;

const assert = debug.assert;
const Allocator = mem.Allocator;

/// A wrapping, growable list of items in memory. The list stores `head` and `len` indices into
/// an internal buffer of `T` values. This allows for O(1) insertion/removal at the head and tail
/// of the list.
///
/// This struct stores a `std.mem.Allocator` instance for memory management. To manually specifiy an
/// allocator with each function, see `RingListUnmanaged`.
pub fn RingList(comptime T: type) type {
    return RingListAligned(T, null);
}

/// A wrapping, growable list of arbitrarily aligned items in memory. The list stores `head` and
/// `len` indices into an internal buffer of `T` values aligned to `alignment`-byte addresses. This
/// allows for O(1) insertion/removal at the head and tail of the list. If the specified alignment
/// is `null`, `@alignOf(T)` is used.
///
/// This struct stores a `std.mem.Allocator` instance for memory management. To manually specifiy an
/// allocator with each function, see `RingListUnmanaged`.
pub fn RingListAligned(comptime T: type, comptime alignment: ?u29) type {
    if (alignment != null and alignment.? == @alignOf(T)) {
        return RingListAligned(T, null);
    }

    const S = if (alignment) |a| []align(a) T else []T;

    return struct {
        allocator: Allocator,

        /// Contents of the list. This field is not intended to be accessed directly, instead use
        /// `get`, `set` and `slice`. `items.len` is the capacity of the list.
        ///
        /// Pointers from `set` and `Iterator.next` may be invalidated by various functions
        /// in accordance with the respective documentation.
        items: S = &[_]T{},
        /// The position of the beginning of the list.
        head: usize = 0,
        /// The number of items stored in the list.
        len: usize = 0,

        const Self = @This();

        /// Deinitialize with `deinit`.
        pub fn init(allocator: mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Initialize with capacity to hold exactly `num` elements.
        /// Deinitialize with `deinit`.
        pub fn initCapacity(allocator: mem.Allocator, num: usize) Allocator.Error!Self {
            var self = Self.init(allocator);
            try self.ensureTotalCapacityPrecise(num);
            return self;
        }

        /// Release all owned memory.
        pub fn deinit(self: Self) void {
            if (self.capacity() != 0) {
                self.allocator.free(self.items);
            }
        }

        /// Initializes a `RingListUnmanaged` with the `items`, `head` and `len` fields of this
        /// `RingList`. Empties this `RingList`.
        pub fn toUnmanaged(self: *Self) RingListAlignedUnmanaged(T, alignment) {
            const result = .{
                .items = self.items,
                .head = self.head,
                .len = self.len,
            };

            self.* = Self.init(self.allocator);

            return result;
        }

        /// Creates a copy of this RingList using the same allocator. Items in the copy will be
        /// contiguous, regardless of the ordering of `self`.
        pub fn clone(self: Self) Allocator.Error!Self {
            var cloned = try Self.initCapacity(self.allocator, self.capacity());
            const slice = self.sliceAt(0, self.len);
            slice.copyTo(cloned.items);
            cloned.len = self.len;
            return cloned;
        }

        pub usingnamespace RingListImpl(T, alignment, Self);

        /// Pushes an item to the back of the list. Reallocates buffer if needed, in which case
        /// pointers will be invalidated.
        pub fn pushBack(self: *Self, item: T) !void {
            if (self.capacity() == self.len)
                try self.ensureUnusedCapacity(1);
            self.pushBackAssumeCapacity(item);
        }

        /// Pushes an item to the front of the list. Reallocates buffer if needed, in which case
        /// pointers will be invalidated.
        pub fn pushFront(self: *Self, item: T) !void {
            if (self.capacity() == self.len)
                try self.ensureUnusedCapacity(1);
            self.pushFrontAssumeCapacity(item);
        }

        /// Modify the list so that it an hold at least `new_capacity` items. Reallocates buffer
        /// if needed, in which case pointers will be invalidated.
        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (self.capacity() >= new_capacity)
                return;

            const capacity = growCapacity(self.capacity(), new_capacity);
            return self.ensureTotalCapacityPrecise(capacity);
        }

        /// Modify the list so that it can hold `new_capacity` items. Like `ensureTotalCapacity`,
        /// but the resulting capacity is guaranteed to be equal to `new_capacity. Reallocates
        /// buffer if needed, in which case pointers will be invalidated.
        pub fn ensureTotalCapacityPrecise(self: *Self, new_capacity: usize) Allocator.Error!void {
            if (@sizeOf(T) == 0) {
                self.items.len = math.maxInt(usize);
                return;
            }

            if (self.capacity() >= new_capacity)
                return;

            const slices = self.sliceAt(self.head, self.len);

            // We first try a resize in place. If it succeeds, the overflowing items will not
            // properly fill the newly created space, so we need to move them into place. Otherwise
            // we allocate a completely new buffer to copy our items into, which avoids `realloc()`
            // copying our unused capacity.
            if (self.allocator.resize(self.items, new_capacity)) {
                const old_capacity = self.capacity();
                self.items.len = new_capacity;

                if (slices.second.len == 0)
                    return; // Nothing needs to be moved.

                const count = @min(slices.second.len, new_capacity - old_capacity);
                @memcpy(self.items[old_capacity..][0..count], slices.second[0..count]);
                const left = slices.second.len - count;
                @memcpy(self.items[0..left], slices.second[count..][0..left]);
            } else {
                const items = try self.allocator.alignedAlloc(T, alignment, new_capacity);
                slices.copyTo(items);

                self.deinit();

                self.items = items;
                self.head = 0;
            }
        }

        /// Modify the list so that is can hold at least `additional_count` more items. Reallocates
        /// buffer if needed, in which case pointers will be invalidated.
        pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) Allocator.Error!void {
            return self.ensureTotalCapacity(try addOrOom(self.capacity(), additional_count));
        }
    };
}

/// A wrapping, growable list of items in memory. The list stores `head` and `len` indices into
/// an internal buffer of `T` values. This allows for O(1) insertion/removal at the head and tail
/// of the list.
///
/// Functions which may allocate memory take a `std.mem.Allocator` instance, the same allocator
/// must be used throughout the list's lifetime.
pub fn RingListUnmanaged(comptime T: type) type {
    return RingListAlignedUnmanaged(T, null);
}

/// A wrapping, growable list of arbitrarily aligned items in memory. The list stores `head` and
/// `len` indices into an internal buffer of `T` values aligned to `alignment`-byte addresses. This
/// allows for O(1) insertion/removal at the head and tail of the list. If the specified alignment
/// is `null`, `@alignOf(T)` is used.
///
/// Functions which may allocate memory take a `std.mem.Allocator` instance, the same allocator
/// must be used throughout the list's lifetime.
pub fn RingListAlignedUnmanaged(comptime T: type, comptime alignment: ?u29) type {
    if (alignment != null and alignment.? == @alignOf(T)) {
        return RingListAligned(T, null);
    }

    const S = if (alignment) |a| []align(a) T else []T;

    return struct {
        /// Contents of the list. This field is not intended to be accessed directly, instead use
        /// `get`, `set` and `slice`. `items.len` is the capacity of the list.
        ///
        /// Pointers from `set` and `Iterator.next` may be invalidated by various functions
        /// in accordance with the respective documentation.
        items: S = &[_]T{},
        /// The position of the beginning of the list.
        head: usize = 0,
        /// The number of items stored in the list.
        len: usize = 0,

        const Self = @This();

        /// Initialize with capacity to hold exactly `num` elements.
        /// Deinitialize with `deinit`.
        pub fn initCapacity(allocator: mem.Allocator, num: usize) Allocator.Error!Self {
            var self = Self{};
            try self.ensureTotalCapacityPrecise(allocator, num);
            return self;
        }

        /// Release all owned memory.
        pub fn deinit(self: Self, allocator: Allocator) void {
            if (self.capacity() != 0) {
                allocator.free(self.items);
            }
        }

        /// Initializes a RingListManaged with the `items`, `head` and `len` fields of this
        /// `RingList`, and the passed allocator. Empties this RingList.
        pub fn toManaged(self: *Self, allocator: Allocator) RingListAligned(T, alignment) {
            const result = .{
                .allocator = allocator,
                .items = self.items,
                .head = self.head,
                .len = self.len,
            };

            self.* = Self{};

            return result;
        }

        /// Creates a copy of this RingList using the same allocator. Items in the copy will be
        /// contiguous, regardless of the ordering of `self`.
        pub fn clone(self: Self, allocator: Allocator) Allocator.Error!Self {
            var cloned = try Self.initCapacity(allocator, self.capacity());
            const slice = self.sliceAt(0, self.len);
            slice.copyTo(cloned.items);
            cloned.len = self.len;
            return cloned;
        }

        pub usingnamespace RingListImpl(T, alignment, Self);

        /// Pushes an item to the back of the list. Reallocates buffer if needed, in which case
        /// pointers will be invalidated.
        pub fn pushBack(self: *Self, allocator: Allocator, item: T) !void {
            if (self.capacity() == self.len)
                try self.ensureUnusedCapacity(allocator, 1);
            self.pushBackAssumeCapacity(item);
        }

        /// Pushes an item to the front of the list. Reallocates buffer if needed, in which case
        /// pointers will be invalidated.
        pub fn pushFront(self: *Self, allocator: Allocator, item: T) !void {
            if (self.capacity() == self.len)
                try self.ensureUnusedCapacity(allocator, 1);
            self.pushFrontAssumeCapacity(item);
        }

        /// Modify the list so that is can hold at least `additional_count` more items. Reallocates
        /// buffer if needed, in which case pointers will be invalidated.
        pub fn ensureUnusedCapacity(
            self: *Self,
            allocator: Allocator,
            additional_count: usize,
        ) Allocator.Error!void {
            return self.ensureTotalCapacity(allocator, try addOrOom(
                self.capacity(),
                additional_count,
            ));
        }

        /// Modify the list so that it an hold at least `new_capacity` items. Reallocates buffer
        /// if needed, in which case pointers will be invalidated.
        pub fn ensureTotalCapacity(
            self: *Self,
            allocator: Allocator,
            new_capacity: usize,
        ) Allocator.Error!void {
            if (self.capacity() >= new_capacity)
                return;

            const capacity = growCapacity(self.capacity(), new_capacity);
            return self.ensureTotalCapacityPrecise(allocator, capacity);
        }

        /// Modify the list so that it can hold `new_capacity` items. Like `ensureTotalCapacity`,
        /// but the resulting capacity is guaranteed to be equal to `new_capacity. Reallocates
        /// buffer if needed, in which case pointers will be invalidated.
        pub fn ensureTotalCapacityPrecise(
            self: *Self,
            allocator: Allocator,
            new_capacity: usize,
        ) Allocator.Error!void {
            if (@sizeOf(T) == 0) {
                self.items.len = math.maxInt(usize);
                return;
            }

            if (self.capacity() >= new_capacity)
                return;

            const slices = self.sliceAt(self.head, self.len);

            // We first try a resize in place. If it succeeds, the overflowing items will not
            // properly fill the newly created space, so we need to move them into place. Otherwise
            // we allocate a completely new buffer to copy our items into, which avoids `realloc()`
            // copying our unused capacity.
            if (allocator.resize(self.items, new_capacity)) {
                const old_capacity = self.capacity();
                self.items.len = new_capacity;

                if (slices.second.len == 0)
                    return; // Nothing needs to be moved.

                const count = @min(slices.second.len, new_capacity - old_capacity);
                @memcpy(self.items[old_capacity..][0..count], slices.second[0..count]);
                const left = slices.second.len - count;
                @memcpy(self.items[0..left], slices.second[count..][0..left]);
            } else {
                const items = try allocator.alignedAlloc(T, alignment, new_capacity);
                slices.copyTo(items);

                self.deinit(allocator);

                self.items = items;
                self.head = 0;
            }
        }
    };
}

/// Common methods for RingList implementations.
fn RingListImpl(comptime T: type, comptime alignment: ?u29, comptime Self: type) type {
    const S = if (alignment) |a| []align(a) T else []T;

    return struct {
        /// Map `index` into the backing slice.
        pub fn mask(self: Self, index: usize) usize {
            if (self.capacity() == 0)
                return 0; // Prevents division by zero. Is this a hack? Maybe...
            return index % self.capacity();
        }

        /// Returns the maximum number of items the RingList can store without resizing.
        pub inline fn capacity(self: Self) usize {
            return self.items.len;
        }

        /// A `Slice` represents a region of a RingList. The region is split in two sections as the
        /// data will not be contiguous if the region wraps within the internal buffer.
        pub const Slice = struct {
            first: S,
            second: S,

            /// Copies the items in `self` into `dest`.
            pub fn copyTo(self: Slice, dest: []align(1) T) void {
                @memcpy(dest[0..self.first.len], self.first);
                @memcpy(dest[self.first.len..][0..self.second.len], self.second);
            }
        };

        /// Returns a `Slice` for the region of the ring buffer from `start` to `start + length`.
        /// Asserts that requested slice is within bounds.
        pub fn sliceAt(self: Self, start: usize, length: usize) Slice {
            assert(self.len - start >= length);

            const head = self.mask(start);
            const tail = @min(self.capacity(), head + length);

            const first = self.items[head..tail];
            const left = length - first.len;
            const second = self.items[0..left];

            return .{
                .first = first,
                .second = second,
            };
        }

        /// Returns a `Slice` for the last `length` items in the buffer.
        pub fn sliceLast(self: Self, length: usize) Slice {
            return self.sliceAt(self.head + self.len - length, length);
        }

        /// Returns a pointer to the item at `index`. Asserts that index is within bounds.
        pub fn get(self: Self, index: usize) *T {
            assert(index < self.len);
            return &self.items[self.mask(self.head + index)];
        }

        /// Returns a pointer to the item at `index`. Returns `null` if index is out of bounds.
        pub fn getOrNull(self: Self, index: usize) ?*T {
            if (index >= self.len)
                return null;
            return self.get(index);
        }

        /// An iterator over the items in the RingList.
        pub const Iterator = struct {
            context: *const Self,
            index: usize = 0,

            /// Returns the next item in the iterator, or `null` if the end has been reached.
            pub fn next(self: *Iterator) ?*T {
                defer self.index += 1;
                return self.context.getOrNull(self.index);
            }

            /// Resets the iterator.
            pub fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        /// Returns an iterator over the items in the RingList.
        pub fn iterator(self: *const Self) Iterator {
            return .{ .context = self };
        }

        /// Pushes an item to the back of the list. Asserts that the list is not full.
        pub fn pushBackAssumeCapacity(self: *Self, item: T) void {
            assert(self.capacity() >= self.len);

            const tail = self.mask(self.head + self.len);
            self.items[tail] = item;

            self.len += 1;
        }

        /// Pushes an item to the front of the list. Asserts that the list is not full.
        pub fn pushFrontAssumeCapacity(self: *Self, item: T) void {
            assert(self.capacity() >= self.len);

            self.head = self.mask(self.head + self.capacity() - 1);
            self.items[self.head] = item;

            self.len += 1;
        }

        // TODO: Implememnt
        // pub fn pushSliceBackAssumeCapacity(self: *Self, items: []align(1) const T) void {
        //     _ = self; // autofix
        //     _ = items; // autofix
        // }

        // TODO: Implememnt
        // pub fn pushSliceFrontAssumeCapacity(self: *Self, items: []align(1) const T) void {
        //     _ = self; // autofix
        //     _ = items; // autofix
        // }

        /// Pops an item from the back of the list. Asserts that the list is not empty.
        pub fn popBack(self: *Self) T {
            const tail = self.mask(self.head + self.len - 1);
            self.len -= 1;
            return self.items[tail];
        }

        /// Pops an item from the back of the list. Returns `null` if the list is empty.
        pub fn popBackOrNull(self: *Self) ?T {
            if (self.len == 0)
                return null;
            return self.popFront();
        }

        /// Pops an item from the front of the list. Asserts that the list is not empty.
        pub fn popFront(self: *Self) T {
            const head = self.head;
            self.head = self.mask(self.head + 1);
            self.len -= 1;
            return self.items[head];
        }

        /// Pops an item from the front of the list. Returns `null` if the list is empty.
        pub fn popFrontOrNull(self: *Self) ?T {
            if (self.len == 0)
                return null;
            return self.popFront();
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

/// Performs `a + b`, returning `error.OutOfMemory` if would overflow `usize`.
fn addOrOom(a: usize, b: usize) Allocator.Error!usize {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0)
        return error.OutOfMemory;
    return result[0];
}

const testing = std.testing;

test "RingList/RingListUnmanaged.init" {
    {
        var list = RingList(i32).init(testing.allocator);
        defer list.deinit();

        try testing.expect(list.len == 0);
        try testing.expect(list.capacity() == 0);
    }

    {
        var list = RingListUnmanaged(i32){};

        try testing.expect(list.len == 0);
        try testing.expect(list.capacity() == 0);
    }
}

test "RingList/RingListUnmanaged.initCapacity" {
    {
        var list = try RingList(i8).initCapacity(testing.allocator, 200);
        defer list.deinit();

        try testing.expect(list.len == 0);
        try testing.expect(list.capacity() >= 200);
    }

    {
        var list = try RingListUnmanaged(i8).initCapacity(testing.allocator, 200);
        defer list.deinit(testing.allocator);

        try testing.expect(list.len == 0);
        try testing.expect(list.capacity() >= 200);
    }
}

test "RingList/RingListUnmanaged.clone" {
    {
        var list = RingList(i32).init(testing.allocator);

        try list.pushBack(-1);
        try list.pushBack(3);
        try list.pushBack(5);

        var clone = try list.clone();
        defer clone.deinit();

        try testing.expectEqualSlices(i32, list.items, clone.items);
        try testing.expectEqual(list.allocator, clone.allocator);
        try testing.expect(clone.capacity() >= list.capacity());

        list.deinit();

        try testing.expectEqual(@as(i32, 5), clone.popBack());
        try testing.expectEqual(@as(i32, 3), clone.popBack());
        try testing.expectEqual(@as(i32, -1), clone.popBack());
    }

    {
        var list = RingListUnmanaged(i32){};

        try list.pushBack(testing.allocator, -1);
        try list.pushBack(testing.allocator, 3);
        try list.pushBack(testing.allocator, 5);

        var clone = try list.clone(testing.allocator);
        defer clone.deinit(testing.allocator);

        try testing.expectEqualSlices(i32, list.items, clone.items);
        try testing.expect(clone.capacity() >= list.capacity());

        list.deinit(testing.allocator);

        try testing.expectEqual(@as(i32, 5), clone.popBack());
        try testing.expectEqual(@as(i32, 3), clone.popBack());
        try testing.expectEqual(@as(i32, -1), clone.popBack());
    }
}

test "RingList/RingListUnmanaged(u0)" {
    // A RingList of zero-sized types should not need to allocate memory.
    {
        var list = RingList(u0).init(testing.failing_allocator);
        defer list.deinit();

        try list.pushBack(0);
        try list.pushBack(0);
        try list.pushBack(0);

        try testing.expectEqual(@as(usize, 3), list.len);

        try testing.expectEqual(@as(u0, 0), list.popBack());
        try testing.expectEqual(@as(u0, 0), list.popBack());
        try testing.expectEqual(@as(u0, 0), list.popBack());
        try testing.expectEqual(@as(?u0, null), list.popBackOrNull());
    }

    {
        var list = RingListUnmanaged(u0){};
        defer list.deinit(testing.failing_allocator);

        try list.pushBack(testing.failing_allocator, 0);
        try list.pushBack(testing.failing_allocator, 0);
        try list.pushBack(testing.failing_allocator, 0);

        try testing.expectEqual(@as(usize, 3), list.len);

        try testing.expectEqual(@as(u0, 0), list.popBack());
        try testing.expectEqual(@as(u0, 0), list.popBack());
        try testing.expectEqual(@as(u0, 0), list.popBack());
        try testing.expectEqual(@as(?u0, null), list.popBackOrNull());
    }
}

test "RingList/RingListUnmanaged: push/pop" {
    {
        var list = RingList(i8).init(testing.allocator);
        defer list.deinit();

        try list.pushBack(-1);
        try list.pushBack(3);
        try list.pushBack(5);

        try testing.expectEqual(@as(usize, 3), list.len);

        try testing.expectEqual(@as(i32, -1), list.popFront());
        try testing.expectEqual(@as(i32, 3), list.popFront());
        try testing.expectEqual(@as(i32, 5), list.popFront());

        try testing.expectEqual(@as(usize, 0), list.len);

        try list.pushFront(-1);
        try list.pushFront(3);
        try list.pushFront(5);

        try testing.expectEqual(@as(usize, 3), list.len);

        try testing.expectEqual(@as(i32, -1), list.popBack());
        try testing.expectEqual(@as(i32, 3), list.popBack());
        try testing.expectEqual(@as(i32, 5), list.popBack());

        try testing.expectEqual(@as(usize, 0), list.len);
    }

    {
        var list = RingListUnmanaged(i8){};
        defer list.deinit(testing.allocator);

        try list.pushBack(testing.allocator, -1);
        try list.pushBack(testing.allocator, 3);
        try list.pushBack(testing.allocator, 5);

        try testing.expectEqual(@as(usize, 3), list.len);

        try testing.expectEqual(@as(i32, -1), list.popFront());
        try testing.expectEqual(@as(i32, 3), list.popFront());
        try testing.expectEqual(@as(i32, 5), list.popFront());

        try testing.expectEqual(@as(usize, 0), list.len);

        try list.pushFront(testing.allocator, -1);
        try list.pushFront(testing.allocator, 3);
        try list.pushFront(testing.allocator, 5);

        try testing.expectEqual(@as(usize, 3), list.len);

        try testing.expectEqual(@as(i32, -1), list.popBack());
        try testing.expectEqual(@as(i32, 3), list.popBack());
        try testing.expectEqual(@as(i32, 5), list.popBack());

        try testing.expectEqual(@as(usize, 0), list.len);
    }
}

// TODO: Implememnt
// test "pushbackslice" {
//     var list = try RingList(i8).initCapacity(testing.allocator, 20);
//     defer list.deinit();

//     list.pushSliceBackAssumeCapacity(&[_]i8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 });

//     var iter = list.iterator();

//     try testing.expectEqual(iter.next().?.*, 0);
//     try testing.expectEqual(iter.next().?.*, 1);
//     try testing.expectEqual(iter.next().?.*, 2);
//     try testing.expectEqual(iter.next().?.*, 3);
//     try testing.expectEqual(iter.next().?.*, 4);
//     try testing.expectEqual(iter.next().?.*, 5);
//     try testing.expectEqual(iter.next().?.*, 6);
//     try testing.expectEqual(iter.next().?.*, 7);
//     try testing.expectEqual(iter.next().?.*, 8);
//     try testing.expectEqual(iter.next().?.*, 9);
// }
