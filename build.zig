const std = @import("std");
const mach = @import("mach");
const gobject_build = @import("gobject");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "locale_dir", b.getInstallPath(.{ .custom = "share/locale" }, ""));
    build_options.addOption([]const u8, "socket_path", b.getInstallPath(.{ .custom = "socket" }, ""));
    build_options.addOption([]const u8, "atlas_path", b.getInstallPath(.{ .bin = {} }, "andromeda-atlas"));

    const sqlite_dep = b.dependency("sqlite", .{ .SQLITE_ENABLE_RTREE = true });
    const sqlite = sqlite_dep.module("sqlite");

    const nng_dep = b.dependency("nng", .{});
    const nng = nng_dep.module("nng");

    const shm = b.createModule(.{
        .root_source_file = b.path("shm/lib.zig"),
    });

    const shared_object = b.createModule(.{
        .root_source_file = b.path("shared-object/lib.zig"),
        .imports = &.{.{ .name = "shm", .module = shm }},
    });

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
        .deps = &.{
            .{ .name = "sqlite", .module = sqlite },
            .{ .name = "shared-object", .module = shared_object },
            .{ .name = "nng", .module = nng },
        },
    });

    atlas.module.addOptions("build_options", build_options);

    if (b.args) |args| atlas.run.addArgs(args);

    const run_atlas = b.step("run-atlas", "Run the atlas");
    run_atlas.dependOn(&atlas.run.step);

    b.getInstallStep().dependOn(&atlas.install.step);

    {
        const control_panel = b.addExecutable(.{
            .name = "andromeda-control-panel",
            .root_source_file = b.path("./control-panel/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        control_panel.linkLibC();
        control_panel.root_module.addOptions("build_options", build_options);

        control_panel.root_module.addImport("sqlite", sqlite);
        control_panel.root_module.addImport("shared-object", shared_object);
        control_panel.root_module.addImport("nng", nng);

        const gobject = b.dependency("gobject", .{});
        const libintl = b.dependency("libintl", .{});

        control_panel.root_module.addImport("glib", gobject.module("glib2"));
        control_panel.root_module.addImport("gobject", gobject.module("gobject2"));
        control_panel.root_module.addImport("gio", gobject.module("gio2"));
        control_panel.root_module.addImport("gdk", gobject.module("gdk4"));
        control_panel.root_module.addImport("gtk", gobject.module("gtk4"));
        control_panel.root_module.addImport("libintl", libintl.module("libintl"));

        b.installArtifact(control_panel);

        const control_panel_artifact = b.addRunArtifact(control_panel);
        control_panel_artifact.step.dependOn(&atlas.install.step);

        const run_control_panel = b.step("run", "Run the control panel");
        run_control_panel.dependOn(&control_panel_artifact.step);
    }
}
