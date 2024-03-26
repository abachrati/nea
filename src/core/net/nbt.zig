const std = @import("std");

const ascii = std.ascii;
const math = std.math;
const meta = std.meta;
const mem = std.mem;
const fmt = std.fmt;

pub const Nbt = struct {
    name: ?[]const u8,
    value: Value,

    /// Parses an NBT tree
    pub fn parse(alloc: mem.Allocator, reader: anytype, is_named: bool) !*Nbt {
        const tag = meta.intToEnum(Tag, try reader.readByte()) catch return error.InvalidTag;
        const root = try alloc.create(Nbt);
        errdefer alloc.destroy(root);
        root.name = if (is_named) try parseArray(alloc, u8, u16, reader) else null;
        root.value = try parseValue(alloc, reader, tag);
        return root;
    }

    /// Recursively serializes an NBT tree to the writer
    pub fn write(self: Nbt, writer: anytype) !void {
        try writer.writeByte(@intFromEnum(self.value));
        if (self.name) |name| try writeArray(u8, u16, name, writer);
        try writeValue(self.value, writer);
    }

    /// Serializes a NBT tree to an SNBT string
    pub fn toSnbt(self: *const Nbt, writer: anytype) !void {
        try writer.print("{{\"{s}\":", .{self.name orelse ""});
        try snbtWriteValue(self.value, writer);
        try writer.writeAll("}");
    }

    pub fn format(
        self: *const Nbt,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try self.toSnbt(writer);
    }

    /// Recursively deallocates the NBT tree
    pub fn deinit(self: *Nbt, alloc: mem.Allocator) void {
        if (self.name) |name| alloc.free(name);
        self.value.deinit(alloc);
        alloc.destroy(self);
    }
};

pub const Tag = enum {
    end,
    byte,
    short,
    int,
    long,
    float,
    double,
    byte_array,
    string,
    list,
    compound,
    int_array,
    long_array,
};

pub const List = struct { tag: Tag, values: std.ArrayListUnmanaged(Value) };
pub const Compound = std.StringHashMapUnmanaged(Value);

pub const Value = union(Tag) {
    // zig fmt: off
    end:        void,
    byte:       i8,
    short:      i16,
    int:        i32,
    long:       i64,
    float:      f32,
    double:     f64,
    byte_array: []const i8,
    string:     []const u8,
    list:       List,
    compound:   Compound,
    int_array:  []const i32,
    long_array: []const i64,
    // zig fmt: on

    /// Recursively deallocates the NBT tree
    pub fn deinit(self: *Value, alloc: mem.Allocator) void {
        switch (self.*) {
            inline .byte_array, .string, .int_array, .long_array => |d| alloc.free(d),
            .list => |*d| {
                for (d.values.items) |*item| item.deinit(alloc);
                d.values.deinit(alloc);
            },
            .compound => |*d| {
                var iter = d.iterator();
                while (iter.next()) |e| {
                    alloc.free(e.key_ptr.*);
                    e.value_ptr.deinit(alloc);
                }
                d.deinit(alloc);
            },
            else => {}, // Primitive values do not need to be freed
        }
    }
};

pub const NbtBuilder = struct {
    alloc: mem.Allocator,

    nbt: *Nbt,
    stack: std.ArrayListUnmanaged(*Value),

    pub fn init(alloc: mem.Allocator) !NbtBuilder {
        return .{ .alloc = alloc, .root = try alloc.create(Nbt), .stack = .{} };
    }

    /// Deallocates builder and passes back NBT tree
    pub fn final(self: *NbtBuilder) *Nbt {
        self.stack.deinit(self.alloc);
        return self.nbt;
    }

    /// Add a value to the current scope. If the contents of `value` are a slice, they must
    /// be heap allocated. `name` must be non-null within a compound, and in a list it is ignored
    pub fn addValue(self: *NbtBuilder, name: ?[]const u8, value: Value) !*Value {
        if (self.stack.items.len == 0) {
            self.nbt.name = if (name) |n| try self.alloc.dupe(u8, n) else null;
            self.nbt.value = value;
            return &self.nbt.value;
        } else switch (self.stack.getLast().*) {
            .list => |*d| {
                try d.values.append(self.alloc, value);
                return &d.values.items[d.values.items.len - 1];
            },
            .compound => |*d| {
                try d.put(self.alloc, try self.alloc.dupe(u8, name.?), value);
                return d.getPtr(name.?).?;
            },
            else => unreachable,
        }
    }

    pub fn startCompound(self: *NbtBuilder, name: ?[]const u8) !void {
        try self.stack.append(self.alloc, try self.addValue(name, .{ .compound = Compound{} }));
    }

    pub fn endCompound(self: *NbtBuilder) void {
        if (self.stack.items.len < 1 or self.stack.pop().* != .compound)
            @panic("`endCompound()` called in invalid scope");
    }

    pub fn startList(self: *NbtBuilder, name: ?[]const u8, tag: Tag) !void {
        try self.stack.append(self.alloc, try self.addValue(name, .{
            .list = .{ .tag = tag, .values = std.ArrayListUnmanaged(Value){} },
        }));
    }

    pub fn endList(self: *NbtBuilder) void {
        if (self.stack.items.len < 1 or self.stack.pop().* != .list)
            @panic("`endList()` called in invalid scope");
    }
};

fn ParseError(comptime Reader: type) type {
    return mem.Allocator.Error || Reader.Error || error{InvalidTag};
}

fn parseArray(
    alloc: mem.Allocator,
    comptime V: type,
    comptime L: type,
    reader: anytype,
) ![]const V {
    const length: usize = @max(try reader.readInt(L, .big), 0);
    const data = try alloc.alloc(V, length);
    try reader.readNoEof(mem.sliceAsBytes(data));
    // The data that was just read was big-endian, not native-endian
    if (@sizeOf(V) > 1) {
        for (data, 0..) |d, i| data[i] = mem.bigToNative(V, d);
    }
    return data;
}

fn parseList(alloc: mem.Allocator, reader: anytype) !List {
    const tag = meta.intToEnum(Tag, try reader.readByte()) catch return error.InvalidTag;
    const length = @max(try reader.readInt(i32, .big), 0);
    if (tag == .end and length > 0) return error.InvalidTag;
    var values = try std.ArrayListUnmanaged(Value).initCapacity(alloc, length);
    for (0..length) |_| try values.append(alloc, try parseValue(alloc, reader, tag));
    return .{ .tag = tag, .values = values };
}

fn parseCompound(alloc: mem.Allocator, reader: anytype) !Compound {
    var compound = Compound{};
    while (true) {
        const tag = meta.intToEnum(Tag, try reader.readByte()) catch return error.InvalidTag;
        if (tag == .end) break;
        try compound.put(
            alloc,
            try parseArray(alloc, u8, u16, reader),
            try parseValue(alloc, reader, tag),
        );
    }
    return compound;
}

/// Recursively parses a value of the given tag. Returned value should be `deinit`-ed
fn parseValue(alloc: mem.Allocator, reader: anytype, tag: Tag) ParseError(@TypeOf(reader))!Value {
    return switch (tag) {
        // zig fmt: off
        .end        => .end,
        .byte       => .{ .byte       = try reader.readByteSigned() },
        .short      => .{ .short      = try reader.readInt(i16, .big) },
        .int        => .{ .int        = try reader.readInt(i32, .big) },
        .long       => .{ .long       = try reader.readInt(i64, .big) },
        .float      => .{ .float      = @as(f32, @bitCast(try reader.readInt(u32, .big))) },
        .double     => .{ .double     = @as(f64, @bitCast(try reader.readInt(u64, .big))) },
        .byte_array => .{ .byte_array = try parseArray(alloc,  i8, i32, reader) },
        .string     => .{ .string     = try parseArray(alloc,  u8, u16, reader) },
        .list       => .{ .list       = try parseList(alloc, reader) },
        .compound   => .{ .compound   = try parseCompound(alloc, reader) },
        .int_array  => .{ .int_array  = try parseArray(alloc, i32, i32, reader) },
        .long_array => .{ .long_array = try parseArray(alloc, i64, i32, reader) },
        // zig fmt: on
    };
}

fn WriteError(comptime Writer: type) type {
    return Writer.Error || error{InvalidLength};
}

fn writeArray(comptime V: type, comptime L: type, array: []const V, writer: anytype) !void {
    const length = math.cast(L, array.len) orelse return error.InvalidLength;
    try writer.writeInt(L, length, .big);
    if (@sizeOf(V) == 1)
        try writer.writeAll(mem.sliceAsBytes(array))
    else for (array) |d|
        try writer.writeAll(mem.asBytes(&d));
}

fn writeList(list: List, writer: anytype) !void {
    try writer.writeByte(@intFromEnum(list.tag));
    try writer.writeInt(i32, @intCast(list.values.items.len), .big);
    for (list.values.items) |i| try writeValue(i, writer);
}

fn writeCompound(compound: Compound, writer: anytype) !void {
    var iter = compound.iterator();
    while (iter.next()) |e| {
        try writer.writeByte(@intFromEnum(e.value_ptr.*));
        try writeArray(u8, u16, e.key_ptr.*, writer);
        try writeValue(e.value_ptr.*, writer);
    }
    try writer.writeByte(@intFromEnum(Tag.end));
}

/// Recursively serializes a value to the writer
fn writeValue(value: Value, writer: anytype) WriteError(@TypeOf(writer))!void {
    switch (value) {
        // zig fmt: off
        .end        => {},
        .byte       => |d| try writer.writeByte(@bitCast(d)),
        .short      => |d| try writer.writeInt(i16, d, .big),
        .int        => |d| try writer.writeInt(i32, d, .big),
        .long       => |d| try writer.writeInt(i64, d, .big),
        .float      => |d| try writer.writeInt(u32, @bitCast(d), .big),
        .double     => |d| try writer.writeInt(u64, @bitCast(d), .big),
        .byte_array => |d| try writeArray(i8, i32, d, writer),
        .string     => |d| try writeArray(u8, u16, d, writer),
        .list       => |d| try writeList(d, writer),
        .compound   => |d| try writeCompound(d, writer),
        .int_array  => |d| try writeArray(i32, i32, d, writer),
        .long_array => |d| try writeArray(i64, i32, d, writer),
        // zig fmt: on
    }
}

fn snbtWriteArray(
    comptime V: type,
    comptime prefix: []const u8,
    array: []const V,
    writer: anytype,
) !void {
    if (array.len == 0) try writer.writeAll("[" ++ prefix ++ "]") else {
        try writer.writeAll("[" ++ prefix);
        for (array[0 .. array.len - 1]) |d| try writer.print("{d},", .{d});
        try writer.print("{d}", .{array[array.len - 1]});
        try writer.writeAll("]");
    }
}

fn snbtWriteList(list: List, writer: anytype) !void {
    const array = list.values.items;
    if (array.len == 0) try writer.writeAll("[]") else {
        try writer.writeAll("[");
        for (array[0 .. array.len - 1]) |d| {
            try snbtWriteValue(d, writer);
            try writer.writeAll(",");
        }
        try snbtWriteValue(array[array.len - 1], writer);
        try writer.writeAll("]");
    }
}

fn snbtWriteCompound(compound: Compound, writer: anytype) !void {
    if (compound.size == 0) try writer.writeAll("{}") else {
        try writer.writeAll("{");
        var iter = compound.iterator();
        for (0..compound.size - 1) |_| {
            const e = iter.next().?;
            try writer.print("\"{s}\":", .{e.key_ptr.*});
            try snbtWriteValue(e.value_ptr.*, writer);
            try writer.writeAll(",");
        }
        const e = iter.next().?;
        try writer.print("\"{s}\":", .{e.key_ptr.*});
        try snbtWriteValue(e.value_ptr.*, writer);
        try writer.writeAll("}");
    }
}

fn snbtWriteValue(value: Value, writer: anytype) @TypeOf(writer).Error!void {
    switch (value) {
        // zig fmt: off
        .end        => {},
        .byte       => |d| try writer.print("{d}", .{d}),
        .short      => |d| try writer.print("{d}", .{d}),
        .int        => |d| try writer.print("{d}", .{d}),
        .long       => |d| try writer.print("{d}", .{d}),
        .float      => |d| try writer.print("{d}", .{d}),
        .double     => |d| try writer.print("{d}", .{d}),
        .byte_array => |d| try snbtWriteArray(i8, "B;", d, writer),
        .string     => |d| try writer.print("\"{s}\"", .{d}),
        .list       => |d| try snbtWriteList(d, writer),
        .compound   => |d| try snbtWriteCompound(d, writer),
        .int_array  => |d| try snbtWriteArray(i32, "I;", d, writer),
        .long_array => |d| try snbtWriteArray(i64, "I;", d, writer),
        // zig fmt: on
    }
}
