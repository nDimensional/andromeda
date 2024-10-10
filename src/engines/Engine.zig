const std = @import("std");

const Graph = @import("../Graph.zig");
const Params = @import("../Params.zig");
const SimulatedAnnealing = @import("SimulatedAnnealing.zig");
const ForceAtlas2 = @import("ForceAtlas2.zig");

pub const EngineTag = enum { ForceDirected, SimulatedAnnealing };
pub const Engine = union(EngineTag) {
    ForceDirected: *ForceAtlas2,
    SimulatedAnnealing: *SimulatedAnnealing,

    pub fn init(allocator: std.mem.Allocator, graph: *Graph, params: *const Params, tag: EngineTag) !Engine {
        switch (tag) {
            .ForceDirected => {
                const engine = try ForceAtlas2.init(allocator, graph, params);
                return .{ .ForceDirected = engine };
            },
            .SimulatedAnnealing => {
                const engine = try SimulatedAnnealing.init(allocator, graph, params);
                return .{ .SimulatedAnnealing = engine };
            },
        }
    }

    pub fn deinit(self: Engine) void {
        switch (self) {
            .ForceDirected => |engine| engine.deinit(),
            .SimulatedAnnealing => |engine| engine.deinit(),
        }
    }

    pub fn tick(self: Engine) !f32 {
        return switch (self) {
            .ForceDirected => |engine| try engine.tick(),
            .SimulatedAnnealing => |engine| try engine.tick(),
        };
    }

    pub fn count(self: Engine) usize {
        return switch (self) {
            .ForceDirected => |engine| engine.count,
            .SimulatedAnnealing => |engine| engine.count,
        };
    }
};
