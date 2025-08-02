const std = @import("std");

pub const epsilon = 0.0000001;

pub fn getNorm(comptime R: u3, f: @Vector(R, f32)) f32 {
    return std.math.sqrt(@reduce(.Add, f * f));
}
