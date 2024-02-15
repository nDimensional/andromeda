const std = @import("std");

const ul = @import("ul");
const Platform = ul.Ultralight.Platform;

const Environment = @import("Environment.zig");

const allocator = std.heap.c_allocator;

pub fn main() !void {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    const path = args.next() orelse @panic("missing path argument");
    std.log.info("GOT PATH: {s}", .{path});

    try std.io.getStdOut().writer().print("\n", .{});

    Platform.setFileSystem(Platform.filesystem);
    // Platform.setLogger(Platform.logger);

    var env: Environment = undefined;
    try env.init(allocator, path);
    defer env.deinit();

    env.run();
}
