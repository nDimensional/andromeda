const std = @import("std");

const glib = @import("glib");
const gio = @import("gio");
const gtk = @import("gtk");
const gobject = @import("gobject");
const sho = @import("shared-object");
const sqlite = @import("sqlite");

const Progress = @import("Progress.zig");

pub const UpdateParams = struct { x: f32, y: f32, id: u32 };
pub const SelectEdgesBySourceParams = struct { source: u32, min_target: u32, max_target: u32 };
pub const SelectEdgesBySourceResult = struct { target: u32 };
pub const SelectEdgesByTargetParams = struct { target: u32, min_source: u32, max_source: u32 };
pub const SelectEdgesByTargetResult = struct { source: u32 };
pub const CountEdgesBySourceParams = struct { source: u32, min_target: u32, max_target: u32 };
pub const CountEdgesBySourceResult = struct { count: usize };
pub const CountEdgesByTargetParams = struct { target: u32, min_source: u32, max_source: u32 };
pub const CountEdgesByTargetResult = struct { count: usize };

pub const SelectNodesParams = struct {};
pub const SelectNodesResult = struct { id: u32, x: f32, y: f32 };
pub const SelectEdgesParams = struct {};
pub const SelectEdgesResult = struct { source: u32, target: u32 };

pub const CountParams = struct {};
pub const CountResult = struct { count: usize };

pub const CountEdgesInRangeParams = struct { min_source: u32, max_source: u32, min_target: u32, max_target: u32 };
pub const CountEdgesInRangeResult = struct { count: usize };

pub const SelectEdgesInRangeParams = struct { min_source: u32, max_source: u32, min_target: u32, max_target: u32 };
pub const SelectEdgesInRangeResult = struct { source: u32, target: u32 };

const Store = @This();

allocator: std.mem.Allocator,
db: sqlite.Database,

count_nodes: sqlite.Statement(CountParams, CountResult),
count_edges: sqlite.Statement(CountParams, CountResult),
select_nodes: sqlite.Statement(SelectNodesParams, SelectNodesResult),
select_edges: sqlite.Statement(SelectEdgesParams, SelectEdgesResult),
select_edges_by_source: sqlite.Statement(SelectEdgesBySourceParams, SelectEdgesBySourceResult),
select_edges_by_target: sqlite.Statement(SelectEdgesByTargetParams, SelectEdgesByTargetResult),
count_edges_by_source: sqlite.Statement(CountEdgesBySourceParams, CountEdgesBySourceResult),
count_edges_by_target: sqlite.Statement(CountEdgesByTargetParams, CountEdgesByTargetResult),
select_edges_in_range: sqlite.Statement(SelectEdgesInRangeParams, SelectEdgesInRangeResult),
count_edges_in_range: sqlite.Statement(CountEdgesInRangeParams, CountEdgesInRangeResult),
update: sqlite.Statement(UpdateParams, void),

pub const Options = struct {
    path: ?[*:0]const u8 = null,
    progress_bar: ?*gtk.ProgressBar = null,
};

pub fn init(allocator: std.mem.Allocator, options: Options) !*Store {
    const store = try allocator.create(Store);
    store.allocator = allocator;
    store.db = try sqlite.Database.open(.{ .path = options.path, .create = false });

    store.count_edges = try store.db.prepare(CountParams, CountResult,
        \\ SELECT count(*) as count FROM edges
    );

    store.count_nodes = try store.db.prepare(CountParams, CountResult,
        \\ SELECT count(*) as count FROM nodes
    );

    store.select_nodes = try store.db.prepare(SelectNodesParams, SelectNodesResult,
        \\ SELECT rowid AS id, x, y FROM nodes ORDER BY rowid ASC
    );

    store.select_edges = try store.db.prepare(SelectEdgesParams, SelectEdgesResult,
        \\ SELECT source, target FROM edges
    );

    store.select_edges_by_source = try store.db.prepare(SelectEdgesBySourceParams, SelectEdgesBySourceResult,
        \\ SELECT target FROM edges WHERE source = :source AND :min_target <= target AND target <= :max_target
    );

    store.select_edges_by_target = try store.db.prepare(SelectEdgesByTargetParams, SelectEdgesByTargetResult,
        \\ SELECT source FROM edges WHERE target = :target AND :min_source <= source AND source <= :max_source
    );

    store.count_edges_by_source = try store.db.prepare(CountEdgesBySourceParams, CountEdgesBySourceResult,
        \\ SELECT count(*) as count FROM edges WHERE source = :source AND :min_target <= target AND target <= :max_target
    );

    store.count_edges_by_target = try store.db.prepare(CountEdgesByTargetParams, CountEdgesByTargetResult,
        \\ SELECT count(*) as count FROM edges WHERE target = :target AND :min_source <= source AND source <= :max_source
    );

    store.select_edges_in_range = try store.db.prepare(SelectEdgesInRangeParams, SelectEdgesInRangeResult,
        \\ SELECT source, target FROM edges
        \\   WHERE :min_target <= target
        \\     AND target <= :max_target
        \\     AND :min_source <= source
        \\     AND source <= :max_source
    );

    store.count_edges_in_range = try store.db.prepare(CountEdgesInRangeParams, CountEdgesInRangeResult,
        \\ SELECT count(*) as count FROM edges
        \\   WHERE :min_target <= target
        \\     AND target <= :max_target
        \\     AND :min_source <= source
        \\     AND source <= :max_source
    );

    store.update = try store.db.prepare(UpdateParams, void,
        \\ UPDATE nodes SET x = :x, y = :y WHERE rowid = :id
    );

    return store;
}

pub fn deinit(self: *const Store) void {
    self.count_nodes.finalize();
    self.count_edges.finalize();
    self.select_nodes.finalize();
    self.select_edges.finalize();
    self.select_edges_by_source.finalize();
    self.select_edges_by_target.finalize();
    self.count_edges_by_source.finalize();
    self.count_edges_by_target.finalize();
    self.select_edges_in_range.finalize();
    self.count_edges_in_range.finalize();
    self.update.finalize();

    self.db.close();
    self.allocator.destroy(self);
}

pub fn countNodes(self: *const Store) !usize {
    try self.count_nodes.bind(.{});
    defer self.count_nodes.reset();

    const result = try self.count_nodes.step() orelse return error.NoResults;
    return result.count;
}

pub fn countEdges(self: *const Store) !usize {
    try self.count_edges.bind(.{});
    defer self.count_edges.reset();

    const result = try self.count_edges.step() orelse return error.NoResults;
    return result.count;
}

pub fn countEdgesInRange(self: *const Store, params: CountEdgesInRangeParams) !usize {
    try self.count_edges_in_range.bind(params);
    defer self.count_edges_in_range.reset();

    const result = try self.count_edges_in_range.step() orelse return error.NoResults;
    return result.count;
}
