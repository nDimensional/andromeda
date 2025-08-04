const std = @import("std");

/// Get the force exerted on `a` by `b`
pub inline fn getAttraction(attraction: f32, a: @Vector(2, f32), b: @Vector(2, f32), weight: f32) @Vector(2, f32) {
    var delta = b - a;
    delta *= @splat(attraction * weight);
    return delta;
}

pub inline fn getRepulsion(
    repulsion: f32,
    a_position: @Vector(2, f32),
    a_mass: f32,
    b_position: @Vector(2, f32),
    b_mass: f32,
) @Vector(2, f32) {
    const delta: @Vector(2, f32) = b_position - a_position;
    const dist2: f32 = @reduce(.Add, delta * delta);
    if (dist2 == 0)
        return @splat(0);

    const dist: f32 = std.math.sqrt(dist2);
    const unit = delta / @as(@Vector(2, f32), @splat(dist));

    // inv_linear
    const f = repulsion * a_mass * b_mass / dist;

    // // inv_square
    // const f = repulsion * a_mass * b_mass / dist2;
    return unit * @as(@Vector(2, f32), @splat(f));
}
