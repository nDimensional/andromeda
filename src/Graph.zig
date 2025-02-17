const std = @import("std");

const glib = @import("glib");
const gio = @import("gio");
const gtk = @import("gtk");
const gobject = @import("gobject");
const sqlite = @import("sqlite");

const Store = @import("Store.zig");

const Progress = @import("Progress.zig");
const Params = @import("Params.zig");
const utils = @import("utils.zig");

const Graph = @This();

pub const Node = struct {
    mass: f32,
    position: @Vector(2, f32),
};

const OutgoingEdge = struct { target: u32, weight: f32 };
const IncomingEdge = struct { source: u32, weight: f32 };

pub const Options = struct {
    progress_bar: ?*gtk.ProgressBar = null,
};

allocator: std.mem.Allocator,
progress: Progress,
store: *Store,

prng: std.Random.Xoshiro256,

node_count: usize,
edge_count: usize,

outgoing_edges: []std.ArrayListUnmanaged(OutgoingEdge),
incoming_edges: []std.ArrayListUnmanaged(IncomingEdge),

mass: []f32,
positions: []@Vector(2, f32),
node_index: std.AutoArrayHashMap(u32, u32),

pub fn init(allocator: std.mem.Allocator, store: *Store, options: Options) !*Graph {
    const graph = try allocator.create(Graph);
    graph.allocator = allocator;
    graph.progress = Progress{ .progress_bar = options.progress_bar };
    graph.store = store;
    graph.prng = std.Random.Xoshiro256.init(0);
    graph.node_count = try store.countNodes();
    graph.edge_count = try store.countEdges();

    std.log.info("NODE_COUNT: {d}", .{graph.node_count});
    std.log.info("EDGE_COUNT: {d}", .{graph.edge_count});

    graph.outgoing_edges = try allocator.alloc(std.ArrayListUnmanaged(OutgoingEdge), graph.node_count);
    graph.incoming_edges = try allocator.alloc(std.ArrayListUnmanaged(IncomingEdge), graph.node_count);

    for (graph.outgoing_edges) |*list| list.* = std.ArrayListUnmanaged(OutgoingEdge){};
    for (graph.incoming_edges) |*list| list.* = std.ArrayListUnmanaged(IncomingEdge){};

    graph.node_index = std.AutoArrayHashMap(u32, u32).init(allocator);

    graph.positions = try allocator.alloc(@Vector(2, f32), graph.node_count);
    for (graph.positions) |*p| p.* = .{ 0, 0 };

    graph.mass = try allocator.alloc(f32, graph.node_count);
    for (graph.mass) |*z| z.* = 1.0;

    return graph;
}

pub fn deinit(self: *Graph) void {
    self.node_index.deinit();
    self.allocator.free(self.mass);
    self.allocator.free(self.positions);

    for (self.outgoing_edges) |*list| list.deinit(self.allocator);
    for (self.incoming_edges) |*list| list.deinit(self.allocator);

    self.allocator.free(self.outgoing_edges);
    self.allocator.free(self.incoming_edges);

    self.allocator.destroy(self);
}

pub fn reload(self: Graph) !void {
    // const total: f64 = @floatFromInt(self.node_count);

    try self.store.select_nodes.bind(.{});
    defer self.store.select_nodes.reset();

    while (try self.store.select_nodes.step()) |node| {
        const i = self.node_index.get(node.id) orelse return error.InvalidNodeId;
        self.positions[i] = .{ node.x, node.y };
        // if (i % batch_size == 0) {
        //     const value = @as(f64, @floatFromInt(i)) / total;
        //     self.progress.setValue(value);
        // }
    }
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

    try self.node_index.ensureTotalCapacity(self.node_count);

    const total: f64 = @floatFromInt(self.node_count);

    try self.store.select_nodes.bind(.{});
    defer self.store.select_nodes.reset();

    var i: usize = 0;
    while (try self.store.select_nodes.step()) |node| : (i += 1) {
        if (i >= self.node_count) break;

        self.node_index.putAssumeCapacityNoClobber(node.id, @intCast(i));
        self.positions[i] = .{ node.x, node.y };

        if (i % batch_size == 0) {
            const value = @as(f64, @floatFromInt(i)) / total;
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

    var n: usize = 0;
    while (try self.store.select_edges.step()) |edge| : (n += 1) {
        const s = self.node_index.get(edge.source) orelse return error.NodeNotFound;
        const t = self.node_index.get(edge.target) orelse return error.NodeNotFound;
        try self.outgoing_edges[s].append(self.allocator, .{ .target = t, .weight = edge.weight });
        try self.incoming_edges[t].append(self.allocator, .{ .source = s, .weight = edge.weight });
        self.edge_count += 1;

        if (n % batch_size == 0) {
            const value = @as(f64, @floatFromInt(n)) / total;
            self.progress.setValue(value);
        }
    }

    for (0..self.node_count) |i| {
        const incoming_degree = self.incoming_edges[i].items.len;
        self.mass[i] = utils.getMass(incoming_degree);
    }
}

pub fn save(self: *Graph) !void {
    try self.store.db.exec("BEGIN TRANSACTION", .{});

    var iter = self.node_index.iterator();

    while (iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const i = entry.value_ptr.*;
        const p = self.positions[i];
        try self.store.update.exec(.{ .x = p[0], .y = p[1], .id = id });
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
