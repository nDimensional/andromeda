const std = @import("std");

const Listener = @This();

fd: std.os.fd_t,
kq: std.os.fd_t,
changes: [1]std.os.Kevent,

pub fn init(path: [*:0]const u8) Listener {
    const fd = std.os.darwin.open(path, std.os.darwin.O.RDONLY);
    const kq = std.os.darwin.kqueue();

    return .{
        .fd = fd,
        .kq = kq,
        .changes = .{.{
            .ident = @intCast(fd),
            .filter = std.os.darwin.EVFILT_VNODE,
            .flags = std.os.darwin.EV_ADD | std.os.darwin.EV_ENABLE | std.os.darwin.EV_CLEAR,
            .fflags = std.os.darwin.NOTE_WRITE,
            .data = 0,
            .udata = 0,
        }},
    };
}

pub fn deinit(self: Listener) void {
    std.os.close(self.fd);
    std.os.close(self.kq);
}

pub fn poll(self: Listener) !?std.os.Kevent {
    var events: [1]std.os.Kevent = undefined;

    const nev = std.os.darwin.kevent(
        self.kq,
        &self.changes,
        self.changes.len,
        &events,
        events.len,
        &.{ .tv_sec = 0, .tv_nsec = 0 },
    );

    if (nev < 0) {
        return error.EPOLL;
    } else if (nev == 0) {
        return null;
    } else {
        return events[0];
    }
}
