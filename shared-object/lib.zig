const std = @import("std");
const shm = @import("shm");

pub fn Writer(comptime name: []const u8) type {
    const shm_name = "/" ++ name;
    return struct {
        const Self = @This();

        map: []align(std.mem.page_size) const u8,
        data: []u8,

        pub fn init(size: usize) !Self {
            shm.unlink(shm_name) catch |err| switch (err) {
                error.NOENT => {},
                else => return err,
            };

            const fd = try shm.open(shm_name, .ReadWrite, .{ .create = true, .exclusive = true });
            defer std.posix.close(fd);

            const map_size = @sizeOf(usize) + size;

            try std.posix.ftruncate(fd, map_size);

            const prot = std.posix.PROT.READ | std.posix.PROT.WRITE;
            const map = try std.posix.mmap(null, map_size, prot, .{ .TYPE = .SHARED }, fd, 0);

            var buf: [@sizeOf(usize)]u8 = undefined;
            std.mem.writeInt(usize, &buf, size, .big);
            @memcpy(map[0..@sizeOf(usize)], &buf);

            return .{ .map = map, .data = map[@sizeOf(usize)..] };
        }

        pub fn deinit(self: Self) void {
            std.posix.munmap(self.map);
            shm.unlink(shm_name) catch |err| @panic(@errorName(err));
        }
    };
}

pub fn Reader(comptime name: []const u8) type {
    const shm_name = "/" ++ name;

    return struct {
        const Self = @This();

        map: []align(std.mem.page_size) const u8,
        data: []const u8,

        pub fn init() !Self {
            const fd = try shm.open(shm_name, .ReadOnly, .{});
            defer std.posix.close(fd);

            const size = try getSize(fd);
            const map_size = @sizeOf(usize) + size;
            const map = try std.posix.mmap(null, map_size, std.posix.PROT.READ, .{ .TYPE = .SHARED }, fd, 0);
            return .{ .map = map, .data = map[@sizeOf(usize)..] };
        }

        fn getSize(fd: std.posix.fd_t) !usize {
            const map = try std.posix.mmap(null, @sizeOf(usize), std.posix.PROT.READ, .{ .TYPE = .SHARED }, fd, 0);
            defer std.posix.munmap(map);
            return std.mem.readInt(usize, map[0..@sizeOf(usize)], .big);
        }

        pub fn deinit(self: Self) void {
            std.posix.munmap(self.map);
        }
    };
}
