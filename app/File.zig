const std = @import("std");

const File = @This();

data: []align(std.mem.page_size) const u8,

pub fn init(path: []const u8) !File {
    std.log.info("opening {s}", .{path});
    const fd = try std.os.open(path, std.os.O.RDONLY, 644);
    defer std.os.close(fd);

    const stat = try std.os.fstat(fd);
    const data = try std.os.mmap(null, @intCast(stat.size), std.os.PROT.READ, std.os.MAP.SHARED, fd, 0);
    return File{ .data = data };
}

pub fn deinit(self: File) void {
    std.os.munmap(self.data);
}
