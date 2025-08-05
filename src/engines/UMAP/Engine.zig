const std = @import("std");

const quadtree = @import("../../quadtree.zig");
const Quadtree = quadtree.Quadtree;
const Area = quadtree.Area;

const Params = @import("../../Params.zig");
const Graph = @import("../../Graph.zig");
const utils = @import("../../utils.zig");

const forces = @import("./forces.zig");

const Engine = @This();

const Stats = struct {
    energy: f32 = 0,
    min_x: f32 = 0,
    max_x: f32 = 0,
    min_y: f32 = 0,
    max_y: f32 = 0,
};

const free_threads = 1;

allocator: std.mem.Allocator,
timer: std.time.Timer,
graph: *const Graph,
trees: [4]Quadtree,
node_forces: []Params.Force,

pool_size: usize,
thread_pool: []std.Thread,
stats_pool: []Stats,

tick_count: u64,

stats: Stats,

params: *const Params,

pub fn init(allocator: std.mem.Allocator, graph: *const Graph, params: *const Params) !*Engine {
    const area = Area{};

    const self = try allocator.create(Engine);
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.graph = graph;
    self.params = params;
    self.timer = try std.time.Timer.start();

    const cpu_count = try std.Thread.getCpuCount();
    self.pool_size = @max(1 + free_threads, cpu_count) - free_threads;

    self.thread_pool = try allocator.alloc(std.Thread, self.pool_size);
    errdefer allocator.free(self.thread_pool);

    self.stats_pool = try allocator.alloc(Stats, self.pool_size);
    errdefer allocator.free(self.stats_pool);

    for (0..self.trees.len) |i| {
        const q = @as(u2, @intCast(i));
        self.trees[i] = Quadtree.init(allocator, area.divide(@enumFromInt(q)));
    }

    self.node_forces = try allocator.alloc(Params.Force, graph.node_count);
    errdefer allocator.free(self.node_forces);
    for (self.node_forces) |*f| f.* = @splat(0);

    self.tick_count = 0;
    self.stats = Stats{};

    for (graph.positions) |p| {
        self.stats.min_x = @min(self.stats.min_x, p[0]);
        self.stats.max_x = @max(self.stats.max_x, p[0]);
        self.stats.min_y = @min(self.stats.min_y, p[1]);
        self.stats.max_y = @max(self.stats.max_y, p[1]);
    }

    return self;
}

pub fn deinit(self: *const Engine) void {
    inline for (self.trees) |q| q.deinit();
    self.allocator.free(self.node_forces);
    self.allocator.free(self.thread_pool);
    self.allocator.free(self.stats_pool);
    self.allocator.destroy(self);
}

pub fn getBoundingSize(self: Engine) !f32 {
    const max = @max(
        @abs(self.stats.min_x),
        @abs(self.stats.max_x),
        @abs(self.stats.min_y),
        @abs(self.stats.max_y),
    );
    const s = max * 2;
    return std.math.pow(f32, 2, @ceil(@log2(s)));
}

pub fn tick(self: *Engine) !u64 {
    std.log.info("tick {d}", .{self.tick_count});
    self.timer.reset();

    try self.rebuildTrees();

    const node_count = self.graph.node_count;
    for (0..self.pool_size) |pool_i| {
        const min = pool_i * node_count / self.pool_size;
        const max = (pool_i + 1) * node_count / self.pool_size;
        self.thread_pool[pool_i] = try std.Thread.spawn(.{}, updateNodes, .{ self, min, max, &self.stats_pool[pool_i] });
    }

    for (0..self.pool_size) |i| self.thread_pool[i].join();

    std.log.info("updated node forces in {d}ms", .{self.timer.lap() / 1_000_000});

    self.stats = Stats{};

    for (self.stats_pool) |stats| {
        self.stats.min_x = @min(self.stats.min_x, stats.min_x);
        self.stats.max_x = @max(self.stats.max_x, stats.max_x);
        self.stats.min_y = @min(self.stats.min_y, stats.min_y);
        self.stats.max_y = @max(self.stats.max_y, stats.max_y);
        self.stats.energy += stats.energy;
    }

    std.log.info("applied forces in {d}ms", .{self.timer.lap() / 1_000_000});

    const total: f32 = @floatFromInt(self.graph.node_count);

    std.log.info("energy: {d}", .{self.stats.energy / total});

    self.tick_count += 1;
    return self.tick_count;
}

fn rebuildTrees(self: *Engine) !void {
    const s = try self.getBoundingSize();
    const area = Area{ .s = s };

    var pool: [4]std.Thread = undefined;
    for (0..4) |i| {
        const tree = &self.trees[i];
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
        if (tree.area.contains(p))
            try tree.insert(p, 1.0);
    }
}

fn updateNodes(self: *Engine, min: usize, max: usize, stats: *Stats) !void {
    const temperature = self.params.temperature;
    const attraction = self.params.attraction;
    const repulsion = self.params.repulsion;

    const center: @Vector(2, f32) = @splat(-self.params.center);

    stats.min_x = 0;
    stats.max_x = 0;
    stats.min_y = 0;
    stats.max_y = 0;
    stats.energy = 0;

    for (min..max) |i| {
        if (i >= self.graph.node_count)
            break;

        var p = self.graph.positions[i];

        var f: @Vector(2, f32) = .{ 0, 0 };

        for (self.graph.outgoing_edges[i].items) |edge| {
            const t = self.graph.positions[edge.target];
            f += forces.getAttraction(repulsion, attraction, p, t, edge.weight);
        }

        for (self.graph.incoming_edges[i].items) |edge| {
            const s = self.graph.positions[edge.source];
            f += forces.getAttraction(repulsion, attraction, p, s, edge.weight);
        }

        for (&self.trees) |*tree|
            f += forces.getRepulsion(repulsion, tree, .{ .position = p, .mass = 1.0 });

        f += center * p;
        self.node_forces[i] = f;

        {
            p += @as(@Vector(2, f32), @splat(temperature)) * f;
            self.graph.positions[i] = p;
        }

        {
            // const magnitude = utils.norm(f);
            // if (magnitude > 10_000)
            //     f /= @splat(magnitude - 10_000);

            // const swing = utils.norm(self.node_forces[i] - f);
            // self.node_forces[i] = f;

            // const k_s = 100;
            // const s_g = temperature;
            // const speed = k_s * s_g / (1 + s_g * @sqrt(swing));

            // p += @as(@Vector(2, f32), @splat(speed * temperature)) * f;
            // self.graph.positions[i] = p;
        }

        stats.min_x = @min(stats.min_x, p[0]);
        stats.max_x = @max(stats.max_x, p[0]);
        stats.min_y = @min(stats.min_y, p[1]);
        stats.max_y = @max(stats.max_y, p[1]);
        stats.energy += utils.norm(f);
    }
}
