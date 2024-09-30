const std = @import("std");

const glib = @import("glib");
const gio = @import("gio");
const gtk = @import("gtk");
const gobject = @import("gobject");
const sho = @import("shared-object");
const sqlite = @import("sqlite");

const Store = @import("Store.zig");

const Progress = @import("Progress.zig");

pub const Count = struct { count: usize };

const Graph = @This();
const SHM_NAME = "ANDROMEDA";

pub const FilterType = enum { all, count };
pub const Filter = union(FilterType) {
    all: void,
    count: usize,
};

allocator: std.mem.Allocator,
progress: Progress,
filter: Filter,
store: *Store,

prng: std.Random.Xoshiro256,

node_count: usize,
edge_count: usize,

outgoing_edges: []std.ArrayListUnmanaged(u32),
incoming_edges: []std.ArrayListUnmanaged(u32),

z: []f32,

positions: []@Vector(2, f32),
writer: sho.Writer(SHM_NAME),

pub const Options = struct {
    filter: Filter = .{ .all = {} },
    progress_bar: ?*gtk.ProgressBar = null,
};

pub fn init(allocator: std.mem.Allocator, store: *Store, options: Options) !*Graph {
    const graph = try allocator.create(Graph);
    graph.allocator = allocator;
    graph.progress = Progress{ .progress_bar = options.progress_bar };
    graph.filter = options.filter;
    graph.store = store;

    graph.prng = std.Random.Xoshiro256.init(0);

    // std.log.info("STORE_NODE_COUNT: {d}", .{store.node_count});

    switch (options.filter) {
        .all => {
            graph.node_count = try store.countNodes();
            graph.edge_count = try store.countEdges();
        },
        .count => |count| {
            graph.node_count = count;
            graph.edge_count = 0;
            // graph.edge_count = try store.countEdgesInRange(.{
            //     .min_source = 1,
            //     .max_source = @intCast(count),
            //     .min_target = 1,
            //     .max_target = @intCast(count),
            // });
        },
    }

    std.log.info("NODE_COUNT: {d}", .{graph.node_count});
    std.log.info("EDGE_COUNT: {d}", .{graph.edge_count});

    graph.outgoing_edges = try allocator.alloc(std.ArrayListUnmanaged(u32), graph.node_count);
    graph.incoming_edges = try allocator.alloc(std.ArrayListUnmanaged(u32), graph.node_count);

    for (graph.outgoing_edges) |*list| list.* = std.ArrayListUnmanaged(u32){};
    for (graph.incoming_edges) |*list| list.* = std.ArrayListUnmanaged(u32){};

    const writer_size = @sizeOf(@Vector(2, f32)) * graph.node_count;
    graph.writer = try sho.Writer(SHM_NAME).init(writer_size);

    const positions_ptr: [*]@Vector(2, f32) = @alignCast(@ptrCast(graph.writer.data.ptr));
    graph.positions = positions_ptr[0..graph.node_count];

    graph.z = try allocator.alloc(f32, graph.node_count);
    for (graph.z) |*z| z.* = 0;

    return graph;
}

pub fn deinit(self: *const Graph) void {
    self.allocator.free(self.z);

    for (self.outgoing_edges) |*list| list.deinit(self.allocator);
    for (self.incoming_edges) |*list| list.deinit(self.allocator);

    self.allocator.free(self.outgoing_edges);
    self.allocator.free(self.incoming_edges);

    self.writer.deinit();
    self.allocator.destroy(self);
}

pub const LoadOptions = struct {
    callback: ?*const fn (_: ?*gobject.Object, res: *gio.AsyncResult, data: ?*anyopaque) callconv(.C) void = null,
    callback_data: ?*anyopaque = null,
};

pub fn load(self: *Graph, options: LoadOptions) void {
    const task = gio.Task.new(null, null, options.callback, options.callback_data);
    defer task.unref();

    task.setTaskData(self, null);
    task.runInThread(&loadTask);
}

fn loadTask(task: *gio.Task, _: ?*gobject.Object, task_data: ?*anyopaque, cancellable: ?*gio.Cancellable) callconv(.C) void {
    std.log.info("loadTask", .{});

    const self: *Graph = @alignCast(@ptrCast(task_data));

    self.loadNodes(cancellable) catch |err| @panic(@errorName(err));
    self.loadEdges(cancellable) catch |err| @panic(@errorName(err));

    task.returnPointer(null, null);
}

const batch_size = 1024;

const LOADING_NODES = "Loading nodes...";

fn loadNodes(self: *Graph, cancellable: ?*gio.Cancellable) !void {
    _ = cancellable;

    std.log.info("loading nodes...", .{});
    self.progress.setText(LOADING_NODES);

    const total: f64 = @floatFromInt(self.node_count);

    try self.store.select_nodes.bind(.{});
    defer self.store.select_nodes.reset();

    var j: usize = 0;
    while (try self.store.select_nodes.step()) |node| : (j += 1) {
        if (j >= self.node_count) break;

        const i = node.idx - 1;
        self.positions[i] = .{ node.x, node.y };
        // self.z[i] = @floatFromInt(node.incoming_degree);

        if (j % batch_size == 0) {
            const value = @as(f64, @floatFromInt(j)) / total;
            self.progress.setValue(value);
        }
    }
}

const LOADING_EDGES = "Loading edges...";

fn loadEdges(self: *Graph, cancellable: ?*gio.Cancellable) !void {
    _ = cancellable;

    std.log.info("loading edges...", .{});
    self.progress.setText(LOADING_EDGES);

    const total: f64 = @floatFromInt(self.edge_count);

    try self.store.select_edges.bind(.{});
    defer self.store.select_edges.reset();

    var i: usize = 0;
    while (try self.store.select_edges.step()) |edge| {
        const s: u32 = @intCast(edge.source - 1);
        const t: u32 = @intCast(edge.target - 1);
        if (s < self.node_count and t < self.node_count) {
            try self.outgoing_edges[s].append(self.allocator, t);
            try self.incoming_edges[t].append(self.allocator, s);

            self.z[t] += 1;
            self.edge_count += 1;

            if (i % batch_size == 0) {
                const value = @as(f64, @floatFromInt(i)) / total;
                self.progress.setValue(value);
                i += 1;
            }
        }
    }
}

pub fn save(self: *Graph) !void {
    try self.store.db.exec("BEGIN TRANSACTION", .{});

    for (0..self.node_count) |i| {
        const idx: u32 = @intCast(i + 1);
        const p = self.positions[i];
        try self.store.update.exec(.{ .x = p[0], .y = p[1], .idx = idx });
    }

    try self.store.db.exec("COMMIT TRANSACTION", .{});
}

pub fn randomize(self: *Graph, s: f32) void {
    var random = self.prng.random();
    for (0..self.node_count) |i| {
        const p = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.node_count));

        var x = s * random.float(f32);
        x -= s / 2;
        x += p;

        var y = s * random.float(f32);
        y -= s / 2;
        y += p;

        self.positions[i] = .{ x, y };
    }
}
