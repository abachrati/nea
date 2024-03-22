pub fn read(comptime T: type, allocator: mem.Allocator, reader: anytype) !T {
    switch (@typeInfo(T)) {
        .Int => return reader.readInt(T, .big),
        .Bool => return reader.readByte() != 0,
        .Float => {
            const U = meta.Int(.unsigned, @bitSizeOf(T));
            return @bitCast(reader.readInt(U, .big));
        },

        .Optional => |opt| {
            if (try read(bool, allocator, reader)) {
                return read(opt.child, allocator, reader);
            }
            return null;
        },

        .Struct => {},

        .Union, .Opaque => {},

        else => {},
    }

    @compileError("Unsupported type `" ++ @typeName(T) ++ "`");
}

pub fn write(comptime T: type, value: T, writer: anytype) !void {
    switch (@typeInfo(T)) {
        .Int => return writer.writeInt(T, value, .big),
        .Bool => return writer.writeByte(@intFromBool(value)),
        .Float => {
            const U = meta.Int(.unsigned, @bitSizeOf(T));
            return writer.writeInt(U, @as(U, @bitCast(T)), .big);
        },

        .Optional => |opt| {
            try writer.writeInt(@intFromBool(value != null));
            return if (value) |val| write(opt.child, val);
        },

        .Struct => |str| {
            return if (@hasDecl(T, "write"))
                value.write(writer)
            else inline for (str.fields) |field| {
                try write(field.type, @field(value, field.name));
            };
        },

        .Union, .Opaque => if (@hasDecl(T, "write")) {
            return value.write(writer);
        },

        else => {},
    }

    @compileError("Unsupported type `" ++ @typeName(T) ++ "`");
}

pub fn size(comptime T: type, value: T) !usize {
    switch (@typeInfo(T)) {
        .Int, .Bool, .Float => return @sizeOf(T),
        .Optional => |opt| return @sizeOf(bool) + if (value) |val| size(opt.child, val) else 0,

        .Struct => |str| {
            if (@hasDecl(T, "size")) {
                return value.size();
            } else {
                var a = 0;

                inline for (str.fields) |field| {
                    a += size(field.type, @field(value, field.name));
                }

                return a;
            }
        },

        .Union, .Opaque => if (@hasDecl(T, "size")) {
            return value.size();
        },

        else => {},
    }

    @compileError("Unsupported type `" ++ @typeName(T) ++ "`");
}

pub fn format(
    self: Uuid,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    const table = "0123456789abcdef";
    const buf = "00000000-0000-0000-0000-000000000000".*;

    var i = 0;
    for (mem.toBytes(self.raw)) |byte| {
        if (i == 8 or i == 13 or i == 18 or i == 23) i += 1;
        buf[i + 0] = table[byte >> 4];
        buf[i + 1] = table[byte & 15];
    }

    return writer.writeAll(buf);
}
