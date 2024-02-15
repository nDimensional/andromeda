const std = @import("std");

const chan = @import("chan");

const Store = @import("Store.zig");
const Quadtree = @import("Quadtree.zig");
const forces = @import("forces.zig");

pub fn WorkerPool(comptime size: usize) type {
    if (size < 4) @compileError("WorkerPool size must be at least 4");

    return struct {
        const Self = @This();

        timer: std.time.Timer,
        pool: [size]Worker = undefined,
        node_forces: []@Vector(2, f32) = undefined,
        edge_forces: [size][]@Vector(2, f32) = undefined,

        pub fn init(allocator: std.mem.Allocator, store: *Store) !Self {
            const timer = try std.time.Timer.start();
            var self = Self{ .timer = timer };

            self.node_forces = try allocator.alloc(@Vector(2, f32), store.node_count);
            for (self.node_forces) |*f| f.* = .{ 0, 0 };

            for (0..size) |i| {
                self.edge_forces[i] = try allocator.alloc(@Vector(2, f32), store.node_count);
                for (self.edge_forces[i]) |*f| f.* = .{ 0, 0 };
            }

            for (0..size) |i| self.pool[i] = try Worker.init();
            return self;
        }

        pub fn deinit(self: Self) void {
            for (self.pool) |worker| worker.deinit();
        }

        pub fn stop(self: Self) !void {
            for (self.pool) |worker| try worker.stop();
        }

        pub fn tick(self: Self, store: *Store) !f32 {
            self.timer.reset();

            {
                const s = try store.getBoundingSize();
                const area = Quadtree.Area{ .s = s };

                for (0..4) |i| {
                    const tree = &store.quads[i];
                    tree.reset(area.divide(@enumFromInt(i)));
                    try self.pool[i].send(.{ .rebuildQuad = .{ .store = store, .tree = tree } });
                }

                for (0..4) |i| try self.pool[i].join();

                std.log.info("rebuilt quadtree in {d}ms", .{self.timer.lap() / 1_000_000});
            }

            {
                for (self.pool, 0..) |worker, i| {
                    const min = i * self.node_count / size;
                    const max = (i + 1) * self.node_count / size;
                    try worker.send(.{ .updateNodes = .{ .store = store, .min = min, .max = max, .result = self.node_forces } });
                }

                for (self.pool) |worker| try worker.join();

                std.log.info("applied node forces in {d}ms", .{self.timer.lap() / 1_000_000});
            }

            {
                for (self.pool, 0..) |worker, i| {
                    const min = i * self.edge_count / size;
                    const max = (i + 1) * self.edge_count / size;
                    try worker.send(.{ .updateEdges = .{ .store = store, .min = min, .max = max, .result = self.edge_forces[i] } });
                }

                for (self.pool) |worker| try worker.join();

                std.log.info("applied edge forces in {d}ms", .{self.timer.lap() / 1_000_000});
            }

            // self.min_x = 0;
            // self.max_x = 0;
            // self.min_y = 0;
            // self.max_y = 0;

            const temperature: @Vector(2, f32) = @splat(self.temperature);

            var sum: f32 = 0;
            for (0..store.node_count) |i| {
                var f = self.node_forces[i];
                inline for (self.edge_forces) |edge_forces| f += edge_forces[i];

                sum += std.math.sqrt(@reduce(.Add, f * f));

                f *= temperature;
                store.x[i] += f[0];
                store.y[i] += f[1];

                store.min_x = @min(store.min_x, store.x[i]);
                store.max_x = @max(store.max_x, store.x[i]);
                store.min_y = @min(store.min_y, store.y[i]);
                store.max_y = @max(store.max_y, store.y[i]);

                self.node_forces[i] = .{ 0, 0 };
                inline for (self.edge_forces) |edge_forces| edge_forces[i] = .{ 0, 0 };
            }

            return sum / @as(f32, @floatFromInt(store.node_count));
        }

        // pub inline fn getNodeForce(self: Self, i: u32) @Vector(2, f32) {
        //     var f = self.node_forces[i];
        //     inline for (self.edge_forces) |edge_forces| f += edge_forces[i];

        //     self.node_forces[i] = .{ 0, 0 };
        //     inline for (self.edge_forces) |edge_forces| edge_forces[i] = .{ 0, 0 };

        //     return f;
        // }
    };
}

pub const Request = union {
    rebuildQuad: struct { store: *Store, tree: *Quadtree },
    updateNodes: struct { store: *Store, min: usize, max: usize, node_forces: []@Vector(2, f32) },
    updateEdges: struct { store: *Store, min: usize, max: usize, force: []@Vector(2, f32) },
};

const Worker = struct {
    c: chan.Chan(Request),
    t: std.Thread,

    pub fn init() !Worker {
        const c = try chan.Chan(Request).init(0);
        const t = try std.Thread.spawn(.{}, run, .{c});
        return .{ .c = c, .t = t };
    }

    pub fn deinit(self: Worker) void {
        self.c.deinit();
    }

    pub fn send(self: Worker, req: *Request) !void {
        try self.c.send(req);
    }

    pub fn join(self: Worker) !void {
        _ = try self.c.recv();
    }

    pub fn stop(self: Worker) !void {
        try self.c.send(null);
        self.t.join();
    }

    fn run(c: chan.Chan(Request)) void {
        listen(c) catch |err| {
            std.log.err("{s}", .{@errorName(err)});
        };
    }

    fn listen(c: chan.Chan(Request)) !void {
        while (try c.recv()) |req| {
            switch (req) {
                .rebuildQuad => |params| try rebuildQuad(params.store, params.tree),
                .updateNodes => |params| try updateNodeForces(params.store, params.min, params.max, params.node_forces),
                .updateEdges => |params| try updateEdgeForces(params.store, params.min, params.max, params.force),
            }

            try c.send(null);
        }
    }
};

fn rebuildQuad(store: *Store, tree: *Quadtree) !void {
    var i: u32 = 0;
    while (i < store.node_count) : (i += 1) {
        const p = @Vector(2, f32){ store.x[i], store.y[i] };
        if (tree.area.contains(p)) {
            const mass = forces.getMass(store.z[i]);
            try tree.insert(i + 1, p, mass);
        }
    }
}

fn updateNodeForces(store: *Store, min: usize, max: usize, result: []@Vector(2, f32)) void {
    for (min..max) |i| {
        if (i >= store.node_count) {
            break;
        }

        const p = @Vector(2, f32){ store.x[i], store.y[i] };
        const mass = forces.getMass(store.z[i]);

        for (store.quads) |tree| result[i] += tree.getForce(store.repulsion, p, mass);
    }
}

fn updateEdgeForces(store: *Store, min: usize, max: usize, result: []@Vector(2, f32)) void {
    for (min..max) |i| {
        if (i >= store.edge_count) {
            break;
        }

        const s = store.source[i] - 1;
        const t = store.target[i] - 1;

        const f = forces.getAttraction(store.attraction, .{ store.x[s], store.y[s] }, .{ store.x[t], store.y[t] });

        result[s] += f;
        result[t] -= f;
    }
}
