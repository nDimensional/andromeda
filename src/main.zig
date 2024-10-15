const builtin = @import("builtin");
const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");

const build_options = @import("build_options");

const ApplicationWindow = @import("ApplicationWindow.zig").ApplicationWindow;

const application_id = "xyz.ndimensional.andromeda";
pub fn main() void {
    const app = gtk.Application.new(application_id, .{});
    defer app.unref();

    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &handleApplicationActivate, null, .{});

    if (builtin.os.tag.isDarwin()) {
        setAccelsForAction(app, "win.open", "<Meta>o");
        setAccelsForAction(app, "win.save", "<Meta>s");
        setAccelsForAction(app, "win.randomize", "<Meta>r");
        setAccelsForAction(app, "window.close", "<Meta>w");
    } else {
        setAccelsForAction(app, "win.open", "<Control>o");
        setAccelsForAction(app, "win.save", "<Control>s");
        setAccelsForAction(app, "win.randomize", "<Control>r");
        setAccelsForAction(app, "window.close", "<Control>w");
    }

    setAccelsForAction(app, "win.start", "space");
    setAccelsForAction(app, "win.stop", "space");

    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

fn setAccelsForAction(app: *gtk.Application, action: [*:0]const u8, accel: [*:0]const u8) void {
    const accels: []const ?[*:0]const u8 = &.{ accel, null };
    app.setAccelsForAction(action, @ptrCast(accels.ptr));
}

fn handleApplicationActivate(app: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    const window = ApplicationWindow.new(app);
    window.as(gtk.Window).present();
}
