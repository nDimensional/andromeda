const std = @import("std");

const Quadtree = @import("Quadtree.zig");
const Store = @import("Store.zig");

const forces = @import("forces.zig");
const Point = forces.Point;
const Force = forces.Force;

const Engine = @This();
const SHM_NAME = "ANDROMEDA";

const node_pool_size = 16;
const edge_pool_size = 16;

allocator: std.mem.Allocator,
prng: std.rand.Xoshiro256,
timer: std.time.Timer,
store: *const Store,
quads: [4]Quadtree,
node_forces: []Force,
edge_forces: [edge_pool_size][]Force,

count: u64 = 0,
min_y: f32 = 0,
max_y: f32 = 0,
min_x: f32 = 0,
max_x: f32 = 0,

attraction: f32,
repulsion: f32,
temperature: f32,

pub fn init(allocator: std.mem.Allocator, store: *const Store) !*Engine {
    const area = Quadtree.Area{};

    const self = try allocator.create(Engine);
    self.allocator = allocator;
    self.prng = std.rand.Xoshiro256.init(0);
    self.store = store;
    self.timer = try std.time.Timer.start();

    for (0..self.quads.len) |i| {
        const q = @as(u2, @intCast(i));
        self.quads[i] = Quadtree.init(allocator, area.divide(@enumFromInt(q)));
    }

    self.node_forces = try allocator.alloc(Force, store.node_count);
    for (self.node_forces) |*f| f.* = .{ 0, 0 };

    for (0..edge_pool_size) |i| {
        self.edge_forces[i] = try allocator.alloc(Force, store.node_count);
        for (self.edge_forces[i]) |*f| f.* = .{ 0, 0 };
    }

    self.count = 0;
    self.min_x = 0;
    self.max_x = 0;
    self.min_y = 0;
    self.max_y = 0;

    // self.attraction = 1.0;
    // self.repulsion = 1.0;
    // self.temperature = 10.0;
    self.attraction = 0.0001;
    self.repulsion = 100.0;
    self.temperature = 0.1;

    for (store.positions) |p| {
        self.min_x = @min(self.min_x, p[0]);
        self.max_x = @max(self.max_x, p[0]);
        self.min_y = @min(self.min_y, p[1]);
        self.max_y = @max(self.max_y, p[1]);
    }

    return self;
}

pub fn deinit(self: *const Engine) void {
    inline for (self.quads) |q| q.deinit();

    self.allocator.free(self.node_forces);
    inline for (self.edge_forces) |edge_forces| {
        self.allocator.free(edge_forces);
    }

    self.allocator.destroy(self);
}

pub fn getBoundingSize(self: Engine) !f32 {
    const s = @max(@abs(self.min_x), @abs(self.max_x), @abs(self.min_y), @abs(self.max_y)) * 2;
    return std.math.pow(f32, 2, @ceil(@log2(s)));
}

pub fn randomize(self: *Engine, s: f32) void {
    var random = self.prng.random();
    for (0..self.store.node_count) |i| {
        const p = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.store.node_count));

        // var x: f32 = @floatFromInt(random.uintLessThan(u32, s));
        // x -= @floatFromInt(s / 2);
        var x = s * random.float(f32);
        x -= s / 2;
        x += p;

        // var y: f32 = @floatFromInt(random.uintLessThan(u32, s));
        // y -= @floatFromInt(s / 2);
        var y = s * random.float(f32);
        y -= s / 2;
        y += p;

        self.store.positions[i] = .{ x, y };
    }

    self.count += 1;
}

pub fn tick(self: *Engine) !f32 {
    self.timer.reset();

    std.log.info("tick: attraction = {d}, repulsion = {d}, temperature = {d}", .{self.attraction, self.repulsion, self.temperature});

    {
        const s = try self.getBoundingSize();
        const area = Quadtree.Area{ .s = s };

        var pool: [4]std.Thread = undefined;
        for (0..4) |i| {
            const tree = &self.quads[i];
            tree.reset(area.divide(@enumFromInt(i)));
            pool[i] = try std.Thread.spawn(.{}, rebuildQuad, .{ self, tree });
        }

        for (0..4) |i| pool[i].join();

        // std.log.info("rebuilt quadtree in {d}ms", .{self.timer.lap() / 1_000_000});
    }

    {
        const node_count = self.store.node_count;
        var pool: [node_pool_size]std.Thread = undefined;
        for (0..node_pool_size) |i| {
            const min = i * node_count / node_pool_size;
            const max = (i + 1) * node_count / node_pool_size;
            pool[i] = try std.Thread.spawn(.{}, updateNodeForces, .{ self, min, max, self.node_forces });
        }

        for (0..node_pool_size) |i| pool[i].join();

        // std.log.info("applied node forces in {d}ms", .{self.timer.lap() / 1_000_000});
    }

    {
        const edge_count = self.store.edge_count;
        var pool: [edge_pool_size]std.Thread = undefined;
        for (0..edge_pool_size) |i| {
            const min = i * edge_count / edge_pool_size;
            const max = (i + 1) * edge_count / edge_pool_size;
            pool[i] = try std.Thread.spawn(.{}, updateEdgeForces, .{ self, min, max, self.edge_forces[i] });
        }

        for (0..edge_pool_size) |i| pool[i].join();

        // std.log.info("applied edge forces in {d}ms", .{self.timer.lap() / 1_000_000});
    }

    self.min_x = 0;
    self.max_x = 0;
    self.min_y = 0;
    self.max_y = 0;

    const temperature: Force = @splat(self.temperature);

    var sum: f32 = 0;
    for (0..self.store.node_count) |i| {
        var f = self.node_forces[i];
        inline for (self.edge_forces) |edge_forces| f += edge_forces[i];

        sum += std.math.sqrt(@reduce(.Add, f * f));

        f *= temperature;

        const p = self.store.positions[i] + f;
        self.store.positions[i] = p;

        self.min_x = @min(self.min_x, p[0]);
        self.max_x = @max(self.max_x, p[0]);
        self.min_y = @min(self.min_y, p[1]);
        self.max_y = @max(self.max_y, p[1]);

        self.node_forces[i] = .{ 0, 0 };
        inline for (self.edge_forces) |edge_forces| edge_forces[i] = .{ 0, 0 };
    }

    self.count += 1;
    return sum / @as(f32, @floatFromInt(self.store.node_count));
}

fn updateEdgeForces(self: *Engine, min: usize, max: usize, force: []Force) void {
    for (min..max) |i| {
        if (i >= self.store.edge_count) {
            break;
        }

        const s = self.store.source[i] - 1;
        const t = self.store.target[i] - 1;
        const f = forces.getAttraction(self.attraction, self.store.positions[s], self.store.positions[t]);

        force[s] += f;
        force[t] -= f;
    }
}

fn updateNodeForces(self: *Engine, min: usize, max: usize, node_forces: []Force) void {
    for (min..max) |i| {
        if (i >= self.store.node_count) {
            break;
        }

        const p = self.store.positions[i];
        const mass = forces.getMass(self.store.z[i]);

        for (self.quads) |tree| {
            node_forces[i] += tree.getForce(self.repulsion, p, mass);
        }
    }
}

pub fn rebuildQuad(self: *Engine, tree: *Quadtree) !void {
    // var timer = try std.time.Timer.start();

    var i: u32 = 0;
    while (i < self.store.node_count) : (i += 1) {
        const p = self.store.positions[i];
        if (tree.area.contains(p)) {
            const mass = forces.getMass(self.store.z[i]);
            try tree.insert(i + 1, p, mass);
        }
    }

    // std.log.info("rebuildQuad in {d}ms ({d} nodes)", .{ timer.read() / 1_000_000, tree.tree.items.len });
}

fn getNodeForce(self: *Engine, p: Point, mass: f32) Force {
    var force = Force{ 0, 0 };
    for (0..self.store.node_count) |i| {
        force += forces.getRepulsion(self.store.repulsion, p, mass, self.store.positions[i], forces.getMass(self.store.z[i]));
    }

    return force;
}
