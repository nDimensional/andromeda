const std = @import("std");
const mach = @import("mach");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite = b.dependency("sqlite", .{ .SQLITE_ENABLE_RTREE = true });

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
        .core = true,
    });

    const atlas = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "andromeda-atlas",
        .src = "atlas/App.zig",
        .target = target,
        .optimize = optimize,
        .deps = &.{.{ .name = "sqlite", .module = sqlite.module("sqlite") }},
    });


    if (b.args) |args| atlas.run.addArgs(args);

    const run_atlas = b.step("run-atlas", "Run the atlas");
    run_atlas.dependOn(&atlas.run.step);

    const control_panel = b.addExecutable(.{
        .name = "andromeda",
        .root_source_file = b.path("./src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    control_panel.linkSystemLibrary("gtk4");
    b.installArtifact(control_panel);

    const control_panel_artifact = b.addRunArtifact(control_panel);
    const runcontrol_panel = b.step("run", "Run the control panel");
    runcontrol_panel.dependOn(&control_panel_artifact.step);
}
