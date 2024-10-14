const std = @import("std");
const norm = @import("utils.zig").norm;

pub const Point = @Vector(2, f32);
pub const Force = @Vector(2, f32);

const Self = @This();

attraction: f32 = 0.00001,
repulsion: f32 = 10.0,
center: f32 = 1.0,
temperature: f32 = 0.3,

/// Get the force exerted on A by B
pub fn getRepulsion(self: Self, a: Point, a_mass: f32, b: Point, b_mass: f32) Force {
    const delta = b - a;

    const dist = norm(delta);
    if (dist == 0) {
        return @splat(0);
    }

    const unit = delta / @as(Force, @splat(dist));

    const f = -1 * (-self.repulsion / 500) * a_mass * b_mass / dist;

    return unit * @as(Force, @splat(f));
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
