const std = @import("std");

const File = @This();

data: []align(std.mem.page_size) const u8,

pub fn init(path: []const u8) !File {
    std.log.info("opening {s}", .{path});
    const fd = try std.posix.open(path, .{.ACCMODE = .RDONLY}, 644);
    defer std.posix.close(fd);

    const stat = try std.posix.fstat(fd);
    const data = try std.posix.mmap(null, @intCast(stat.size), std.posix.PROT.READ, .{.TYPE = .SHARED}, fd, 0);
    return File{ .data = data };
}

pub fn deinit(self: File) void {
    std.posix.munmap(self.data);
}
