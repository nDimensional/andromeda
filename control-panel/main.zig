const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const nng = @import("nng");

const build_options = @import("build_options");

const ApplicationWindow = @import("ApplicationWindow.zig").ApplicationWindow;

const application_id = "xyz.ndimensional.andromeda";
pub fn main() void {
    nng.setLogger(.SYSTEM);

    const app = gtk.Application.new(application_id, .{});
    defer app.unref();

    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    const window = ApplicationWindow.new(app);
    window.as(gtk.Window).present();
}
