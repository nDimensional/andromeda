const std = @import("std");

pub inline fn norm(f: @Vector(2, f32)) f32 {
    return std.math.sqrt(@reduce(.Add, f * f));
}
