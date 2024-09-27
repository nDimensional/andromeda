const std = @import("std");

const Quadtree = @import("../Quadtree.zig");
const Store = @import("../Store.zig");

const Params = @import("../Params.zig");

const Engine = @This();

const table_size = 16384;

const node_pool_size = 15;
const edge_pool_size = 15;

var energy_pool: [node_pool_size]f32 = undefined;
var min_x_pool: [node_pool_size]f32 = undefined;
var max_x_pool: [node_pool_size]f32 = undefined;
var min_y_pool: [node_pool_size]f32 = undefined;
var max_y_pool: [node_pool_size]f32 = undefined;

allocator: std.mem.Allocator,
timer: std.time.Timer,
store: *const Store,
quads: [4]Quadtree,
outgoing_edges: []std.ArrayListUnmanaged(u32),
incoming_edges: []std.ArrayListUnmanaged(u32),

cos_table: [table_size]f32,
sin_table: [table_size]f32,
prng: std.rand.Xoshiro256,
random: std.Random,

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

    self.outgoing_edges = try allocator.alloc(std.ArrayListUnmanaged(u32), store.node_count);
    self.incoming_edges = try allocator.alloc(std.ArrayListUnmanaged(u32), store.node_count);

    for (self.outgoing_edges) |*edges| edges.* = std.ArrayListUnmanaged(u32){};
    for (self.incoming_edges) |*edges| edges.* = std.ArrayListUnmanaged(u32){};

    for (0..store.edge_count) |i| {
        const s = store.source[i] - 1;
        const t = store.target[i] - 1;
        try self.outgoing_edges[s].append(allocator, t);
        try self.outgoing_edges[t].append(allocator, s);
    }

    for (0..self.quads.len) |i| {
        const q = @as(u2, @intCast(i));
        self.quads[i] = Quadtree.init(allocator, area.divide(@enumFromInt(q)));
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

    for (0..table_size) |i| {
        const angle: f32 = std.math.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(table_size));
        self.cos_table[i] = std.math.cos(angle);
        self.sin_table[i] = std.math.sin(angle);
    }

    self.prng = std.rand.Xoshiro256.init(0);
    self.random = self.prng.random();

    try self.rebuildTrees();

    return self;
}

pub fn deinit(self: *const Engine) void {
    inline for (self.quads) |q| q.deinit();

    for (self.outgoing_edges) |*edges| edges.deinit(self.allocator);
    for (self.incoming_edges) |*edges| edges.deinit(self.allocator);
    self.allocator.free(self.outgoing_edges);
    self.allocator.free(self.incoming_edges);

    self.allocator.destroy(self);
}

pub fn getBoundingSize(self: Engine) !f32 {
    const s = @max(@abs(self.min_x), @abs(self.max_x), @abs(self.min_y), @abs(self.max_y)) * 2;
    return std.math.pow(f32, 2, @ceil(@log2(s)));
}

pub fn tick(self: *Engine) !f32 {
    std.log.info("tick {d}", .{self.count});

    try self.rebuildTrees();

    var sum: f32 = 0;

    self.timer.reset();

    for (0..self.store.node_count) |i| {
        sum += try self.updateNode(i);
    }

    // {
    //     const node_count = self.store.node_count;
    //     var pool: [node_pool_size]std.Thread = undefined;
    //     for (0..node_pool_size) |i| {
    //         const min = i * node_count / node_pool_size;
    //         const max = (i + 1) * node_count / node_pool_size;
    //         pool[i] = try std.Thread.spawn(.{}, updateNodeRange, .{ self, min, max, i });
    //     }

    //     for (0..node_pool_size) |i| pool[i].join();

    //     std.log.info("updated node forces in {d}ms", .{self.timer.lap() / 1_000_000});
    // }

    std.log.info("updated all nodes in {d}ms", .{self.timer.read() / 1_000_000});

    self.min_x = 0;
    self.max_x = 0;
    self.min_y = 0;
    self.max_y = 0;

    for (self.store.positions) |p| {
        self.min_x = @min(self.min_x, p[0]);
        self.max_x = @max(self.max_x, p[0]);
        self.min_y = @min(self.min_y, p[1]);
        self.max_y = @max(self.max_y, p[1]);
    }

    self.count += 1;

    const energy = sum / @as(f32, @floatFromInt(self.store.node_count));
    std.log.info("energy: {d}", .{energy});

    return energy;
}

fn rebuildTrees(self: *Engine) !void {
    self.timer.reset();

    const s = try self.getBoundingSize();
    const area = Quadtree.Area{ .s = s };

    var pool: [4]std.Thread = undefined;
    for (0..4) |i| {
        const tree = &self.quads[i];
        tree.reset(area.divide(@enumFromInt(i)));
        pool[i] = try std.Thread.spawn(.{}, rebuildTree, .{ self, tree });
    }

    for (0..4) |i| pool[i].join();

    std.log.info("rebuilt quadtree in {d}ms", .{self.timer.read() / 1_000_000});
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

fn updateNodeRange(self: *Engine, min: usize, max: usize, bucket: usize) !void {
    var sum: f32 = 0;
    for (min..max) |i| {
        sum += try self.updateNode(i);
    }

    energy_pool[bucket] = sum;
}

fn updateNode(self: *Engine, i: usize) !f32 {
    // const idx: u32 = @intCast(i + 1);
    const a = self.store.positions[i];

    const magnitude = self.random.float(f32) * self.params.temperature;
    const angle = self.random.uintLessThan(u32, table_size);
    const delta: Params.Force = .{
        magnitude * self.cos_table[angle],
        magnitude * self.sin_table[angle],
    };

    const b = a + delta;

    const center: Params.Force = @splat(self.params.center);
    const mass_i = self.params.getMass(self.store.z[i]);

    var f_a = Params.Force{ 0, 0 };
    var f_b = Params.Force{ 0, 0 };

    for (self.quads) |tree| {
        f_a += tree.getForce(self.params, a, mass_i);
        f_b += tree.getForce(self.params, b, mass_i);
    }

    f_a += center * self.params.getAttraction(a, .{ 0, 0 });
    f_b += center * self.params.getAttraction(b, .{ 0, 0 });

    for (self.outgoing_edges[i].items) |t| {
        const p_t = self.store.positions[t];
        f_a += self.params.getAttraction(a, p_t);
        f_b += self.params.getAttraction(b, p_t);
    }

    for (self.incoming_edges[i].items) |s| {
        const p_s = self.store.positions[s];
        f_a += self.params.getAttraction(p_s, a);
        f_b += self.params.getAttraction(p_s, b);
    }

    const energy_a = @reduce(.Add, f_a * f_a);
    const energy_b = @reduce(.Add, f_b * f_b);

    switch (std.math.order(energy_a, energy_b)) {
        // .lt, .eq => {
        .gt => {
            self.store.positions[i] = a;
            return std.math.sqrt(energy_a);
        },
        // .gt => {
        .lt, .eq => {
            self.store.positions[i] = b;
            for (&self.quads) |*quad| if (quad.area.contains(a)) try quad.remove(a, mass_i);
            for (&self.quads) |*quad| if (quad.area.contains(b)) try quad.insert(b, mass_i);
            return std.math.sqrt(energy_b);
        },
    }
}
