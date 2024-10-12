const std = @import("std");

pub fn main() !void {
    const min = std.math.floatMin(f32);
    const max = std.math.floatMax(f32);

    std.log.info("min: {d}", .{min});
    std.log.info("std.math.log2(min): {d}", .{std.math.log2(min)});

    std.log.info("max: {d}", .{max});
    std.log.info("std.math.log2(max): {d}", .{std.math.log2(max)});
}
