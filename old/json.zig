const std = @import("std");
const ascii = std.ascii;
const heap = std.heap;
const fmt = std.fmt;
const mem = std.mem;

pub const Type = enum {
    object,
    array,
    string,
    integer,
    boolean,
    null,
};

pub const Token = struct {
    length: usize = 1,
    parent: ?usize = null,
    children: usize = 0,

    value: Value,

    pub const Value = union(Type) {
        object,
        array,
        string: String, // slice with buffer[pos..][0..len]
        integer: i64,
        boolean: bool,
        null,
    };

    const String = struct {
        pos: usize,
        len: usize,
    };
};

pub const Parser = struct {
    current: usize = 0,
    parent: ?usize = null,

    pos: usize = 0,

    pub const Error = error{
        /// Bad token, JSON is corrupt or invalid
        InvalidJson,
        /// Expected more JSON data
        MissingJson,
        /// Not enough tokens for the given JSON
        OutOfTokens,
    };

    pub fn parse(self: *Parser, buffer: []const u8, tokens: ?[]Token) Error!usize {
        while (self.pos < buffer.len) : (self.pos += 1) {
            switch (buffer[self.pos]) {
                // zig fmt: off
                '{', '['              => |char| try self.openObject(tokens, char),
                '}', ']'              => |char| try self.closeObject(tokens, char),
                ','                   =>        try self.nextElement(tokens),
                '"', '\''             => |char| try self.parseString(buffer, tokens, char),
                '-', '0'...'9'        =>        try self.parseNumber(buffer, tokens),
                't', 'f', 'n'         =>        try self.parsePrimitive(buffer, tokens),

                ':'                   => self.parent = self.current - 1,
                '\t', '\r', '\n', ' ' => continue,

                else                  => return error.InvalidJson,
                // zig fmt: on
            }
        }

        if (self.parent != null) {
            return error.MissingJson;
        }

        return self.current;
    }

    fn openObject(self: *Parser, tokens: ?[]Token, char: u8) Error!void {
        if (tokens != null) {
            const kind: Token.Value = if (char == '{') .object else .array;

            if (self.parent != null and tokens.?[self.parent.?].value == .object) {
                return error.InvalidJson; // Objects and arrays cannot be keys
            }

            try self.addToken(tokens.?, .{
                .parent = self.parent,
                .value = kind,
            });
        }

        self.parent = self.current - 1;
    }

    fn closeObject(self: *Parser, tokens: ?[]Token, char: u8) Error!void {
        if (self.parent != null and tokens != null) {
            const kind: Type = if (char == '}') .object else .array;

            var parent = self.parent.?;

            while (true) {
                const token = &tokens.?[parent];

                if (token.value == kind) {
                    token.length = self.current - parent;
                    self.parent = token.parent;
                    break;
                }

                if (token.parent == null) {
                    break;
                }

                parent = token.parent.?;
            }
        }
    }

    fn nextElement(self: *Parser, tokens: ?[]Token) Error!void {
        if (self.parent != null and tokens != null) {
            const parent = tokens.?[self.parent.?];

            if (parent.value != .object and parent.value != .array) {
                self.parent = parent.parent;
            }
        }
    }

    fn parseString(self: *Parser, buffer: []const u8, tokens: ?[]Token, char: u8) Error!void {
        try self.addToken(tokens, .{
            .parent = self.parent,
            .value = .{
                .string = try self.parseQuoted(buffer, char),
            },
        });
    }

    fn parseNumber(self: *Parser, buffer: []const u8, tokens: ?[]Token) Error!void {
        const str = try self.parseUnquoted(buffer);

        try self.addToken(tokens, .{
            .parent = self.parent,
            .value = .{
                .integer = fmt.parseInt(i64, buffer[str.pos..][0..str.len], 0) catch {
                    return error.InvalidJson;
                },
            },
        });
    }

    fn parsePrimitive(self: *Parser, buffer: []const u8, tokens: ?[]Token) Error!void {
        const map = std.ComptimeStringMap(Token.Value, .{
            .{ "null", .{ .null = {} } },
            .{ "true", .{ .boolean = true } },
            .{ "false", .{ .boolean = false } },
        });

        const str = try self.parseUnquoted(buffer);

        return self.addToken(tokens, .{
            .parent = self.parent,
            .value = map.get(buffer[str.pos..][0..str.len]) orelse {
                return error.InvalidJson;
            },
        });
    }

    fn parseUnquoted(self: *Parser, buffer: []const u8) Error!Token.String {
        const start = self.pos;
        errdefer self.pos = start;

        self.pos += 1;

        while (self.pos < buffer.len) : (self.pos += 1) {
            switch (buffer[self.pos]) {
                '\t', '\r', '\n', ' ', ':', ',', ']', '}' => break,
                else => continue,
            }
        }

        defer self.pos -= 1;
        return .{
            .pos = start,
            .len = self.pos - start,
        };
    }

    fn parseQuoted(self: *Parser, buffer: []const u8, char: u8) Error!Token.String {
        var start = self.pos;
        errdefer self.pos = start;

        self.pos += 1;

        while (self.pos < buffer.len) : (self.pos += 1) {
            if (buffer[self.pos] == char) {
                break;
            }

            if (buffer[self.pos] == '\\') {
                self.pos += 1;

                if (self.pos >= buffer.len) {
                    return error.MissingJson;
                }

                switch (buffer[self.pos]) {
                    '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => continue,
                    'u' => {
                        self.pos += 4;

                        if (self.pos >= buffer.len) {
                            return error.MissingJson;
                        }

                        for (buffer[self.pos - 4 ..][0..4]) |c| {
                            if (!ascii.isHex(c)) {
                                return error.InvalidJson;
                            }
                        }
                    },
                    else => return error.InvalidJson,
                }
            }
        } else {
            return error.MissingJson;
        }

        start += 1;

        return .{
            .pos = start,
            .len = self.pos - start,
        };
    }

    fn addToken(self: *Parser, tokens: ?[]Token, token: Token) Error!void {
        if (tokens) |toks| {
            if (self.current >= toks.len) {
                return error.OutOfTokens;
            }

            toks[self.current] = token;

            if (token.parent) |parent| {
                toks[parent].children += 1;
            }
        }

        self.current += 1;
    }
};

// pub fn Parsed(comptime T: type) type {
//     return struct {
//         arena: heap.ArenaAllocator,
//         inner: T,

//         const Self = @This();

//         pub fn deinit(self: *Self) void {
//             self.arena.deinit();
//             self.* = undefined;
//         }
//     };
// }

// pub fn parse(comptime T: type, allocator: mem.Allocator, buffer: []const u8) !Parsed(T) {}
