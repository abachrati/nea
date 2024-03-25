//! Random helper functions/structs.

const std = @import("std");
const math = std.math;

/// Returns the slice, or `null` if it is empty. Meant to be used with `orelse`
pub inline fn maybeEmpty(slice: anytype) ?@TypeOf(slice) {
    return if (slice.len == 0) null else slice;
}

/// Attempts to cast `x` into `T`, returning `error.Overflow` if value does not fit.
pub inline fn cast(comptime T: type, x: anytype) error{Overflow}!T {
    return math.cast(T, x) orelse error.Overflow;
}
