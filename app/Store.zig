const std = @import("std");

const sqlite = @import("sqlite");

// const ul = @import("ul");
// const Context = ul.JavaScriptCore.Context;

const Quadtree = @import("Quadtree.zig");
const forces = @import("forces.zig");

const Store = @This();

const UpdateParams = struct { x: f32, ey: f32, idx: u32 };
pub const AreaParams = struct { minX: f32, maxX: f32, minY: f32, maxY: f32, minZ: f32 };
pub const AreaResult = struct { idx: u32 };

pub const Count = struct { count: usize };

const node_pool_size = 16;
const edge_pool_size = 16;

allocator: std.mem.Allocator,
prng: std.rand.Xoshiro256 = std.rand.Xoshiro256.init(0),
db: sqlite.Database,

update: sqlite.Statement(UpdateParams, void),
select_ids: sqlite.Statement(AreaParams, AreaResult),
ids: std.ArrayList(u32),

node_count: usize = 0,
edge_count: usize = 0,

source: []u32 = undefined,
target: []u32 = undefined,
positions: []@Vector(2, f32) = undefined,
// x: []f32 = undefined,
// y: []f32 = undefined,
z: []f32 = undefined,

min_y: f32 = 0,
max_y: f32 = 0,
min_x: f32 = 0,
max_x: f32 = 0,

node_forces: []@Vector(2, f32) = undefined,
edge_forces: [edge_pool_size][]@Vector(2, f32) = undefined,

quads: [4]Quadtree = undefined,

attraction: f32 = 0.0001,
repulsion: f32 = 100.0,
temperature: f32 = 0.1,

timer: std.time.Timer,

pub fn init(allocator: std.mem.Allocator, path: [*:0]const u8) !Store {
    const db = try sqlite.Database.open(.{ .path = path, .create = false });

    const update = try db.prepare(UpdateParams, void,
        \\ UPDATE atlas SET minX = :x, maxX = :x, minY = :y, maxY = :y WHERE idx = :idx
    );

    const select_ids = try db.prepare(AreaParams, AreaResult,
        \\ SELECT idx FROM atlas WHERE :minX <= minX AND maxX <= :maxX AND :minY <= minY AND maxY <= :maxY AND :minZ <= minZ
    );

    const area = Quadtree.Area{};

    var store = Store{
        .allocator = allocator,
        .db = db,

        .update = update,
        .select_ids = select_ids,
        .ids = std.ArrayList(u32).init(allocator),
        .timer = try std.time.Timer.start(),
    };

    for (0..store.quads.len) |i| {
        const q = @as(u2, @intCast(i));
        store.quads[i] = Quadtree.init(allocator, area.divide(@enumFromInt(q)));
    }

    {
        const count_edges = try store.db.prepare(struct {}, Count, "SELECT count(*) as count FROM edges");
        defer count_edges.finalize();

        try count_edges.bind(.{});
        if (try count_edges.step()) |result| {
            store.edge_count = result.count;
        }
    }

    store.source = try allocator.alloc(u32, store.edge_count);
    store.target = try allocator.alloc(u32, store.edge_count);

    {
        const Edge = struct { source: u32, target: u32 };
        const select_edges = try store.db.prepare(struct {}, Edge, "SELECT source, target FROM edges");
        defer select_edges.finalize();

        try select_edges.bind(.{});
        defer select_edges.reset();

        var i: usize = 0;
        while (try select_edges.step()) |edge| : (i += 1) {
            store.source[i] = edge.source;
            store.target[i] = edge.target;
        }
    }

    {
        const count_nodes = try store.db.prepare(struct {}, Count, "SELECT count(*) as count FROM nodes");
        defer count_nodes.finalize();

        try count_nodes.bind(.{});
        defer count_nodes.reset();

        if (try count_nodes.step()) |result| {
            store.node_count = result.count;
        }
    }

    // store.x = try allocator.alloc(f32, store.node_count);
    // store.y = try allocator.alloc(f32, store.node_count);
    store.positions = try allocator.alloc(@Vector(2, f32), store.node_count);
    store.z = try allocator.alloc(f32, store.node_count);

    {
        const Node = struct { idx: u32, x: f32, y: f32, incoming_degree: f32 };
        const select_nodes = try store.db.prepare(struct {}, Node,
            \\ SELECT idx, minX AS x, minY AS y, minZ AS incoming_degree FROM atlas
        );
        defer select_nodes.finalize();

        try select_nodes.bind(.{});
        defer select_nodes.reset();
        while (try select_nodes.step()) |node| {
            const i = node.idx - 1;
            // store.x[i] = node.x;
            // store.y[i] = node.y;
            store.positions[i] = .{node.x, node.y};
            store.z[i] = node.incoming_degree;

            store.min_x = @min(store.min_x, node.x);
            store.max_x = @max(store.max_x, node.x);
            store.min_y = @min(store.min_y, node.y);
            store.max_y = @max(store.max_y, node.y);
        }
    }

    store.node_forces = try allocator.alloc(@Vector(2, f32), store.node_count);
    for (store.node_forces) |*f| f.* = .{ 0, 0 };

    for (0..edge_pool_size) |i| {
        store.edge_forces[i] = try allocator.alloc(@Vector(2, f32), store.node_count);
        for (store.edge_forces[i]) |*f| f.* = .{ 0, 0 };
    }

    return store;
}

pub fn deinit(self: Store) void {
    self.update.finalize();
    self.select_ids.finalize();
    self.db.close();

    self.ids.deinit();

    inline for (self.quads) |q| q.deinit();

    self.allocator.free(self.source);
    self.allocator.free(self.target);
    // self.allocator.free(self.x);
    // self.allocator.free(self.y);
    self.allocator.free(self.positions);
    self.allocator.free(self.z);

    self.allocator.free(self.node_forces);
    inline for (self.edge_forces) |edge_forces| self.allocator.free(edge_forces);
}

// pub fn inject(self: *Store, ctx: Context) !void {
//     const global = ctx.getGlobal();

//     ctx.setProperty(global, "node_count", ctx.makeNumber(@floatFromInt(self.node_count)));
//     ctx.setProperty(global, "edge_count", ctx.makeNumber(@floatFromInt(self.edge_count)));

//     ctx.setProperty(global, "source", try ctx.makeTypedArray(u32, self.source));
//     ctx.setProperty(global, "target", try ctx.makeTypedArray(u32, self.target));
//     ctx.setProperty(global, "x", try ctx.makeTypedArray(f32, self.x));
//     ctx.setProperty(global, "y", try ctx.makeTypedArray(f32, self.y));
//     ctx.setProperty(global, "z", try ctx.makeTypedArray(f32, self.z));

//     ctx.setProperty(global, "attraction", ctx.makeNumber(self.attraction));
//     ctx.setProperty(global, "repulsion", ctx.makeNumber(self.repulsion));
//     ctx.setProperty(global, "temperature", ctx.makeNumber(self.temperature));
// }

pub fn getBoundingSize(self: Store) !f32 {
    const s = @max(@abs(self.min_x), @abs(self.max_x), @abs(self.min_y), @abs(self.max_y)) * 2;
    return std.math.pow(f32, 2, @ceil(@log2(s)));
}

pub fn randomize(self: *Store, s: u32) void {
    var random = self.prng.random();
    for (0..self.node_count) |i| {
        const p = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.node_count));

        self.x[i] = @floatFromInt(random.uintLessThan(u32, s));
        self.x[i] -= @floatFromInt(s / 2);
        self.x[i] += p;

        self.y[i] = @floatFromInt(random.uintLessThan(u32, s));
        self.y[i] -= @floatFromInt(s / 2);
        self.y[i] += p;
    }
}

pub fn tick(self: *Store) !f32 {
    self.timer.reset();

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

        std.log.info("rebuilt quadtree in {d}ms", .{self.timer.lap() / 1_000_000});
    }

    {
        var pool: [node_pool_size]std.Thread = undefined;
        for (0..node_pool_size) |i| {
            const min = i * self.node_count / node_pool_size;
            const max = (i + 1) * self.node_count / node_pool_size;
            pool[i] = try std.Thread.spawn(.{}, updateNodeForces, .{ self, min, max, self.node_forces });
        }

        for (0..node_pool_size) |i| pool[i].join();

        std.log.info("applied node forces in {d}ms", .{self.timer.lap() / 1_000_000});
    }

    {
        var pool: [edge_pool_size]std.Thread = undefined;
        for (0..edge_pool_size) |i| {
            const min = i * self.edge_count / edge_pool_size;
            const max = (i + 1) * self.edge_count / edge_pool_size;
            pool[i] = try std.Thread.spawn(.{}, updateEdgeForces, .{ self, min, max, self.edge_forces[i] });
        }

        for (0..edge_pool_size) |i| pool[i].join();

        std.log.info("applied edge forces in {d}ms", .{self.timer.lap() / 1_000_000});
    }

    self.min_x = 0;
    self.max_x = 0;
    self.min_y = 0;
    self.max_y = 0;

    const temperature: @Vector(2, f32) = @splat(self.temperature);

    var sum: f32 = 0;
    for (0..self.node_count) |i| {
        var f = self.node_forces[i];
        inline for (self.edge_forces) |edge_forces| f += edge_forces[i];

        sum += std.math.sqrt(@reduce(.Add, f * f));

        f *= temperature;
        self.x[i] += f[0];
        self.y[i] += f[1];

        self.min_x = @min(self.min_x, self.x[i]);
        self.max_x = @max(self.max_x, self.x[i]);
        self.min_y = @min(self.min_y, self.y[i]);
        self.max_y = @max(self.max_y, self.y[i]);

        self.node_forces[i] = .{ 0, 0 };
        inline for (self.edge_forces) |edge_forces| edge_forces[i] = .{ 0, 0 };
    }

    return sum / @as(f32, @floatFromInt(self.node_count));
}

fn updateEdgeForces(self: *Store, min: usize, max: usize, force: []@Vector(2, f32)) void {
    for (min..max) |i| {
        if (i >= self.edge_count) {
            break;
        }

        const s = self.source[i] - 1;
        const t = self.target[i] - 1;

        const f = forces.getAttraction(self.attraction, .{ self.x[s], self.y[s] }, .{ self.x[t], self.y[t] });

        force[s] += f;
        force[t] -= f;
    }
}

fn updateNodeForces(self: *Store, min: usize, max: usize, node_forces: []@Vector(2, f32)) void {
    for (min..max) |i| {
        if (i >= self.node_count) {
            break;
        }

        const p = @Vector(2, f32){ self.x[i], self.y[i] };
        const mass = forces.getMass(self.z[i]);

        for (self.quads) |tree| node_forces[i] += tree.getForce(self.repulsion, p, mass);
    }
}

pub fn rebuildQuad(self: *Store, tree: *Quadtree) !void {
    var timer = try std.time.Timer.start();

    var i: u32 = 0;
    while (i < self.node_count) : (i += 1) {
        const p = @Vector(2, f32){ self.x[i], self.y[i] };
        if (tree.area.contains(p)) {
            const mass = forces.getMass(self.z[i]);
            try tree.insert(i + 1, p, mass);
        }
    }

    std.log.info("rebuildQuad in {d}ms ({d} nodes)", .{ timer.read() / 1_000_000, tree.tree.items.len });
}

fn getNodeForce(self: *Store, p: @Vector(2, f32), mass: f32) @Vector(2, f32) {
    var force = @Vector(2, f32){ 0, 0 };
    for (0..self.node_count) |i| {
        force += forces.getRepulsion(self.repulsion, p, mass, .{ self.x[i], self.y[i] }, forces.getMass(self.z[i]));
    }

    return force;
}

pub fn save(self: *Store) !void {
    // const Node = struct { x: f32, y: f32, idx: u32 };
    // const update = try self.db.prepare(Node, void, "UPDATE atlas SET minX = :x, maxX = :x, minY = :y, maxY = :y WHERE idx = :idx");
    // defer update.deinit();

    {
        const begin = try self.db.prepare(struct {}, void, "BEGIN TRANSACTION");
        defer begin.finalize();
        try begin.exec(.{});
    }

    for (0..self.node_count) |i| {
        const idx: u32 = @intCast(i + 1);
        try self.update.exec(.{ .x = self.x[i], .y = self.y[i], .idx = idx });
    }

    {
        const commit = try self.db.prepare(struct {}, void, "COMMIT TRANSACTION");
        defer commit.finalize();
        try commit.exec(.{});
    }
}

pub fn refresh(self: *Store, area: AreaParams) ![]u32 {
    self.ids.clearRetainingCapacity();

    try self.select_ids.bind(area);
    defer self.select_ids.reset();

    while (try self.select_ids.step()) |node| {
        try self.ids.append(node.idx);
    }

    std.log.info("there are {d} nodes in the area", .{self.ids.items.len});
    return self.ids.items;
}
