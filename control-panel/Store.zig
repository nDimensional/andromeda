const std = @import("std");

const glib = @import("glib");
const gio = @import("gio");
const gtk = @import("gtk");
const gobject = @import("gobject");
const sho = @import("shared-object");
const sqlite = @import("sqlite");

const Progress = @import("Progress.zig");

pub const UpdateParams = struct { x: f32, y: f32, idx: u32 };
pub const Count = struct { count: usize };

const Store = @This();
const SHM_NAME = "ANDROMEDA";

const node_pool_size = 16;
const edge_pool_size = 16;

allocator: std.mem.Allocator,
progress: Progress,
prng: std.rand.Xoshiro256 = std.rand.Xoshiro256.init(0),
db: sqlite.Database,

update: sqlite.Statement(UpdateParams, void),

node_count: usize = 0,
edge_count: usize = 0,

source: []u32 = undefined,
target: []u32 = undefined,
z: []f32 = undefined,

positions: []@Vector(2, f32) = undefined,
writer: sho.Writer(SHM_NAME) = undefined,

pub const Options = struct {
    path: ?[*:0]const u8 = null,
    progress_bar: ?*gtk.ProgressBar = null,
};

pub fn init(allocator: std.mem.Allocator, options: Options) !*Store {
    const store = try allocator.create(Store);
    store.allocator = allocator;
    store.progress = Progress { .progress_bar = options.progress_bar };

    store.db = try sqlite.Database.open(.{ .path = options.path, .create = false });

    store.update = try store.db.prepare(UpdateParams, void,
        \\ UPDATE nodes SET x = :x, y = :y WHERE idx = :idx
    );

    {
        const count_edges = try store.db.prepare(struct {}, Count, "SELECT count(*) as count FROM edges");
        defer count_edges.finalize();

        try count_edges.bind(.{});
        const result = try count_edges.step() orelse return error.NoResults;
        store.edge_count = result.count;
    }

    store.source = try allocator.alloc(u32, store.edge_count);
    store.target = try allocator.alloc(u32, store.edge_count);

    {
        const count_nodes = try store.db.prepare(struct {}, Count, "SELECT count(*) as count FROM nodes");
        defer count_nodes.finalize();

        try count_nodes.bind(.{});
        const result = try count_nodes.step() orelse return error.NoResults;
        store.node_count = result.count;
    }

    const size = @sizeOf(@Vector(2, f32)) * store.node_count;
    store.writer = try sho.Writer(SHM_NAME).init(size);

    const positions_ptr: [*]@Vector(2, f32) = @alignCast(@ptrCast(store.writer.data.ptr));
    store.positions = positions_ptr[0..store.node_count];

    store.z = try allocator.alloc(f32, store.node_count);

    return store;
}

pub fn deinit(self: *const Store) void {
    self.update.finalize();
    self.db.close();

    self.allocator.free(self.source);
    self.allocator.free(self.target);
    self.allocator.free(self.z);

    self.writer.deinit();

    self.allocator.destroy(self);
}

pub const LoadOptions = struct {
    callback: ?*const fn (_: ?*gobject.Object, res: *gio.AsyncResult, data: ?*anyopaque) callconv(.C) void = null,
    callback_data: ?*anyopaque = null,
};

pub fn load(self: *Store, options: LoadOptions) void {
    const task = gio.Task.new(null, null, options.callback, options.callback_data);
    defer task.unref();

    task.setTaskData(self, null);
    task.runInThread(&loadTask);
}

fn loadTask(task: *gio.Task, _: ?*gobject.Object, task_data: ?*anyopaque, cancellable: ?*gio.Cancellable) callconv(.C) void {
    std.log.info("loadTask", .{});

    const self: *Store = @alignCast(@ptrCast(task_data));

    self.loadNodes(cancellable) catch |err| @panic(@errorName(err));
    self.loadEdges(cancellable) catch |err| @panic(@errorName(err));

    task.returnPointer(null, null);
}

const batch_size = 1024;

const LOADING_NODES = "Loading nodes";

fn loadNodes(self: *Store, cancellable: ?*gio.Cancellable) !void {
    _ = cancellable;

    std.log.info("loading nodes...", .{});
    self.progress.setText(LOADING_NODES);

    const total: f64 = @floatFromInt(self.node_count);

    const Node = struct { idx: u32, incoming_degree: u32, x: f32, y: f32 };
    const select_nodes = try self.db.prepare(struct {}, Node,
        \\ SELECT idx, incoming_degree, x, y FROM nodes
    );

    defer select_nodes.finalize();

    try select_nodes.bind(.{});
    defer select_nodes.reset();

    var j: usize = 0;
    while (try select_nodes.step()) |node| : (j += 1) {
        const i = node.idx - 1;
        self.positions[i] = .{ node.x, node.y };
        self.z[i] = @floatFromInt(node.incoming_degree);

        if (j % batch_size == 0) {
            const value = @as(f64, @floatFromInt(j)) / total;
            self.progress.setValue(value);
        }
    }
}

const LOADING_EDGES = "Loading edges";

fn loadEdges(self: *Store, cancellable: ?*gio.Cancellable) !void {
    _ = cancellable;

    std.log.info("loading edges...", .{});
    self.progress.setText(LOADING_EDGES);

    const total: f64 = @floatFromInt(self.edge_count);

    const Edge = struct { source: u32, target: u32 };
    const select_edges = try self.db.prepare(struct {}, Edge, "SELECT source, target FROM edges");
    defer select_edges.finalize();

    try select_edges.bind(.{});
    defer select_edges.reset();

    var i: usize = 0;
    while (try select_edges.step()) |edge| : (i += 1) {
        self.source[i] = edge.source;
        self.target[i] = edge.target;

        if (i % batch_size == 0) {
            const value = @as(f64, @floatFromInt(i)) / total;
            self.progress.setValue(value);
        }
    }
}

pub fn save(self: *Store) !void {
    try self.db.exec("BEGIN TRANSACTION", .{});

    for (0..self.node_count) |i| {
        const idx: u32 = @intCast(i + 1);
        const p = self.positions[i];
        try self.update.exec(.{ .x = p[0], .y = p[1], .idx = idx });
    }

    try self.db.exec("COMMIT TRANSACTION", .{});
}
