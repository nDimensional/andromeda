const std = @import("std");
const LazyPath = std.Build.LazyPath;

const mach = @import("mach");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const exe = b.addExecutable(.{
    //     .name = "andromeda",
    //     .root_source_file = LazyPath.relative("./exe/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
        .core = true,
    });

    const exe = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "andromeda",
        .src = "exe/main.zig",
        .target = target,
        .optimize = optimize,
        .deps = &[_]std.Build.Module.Import{},
    });

    if (b.args) |args| exe.run.addArgs(args);

    const run = b.step("run", "Run the app");
    run.dependOn(&exe.run.step);

    // const sqlite = b.dependency("sqlite", .{ .SQLITE_ENABLE_RTREE = true });
    // const ultralight = b.dependency("ultralight", .{ .SDK = @as([]const u8, "SDK") });

    // const app = b.addExecutable(.{
    //     .name = "andromeda",
    //     .root_source_file = LazyPath.relative("./app/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // app.root_module.addImport("sqlite", sqlite.module("sqlite"));
    // app.root_module.addImport("ul", ultralight.module("ul"));

    // app.linkLibC();
    // b.installArtifact(app);

    // const app_artifact = b.addRunArtifact(app);
    // if (b.args) |args| {
    //     for (args) |arg| {
    //         std.log.info("WOW GOT ARG: {s}", .{arg});
    //     }
    //     app_artifact.addArgs(args);
    // }

    // const run = b.step("run", "Run the app");
    // run.dependOn(&app_artifact.step);
}
