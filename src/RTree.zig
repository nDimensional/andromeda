const std = @import("std");

const Quadtree = @import("Quadtree.zig");
const Params = @import("Params.zig");

pub fn RTree(comptime R: u3, comptime Mass: type) type {
    comptime {
        switch (@typeInfo(Mass)) {
            .Int, .Float => {},
            else => @compileError("Mass must be an integer or float type"),
        }
    }

    return struct {
        const Self = @This();

        pub const Error = std.mem.Allocator.Error || error{ Empty, NotFound, InvalidArea, InvalidMass };

        pub const fanout = 1 << R;
        pub const N = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = R } });

        comptime {
            std.debug.assert(fanout == std.math.maxInt(N) + 1);
        }

        pub const Vector = @Vector(R, f32);
        pub const Point = @Vector(R, f32);

        pub const Quadrant = @Vector(R, bool);

        pub fn cellFromIndex(n: N) Quadrant {
            var q: Quadrant = @splat(false);
            inline for (0..R) |i| {
                const needle = (1 << (R - 1 - i));
                const bit = n & needle;
                q[i] = bit != 0;
            }

            return q;
        }

        pub fn indexFromCell(q: Quadrant) N {
            var n: N = 0;
            inline for (0..R) |i| {
                if (q[i]) {
                    const needle = @as(N, 1) << (R - 1 - i);
                    n |= needle;
                }
            }

            return n;
        }

        pub const Area = struct {
            s: f32 = 0,
            c: Point = @splat(0),

            pub fn locate(area: Area, point: Point) Quadrant {
                return area.c <= point;
            }

            pub fn divide(area: Area, quadrant: Quadrant) Area {
                const s = area.s / 2;
                const d = s / 2;

                var delta: Vector = @splat(0);
                inline for (0..R) |i| {
                    delta[i] = if (quadrant[i]) d else -d;
                }

                return .{ .s = s, .c = area.c + delta };
            }

            pub fn contains(area: Area, point: Point) bool {
                const s: Vector = @splat(area.s / 2);
                const min = area.c - s;
                const max = area.c + s;
                return @reduce(.And, min <= point) and @reduce(.And, point <= max);
            }
        };

        pub const Body = packed struct {
            position: Point = @splat(0),
            mass: Mass = 0,
        };

        pub const Node = struct {
            pub const NULL = std.math.maxInt(u32);

            body: Body,
            children: [fanout]u32 = .{NULL} ** fanout,

            pub inline fn isEmpty(node: Node) bool {
                inline for (node.children) |child| {
                    if (child != NULL) {
                        return false;
                    }
                }

                return true;
            }

            pub inline fn getQuadrant(node: Node, quadrant: Quadrant) u32 {
                const i = indexFromCell(quadrant);
                return node.children[i];
            }

            pub inline fn setQuadrant(node: *Node, quadrant: Quadrant, child: u32) void {
                const i = indexFromCell(quadrant);
                node.children[i] = child;
            }

            pub fn add(node: *Node, body: Body) void {
                var node_mass: Vector = @splat(0);
                var point_mass: Vector = @splat(0);

                switch (@typeInfo(Mass)) {
                    .Int => {
                        inline for (0..R) |i| {
                            node_mass[i] = @floatFromInt(node.body.mass);
                            point_mass[i] = @floatFromInt(body.mass);
                        }
                    },
                    .Float => {
                        inline for (0..R) |i| {
                            node_mass[i] = @floatCast(node.body.mass);
                            point_mass[i] = @floatCast(body.mass);
                        }
                    },
                    else => @compileError("Mass must be an integer or float type"),
                }

                const total_mass = node_mass + point_mass;
                node.body.position = (node.body.position * node_mass + body.position * point_mass) / total_mass;
                node.body.mass += body.mass;
            }

            pub fn remove(node: *Node, body: Body) void {
                var total_mass: Vector = @splat(0);
                var point_mass: Vector = @splat(0);

                switch (@typeInfo(Mass)) {
                    .Int => {
                        inline for (0..R) |i| {
                            total_mass[i] = @floatFromInt(node.body.mass);
                            point_mass[i] = @floatFromInt(body.mass);
                        }
                    },
                    .Float => {
                        inline for (0..R) |i| {
                            total_mass[i] = @floatCast(node.body.mass);
                            point_mass[i] = @floatCast(body.mass);
                        }
                    },
                    else => @compileError("Mass must be an integer or float type"),
                }

                const node_mass = total_mass - point_mass;
                node.body.position = (node.body.position * node_mass - body.position * point_mass) / total_mass;
                node.body.mass -= body.mass;
            }
        };

        area: Area,
        tree: std.ArrayList(Node),
        threshold: f32 = 0.5,

        pub fn init(allocator: std.mem.Allocator, area: Area) Self {
            return .{ .tree = std.ArrayList(Node).init(allocator), .area = area };
        }

        pub fn deinit(self: Self) void {
            self.tree.deinit();
        }

        pub fn reset(self: *Self, area: Area) void {
            self.area = area;
            self.tree.clearRetainingCapacity();
        }

        pub fn insert(self: *Self, body: Body) Error!void {
            if (self.tree.items.len == 0) {
                try self.tree.append(Node{ .body = body });
            } else {
                if (self.area.s == 0) {
                    return Error.InvalidArea;
                }

                try self.insertNode(0, self.area, body);
            }
        }

        fn insertNode(self: *Self, id: u32, area: Area, body: Body) Error!void {
            if (id >= self.tree.items.len) {
                return Error.NotFound;
            }

            if (area.s == 0) {
                return Error.InvalidArea;
            }

            if (self.tree.items[id].isEmpty()) {
                const node = self.tree.items[id];

                const index: u32 = @intCast(self.tree.items.len);
                try self.tree.append(node);

                self.tree.items[id].setQuadrant(area.locate(node.body.position), index);
            }

            self.tree.items[id].add(body);

            const quadrant = area.locate(body.position);
            const child = self.tree.items[id].getQuadrant(quadrant);

            if (child != Node.NULL) {
                const center = self.tree.items[child].body.position;
                if (@reduce(.And, center == body.position)) {
                    self.tree.items[child].body.mass += body.mass;
                    return;
                }

                try self.insertNode(child, area.divide(quadrant), body);
            } else {
                const index: u32 = @intCast(self.tree.items.len);
                try self.tree.append(.{ .body = body });
                self.tree.items[id].setQuadrant(quadrant, index);
            }
        }

        pub fn remove(self: *Self, body: Body) Error!void {
            if (self.tree.items.len == 0) {
                return Error.Empty;
            }

            const remove_root = try self.removeNode(0, self.area, body);
            if (remove_root) {
                self.tree.clearRetainingCapacity();
            }
        }

        fn removeNode(self: *Self, id: u32, area: Area, body: Body) Error!bool {
            if (id >= self.tree.items.len) {
                return Error.NotFound;
            }

            if (area.s == 0) {
                return Error.InvalidArea;
            }

            if (self.tree.items[id].isEmpty()) {
                if (self.tree.items[id].body.mass < body.mass) {
                    return Error.InvalidMass;
                }

                return true;
            }

            const quadrant = area.locate(body.position);
            const child = self.tree.items[id].getQuadrant(quadrant);
            const remove_child = try self.removeNode(child, area.divide(quadrant), body);
            if (remove_child) {
                self.tree.items[id].setQuadrant(quadrant, Node.NULL);
            }

            self.tree.items[id].remove(body);
            if (self.tree.items[id].isEmpty()) {
                return true;
            }

            return false;
        }

        pub fn getTotalMass(self: Self) Mass {
            if (self.tree.items.len == 0) {
                return 0;
            } else {
                return self.tree.items[0].body.mass;
            }
        }

        pub fn getForce(self: Self, params: *const Params, body: Body) !Vector {
            if (self.tree.items.len == 0) {
                return @as(Vector, @splat(0));
            } else {
                return try self.getForceNode(params, 0, self.area.s, body);
            }
        }

        fn getForceNode(self: Self, params: *const Params, id: u32, s: f32, body: Body) !Vector {
            if (id >= self.tree.items.len) {
                return Error.NotFound;
            }

            const node = self.tree.items[id];
            if (node.isEmpty()) {
                return params.getRepulsion(body.position, body.mass, node.body.position, node.body.mass);
            }

            const delta = node.body.position - body.position;
            const norm = @reduce(.Add, delta * delta);
            const d = std.math.sqrt(norm);

            if (s / d < self.threshold) {
                return params.getRepulsion(body.position, body.mass, node.body.position, node.body.mass);
            }

            var f: Vector = @splat(0);
            inline for (node.children) |child| {
                if (child != Node.NULL) {
                    f += try self.getForceNode(params, child, s / 2, body);
                }
            }

            return f;
        }

        pub fn print(self: *Self, log: std.fs.File.Writer) !void {
            try self.printNode(log, 0, 1);
        }

        fn printNode(self: *Self, log: std.fs.File.Writer, id: u32, depth: usize) !void {
            if (id >= self.tree.items.len) {
                return Error.NotFound;
            }

            const node = self.tree.items[id];
            if (node.isEmpty()) {
                try log.print("leaf {d} (mass {d})\n", .{ id, node.body.mass });
            } else {
                try log.print("node {d} (mass {d})\n", .{ id, node.body.mass });
                inline for (0..fanout) |i| {
                    try log.writeByteNTimes(' ', depth * 2);
                    try log.print("{b:0>2}: ", .{i});
                    if (node.children[i] == Node.NULL) {
                        try log.print("leaf {d} (mass {d})\n", .{ id, node.body.mass });
                    } else {
                        try self.printNode(log, node.children[i], depth + 1);
                    }
                }
            }
        }
    };
}

test "cellFromIndex / indexFromCell" {
    const Tree = RTree(2, f32);

    inline for (0..Tree.fanout) |i| {
        const cell = Tree.cellFromIndex(i);
        try std.testing.expectEqual(i, Tree.indexFromCell(cell));
    }
}

test "create RTree(3, f32)" {
    const s: f32 = 8192;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var prng = std.Random.Xoshiro256.init(0);
    const random = prng.random();

    const Tree = RTree(3, u32);

    var rtree = Tree.init(allocator, .{ .s = s });
    defer rtree.deinit();

    var bodies = std.ArrayList(Tree.Body).init(allocator);
    defer bodies.deinit();

    var total_mass: u32 = 0;

    const count = 10000;
    for (0..count) |_| {
        const x = (random.float(f32) - 0.5) * s;
        const y = (random.float(f32) - 0.5) * s;
        const z = (random.float(f32) - 0.5) * s;

        const mass = random.uintLessThan(u32, 256) + 1;

        try rtree.insert(.{ .position = .{ x, y, z }, .mass = mass });
        try bodies.append(.{ .position = .{ x, y, z }, .mass = mass });

        total_mass += mass;
        try std.testing.expectEqual(rtree.tree.items[0].body.mass, total_mass);
    }

    for (bodies.items) |body| {
        try rtree.remove(body);
        total_mass -= body.mass;
        try std.testing.expectEqual(rtree.getTotalMass(), total_mass);
    }
}

test "compare RTree(2) with Quadtree" {
    const s: f32 = 8192;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var prng = std.Random.Xoshiro256.init(0);
    const random = prng.random();

    var quadtree = Quadtree.init(allocator, .{ .s = s });
    defer quadtree.deinit();

    const Tree = RTree(2, f32);

    var rtree = Tree.init(allocator, .{ .s = s });
    defer rtree.deinit();

    var bodies = std.ArrayList(Tree.Body).init(allocator);
    defer bodies.deinit();

    var total_mass: f32 = 0;

    const count = 10000;
    for (0..count) |_| {
        const x = (random.float(f32) - 0.5) * s;
        const y = (random.float(f32) - 0.5) * s;
        const mass: f32 = @floatFromInt(1 + random.uintLessThan(u32, 256));

        try quadtree.insert(.{ x, y }, mass);
        try rtree.insert(.{ .position = .{ x, y }, .mass = mass });
        try bodies.append(.{ .position = .{ x, y }, .mass = mass });

        total_mass += mass;
        try std.testing.expectEqual(quadtree.getTotalMass(), total_mass);
        try std.testing.expectEqual(rtree.getTotalMass(), total_mass);
    }

    const params = Params{};

    for (0..10000) |_| {
        const x = (random.float(f32) - 0.5) * s;
        const y = (random.float(f32) - 0.5) * s;
        const mass: f32 = @floatFromInt(1 + random.uintLessThan(u32, 256));

        try std.testing.expectEqual(
            quadtree.getForce(&params, .{ x, y }, mass),
            try rtree.getForce(&params, .{ .position = .{ x, y }, .mass = mass }),
        );
    }

    for (bodies.items) |body| {
        try quadtree.remove(body.position, body.mass);
        try rtree.remove(body);
        total_mass -= body.mass;
        try std.testing.expectEqual(quadtree.getTotalMass(), total_mass);
        try std.testing.expectEqual(rtree.getTotalMass(), total_mass);
    }
}
