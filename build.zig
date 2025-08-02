const std = @import("std");
const gobject_build = @import("gobject");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "locale_dir", b.getInstallPath(.{ .custom = "share/locale" }, ""));

    const sqlite_dep = b.dependency("sqlite", .{});
    const sqlite = sqlite_dep.module("sqlite");

    const rtree_dep = b.dependency("rtree", .{});
    const quadtree = rtree_dep.module("quadtree");

    const exe = b.addExecutable(.{
        .name = "andromeda",
        .root_source_file = b.path("./src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.root_module.addOptions("build_options", build_options);

    // exe.root_module.linkFramework("OpenGL", .{});
    exe.root_module.linkSystemLibrary("epoxy", .{});

    exe.root_module.addImport("quadtree", quadtree);
    exe.root_module.addImport("sqlite", sqlite);

    const gobject = b.dependency("gobject", .{});
    const libintl = b.dependency("libintl", .{});

    exe.root_module.addImport("glib", gobject.module("glib2"));
    exe.root_module.addImport("gobject", gobject.module("gobject2"));
    exe.root_module.addImport("gio", gobject.module("gio2"));
    exe.root_module.addImport("gdk", gobject.module("gdk4"));
    exe.root_module.addImport("gtk", gobject.module("gtk4"));
    exe.root_module.addImport("pango", gobject.module("pango1"));
    exe.root_module.addImport("libintl", libintl.module("libintl"));

    b.installArtifact(exe);

    const run_artifact = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_artifact.step);
}
