const std = @import("std");

const utils = @import("../../utils.zig");
const quadtree = @import("../../quadtree.zig");

// const a: comptime_float = 0.012708355085885595;
// const b: comptime_float = 0.790494785587651;

const a: comptime_float = 0.9995310293272468;
const b: comptime_float = 0.7972444496423875;

// const a = 1.895605866250001;
// const b = 0.8006378441402028;

const e: comptime_float = 0.001;

// const scale: @Vector(2, f32) = @splat(1000);
const scale: @Vector(2, f32) = @splat(1);

/// F_attractive = w_ij * (y_i - y_j) * (-2 * a * b * dist^(2*b-1)) / (1 + dist^(2b))
pub inline fn getAttraction(repulsion: f32, attraction: f32, a_position: @Vector(2, f32), b_position: @Vector(2, f32), weight: f32) @Vector(2, f32) {
    // Attractive force
    const delta = (a_position - b_position) / scale;
    const dist2 = @reduce(.Add, delta * delta);
    const dist = @sqrt(dist2);

    const n = -2 * a * b * std.math.pow(f32, dist, (2 * b) - 1);
    const d = 1 + dist2;
    const k = attraction * weight * n / d;
    var f = @as(@Vector(2, f32), @splat(k)) * delta;

    // _ = repulsion;
    const r = 2 * b / ((e + dist2) * (1 + a * std.math.pow(f32, dist, 2 * b)));
    f += @as(@Vector(2, f32), @splat(repulsion * r * weight)) * delta;

    return f * scale;
}

pub inline fn getRepulsion(repulsion: f32, qt: *const quadtree.Quadtree, body: quadtree.Body) @Vector(2, f32) {
    if (qt.tree.items.len == 0)
        return .{ 0, 0 };

    return getRepulsionNode(repulsion, qt, 0, qt.area.s, body);
}

const threshold = 0.5;

fn getRepulsionNode(repulsion: f32, qt: *const quadtree.Quadtree, id: u32, s: f32, body: quadtree.Body) @Vector(2, f32) {
    if (id >= qt.tree.items.len)
        @panic("index out of range");

    const node = qt.tree.items[id];
    if (node.isEmpty())
        return getRepulsionForce(repulsion, body.position, body.mass, node.center, node.mass);

    const d = utils.norm(node.center - body.position);
    if (s / d < threshold)
        return getRepulsionForce(repulsion, body.position, body.mass, node.center, node.mass);

    const s2 = s / 2;
    var f = @Vector(2, f32){ 0, 0 };
    if (node.sw != quadtree.Node.NULL) f += getRepulsionNode(repulsion, qt, node.sw, s2, body);
    if (node.nw != quadtree.Node.NULL) f += getRepulsionNode(repulsion, qt, node.nw, s2, body);
    if (node.se != quadtree.Node.NULL) f += getRepulsionNode(repulsion, qt, node.se, s2, body);
    if (node.ne != quadtree.Node.NULL) f += getRepulsionNode(repulsion, qt, node.ne, s2, body);

    return f;
}

/// F_repulsive = (2 * b) / ((ε + dist^2) * (1 + a * dist^(2*b))) * (y_i - y_j)
pub inline fn getRepulsionForce(
    repulsion: f32,
    a_position: @Vector(2, f32),
    a_mass: f32,
    b_position: @Vector(2, f32),
    b_mass: f32,
) @Vector(2, f32) {
    const delta: @Vector(2, f32) = (a_position - b_position) / scale;
    const dist2: f32 = @reduce(.Add, delta * delta);
    if (dist2 == 0)
        return @splat(0);

    const dist: f32 = @sqrt(dist2);
    const f = a_mass * b_mass * 2 * b / ((e + dist2) * (1 + a * std.math.pow(f32, dist, 2 * b)));

    return @as(@Vector(2, f32), @splat(repulsion * f)) * delta * scale;
}
