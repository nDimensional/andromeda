const std = @import("std");

const utils = @import("utils.zig");

const Force = @This();

const Exponent = union(enum) {
    inv_sqrt: void,
    inv_linear: void,
    inv_square: void,
    sqrt: void,
    linear: void,
    square: void,
    custom: f32,
};

pub const Params = packed struct {
    /// constant for force equation
    c: f32 = 1,
    /// distance exponent in force equation
    r: f32 = -2,
};

pub fn create(params: Params) Force {
    if (params.r == 2) {
        return .{ .c = params.c, .exp = .{ .square = {} } };
    } else if (params.r == 1) {
        return .{ .c = params.c, .exp = .{ .linear = {} } };
    } else if (params.r == 0.5) {
        return .{ .c = params.c, .exp = .{ .sqrt = {} } };
    } else if (params.r == -0.5) {
        return .{ .c = params.c, .exp = .{ .inv_sqrt = {} } };
    } else if (params.r == -1) {
        return .{ .c = params.c, .exp = .{ .inv_linear = {} } };
    } else if (params.r == -2) {
        return .{ .c = params.c, .exp = .{ .inv_square = {} } };
    } else {
        return .{ .c = params.c, .exp = .{ .custom = params.r } };
    }
}

/// constant for force equation
c: f32 = 1.0,
/// distance exponent in force equation
exp: Exponent = .{ .inv_square = {} },

pub fn getForce(
    self: Force,
    comptime R: u3,
    a_position: @Vector(R, f32),
    a_mass: f32,
    b_position: @Vector(R, f32),
    b_mass: f32,
) @Vector(R, f32) {
    const delta = b_position - a_position;
    const dist = utils.getNorm(R, delta);
    if (dist == 0)
        return @splat(0);

    const unit = delta / @as(@Vector(R, f32), @splat(dist));

    var f = self.c * a_mass * b_mass;
    switch (self.exp) {
        .inv_sqrt => f /= std.math.sqrt(dist),
        .inv_linear => f /= dist,
        .inv_square => f /= dist * dist,
        .sqrt => f *= std.math.sqrt(dist),
        .linear => f *= dist,
        .square => f *= dist * dist,
        .custom => |r| f *= std.math.pow(f32, dist, r),
    }

    return unit * @as(@Vector(R, f32), @splat(f));
}
