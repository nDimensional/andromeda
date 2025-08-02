const std = @import("std");
const utils = @import("utils.zig");

pub const Force = @import("Force.zig");

pub const Quadrant = enum(u2) {
    sw = 0,
    nw = 1,
    se = 2,
    ne = 3,
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

    pub fn getMinDistance(area: Area, point: @Vector(2, f32)) f32 {
        const zero: @Vector(2, f32) = comptime @splat(0);
        const s: @Vector(2, f32) = @splat(area.s / 2);
        const d = @abs(point - area.c) - s;
        return utils.getNorm(2, @max(d, zero));
    }
};

pub const Body = packed struct {
    position: @Vector(2, f32) = .{ 0, 0 },
    mass: f32 = 0,
};

pub const Node = packed struct {
    pub const NULL = std.math.maxInt(u32);

    center: @Vector(2, f32) = .{ 0, 0 },
    mass: f32 = 0,
    sw: u32 = NULL,
    nw: u32 = NULL,
    se: u32 = NULL,
    ne: u32 = NULL,

    pub inline fn isEmpty(node: Node) bool {
        return node.sw == NULL and node.nw == NULL and node.se == NULL and node.ne == NULL;
    }

    pub inline fn getQuadrant(node: Node, quadrant: Quadrant) u32 {
        return switch (quadrant) {
            .sw => node.sw,
            .nw => node.nw,
            .se => node.se,
            .ne => node.ne,
        };
    }

    pub inline fn setQuadrant(node: *Node, quadrant: Quadrant, index: u32) void {
        switch (quadrant) {
            .sw => node.sw = index,
            .nw => node.nw = index,
            .se => node.se = index,
            .ne => node.ne = index,
        }
    }

    pub fn add(node: *Node, position: @Vector(2, f32), mass: f32) void {
        const node_mass: @Vector(2, f32) = @splat(node.mass);
        const body_mass: @Vector(2, f32) = @splat(mass);
        const total_mass = node_mass + body_mass;
        node.center = (node.center * node_mass + position * body_mass) / total_mass;
        node.mass += mass;
    }

    pub fn remove(node: *Node, position: @Vector(2, f32), mass: f32) void {
        const total_mass: @Vector(2, f32) = @splat(node.mass);
        const body_mass: @Vector(2, f32) = @splat(mass);
        const node_mass = total_mass - body_mass;
        node.center = (node.center * node_mass - position * body_mass) / total_mass;
        node.mass -= mass;
    }
};

pub const Options = struct {
    /// threshold for large-body approximation
    threshold: f32 = 0.5,
    force: Force = .{},
};

pub const Quadtree = struct {
    pub const Error = std.mem.Allocator.Error || error{ Empty, OutOfBounds };

    area: Area,
    tree: std.ArrayList(Node),
    force: Force,
    threshold: f32,

    pub fn init(allocator: std.mem.Allocator, area: Area, options: Options) Quadtree {
        return .{
            .tree = std.ArrayList(Node).init(allocator),
            .area = area,
            .force = options.force,
            .threshold = options.threshold,
        };
    }

    pub fn deinit(self: Quadtree) void {
        self.tree.deinit();
    }

    pub fn reset(self: *Quadtree, area: Area) void {
        self.area = area;
        self.tree.clearRetainingCapacity();
    }

    pub fn insert(self: *Quadtree, position: @Vector(2, f32), mass: f32) !void {
        if (!self.area.contains(position))
            return Error.OutOfBounds;

        if (self.tree.items.len == 0) {
            try self.tree.append(Node{ .center = position, .mass = mass });
        } else {
            try self.insertNode(0, self.area, position, mass);
        }
    }

    fn insertNode(self: *Quadtree, id: u32, area: Area, position: @Vector(2, f32), mass: f32) !void {
        std.debug.assert(id < self.tree.items.len);
        std.debug.assert(area.s > 0);

        if (self.tree.items[id].isEmpty()) {
            const node = self.tree.items[id];

            const index: u32 = @intCast(self.tree.items.len);
            try self.tree.append(node);

            self.tree.items[id].setQuadrant(area.locate(node.center), index);
        }

        self.tree.items[id].add(position, mass);

        const quadrant = area.locate(position);
        const child = self.tree.items[id].getQuadrant(quadrant);

        if (child != Node.NULL) {
            const center = self.tree.items[child].center;
            if (@reduce(.And, center == position)) {
                self.tree.items[child].mass += mass;
                return;
            }

            try self.insertNode(child, area.divide(quadrant), position, mass);
        } else {
            const index: u32 = @intCast(self.tree.items.len);
            try self.tree.append(.{ .center = position, .mass = mass });
            self.tree.items[id].setQuadrant(quadrant, index);
        }
    }

    pub fn remove(self: *Quadtree, position: @Vector(2, f32), mass: f32) !void {
        if (self.tree.items.len == 0)
            return Error.Empty;

        if (!self.area.contains(position))
            return Error.OutOfBounds;

        const remove_root = try self.removeNode(0, self.area, position, mass);
        if (remove_root)
            self.tree.clearRetainingCapacity();
    }

    fn removeNode(self: *Quadtree, id: u32, area: Area, position: @Vector(2, f32), mass: f32) !bool {
        std.debug.assert(area.s > 0);
        std.debug.assert(id < self.tree.items.len);

        if (self.tree.items[id].isEmpty()) {
            self.tree.items[id].mass -= mass;
            if (@abs(self.tree.items[id].mass) > utils.epsilon)
                return error.Empty;
            return true;
        }

        const quadrant = area.locate(position);
        const child = self.tree.items[id].getQuadrant(quadrant);
        const child_area = area.divide(quadrant);
        const remove_child = try self.removeNode(child, child_area, position, mass);
        if (remove_child)
            self.tree.items[id].setQuadrant(quadrant, Node.NULL);

        self.tree.items[id].remove(position, mass);
        return self.tree.items[id].isEmpty();
    }

    pub fn getTotalMass(self: Quadtree) f32 {
        if (self.tree.items.len == 0) {
            return 0;
        } else {
            return self.tree.items[0].mass;
        }
    }

    pub inline fn setForceParams(self: *Quadtree, params: Force.Params) void {
        self.force = Force.create(params);
    }

    pub inline fn setThreshold(self: *Quadtree, threshold: f32) void {
        self.threshold = threshold;
    }

    pub fn getForce(self: Quadtree, position: @Vector(2, f32), mass: f32) @Vector(2, f32) {
        if (self.tree.items.len == 0)
            return .{ 0, 0 };

        return self.getForceNode(0, self.area.s, position, mass);
    }

    fn getForceNode(self: Quadtree, id: u32, s: f32, p: @Vector(2, f32), m: f32) @Vector(2, f32) {
        if (id >= self.tree.items.len)
            @panic("index out of range");

        const node = self.tree.items[id];
        if (node.isEmpty())
            return self.force.getForce(2, p, m, node.center, node.mass);

        const d = utils.getNorm(2, node.center - p);
        if (s / d < self.threshold)
            return self.force.getForce(2, p, m, node.center, node.mass);

        const s2 = s / 2;
        var f = @Vector(2, f32){ 0, 0 };
        if (node.sw != Node.NULL) f += self.getForceNode(node.sw, s2, p, m);
        if (node.nw != Node.NULL) f += self.getForceNode(node.nw, s2, p, m);
        if (node.se != Node.NULL) f += self.getForceNode(node.se, s2, p, m);
        if (node.ne != Node.NULL) f += self.getForceNode(node.ne, s2, p, m);

        return f;
    }

    pub const NearestBodyMode = enum { inclusive, exclusive };
    pub fn getNearestBody(self: Quadtree, position: @Vector(2, f32), mode: NearestBodyMode) !Body {
        if (self.tree.items.len == 0)
            return error.Empty;

        var nearest = Body{};
        var neartest_dist = std.math.inf(f32);
        self.getNearestBodyNode(0, self.area, position, mode, &nearest, &neartest_dist);
        return nearest;
    }

    fn getNearestBodyNode(
        self: Quadtree,
        id: u32,
        area: Area,
        position: @Vector(2, f32),
        mode: NearestBodyMode,
        nearest: *Body,
        nearest_dist: *f32,
    ) void {
        if (id >= self.tree.items.len)
            @panic("index out of range");

        const node = self.tree.items[id];

        if (node.isEmpty()) {
            if (@reduce(.And, node.center == position) and mode == .exclusive)
                return;

            const dist = utils.getNorm(2, node.center - position);
            if (dist < nearest_dist.*) {
                nearest.position = node.center;
                nearest.mass = node.mass;
                nearest_dist.* = dist;
            }
        } else if (area.getMinDistance(position) < nearest_dist.*) {
            if (node.sw != Node.NULL)
                self.getNearestBodyNode(node.sw, area.divide(.sw), position, mode, nearest, nearest_dist);
            if (node.nw != Node.NULL)
                self.getNearestBodyNode(node.nw, area.divide(.nw), position, mode, nearest, nearest_dist);
            if (node.se != Node.NULL)
                self.getNearestBodyNode(node.se, area.divide(.se), position, mode, nearest, nearest_dist);
            if (node.ne != Node.NULL)
                self.getNearestBodyNode(node.ne, area.divide(.ne), position, mode, nearest, nearest_dist);
        }
    }

    pub fn print(self: *Quadtree, log: std.fs.File.Writer) !void {
        try self.printNode(log, 0, 1);
    }

    fn printNode(self: *Quadtree, log: std.fs.File.Writer, id: u32, depth: usize) !void {
        if (id >= self.tree.items.len)
            @panic("index out of range");

        const node = self.tree.items[id];

        try log.print("node {d}\n", .{id});
        if (node.sw != Node.NULL) {
            try log.writeByteNTimes(' ', depth * 2);
            try log.print("sw: ", .{});
            try self.printNode(log, node.sw, depth + 1);
        }
        if (node.nw != Node.NULL) {
            try log.writeByteNTimes(' ', depth * 2);
            try log.print("nw: ", .{});
            try self.printNode(log, node.nw, depth + 1);
        }
        if (node.se != Node.NULL) {
            try log.writeByteNTimes(' ', depth * 2);
            try log.print("se: ", .{});
            try self.printNode(log, node.se, depth + 1);
        }
        if (node.ne != Node.NULL) {
            try log.writeByteNTimes(' ', depth * 2);
            try log.print("ne: ", .{});
            try self.printNode(log, node.ne, depth + 1);
        }
    }
};

test "create and construct Quadtree" {
    const s: f32 = 256;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var prng = std.Random.Xoshiro256.init(0);
    const random = prng.random();

    var self = Quadtree.init(allocator, .{ .s = s }, .{});
    defer self.deinit();

    var bodies = std.ArrayList(Node).init(allocator);
    defer bodies.deinit();

    var total_mass: f32 = 0;

    for (0..100) |_| {
        const x = (random.float(f32) - 0.5) * s;
        const y = (random.float(f32) - 0.5) * s;
        const mass: f32 = @floatFromInt(random.uintLessThan(u32, 256));

        try self.insert(.{ x, y }, mass);
        try bodies.append(.{ .center = .{ x, y }, .mass = mass });

        total_mass += mass;
        try std.testing.expectEqual(self.tree.items[0].mass, total_mass);
    }

    for (bodies.items) |body| {
        try self.remove(body.center, body.mass);
        total_mass -= body.mass;
        try std.testing.expectEqual(self.getTotalMass(), total_mass);
    }
}

test "getNearestBody" {
    const s: f32 = 256;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.testing.expect(gpa.deinit() == .ok) catch {};

    var qt = Quadtree.init(allocator, .{ .s = s }, .{});
    defer qt.deinit();

    // Test empty tree
    try std.testing.expectError(error.Empty, qt.getNearestBody(.{ 0, 0 }, .inclusive));

    // Insert bodies in different quadrants
    const p1: @Vector(2, f32) = .{ 10, 10 };
    const p2: @Vector(2, f32) = .{ 100, 100 };
    const p3: @Vector(2, f32) = .{ -50, -50 };

    try qt.insert(p1, 1);
    try qt.insert(p2, 2);
    try qt.insert(p3, 3);

    { // Test finding nearest to a point
        const nearest = try qt.getNearestBody(.{ 15, 15 }, .inclusive);

        // p1 should be nearest to the query point
        try std.testing.expect(@reduce(.And, nearest.position == p1));
        try std.testing.expectEqual(1, nearest.mass);
    }

    { // Test finding nearest to a child, inclusive
        const nearest = try qt.getNearestBody(.{ 10, 10 }, .inclusive);

        // p1 should be nearest to the query point
        try std.testing.expect(@reduce(.And, nearest.position == p1));
        try std.testing.expectEqual(1, nearest.mass);
    }

    { // Test finding nearest to a child, exclusive
        const nearest = try qt.getNearestBody(.{ 10, 10 }, .exclusive);

        // p1 should be nearest to the query point
        try std.testing.expect(@reduce(.And, nearest.position == p3));
        try std.testing.expectEqual(3, nearest.mass);
    }
}
