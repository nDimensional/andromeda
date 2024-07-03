const std = @import("std");
const c = @import("c.zig");

const domain = "xyz.ndimensional.andromeda";

const Andromeda = @This();

app: ?*c.GtkApplication = null,
window: ?*c.GtkWindow = null,
save_button: ?*c.GtkButton = null,
save_button_signal: c.gulong = 0,
open_button: ?*c.GtkButton = null,
open_button_signal: c.gulong = 0,

pub fn init(self: *Andromeda) void {
    self.app = c.gtk_application_new(domain, c.G_APPLICATION_DEFAULT_FLAGS);
    _ = self.connect(c.GtkApplication, self.app, "activate", &activate);
}

pub fn deinit(self: *Andromeda) void {
    c.g_object_unref(self.app);
}

pub fn run(self: *Andromeda) c_int {
    return c.g_application_run(@ptrCast(self.app), 0, null);
}

fn activate(self: *Andromeda, _: ?*c.GtkApplication) void {
    // const self: *Andromeda = @alignCast(@ptrCast(user_data));

    const builder = c.gtk_builder_new();
    defer c.g_object_unref(builder);

    _ = c.gtk_builder_add_from_file(builder, "/Users/joelgustafson/Projects/zig-gtk4/src/builder.ui", null);

    const window = c.gtk_builder_get_object(builder, "window");
    c.gtk_window_set_application(@ptrCast(window), self.app);
    c.gtk_widget_set_visible(@ptrCast(window), 1);

    self.window = @ptrCast(window);

    self.open_button = @ptrCast(c.gtk_builder_get_object(builder, "open"));
    self.open_button_signal = self.connect(c.GtkButton, self.open_button, "clicked", &open_file);

    self.save_button = @ptrCast(c.gtk_builder_get_object(builder, "save"));
    self.save_button_signal = self.connect(c.GtkButton, self.save_button, "clicked", &save_file);
    c.gtk_widget_set_sensitive(@ptrCast(self.save_button), 0);

    c.gtk_window_present(@ptrCast(window));
}

fn Signal(comptime T: type, callback: *const fn (self: *Andromeda, instance: ?*T) void) type {
    return struct {
        pub fn c_handler(instance: c.gpointer, user_data: c.gpointer) callconv(.C) void {
            callback(@alignCast(@ptrCast(user_data)), @alignCast(@ptrCast(instance)));
        }
    };
}

fn connect(
    self: *Andromeda,
    comptime T: type,
    instance: ?*T,
    name: [*:0]const u8,
    comptime callback: *const fn (self: *Andromeda, instance: ?*T) void,
) c.gulong {
    const signal = Signal(T, callback);
    var zero: u32 = 0;
    const flags: *c.GConnectFlags = @ptrCast(&zero);
    return c.g_signal_connect_data(instance, name, @ptrCast(&signal.c_handler), self, null, flags.*);
}

fn disconnect(comptime T: type, instance: ?*T, handler_id: c.gulong) void {
    c.g_signal_handler_disconnect(@ptrCast(instance), handler_id);
}

fn save_file(self: *Andromeda, _: ?*c.GtkButton) void {
    std.log.info("saving...", .{});
    _ = self;
}

fn open_file(self: *Andromeda, _: ?*c.GtkButton) void {
    const dialog = c.gtk_file_dialog_new();
    c.gtk_file_dialog_open(dialog, self.window, null, &open_file_callback, self);
}

fn open_file_callback(source_object: ?*c.GObject, res: ?*c.GAsyncResult, user_data: c.gpointer) callconv(.C) void {
    const dialog: ?*c.GtkFileDialog = @ptrCast(source_object);
    defer c.g_object_unref(dialog);

    const self: *Andromeda = @alignCast(@ptrCast(user_data));

    if (c.gtk_file_dialog_open_finish(dialog, res, null)) |file| {
        defer c.g_object_unref(file);

        if (c.g_file_get_path(file)) |path| {
            std.log.info("GOT PATH: {s}", .{path});
            c.gtk_widget_set_sensitive(@ptrCast(self.save_button), 1);
            c.gtk_widget_set_sensitive(@ptrCast(self.open_button), 0);
        }
    }
}
