const std = @import("std");
const utils = @import("utils.zig");

pub const Point = @Vector(2, f32);
pub const Force = @Vector(2, f32);

const Self = @This();

attraction: f32 = 0.0001,
repulsion: f32 = 100.0,
repulsion_exp: f32 = 1.0,
center: f32 = 1.0,
temperature: f32 = 0.2,
weighted_nodes: bool = true,

/// Get the force exerted on S by T
pub inline fn getAttraction(self: Self, a: Point, b: Point, weight: f32) Force {
    var delta = b - a;
    delta *= @splat(self.attraction * weight);
    return delta;
}

// const A: f32 = 0.11597562594543352;
// const B: f32 = 0.9218550927552056;

// /// Get the force exerted on S by T
// pub inline fn getAttraction(self: Self, a: Point, b: Point, weight: f32) Force {
//     const delta = b - a;
//     const dist2 = @reduce(.Add, delta * delta);
//     const dist = std.math.sqrt(dist2);

//     var f: f32 = 2 * A * B * self.attraction;
//     f *= dist2;
//     f *= std.math.pow(f32, dist, B - 1);
//     f /= (1 + dist2);
//     f *= weight;

//     return delta * @as(@Vector(2, f32), @splat(f));
// }
