const std = @import("std");
const crypto = std.crypto;
const math = std.math;
const meta = std.meta;
const mem = std.mem;

const util = @import("../util/lib.zig");

/// Minecraft-specific variable length numbers, similar to LEB128.
pub fn VarNum(comptime T: type) type {
    const U = meta.Int(.unsigned, @bitSizeOf(T));

    return struct {
        const Self = @This();

        pub fn read(reader: anytype) !T {
            var result: U = 0;
            var offset: u8 = 0;

            while (offset < @bitSizeOf(T)) : (offset += 7) {
                const byte = try reader.readByte();
                result |= @as(U, byte & 0x7f) << @truncate(offset);
                if (byte < 0x80) break;
            } else return error.VarIntTooBig;

            return @bitCast(result);
        }

        pub fn write(self: T, writer: anytype) !void {
            var value: U = @bitCast(self);

            while (value > 0x7f) : (value >>= 7)
                try writer.writeByte((@as(u8, @truncate(value)) & 0x7f) | 0x80);
            try writer.writeByte(@truncate(value));
        }

        pub fn size(self: T) usize {
            return if (self != 0)
                (@bitSizeOf(T) - @clz(@as(U, @bitCast(self))) + 6) / 7
            else
                1;
        }
    };
}

pub const VarInt = VarNum(i32);
pub const VarLong = VarNum(i64);

/// Strings are just VarInt-prefixed byte arrays. In theory, we should also check the number of UTF-
/// 16 codepoints, but we can get by without it.
pub const String = struct {
    pub fn read(allocator: mem.Allocator, reader: anytype) ![]u8 {
        const length = try util.cast(usize, try VarInt.read(reader));
        const self = try allocator.alloc(u8, length);
        errdefer allocator.free(self);
        try reader.readNoEof(self);
        return self;
    }

    pub fn write(self: []const u8, writer: anytype) !void {
        const length = try util.cast(i32, self.len);
        try VarInt.write(length, writer);
        return writer.writeAll(self);
    }

    pub fn size(self: []const u8) !usize {
        const length = try util.cast(i32, self.len);
        return self.len + VarInt.size(length);
    }
};

pub const Uuid = packed struct {
    raw: u128,

    pub fn initV3(data: []const u8) Uuid {
        var bytes: [16]u8 = .{};
        crypto.hash.Md5.hash(data, &bytes, .{});
        bytes[6] ^= bytes[6] & 0xf0;
        bytes[6] |= 0x30;
        return @bitCast(bytes);
    }

    pub inline fn read(reader: anytype) !Uuid {
        return @bitCast(try reader.readInt(u128, .Big));
    }

    pub inline fn write(self: Uuid, writer: anytype) !void {
        return writer.writeInt(u128, self.raw, .Big);
    }

    pub inline fn size(_: Uuid) usize {
        return @sizeOf(u128);
    }

    pub fn format(
        self: Uuid,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const table = "0123456789abcdef";
        var buf = "00000000-0000-0000-0000-000000000000".*;

        var i: usize = 0;
        for (mem.toBytes(self.raw)) |byte| {
            if (i == 8 or i == 13 or i == 18 or i == 23) i += 1;
            buf[i + 0] = table[byte >> 4];
            buf[i + 1] = table[byte & 15];
            i += 2;
        }

        return writer.writeAll(&buf);
    }
};
