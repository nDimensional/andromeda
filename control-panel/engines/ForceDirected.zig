const std = @import("std");

const Quadtree = @import("../Quadtree.zig");
const Graph = @import("../Graph.zig");

const Params = @import("../Params.zig");

const Engine = @This();

const node_pool_size = 15;
const edge_pool_size = 15;

var energy_pool: [node_pool_size]f32 = undefined;
var min_x_pool: [node_pool_size]f32 = undefined;
var max_x_pool: [node_pool_size]f32 = undefined;
var min_y_pool: [node_pool_size]f32 = undefined;
var max_y_pool: [node_pool_size]f32 = undefined;

allocator: std.mem.Allocator,
timer: std.time.Timer,
graph: *const Graph,
quads: [4]Quadtree,
node_forces: []Params.Force,
edge_forces: [edge_pool_size][]Params.Force,

count: u64 = 0,
min_y: f32 = 0,
max_y: f32 = 0,
min_x: f32 = 0,
max_x: f32 = 0,

params: *const Params,

pub fn init(allocator: std.mem.Allocator, graph: *const Graph, params: *const Params) !*Engine {
    const area = Quadtree.Area{};

    const self = try allocator.create(Engine);
    self.allocator = allocator;
    self.graph = graph;
    self.params = params;
    self.timer = try std.time.Timer.start();

    for (0..self.quads.len) |i| {
        const q = @as(u2, @intCast(i));
        self.quads[i] = Quadtree.init(allocator, area.divide(@enumFromInt(q)));
    }

    self.node_forces = try allocator.alloc(Params.Force, graph.node_count);
    for (self.node_forces) |*f| f.* = .{ 0, 0 };

    for (0..edge_pool_size) |i| {
        self.edge_forces[i] = try allocator.alloc(Params.Force, graph.node_count);
        for (self.edge_forces[i]) |*f| f.* = .{ 0, 0 };
    }

    self.count = 0;
    self.min_x = 0;
    self.max_x = 0;
    self.min_y = 0;
    self.max_y = 0;

    for (graph.positions) |p| {
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

    const node_count = self.graph.node_count;
    var pool: [node_pool_size]std.Thread = undefined;
    for (0..node_pool_size) |pool_i| {
        const min = pool_i * node_count / node_pool_size;
        const max = (pool_i + 1) * node_count / node_pool_size;
        pool[pool_i] = try std.Thread.spawn(.{}, updateNodes, .{ self, min, max, pool_i });
    }

    for (0..node_pool_size) |i| pool[i].join();

    std.log.info("updated node forces in {d}ms", .{self.timer.lap() / 1_000_000});

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

    const energy = sum / @as(f32, @floatFromInt(self.graph.node_count));
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
    while (i < self.graph.node_count) : (i += 1) {
        const p = self.graph.positions[i];
        if (tree.area.contains(p)) {
            const mass = self.params.getMass(self.graph.z[i]);
            try tree.insert(p, mass);
        }
    }
}

fn updateNodes(self: *Engine, min: usize, max: usize, pool_i: usize) void {
    const temperature: Params.Force = @splat(self.params.temperature);
    const center: Params.Force = @splat(self.params.center);

    min_x_pool[pool_i] = 0;
    max_x_pool[pool_i] = 0;
    min_y_pool[pool_i] = 0;
    max_y_pool[pool_i] = 0;

    var sum: f32 = 0;
    for (min..max) |i| {
        if (i >= self.graph.node_count) {
            break;
        }

        const mass = self.params.getMass(self.graph.z[i]);
        var p = self.graph.positions[i];

        var f: @Vector(2, f32) = .{ 0, 0 };

        for (self.graph.outgoing_edges[i].items) |j|
            f += self.params.getAttraction(p, self.graph.positions[j]);

        for (self.graph.incoming_edges[i].items) |j|
            f += self.params.getAttraction(p, self.graph.positions[j]);

        for (self.quads) |tree|
            f += tree.getForce(self.params, p, mass);

        f += center * self.params.getAttraction(p, .{ 0, 0 });

        p += temperature * f;
        self.graph.positions[i] = p;

        min_x_pool[pool_i] = @min(min_x_pool[pool_i], p[0]);
        max_x_pool[pool_i] = @max(max_x_pool[pool_i], p[0]);
        min_y_pool[pool_i] = @min(min_y_pool[pool_i], p[1]);
        max_y_pool[pool_i] = @max(max_y_pool[pool_i], p[1]);

        sum += std.math.sqrt(@reduce(.Add, f * f));
    }

    energy_pool[pool_i] = sum;
}

fn getNodeForce(self: *Engine, p: Params.Point, mass: f32) Params.Force {
    var force = Params.Force{ 0, 0 };
    for (0..self.graph.node_count) |i| {
        force += self.params.getRepulsion(p, mass, self.graph.positions[i], self.params.getMass(self.graph.z[i]));
    }

    return force;
}
