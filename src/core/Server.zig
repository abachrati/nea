const std = @import("std");

const sync = @import("sync/lib.zig");

pool: sync.Pool,

const Server = @This();

pub fn init() Server {}
pub fn deinit(self: *Server) void {
    _ = self; // autofix
}
