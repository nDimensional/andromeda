const std = @import("std");

pub inline fn norm(f: @Vector(2, f32)) f32 {
    return std.math.sqrt(@reduce(.Add, f * f));
}

pub inline fn getMass(incoming_degree: usize) f32 {
    const d: f32 = @floatFromInt(incoming_degree);
    return std.math.sqrt(d) + 1;
}
