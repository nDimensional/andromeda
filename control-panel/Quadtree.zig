const std = @import("std");

const forces = @import("forces.zig");
const Quadtree = @This();

pub const Quadrant = enum(u2) {
    ne = 0,
    nw = 1,
    sw = 2,
    se = 3,
};

pub const Area = packed struct {
    s: f32 = 0,
    c: @Vector(2, f32) = .{ 0, 0 },

    pub fn locate(area: Area, point: @Vector(2, f32)) Quadrant {
        const q = point < area.c;

        if (q[0]) {
            if (q[1]) {
                return .sw;
            } else {
                return .nw;
            }
        } else {
            if (q[1]) {
                return .se;
            } else {
                return .ne;
            }
        }
    }

    pub fn divide(area: Area, quadrant: Quadrant) Area {
        const s = area.s / 2;

        var delta: @Vector(2, f32) = switch (quadrant) {
            .sw => .{ -1, -1 },
            .nw => .{ -1, 1 },
            .se => .{ 1, -1 },
            .ne => .{ 1, 1 },
        };

        delta *= @splat(s / 2);

        return .{ .s = s, .c = area.c + delta };
    }

    pub fn contains(area: Area, point: @Vector(2, f32)) bool {
        const s = area.s / 2;
        const min_x = area.c[0] - s;
        const max_x = area.c[0] + s;
        const min_y = area.c[1] - s;
        const max_y = area.c[1] + s;
        if (point[0] < min_x or max_x < point[0]) return false;
        if (point[1] < min_y or max_y < point[1]) return false;
        return true;
    }
};

pub const Body = packed struct {
    pub const NULL = std.math.maxInt(u32);

    idx: u32 = 0,
    center: @Vector(2, f32) = .{ 0, 0 },
    mass: f32 = 0,
    sw: u32 = NULL,
    nw: u32 = NULL,
    se: u32 = NULL,
    ne: u32 = NULL,

    pub fn update(body: *Body, point: @Vector(2, f32), mass: f32) void {
        const node_mass: @Vector(2, f32) = @splat(body.mass);
        const point_mass: @Vector(2, f32) = @splat(mass);
        const total_mass: @Vector(2, f32) = @splat(body.mass + mass);
        body.center = (body.center * node_mass + point * point_mass) / total_mass;
        body.mass = body.mass + mass;
    }

    pub fn getQuadrant(body: Body, quadrant: Quadrant) u32 {
        return switch (quadrant) {
            .sw => body.sw,
            .nw => body.nw,
            .se => body.se,
            .ne => body.ne,
        };
    }

    pub fn setQuadrant(body: *Body, quadrant: Quadrant, index: u32) void {
        switch (quadrant) {
            .sw => body.sw = index,
            .nw => body.nw = index,
            .se => body.se = index,
            .ne => body.ne = index,
        }
    }
};

area: Area,
tree: std.ArrayList(Body),

pub fn init(allocator: std.mem.Allocator, area: Area) Quadtree {
    return .{ .tree = std.ArrayList(Body).init(allocator), .area = area };
}

pub fn deinit(self: Quadtree) void {
    self.tree.deinit();
}

pub fn reset(self: *Quadtree, area: Area) void {
    self.area = area;
    self.tree.clearRetainingCapacity();
}

pub fn insert(self: *Quadtree, idx: u32, position: @Vector(2, f32), mass: f32) !void {
    if (idx == 0) {
        @panic("expected idx != 0");
    }

    if (self.tree.items.len == 0) {
        try self.tree.append(Body{ .idx = idx, .center = position, .mass = mass });
    } else {
        if (self.area.s == 0) {
            @panic("expected self.area.s > 0");
        }

        try self.insertNode(0, self.area, idx, position, mass);
    }
}

fn insertNode(self: *Quadtree, body: u32, area: Area, idx: u32, position: @Vector(2, f32), mass: f32) !void {
    if (body >= self.tree.items.len) {
        @panic("index out of range");
    }

    if (area.s == 0) {
        @panic("expected area.s > 0");
    }

    if (self.tree.items[body].idx != 0) {
        const node = self.tree.items[body];
        if (@reduce(.And, node.center == position)) {
            const offset: @Vector(2, f32) = @splat(area.s / 4);
            const i_1: u32 = @intCast(self.tree.items.len);
            try self.tree.append(.{ .idx = node.idx, .mass = node.mass, .center = node.center - offset });

            self.tree.items[body].idx = 0;
            self.tree.items[body].setQuadrant(.sw, i_1);

            const i_2: u32 = @intCast(self.tree.items.len);
            try self.tree.append(.{ .idx = idx, .center = position + offset, .mass = mass });
            self.tree.items[body].setQuadrant(.ne, i_2);

            return;
        } else {
            const index: u32 = @intCast(self.tree.items.len);
            try self.tree.append(node);

            self.tree.items[body].idx = 0;
            self.tree.items[body].setQuadrant(area.locate(node.center), index);
        }
    }

    self.tree.items[body].update(position, mass);

    const quadrant = area.locate(position);
    const child = self.tree.items[body].getQuadrant(quadrant);

    if (child != Body.NULL) {
        try self.insertNode(child, area.divide(quadrant), idx, position, mass);
    } else {
        const index: u32 = @intCast(self.tree.items.len);
        try self.tree.append(.{ .idx = idx, .center = position, .mass = mass });
        self.tree.items[body].setQuadrant(quadrant, index);
    }
}

pub fn getForce(self: Quadtree, repulsion: f32, p: @Vector(2, f32), mass: f32) @Vector(2, f32) {
    if (self.tree.items.len == 0) {
        return .{ 0, 0 };
    } else {
        return self.getForceBody(repulsion, 0, self.area.s, p, mass);
    }
}

const threshold = 0.5;

fn getForceBody(self: Quadtree, repulsion: f32, body: u32, s: f32, p: @Vector(2, f32), mass: f32) @Vector(2, f32) {
    if (body >= self.tree.items.len) {
        @panic("index out of range");
    }

    const node = self.tree.items[body];

    if (node.idx != 0) {
        return forces.getRepulsion(repulsion, p, mass, node.center, node.mass);
    } else {
        const delta = node.center - p;
        const norm = @reduce(.Add, delta * delta);
        const d = std.math.sqrt(norm);

        if (s / d < threshold) {
            return forces.getRepulsion(repulsion, p, mass, node.center, node.mass);
        } else {
            var f = @Vector(2, f32){ 0, 0 };
            if (node.sw != Body.NULL) f += self.getForceBody(repulsion, node.sw, s / 2, p, mass);
            if (node.nw != Body.NULL) f += self.getForceBody(repulsion, node.nw, s / 2, p, mass);
            if (node.se != Body.NULL) f += self.getForceBody(repulsion, node.se, s / 2, p, mass);
            if (node.ne != Body.NULL) f += self.getForceBody(repulsion, node.ne, s / 2, p, mass);

            return f;
        }
    }
}

pub fn print(self: *Quadtree, log: std.fs.File.Writer) !void {
    try self.printBody(log, 0, 1);
}

fn printBody(self: *Quadtree, log: std.fs.File.Writer, body: u32, depth: usize) !void {
    if (body >= self.tree.items.len) {
        @panic("index out of range");
    }

    const node = self.tree.items[body];

    if (node.idx == 0) {
        try log.print("body {d}\n", .{body});
        if (node.sw != Body.NULL) {
            try log.writeByteNTimes(' ', depth * 2);
            try log.print("sw: ", .{});
            try self.printBody(log, node.sw, depth + 1);
        }
        if (node.nw != Body.NULL) {
            try log.writeByteNTimes(' ', depth * 2);
            try log.print("nw: ", .{});
            try self.printBody(log, node.nw, depth + 1);
        }
        if (node.se != Body.NULL) {
            try log.writeByteNTimes(' ', depth * 2);
            try log.print("se: ", .{});
            try self.printBody(log, node.se, depth + 1);
        }
        if (node.ne != Body.NULL) {
            try log.writeByteNTimes(' ', depth * 2);
            try log.print("ne: ", .{});
            try self.printBody(log, node.ne, depth + 1);
        }
    } else {
        try log.print("idx #{d}\n", .{node.idx});
    }
}
