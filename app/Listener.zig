const std = @import("std");

const Listener = @This();

fd: std.posix.fd_t,
kq: std.posix.fd_t,
changes: [1]std.posix.Kevent,

pub fn init(path: [*:0]const u8) !Listener {
    const fd = try std.posix.openZ(path, .{}, 0o666);
    const kq = try std.posix.kqueue();

    return .{
        .fd = fd,
        .kq = kq,
        .changes = .{.{
            .ident = @intCast(fd),
            .filter = std.c.EVFILT_VNODE,
            .flags = std.c.EV_ADD | std.c.EV_ENABLE | std.c.EV_CLEAR,
            .fflags = std.c.NOTE_WRITE,
            .data = 0,
            .udata = 0,
        }},
    };
}

pub fn deinit(self: Listener) void {
    std.posix.close(self.fd);
    std.posix.close(self.kq);
}

pub fn poll(self: Listener) !?std.posix.Kevent {
    var events: [1]std.posix.Kevent = undefined;

    const nev = try std.posix.kevent(
        self.kq,
        &self.changes,
        &events,
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
