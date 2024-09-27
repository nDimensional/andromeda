const std = @import("std");

const Quadtree = @import("../Quadtree.zig");
const Store = @import("../Store.zig");

const Params = @import("../Params.zig");

const Engine = @This();

// const node_pool_size = 15;
// const edge_pool_size = 15;
const node_pool_size = 1;
const edge_pool_size = 1;

var energy_pool: [node_pool_size]f32 = undefined;
var min_x_pool: [node_pool_size]f32 = undefined;
var max_x_pool: [node_pool_size]f32 = undefined;
var min_y_pool: [node_pool_size]f32 = undefined;
var max_y_pool: [node_pool_size]f32 = undefined;

allocator: std.mem.Allocator,
timer: std.time.Timer,
store: *const Store,
quads: [4]Quadtree,
node_forces: []Params.Force,
edge_forces: [edge_pool_size][]Params.Force,

count: u64 = 0,
min_y: f32 = 0,
max_y: f32 = 0,
min_x: f32 = 0,
max_x: f32 = 0,

params: *const Params,

pub fn init(allocator: std.mem.Allocator, store: *const Store, params: *const Params) !*Engine {
    const area = Quadtree.Area{};

    const self = try allocator.create(Engine);
    self.allocator = allocator;
    self.store = store;
    self.params = params;
    self.timer = try std.time.Timer.start();

    for (0..self.quads.len) |i| {
        const q = @as(u2, @intCast(i));
        self.quads[i] = Quadtree.init(allocator, area.divide(@enumFromInt(q)));
    }

    self.node_forces = try allocator.alloc(Params.Force, store.node_count);
    for (self.node_forces) |*f| f.* = .{ 0, 0 };

    for (0..edge_pool_size) |i| {
        self.edge_forces[i] = try allocator.alloc(Params.Force, store.node_count);
        for (self.edge_forces[i]) |*f| f.* = .{ 0, 0 };
    }

    self.count = 0;
    self.min_x = 0;
    self.max_x = 0;
    self.min_y = 0;
    self.max_y = 0;

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

pub fn tick(self: *Engine) !f32 {
    std.log.info("tick {d}", .{self.count});
    self.timer.reset();

    try self.rebuildTrees();

    {
        const edge_count = self.store.edge_count;
        var pool: [edge_pool_size]std.Thread = undefined;
        for (0..edge_pool_size) |i| {
            const min = i * edge_count / edge_pool_size;
            const max = (i + 1) * edge_count / edge_pool_size;
            pool[i] = try std.Thread.spawn(.{}, updateEdgeForces, .{ self, min, max, self.edge_forces[i] });
        }

        for (0..edge_pool_size) |i| pool[i].join();

        std.log.info("updated edge forces in {d}ms", .{self.timer.lap() / 1_000_000});
    }

    {
        const s = try self.getBoundingSize();
        const area = Quadtree.Area{ .s = s };

        var pool: [4]std.Thread = undefined;
        for (0..4) |i| {
            const tree = &self.quads[i];
            tree.reset(area.divide(@enumFromInt(i)));
            pool[i] = try std.Thread.spawn(.{}, rebuildTree, .{ self, tree });
        }

        for (0..4) |i| pool[i].join();

        std.log.info("rebuilt quadtree in {d}ms", .{self.timer.lap() / 1_000_000});
    }

    {
        const node_count = self.store.node_count;
        var pool: [node_pool_size]std.Thread = undefined;
        for (0..node_pool_size) |i| {
            const min = i * node_count / node_pool_size;
            const max = (i + 1) * node_count / node_pool_size;
            pool[i] = try std.Thread.spawn(.{}, updateNodeForces, .{ self, min, max, i });
        }

        for (0..node_pool_size) |i| pool[i].join();

        std.log.info("updated node forces in {d}ms", .{self.timer.lap() / 1_000_000});
    }

    self.min_x = 0;
    self.max_x = 0;
    self.min_y = 0;
    self.max_y = 0;

    for (min_x_pool) |x| self.min_x = @min(self.min_x, x);
    for (max_x_pool) |x| self.max_x = @max(self.max_x, x);
    for (min_y_pool) |y| self.min_y = @min(self.min_y, y);
    for (max_y_pool) |y| self.max_y = @max(self.max_y, y);

    std.log.info("applied forces in {d}ms", .{self.timer.lap() / 1_000_000});

    self.count += 1;

    var sum: f32 = 0;
    for (energy_pool) |f| sum += f;

    const energy = sum / @as(f32, @floatFromInt(self.store.node_count));
    std.log.info("energy: {d}", .{energy});

    return energy;
}

fn rebuildTrees(self: *Engine) !void {
    const s = try self.getBoundingSize();
    const area = Quadtree.Area{ .s = s };

    var pool: [4]std.Thread = undefined;
    for (0..4) |i| {
        const tree = &self.quads[i];
        tree.reset(area.divide(@enumFromInt(i)));
        pool[i] = try std.Thread.spawn(.{}, rebuildTree, .{ self, tree });
    }

    for (0..4) |i| pool[i].join();

    std.log.info("rebuilt quadtree in {d}ms", .{self.timer.lap() / 1_000_000});
}

fn rebuildTree(self: *Engine, tree: *Quadtree) !void {
    var i: u32 = 0;
    while (i < self.store.node_count) : (i += 1) {
        const p = self.store.positions[i];
        if (tree.area.contains(p)) {
            const mass = self.params.getMass(self.store.z[i]);
            try tree.insert(p, mass);
        }
    }
}

fn updateEdgeForces(self: *Engine, min: usize, max: usize, force: []Params.Force) void {
    for (min..max) |i| {
        if (i >= self.store.edge_count) {
            break;
        }

        const s = self.store.source[i] - 1;
        const t = self.store.target[i] - 1;
        const f = self.params.getAttraction(self.store.positions[s], self.store.positions[t]);

        force[s] += f;
        force[t] -= f;
    }
}

fn updateNodeForces(self: *Engine, min: usize, max: usize, bucket: usize) void {
    const temperature: Params.Force = @splat(self.params.temperature);
    const center: Params.Force = @splat(self.params.center);

    min_x_pool[bucket] = 0;
    max_x_pool[bucket] = 0;
    min_y_pool[bucket] = 0;
    max_y_pool[bucket] = 0;

    var sum: f32 = 0;
    for (min..max) |i| {
        if (i >= self.store.node_count) {
            break;
        }

        const mass = self.params.getMass(self.store.z[i]);
        var p = self.store.positions[i];

        var f: @Vector(2, f32) = .{ 0, 0 };
        inline for (self.edge_forces) |edge_forces| {
            f += edge_forces[i];
            edge_forces[i] = .{ 0, 0 };
        }

        for (self.quads) |tree| {
            f += tree.getForce(self.params, p, mass);
        }

        f += center * self.params.getAttraction(p, .{ 0, 0 });

        p += temperature * f;
        self.store.positions[i] = p;

        min_x_pool[bucket] = @min(min_x_pool[bucket], p[0]);
        max_x_pool[bucket] = @max(max_x_pool[bucket], p[0]);
        min_y_pool[bucket] = @min(min_y_pool[bucket], p[1]);
        max_y_pool[bucket] = @max(max_y_pool[bucket], p[1]);

        sum += std.math.sqrt(@reduce(.Add, f * f));
    }

    energy_pool[bucket] = sum;
}

fn getNodeForce(self: *Engine, p: Params.Point, mass: f32) Params.Force {
    var force = Params.Force{ 0, 0 };
    for (0..self.store.node_count) |i| {
        force += self.params.getRepulsion(p, mass, self.store.positions[i], self.params.getMass(self.store.z[i]));
    }

    return force;
}
