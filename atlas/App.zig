const std = @import("std");
const mach = @import("mach");
const core = mach.core;
const gpu = mach.gpu;

const builtin = @import("builtin");
const build_options = @import("build_options");
const nng = @import("nng");
const sho = @import("shared-object");
const c = @import("c.zig");

const Pipeline = @import("Pipeline.zig");
const Point = Pipeline.Point;
const Body = Pipeline.Body;

pub const App = @This();

const allocator = std.heap.c_allocator;
const SHM_NAME = "ANDROMEDA";
const SOCKET_URL = "ipc://" ++ build_options.socket_path;

const MAX_ZOOM = 8192;
const MIN_ZOOM = 0;

const device_pixel_ratio = if (builtin.os.tag.isDarwin()) 2 else 1;

pub const mach_core_options = core.ComptimeOptions{
    .use_wgpu = false,
    .use_sysgpu = true,
    // .use_wgpu = true,
    // .use_sysgpu = false,
};

node_count: u32,

title_timer: core.Timer,
pipeline: Pipeline,

params: Pipeline.Params,
anchor: ?struct { pos: core.Position, offset: @Vector(2, f32) },
mouse: core.Position,
zoom: f32,

reader: sho.Reader(SHM_NAME),
positions: []const Point,
socket: nng.Socket.SUB,

// const unit = 100;
// const positions: []const Point = &.{
//     .{ 0 * unit, -1 * unit },
//     .{ 0 * unit, 0 * unit },
//     .{ 0 * unit, 1 * unit },
//     .{ 1 * unit, -1 * unit },
//     .{ 1 * unit, 0 * unit },
//     .{ 1 * unit, 1 * unit },
//     .{ -1 * unit, -1 * unit },
//     .{ -1 * unit, 0 * unit },
//     .{ -1 * unit, 1 * unit },
// };

pub fn init(app: *App) !void {
    // app.node_count = @intCast(positions.len);
    app.reader = try sho.Reader(SHM_NAME).init();
    app.node_count = @intCast(app.reader.map.len / @sizeOf(Point));

    const positions_ptr = @as([*]const Point, @alignCast(@ptrCast(app.reader.data.ptr)));
    const positions = positions_ptr[0..app.node_count];
    app.positions = positions;

    try core.init(.{});

    app.pipeline = try Pipeline.init(positions);
    app.title_timer = try core.Timer.start();
    app.anchor = null;
    app.zoom = 0;

    const size = core.size();

    app.params = .{
        .width = @floatFromInt(size.width),
        .height = @floatFromInt(size.height),
        .offset = .{ 0, 0 },
        .scale = 1,
        .min_radius = 10,
        .scale_radius = 1,
        .pixel_ratio = device_pixel_ratio,
    };

    core.setCursorShape(.pointing_hand);

    app.socket = try nng.Socket.SUB.open();
    try app.socket.set("sub:subscribe", "");
    try app.socket.dial(SOCKET_URL);
}

pub fn deinit(app: *App) void {
    app.socket.close();
    app.reader.deinit();

    app.pipeline.deinit();

    core.deinit();
}

pub fn update(app: *App) !bool {
    const size = core.size();
    app.params.width = @floatFromInt(size.width);
    app.params.height = @floatFromInt(size.height);

    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            .mouse_press => |e| {
                switch (e.button) {
                    .left => {
                        core.setCursorShape(.resize_all);
                        app.anchor = .{ .pos = e.pos, .offset = app.params.offset };
                    },
                    else => {},
                }
            },
            .mouse_release => |e| {
                switch (e.button) {
                    .left => {
                        core.setCursorShape(.pointing_hand);
                        if (app.anchor) |anchor| {
                            const delta = @Vector(2, f32){
                                @floatCast(e.pos.x - anchor.pos.x),
                                @floatCast(anchor.pos.y - e.pos.y),
                            };

                            const scale: @Vector(2, f32) = @splat(getScale(app.zoom));

                            app.params.offset = anchor.offset + delta / scale;
                            app.anchor = null;
                        }
                    },
                    else => {},
                }
            },
            .mouse_motion => |e| {
                app.mouse = e.pos;
                if (app.anchor) |anchor| {
                    const delta = @Vector(2, f32){
                        @floatCast(e.pos.x - anchor.pos.x),
                        @floatCast(anchor.pos.y - e.pos.y),
                    };

                    const scale: @Vector(2, f32) = @splat(getScale(app.zoom));

                    app.params.offset = anchor.offset + delta / scale;
                }
            },
            .mouse_scroll => |e| {
                var zoom = app.zoom - 4 * e.yoffset;
                zoom = @min(zoom, MAX_ZOOM);
                zoom = @max(zoom, MIN_ZOOM);
                if (zoom != app.zoom) {
                    const old_scale = getScale(app.zoom);
                    const new_scale = getScale(zoom);
                    app.zoom = zoom;
                    app.params.scale = new_scale;

                    const px = @as(f32, @floatCast(app.mouse.x)) - @as(f32, @floatFromInt(size.width)) / 2;
                    const py = @as(f32, @floatFromInt(size.height)) / 2 - @as(f32, @floatCast(app.mouse.y));
                    const old_x = px / old_scale;
                    const old_y = py / old_scale;
                    const new_x = px / new_scale;
                    const new_y = py / new_scale;
                    app.params.offset += @Vector(2, f32){
                        new_x - old_x,
                        new_y - old_y,
                    };
                }
            },

            .key_press => |e| {
                if (e.key == .w and e.mods.super) {
                    return true;
                }
            },

            else => {},
        }
    }

    var dirty = false;
    while (try app.recv()) |_| dirty = true;

    if (dirty) {
        app.pipeline.updatePositions(app.positions);
    }

    app.pipeline.render(&app.params);

    // update the window title every second
    if (app.title_timer.read() >= 1.0) {
        app.title_timer.reset();
        try core.printTitle("Andromeda [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }

    return false;
}

fn recv(app: *App) !?u64 {
    const msg = app.socket.recv(.{ .NONBLOCK = true }) catch |err| switch (err) {
        error.AGAIN => return null,
        else => return err,
    };

    const body = msg.body();
    if (body.len != 8) {
        return error.INVAL;
    }

    return std.mem.readInt(u64, body[0..8], .big);
}

fn getScale(zoom: f32) f32 {
    return 256 / ((std.math.pow(f32, zoom + 1, 2) - 1) / 256 + 256);
}
