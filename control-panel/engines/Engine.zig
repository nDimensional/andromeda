const std = @import("std");

const Store = @import("../Store.zig");
const Params = @import("../Params.zig");
const SimulatedAnnealing = @import("SimulatedAnnealing.zig");
const ForceDirected = @import("ForceDirected.zig");

pub const EngineTag = enum { ForceDirected, SimulatedAnnealing };
pub const Engine = union(EngineTag) {
    ForceDirected: *ForceDirected,
    SimulatedAnnealing: *SimulatedAnnealing,

    pub fn init(allocator: std.mem.Allocator, store: *Store, params: *const Params, tag: EngineTag) !Engine {
        switch (tag) {
            .ForceDirected => {
                const engine = try ForceDirected.init(allocator, store, params);
                return .{ .ForceDirected = engine };
            },
            .SimulatedAnnealing => {
                const engine = try SimulatedAnnealing.init(allocator, store, params);
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
