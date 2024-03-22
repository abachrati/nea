const std = @import("std");
const meta = std.meta;
const hash = std.hash;

pub fn VarNum(comptime T: type) type {
    const U = meta.Int(.unsigned, @bitSizeOf(T));

    return packed struct {
        const Self = @This();

        pub fn read(reader: anytype) !T {
            var result: U = 0;
            var offset: u8 = 0;

            while (offset < @bitSizeOf(T)) : (offset += 7) {
                const byte = try reader.readByte();
                result |= @as(U, byte & 0x7f) << @truncate(offset);
                if (byte < 0x80) break;
            } else {
                return error.VarIntTooBig;
            }

            return @bitCast(result);
        }

        pub fn write(self: T, writer: anytype) !void {
            var value: U = @bitCast(self);

            while (value > 0x7f) : (value >>= 7) {
                try writer.writeByte((@as(u8, @truncate(value)) & 0x7f) | 0x80);
            }

            try writer.writeByte(@truncate(value));
        }

        pub fn size(self: T) !usize {
            return if (self == 0) 1 else blk: {
                break :blk (@bitSizeOf(T) - @clz(@as(U, @bitCast(self))) + 6) / 7;
            };
        }
    };
}

pub const Uuid = packed struct {
    raw: u128,

    pub fn initV3(data: []const u8) Uuid {
        var bytes: [16]u8 = .{};
        hash.Md5.hash(data, &bytes, .{});
        bytes[6] ^= bytes[6] & 0xf0;
        bytes[6] |= 0x30;
        return @bitCast(bytes);
    }

    pub inline fn read(reader: anytype) Uuid {
        return @bitCast(try reader.readInt(u128, .big));
    }

    pub inline fn write(self: Uuid, writer: anytype) !void {
        return writer.writeInt(u128, self.raw, .big);
    }

    pub inline fn size(_: Uuid) !usize {
        return @sizeOf(u128);
    }
};
