const std = @import("std");

const mem = std.mem;

const src = "src/";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "basalt",
        .root_source_file = .{ .path = src ++ "main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Build and run basalt");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests in all source files");

    var dir = try std.fs.cwd().openDir(src, .{ .iterate = true });
    defer dir.close();

    var walk = try dir.walk(b.allocator);
    defer walk.deinit();

    // Recursively walk the `src/` directory and add all `.zig` files to the test step
    while (try walk.next()) |file| if (mem.endsWith(u8, file.path, ".zig")) {
        const unit = b.addTest(.{
            .root_source_file = .{ .path = b.fmt(src ++ "{s}", .{file.path}) },
        });
        const unit_cmd = b.addRunArtifact(unit);
        test_step.dependOn(&unit_cmd.step);
    };
}
