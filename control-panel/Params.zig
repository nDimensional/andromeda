const std = @import("std");

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

    const norm = @reduce(.Add, delta * delta);
    if (norm == 0) {
        return .{ 0, 0 };
    }

    const dist = std.math.sqrt(norm);

    const unit = delta / @as(@Vector(2, f32), @splat(dist));

    // const f = -repulsion * a_mass * b_mass / norm;
    const f = -1 * (self.repulsion / 500) * a_mass * b_mass / dist;
    return unit * @as(@Vector(2, f32), @splat(f));
}

/// Get the force exerted on S by T
pub inline fn getAttraction(self: Self, s: Point, t: Point) Force {
    var delta = t - s;
    delta *= @splat(self.attraction);
    return delta;
}

pub fn getMass(_: Self, incoming_degree: f32) f32 {
    return std.math.sqrt(incoming_degree);
}
