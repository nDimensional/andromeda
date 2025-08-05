const std = @import("std");

const Graph = @import("../Graph.zig");
const Params = @import("../Params.zig");
const ForceAtlas2 = @import("ForceAtlas2/Engine.zig");
const UMAP = @import("UMAP/Engine.zig");

pub const EngineTag = enum(u8) {
    ForceAtlas2 = 0,
    UMAP = 1,
};

pub const Engine = union(EngineTag) {
    ForceAtlas2: *ForceAtlas2,
    UMAP: *UMAP,

    pub fn init(allocator: std.mem.Allocator, graph: *const Graph, params: *const Params, tag: EngineTag) !Engine {
        return switch (tag) {
            .ForceAtlas2 => .{ .ForceAtlas2 = try ForceAtlas2.init(allocator, graph, params) },
            .UMAP => .{ .UMAP = try UMAP.init(allocator, graph, params) },
        };
    }

    pub fn deinit(self: Engine) void {
        switch (self) {
            .ForceAtlas2 => |engine| engine.deinit(),
            .UMAP => |engine| engine.deinit(),
        }
    }

    pub fn getBoundingSize(self: Engine) !f32 {
        return try switch (self) {
            .ForceAtlas2 => |engine| try engine.getBoundingSize(),
            .UMAP => |engine| try engine.getBoundingSize(),
        };
    }

    pub fn tick(self: Engine) !u64 {
        return switch (self) {
            .ForceAtlas2 => |engine| try engine.tick(),
            .UMAP => |engine| try engine.tick(),
        };
    }
};
