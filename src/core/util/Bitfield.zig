//! Like `std.PackedIntArray`, but with dynamic bitwidth and length

const std = @import("std");

const math = std.math;
const mem = std.mem;

length: usize,
stride: Log2Ceil,

mask: u64,
per_elem: Log2Ceil,

data: []u64,

pub const Self = @This();
pub const Log2Ceil = math.Log2IntCeil(u64);

/// Allocates and initializes bitfield with zeros
pub fn init(alloc: mem.Allocator, stride: Log2Ceil, length: usize) mem.Allocator.Error!Self {
    std.debug.assert(stride > 0 and stride <= @bitSizeOf(u64));

    const per_elem = @bitSizeOf(u64) / stride;
    const mask = if (stride == 64) math.maxInt(i32) else ((@as(u64, 1) << stride) - 1);

    const size = (length + per_elem - 1) / per_elem;
    const data = try alloc.alloc(u64, size);
    @memset(data, 0);

    return .{
        .length = length,
        .stride = stride,
        .mask = mask,
        .per_elem = @truncate(per_elem),
        .data = data,
    };
}

pub fn deinit(self: *Self, alloc: mem.Allocator) void {
    alloc.free(self.data);
    self.* = undefined;
}

pub const ResizeError = SetError || mem.Allocator.Error;

/// Increases or decreases the bit-width of the stored values. O(n) operation.
pub fn resize(self: *Self, alloc: mem.Allocator, stride: Log2Ceil) ResizeError!void {
    var new = try Self.init(alloc, stride, self.length);
    errdefer new.deinit(alloc);

    for (0..self.length) |i| try new.set(i, self.get(i).?);

    self.deinit(alloc);
    self.* = new;
}

/// Returns `null` if index was out of bounds.
pub fn get(self: *Self, index: usize) ?u64 {
    if (index >= self.length) return null;

    const arr_idx = index / self.per_elem;
    const offset = (index - (arr_idx * self.per_elem)) * self.stride;

    return (self.data[arr_idx] >> @truncate(offset)) & self.mask;
}

pub const SetError = error{ OutOfBounds, ValueTooBig };

pub fn set(self: *Self, index: usize, value: u64) !void {
    if (index >= self.length) return error.OutOfBounds;
    if (value > self.mask) return error.ValueTooBig;

    const arr_idx = index / self.per_elem;
    const offset = (index - (arr_idx * self.per_elem)) * self.stride;

    const mask = ~(self.mask << @truncate(offset));
    self.data[arr_idx] = (self.data[arr_idx] & mask) | value << @truncate(offset);
}

pub const Iterator = struct {
    context: *Self,
    index: usize = 0,

    pub inline fn next(self: *Iterator) ?u64 {
        const value = self.context.get(self.index);
        self.index += 1;
        return value;
    }

    pub inline fn reset(self: *Iterator) void {
        self.index = 0;
    }
};

/// Returns an iterator over the values in the array
pub fn iterator(self: *Self) Iterator {
    return .{ .context = self };
}
