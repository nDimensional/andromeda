const std = @import("std");
const norm = @import("utils.zig").norm;

pub const Point = @Vector(2, f32);
pub const Force = @Vector(2, f32);

const Self = @This();

attraction: f32,
repulsion: f32,
center: f32,
temperature: f32,

/// Get the force exerted on A by B
pub fn getRepulsion(self: Self, a: Point, a_mass: f32, b: Point, b_mass: f32) Force {
    const delta = b - a;

    const dist = norm(delta);
    if (dist == 0) {
        return .{ 0, 0 };
    }

    const unit = delta / @as(@Vector(2, f32), @splat(dist));

    const f = -1 * (self.repulsion / 500) * a_mass * b_mass / dist;

    return unit * @as(@Vector(2, f32), @splat(f));
}

/// Get the force exerted on S by T
pub inline fn getAttraction(self: Self, s: Point, t: Point) Force {
    var delta = t - s;
    delta *= @splat(self.attraction);
    return delta;
}

pub inline fn getMass(incoming_degree: f32) f32 {
    return std.math.sqrt(incoming_degree) + 1;
}
