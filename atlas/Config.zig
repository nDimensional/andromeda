const std = @import("std");

const Config = @This();

args: std.process.ArgIterator,
path: [*:0]const u8,

pub fn parse(allocator: std.mem.Allocator) !Config {
    var args = try std.process.argsWithAllocator(allocator);

    var path_arg: ?[*:0]const u8 = null;
    _ = args.next() orelse return error.MissingProgramName;

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            // ...
        } else {
            path_arg = arg;
        }
    }

    if (path_arg) |path| {
        return .{ .args = args, .path = path };
    } else {
        return error.MissingPathArgument;
    }
}

pub fn deinit(self: *Config) void {
    self.args.deinit();
}
