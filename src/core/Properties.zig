const std = @import("std");
const builtin = std.builtin;
const ascii = std.ascii;
const heap = std.heap;
const meta = std.meta;
const fmt = std.fmt;
const mem = std.mem;
const fs = std.fs;

const max_line = 1024;

arena: heap.ArenaAllocator,

// zig fmt: off
@"enable-jmx-monitoring":             bool       = false,
@"rcon.port":                         u16        = 25575,
@"level-seed":                        []const u8 = "",
gamemode:                             []const u8 = "survival",
@"enable-command-block":              bool       = false,
@"enable-query":                      bool       = false,
@"generator-settings":                []const u8 = "{}",
@"enforce-secure-profile":            bool       = true,
@"level-name":                        []const u8 = "world",
motd:                                 []const u8 = "A Minecraft Server",
@"query.port":                        u16        = 25565,
pvp:                                  bool       = true,
@"generate-structures":               bool       = true,
@"max-chained-neighbor-updates":      u32        = 1000000,
difficulty:                           []const u8 = "easy",
@"network-compression-threshold":     u32        = 256,
@"max-tick-time":                     u64        = 60000,
@"require-resource-pack":             bool       = false,
@"use-native-transport":              bool       = true,
@"max-players":                       u32        = 20,
@"online-mode":                       bool       = true,
@"enable-status":                     bool       = true,
@"allow-flight":                      bool       = false,
@"initial-disabled-packs":            []const u8 = "",
@"broadcast-rcon-to-ops":             bool       = true,
@"view-distance":                     u32        = 10,
@"server-ip":                         []const u8 = "",
@"resource-pack-prompt":              []const u8 = "",
@"allow-nether":                      bool       = true,
@"server-port":                       u16        = 25565,
@"enable-rcon":                       bool       = false,
@"sync-chunk-writes":                 bool       = true,
@"op-permission-level":               u32        = 4,
@"prevent-proxy-connections":         bool       = false,
@"hide-online-players":               bool       = false,
@"resource-pack":                     []const u8 = "",
@"entity-broadcast-range-percentage": u32        = 100,
@"simulation-distance":               u32        = 10,
@"rcon.password":                     []const u8 = "",
@"player-idle-timeout":               u32        = 0,
debug:                                bool       = false,
@"force-gamemode":                    bool       = false,
@"rate-limit":                        u32        = 0,
hardcore:                             bool       = false,
@"white-list":                        bool       = false,
@"broadcast-console-to-ops":          bool       = true,
@"spawn-npcs":                        bool       = true,
@"spawn-animals":                     bool       = true,
@"log-ips":                           bool       = true,
@"function-permission-level":         u32        = 2,
@"initial-enabled-packs":             []const u8 = "vanilla",
@"level-type":                        []const u8 = "minecraft\\:normal",
@"text-filtering-config":             []const u8 = "",
@"spawn-monsters":                    bool       = true,
@"enforce-whitelist":                 bool       = false,
@"spawn-protection":                  u32        = 16,
@"resource-pack-sha1":                []const u8 = "",
@"max-world-size":                    u32        = 29999984,
// zig fmt: on

const Properties = @This();

/// Read properties from the file at `path`, using default values if not provided. Writes
/// properties back to the file once parsed.
pub fn load(allocator: mem.Allocator, path: []const u8) !*Properties {
    const self = try allocator.create(Properties);
    errdefer allocator.destroy(self);

    self.* = .{ .arena = heap.ArenaAllocator.init(allocator) };
    errdefer self.arena.deinit();

    if (fs.cwd().openFile(path, .{})) |file| {
        defer file.close();

        var arena = heap.ArenaAllocator.init(allocator);
        var map = std.StringHashMap([]const u8).init(allocator);
        defer arena.deinit();
        defer map.deinit();

        try parseKV(&arena, &map, file.reader());

        // Skip the first field, which is `Properties.arena`
        inline for (meta.fields(Properties)[1..]) |field| {
            if (map.get(field.name)) |value| {
                @field(self, field.name) =
                    parseValue(field.type, self.arena.allocator(), value) catch break;
            }
        }
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    try self.save(path);

    return self;
}

/// Write the options in self to a file at `path`.
pub fn save(self: *Properties, path: []const u8) !void {
    var file = try fs.cwd().createFile(path, .{});
    defer file.close();

    const writer = file.writer();

    try writer.writeAll(
        \\#Minecraft server properties
        \\
    );

    // Skip the first field, which is `Properties.arena`
    inline for (meta.fields(Properties)[1..]) |field| {
        const format = switch (field.type) {
            []const u8 => "s",
            else => "any",
        };

        try writer.print("{s}={" ++ format ++ "}\n", .{
            field.name,
            @field(self, field.name),
        });
    }
}

pub fn deinit(self: *Properties) void {
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self);
}

/// Parse a simple `key = value` list into a hashmap.
fn parseKV(
    arena: *heap.ArenaAllocator,
    out: *std.StringHashMap([]const u8),
    reader: anytype,
) !void {
    while (try reader.readUntilDelimiterOrEofAlloc(arena.allocator(), '\n', max_line)) |raw| {
        const line = mem.trimLeft(u8, raw, &ascii.whitespace);

        if (line.len == 0 or line[0] == '#')
            continue;

        if (mem.indexOfScalar(u8, line, '=')) |idx| {
            const key = mem.trimRight(u8, line[0..idx], &ascii.whitespace);
            const value = mem.trim(u8, line[idx + 1 ..], &ascii.whitespace);
            try out.put(key, value);
        }
    }
}

/// Attempt to parse the contents of `buf` into a supported type.
fn parseValue(comptime T: type, allocator: mem.Allocator, buf: []const u8) !T {
    return switch (T) {
        []const u8 => allocator.dupe(u8, buf),
        else => switch (@typeInfo(T)) {
            .Bool => parseBool(buf),
            .Int => fmt.parseInt(T, buf, 0),
            .Float => fmt.parseFloat(T, buf),
            else => @compileError("Unsupported type " ++ @typeName(T)),
        },
    };
}

inline fn parseBool(buf: []const u8) error{InvalidInput}!bool {
    if (buf.len == 5 and mem.eql(u8, buf, "false"))
        return false;
    if (buf.len == 4 and mem.eql(u8, buf, "true"))
        return true;
    return error.InvalidInput;
}
