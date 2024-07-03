const std = @import("std");
const Andromeda = @import("Andromeda.zig");

pub fn main() !void {
    var andromeda = Andromeda{};
    defer andromeda.deinit();
    andromeda.init();

    const status = andromeda.run();
    std.log.info("status: {any}", .{status});
}
