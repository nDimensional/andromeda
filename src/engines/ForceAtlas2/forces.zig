const std = @import("std");

const utils = @import("../../utils.zig");
const quadtree = @import("../../quadtree.zig");

/// Get the force exerted on `a` by `b`
pub inline fn getAttraction(attraction: f32, a: @Vector(2, f32), b: @Vector(2, f32), weight: f32) @Vector(2, f32) {
    var delta = b - a;
    delta *= @splat(attraction * weight);
    return delta;
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

inline fn getRepulsionForce(
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

    const f = repulsion * a_mass * b_mass * std.math.pow(f32, dist, -0.8);
    return unit * @as(@Vector(2, f32), @splat(f));
}

// optimized inv_linear
// inline fn getRepulsionForce(
//     repulsion: f32,
//     a_position: @Vector(2, f32),
//     a_mass: f32,
//     b_position: @Vector(2, f32),
//     b_mass: f32,
// ) @Vector(2, f32) {
//     const delta: @Vector(2, f32) = b_position - a_position;
//     const dist2: f32 = @reduce(.Add, delta * delta);
//     if (dist2 == 0) return @splat(0);

//     const f = repulsion * a_mass * b_mass / dist2;
//     return delta * @as(@Vector(2, f32), @splat(f));
// }
