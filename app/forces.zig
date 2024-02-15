const std = @import("std");

/// Get the force exerted on A by B
pub fn getRepulsion(repulsion: f32, a: @Vector(2, f32), a_mass: f32, b: @Vector(2, f32), b_mass: f32) @Vector(2, f32) {
    const delta = b - a;

    const norm = @reduce(.Add, delta * delta);
    if (norm == 0) {
        return .{ 0, 0 };
    }

    const dist = std.math.sqrt(norm);

    const unit = delta / @as(@Vector(2, f32), @splat(dist));

    // const f = -repulsion * a_mass * b_mass / norm;
    const f = -1 * (repulsion / 500) * a_mass * b_mass / dist;
    return unit * @as(@Vector(2, f32), @splat(f));
}

/// Get the force exerted on S by T
pub inline fn getAttraction(attraction: f32, s: @Vector(2, f32), t: @Vector(2, f32)) @Vector(2, f32) {
    var delta = t - s;
    delta *= @splat(attraction);
    return delta;
}

pub fn getMass(incoming_degree: f32) f32 {
    return std.math.sqrt(incoming_degree);
}
