const std = @import("std");

const Params = @import("Params.zig");
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

    center: @Vector(2, f32) = .{ 0, 0 },
    mass: f32 = 0,
    sw: u32 = NULL,
    nw: u32 = NULL,
    se: u32 = NULL,
    ne: u32 = NULL,

    pub inline fn isEmpty(body: Body) bool {
        return body.sw == NULL and body.nw == NULL and body.se == NULL and body.ne == NULL;
    }

    pub inline fn getQuadrant(body: Body, quadrant: Quadrant) u32 {
        return switch (quadrant) {
            .sw => body.sw,
            .nw => body.nw,
            .se => body.se,
            .ne => body.ne,
        };
    }

    pub inline fn setQuadrant(body: *Body, quadrant: Quadrant, index: u32) void {
        switch (quadrant) {
            .sw => body.sw = index,
            .nw => body.nw = index,
            .se => body.se = index,
            .ne => body.ne = index,
        }
    }

    pub fn add(body: *Body, point: @Vector(2, f32), mass: f32) void {
        const body_mass: @Vector(2, f32) = @splat(body.mass);
        const point_mass: @Vector(2, f32) = @splat(mass);
        const total_mass = body_mass + point_mass;
        body.center = (body.center * body_mass + point * point_mass) / total_mass;
        body.mass += mass;
    }

    pub fn remove(body: *Body, point: @Vector(2, f32), mass: f32) void {
        const total_mass: @Vector(2, f32) = @splat(body.mass);
        const point_mass: @Vector(2, f32) = @splat(mass);
        const body_mass = total_mass - point_mass;
        body.center = (body.center * body_mass - point * point_mass) / total_mass;
        body.mass -= mass;
    }
};

area: Area,
tree: std.ArrayList(Body),
threshold: f32 = 0.5,

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

pub fn insert(self: *Quadtree, position: @Vector(2, f32), mass: f32) !void {
    if (self.tree.items.len == 0) {
        try self.tree.append(Body{ .center = position, .mass = mass });
    } else {
        if (self.area.s == 0) {
            @panic("expected self.area.s > 0");
        }

        try self.insertNode(0, self.area, position, mass);
    }
}

fn insertNode(self: *Quadtree, body: u32, area: Area, position: @Vector(2, f32), mass: f32) !void {
    if (body >= self.tree.items.len) {
        @panic("index out of range");
    }

    if (area.s == 0) {
        @panic("expected area.s > 0");
    }

    if (self.tree.items[body].isEmpty()) {
        const node = self.tree.items[body];

        const index: u32 = @intCast(self.tree.items.len);
        try self.tree.append(node);

        self.tree.items[body].setQuadrant(area.locate(node.center), index);
    }

    self.tree.items[body].add(position, mass);

    const quadrant = area.locate(position);
    const child = self.tree.items[body].getQuadrant(quadrant);

    if (child != Body.NULL) {
        const center = self.tree.items[child].center;
        if (@reduce(.And, center == position)) {
            self.tree.items[child].mass += mass;
            return;
        }

        try self.insertNode(child, area.divide(quadrant), position, mass);
    } else {
        const index: u32 = @intCast(self.tree.items.len);
        try self.tree.append(.{ .center = position, .mass = mass });
        self.tree.items[body].setQuadrant(quadrant, index);
    }
}

pub fn remove(self: *Quadtree, position: @Vector(2, f32), mass: f32) !void {
    _ = try self.removeNode(0, self.area, position, mass);
    // if (result == true) {
    //     @panic("internal error - remove root body");
    // }
}

fn removeNode(self: *Quadtree, body: u32, area: Area, position: @Vector(2, f32), mass: f32) !bool {
    if (body >= self.tree.items.len) {
        @panic("index out of range");
    }

    if (area.s == 0) {
        @panic("expected area.s > 0");
    }

    if (self.tree.items[body].isEmpty()) {
        if (self.tree.items[body].mass < mass) {
            @panic("internal error removing body");
        }

        return true;
    }

    const quadrant = area.locate(position);
    const child = self.tree.items[body].getQuadrant(quadrant);
    const remove_child = try self.removeNode(child, area.divide(quadrant), position, mass);
    if (remove_child) {
        self.tree.items[body].setQuadrant(quadrant, Body.NULL);
    }

    self.tree.items[body].add(position, -mass);
    if (self.tree.items[body].isEmpty()) {
        if (self.tree.items[body].mass > 0.001) {
            std.log.warn("expected body mass to be 0", .{});
        }

        return true;
    }

    return false;
}

pub fn getForce(self: Quadtree, params: *const Params, p: @Vector(2, f32), mass: f32) @Vector(2, f32) {
    if (self.tree.items.len == 0) {
        return .{ 0, 0 };
    } else {
        return self.getForceBody(params, 0, self.area.s, p, mass);
    }
}

fn getForceBody(self: Quadtree, params: *const Params, body: u32, s: f32, p: @Vector(2, f32), mass: f32) @Vector(2, f32) {
    if (body >= self.tree.items.len) {
        @panic("index out of range");
    }

    const node = self.tree.items[body];
    if (node.isEmpty()) {
        return params.getRepulsion(p, mass, node.center, node.mass);
    }

    const delta = node.center - p;
    const norm = @reduce(.Add, delta * delta);
    const d = std.math.sqrt(norm);

    if (s / d < self.threshold) {
        return params.getRepulsion(p, mass, node.center, node.mass);
    }

    var f = @Vector(2, f32){ 0, 0 };
    if (node.sw != Body.NULL) f += self.getForceBody(params, node.sw, s / 2, p, mass);
    if (node.nw != Body.NULL) f += self.getForceBody(params, node.nw, s / 2, p, mass);
    if (node.se != Body.NULL) f += self.getForceBody(params, node.se, s / 2, p, mass);
    if (node.ne != Body.NULL) f += self.getForceBody(params, node.ne, s / 2, p, mass);

    return f;
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

test "quadtree tests" {
    const s: f32 = 256;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var prng = std.Random.Xoshiro256.init(0);
    const random = prng.random();

    var quadtree = Quadtree.init(allocator, .{ .s = s });
    defer quadtree.deinit();

    var bodies = std.ArrayList(Body).init(allocator);
    defer bodies.deinit();

    var total_mass: f32 = 0;

    for (0..100) |_| {
        const x = (random.float(f32) - 0.5) * s;
        const y = (random.float(f32) - 0.5) * s;
        const mass: f32 = @floatFromInt(1 + random.uintLessThan(u32, 256));

        try quadtree.insert(.{ x, y }, mass);
        try bodies.append(.{ .center = .{ x, y }, .mass = mass });

        total_mass += mass;
        try std.testing.expectEqual(quadtree.tree.items[0].mass, total_mass);
    }

    for (bodies.items) |body| {
        try quadtree.remove(body.center, body.mass);
        total_mass -= body.mass;
        try std.testing.expectEqual(quadtree.tree.items[0].mass, total_mass);
    }
}
