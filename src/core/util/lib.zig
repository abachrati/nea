//! Random helper functions/structs.

const std = @import("std");
const base64 = std.base64;
const math = std.math;
const mem = std.mem;
const fs = std.fs;

pub const Bitfield = @import("Bitfield.zig");

/// Returns the slice, or `null` if it is empty. Meant to be used with `orelse`
pub inline fn maybeEmpty(slice: anytype) ?@TypeOf(slice) {
    return if (slice.len == 0) null else slice;
}

/// Attempts to cast `x` into `T`, returning `error.Overflow` if value does not fit.
pub inline fn cast(comptime T: type, x: anytype) error{Overflow}!T {
    return math.cast(T, x) orelse error.Overflow;
}

pub const favicon_path = "favicon.png";

/// Load the `png` file at `path`, and encode as base64 + mimetype (meant for favicon).
pub fn loadFavicon(allocator: mem.Allocator, path: []const u8) ![]const u8 {
    const mime = "data:image/png;base64,";

    if (!mem.eql(u8, path[path.len - 3 ..], "png"))
        return error.UnknownFile;

    var file = try fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 1 << 13); // Up to 8KiB file
    defer allocator.free(data);

    const Encoder = base64.standard.Encoder;
    const encoded = try allocator.alloc(u8, Encoder.calcSize(data.len) + mime.len);
    @memcpy(encoded[0..mime.len], mime);
    _ = Encoder.encode(encoded[mime.len..], data);
    return encoded;
}
