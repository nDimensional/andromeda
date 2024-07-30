const glib = @import("glib");
const gtk = @import("gtk");

const Progress = @This();

progress_bar: ?*gtk.ProgressBar = null,
text: ?[*:0]const u8 = null,
value: f64 = 0,

pub fn setValue(self: *Progress, value: f64) void {
    self.value = value;
    _ = glib.idleAdd(&setValueCallback, self);
}

fn setValueCallback(data: ?*anyopaque) callconv(.C) c_int {
    const self: *Progress = @alignCast(@ptrCast(data));
    if (self.progress_bar) |progress_bar| {
        progress_bar.setFraction(self.value);
    }

    return 0;
}

pub fn setText(self: *Progress, text: [*:0]const u8) void {
    self.text = text;
    self.value = 0;
    _ = glib.idleAdd(&Progress.setTextCallback, self);
}

fn setTextCallback(data: ?*anyopaque) callconv(.C) c_int {
    const self: *Progress = @alignCast(@ptrCast(data));
    if (self.progress_bar) |progress_bar| {
        progress_bar.setShowText(1);
        progress_bar.setText(self.text);
        progress_bar.setFraction(self.value);
    }

    return 0;
}
