const std = @import("std");
const meta = std.meta;
const mem = std.mem;

const Build = std.Build;

const source = "src/";

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "basalt",
        .root_source_file = .{ .path = source ++ "main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Build and run basalt");
    // Build the binary and add execution to the run step.
    {
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args|
            run_cmd.addArgs(args);

        run_step.dependOn(&run_cmd.step);
    }

    const test_step = b.step("test", "Run tests in all source files");
    // Recursively walk `source` directory and add all `.zig` files to the test step.
    {
        // var dir = try std.fs.cwd().openDir(source, .{ .iterate = true }); // 0.12.0
        var dir = try std.fs.cwd().openIterableDir(source, .{}); // 0.11.0
        defer dir.close();

        var walk = try dir.walk(b.allocator);
        defer walk.deinit();

        while (try walk.next()) |file| if (mem.endsWith(u8, file.path, ".zig")) {
            const unit = b.addTest(.{
                .root_source_file = .{ .path = b.fmt(source ++ "{s}", .{file.path}) },
            });
            const unit_cmd = b.addRunArtifact(unit);
            test_step.dependOn(&unit_cmd.step);
        };
    }
}
