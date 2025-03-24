const std = @import("std");
const utils = @import("utils.zig");

pub const Point = @Vector(2, f32);
pub const Force = @Vector(2, f32);

const Params = @This();

attraction: f32 = 0.0001,
repulsion: f32 = 100.0,
repulsion_exp: f32 = 1.0,
center: f32 = 1.0,
temperature: f32 = 0.2,
weighted_nodes: bool = true,

/// Get the force exerted on S by T
pub inline fn getAttraction(self: Params, a: Point, b: Point, weight: f32) Force {
    var delta = b - a;
    delta *= @splat(self.attraction * weight);
    return delta;
}
