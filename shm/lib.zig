const std = @import("std");
const c = @import("c.zig");

pub const Access = enum { ReadOnly, ReadWrite };
pub const Options = struct {
    create: bool = false,
    exclusive: bool = false,
    truncate: bool = false,
};

pub fn open(name: [*:0]const u8, access: Access, options: Options) !std.posix.fd_t {
    var flags: c_int = 0;
    switch (access) {
        .ReadOnly => flags |= c.O_RDONLY,
        .ReadWrite => flags |= c.O_RDWR,
    }

    if (options.create) flags |= c.O_CREAT;
    if (options.exclusive) flags |= c.O_EXCL;
    if (options.truncate) flags |= c.O_TRUNC;

    const mode = c.S_IRUSR | c.S_IWUSR;

    const fd = c.shm_open(name, flags, mode);
    if (fd == -1) {
        return switch (std.posix.errno(fd)) {
            std.c.E.ACCES => error.ACCES,
            std.c.E.EXIST => error.EXIST,
            std.c.E.INVAL => error.INVAL,
            std.c.E.NAMETOOLONG => error.NAMETOOLONG,
            std.c.E.NFILE => error.NFILE,
            std.c.E.NOENT => error.NOENT,
            else => |e| @panic(@tagName(e)),
        };
    }

    return fd;
}

pub fn unlink(name: [*:0]const u8) !void {
    const rc = c.shm_unlink(name);
    if (rc == -1) {
        return switch (std.posix.errno(rc)) {
            std.c.E.ACCES => error.ACCES,
            std.c.E.NOENT => error.NOENT,
            else => |e| @panic(@tagName(e)),
        };
    }
}
