const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite = b.dependency("sqlite", .{ .SQLITE_ENABLE_RTREE = true });
    const ultralight = b.dependency("ultralight", .{ .SDK = @as([]const u8, "SDK") });

    const app = b.addExecutable(.{
        .name = "andromeda",
        .root_source_file = LazyPath.relative("./app/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    app.root_module.addImport("sqlite", sqlite.module("sqlite"));
    app.root_module.addImport("ul", ultralight.module("ul"));

    app.linkLibC();
    b.installArtifact(app);

    const app_artifact = b.addRunArtifact(app);
    if (b.args) |args| {
        for (args) |arg| {
            std.log.info("WOW GOT ARG: {s}", .{arg});
        }
        app_artifact.addArgs(args);
    }

    const run = b.step("run", "Run the app");
    run.dependOn(&app_artifact.step);
}
