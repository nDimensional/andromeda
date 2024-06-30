const std = @import("std");
const mach = @import("mach");
const core = mach.core;
const gpu = mach.gpu;

const ul = @import("ul");

// const WebGPUSurface = @import("WebGPUSurface.zig");

pub const App = @This();

const Point = @Vector(2, f32);
const Body = packed struct { mass: f32 };

const MAX_ZOOM = 2400;
const MIN_ZOOM = 0;

const panel_width = 640;
const panel_height = 480;

const device_pixel_ratio = 2;

const Params = packed struct {
    width: f32,
    height: f32,
    offset: @Vector(2, f32),
    scale: f32,
    min_radius: f32,
    scale_radius: f32,
    pixel_ratio: f32,
};

comptime {
    std.debug.assert(@sizeOf(Params) == 32);
}

pub const mach_core_options = core.ComptimeOptions{
    // .use_wgpu = false,
    // .use_sysgpu = true,
    .use_wgpu = true,
    .use_sysgpu = false,
};

const vertex_buffer_data: []const Point = &.{
    .{ -1.0, 1.0 },
    .{ 1.0, 1.0 },
    .{ 1.0, -1.0 },
    .{ -1.0, -1.0 },
};

const vertex_buffer_size = vertex_buffer_data.len * @sizeOf(Point);

const index_buffer_data: []const u16 = &.{ 0, 1, 2, 2, 0, 3 };
const index_buffer_size = index_buffer_data.len * @sizeOf(u16);

config: ul.Ultralight.Config,
renderer: ul.Ultralight.Renderer,
view_config: ul.Ultralight.View.Config,
view: ul.Ultralight.View,
surface: ul.Ultralight.Surface,

title_timer: core.Timer,
node_count: u32,

node_pipeline: *gpu.RenderPipeline,
node_pipeline_layout: *gpu.PipelineLayout,

node_bind_group: *gpu.BindGroup,
node_bind_group_layout: *gpu.BindGroupLayout,

panel_pipeline: *gpu.RenderPipeline,
panel_pipeline_layout: *gpu.PipelineLayout,

panel_bind_group: *gpu.BindGroup,
panel_bind_group_layout: *gpu.BindGroupLayout,

texture: *gpu.Texture,
sampler: *gpu.Sampler,

texture_view: *gpu.TextureView,

vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
param_buffer: *gpu.Buffer,
position_buffer: *gpu.Buffer,
node_buffer: *gpu.Buffer,

params: Params,
anchor: ?struct { pos: core.Position, offset: @Vector(2, f32) },
mouse: core.Position,
zoom: f32,

pub fn init(app: *App) !void {
    // ul.Ultralight.Platform.setFileSystem(ul.Ultralight.Platform.filesystem);
    ul.Ultralight.Platform.enablePlatformFileSystem("/Users/joelgustafson/Projects/andromeda");
    ul.Ultralight.Platform.enablePlatformFontLoader();
    ul.Ultralight.Platform.setLogger(ul.Ultralight.Platform.logger);

    app.config = ul.Ultralight.Config.create();
    app.config.setResourcePathPrefix("SDK/resources/");

    app.renderer = ul.Ultralight.Renderer.create(app.config);
    app.view_config = ul.Ultralight.View.Config.create();
    app.view = ul.Ultralight.View.create(app.renderer, panel_width * device_pixel_ratio, panel_height * device_pixel_ratio, app.view_config, null);

    app.view.setDeviceScale(device_pixel_ratio);
    app.view.setDOMReadyCallback(App, app, &onDOMReady);
    app.view.setBeginLoadingCallback(App, app, &onBeginLoading);
    app.view.setFinishLoadingCallback(App, app, &onFinishLoading);
    app.view.setFailLoadingCallback(App, app, &onFailLoading);
    app.view.setConsoleMessageCallback(App, app, &onConsoleMessage);

    app.surface = app.view.getSurface();
    // app.surface.clearDirtyBounds();

    // app.view.loadURL("file:///Users/joelgustafson/Projects/andromeda/assets/app.html");
    app.view.loadHTML(
        \\<!DOCTYPE html>
        \\<html>
        \\  <head>
        \\    <script>console.log("JFKLDSJFKL")</script>
        \\  </head>
        \\  <body>
        \\    <h1>HELLO WORLD</h1>
        \\    <hr />
        \\    <ul>
        \\      <li>a list</li>
        \\      <li>in HTML!</li>
        \\    </ul>
        \\  </body>
        \\</html>
    );

    {
        const pixels = app.surface.lockPixels();
        defer app.surface.unlockPixels();

        std.log.info("pixels: {any} ({d})", .{ pixels.ptr, pixels.len });
        // std.log.info("pixel data: {s}", .{std.fmt.fmtSliceHexLower(pixels)});
    }

    try core.init(.{});

    // Vertex buffer
    {
        app.vertex_buffer = core.device.createBuffer(&.{
            .label = "vertex_buffer",
            .usage = .{ .vertex = true },
            .size = vertex_buffer_size,
            .mapped_at_creation = .true,
        });

        defer app.vertex_buffer.unmap();

        const map = app.vertex_buffer.getMappedRange(Point, 0, vertex_buffer_data.len) orelse
            @panic("failed to get vertex buffer map");

        @memcpy(map, vertex_buffer_data);
    }

    // Index buffer
    {
        app.index_buffer = core.device.createBuffer(&.{
            .label = "index_buffer",
            .usage = .{ .index = true },
            .size = index_buffer_size,
            .mapped_at_creation = .true,
        });

        defer app.index_buffer.unmap();

        const map = app.index_buffer.getMappedRange(u16, 0, index_buffer_data.len) orelse
            @panic("failed to get index buffer map");

        @memcpy(map, index_buffer_data);
    }

    // Param buffer
    {
        app.param_buffer = core.device.createBuffer(&.{
            .label = "param_buffer",
            .usage = gpu.Buffer.UsageFlags{ .uniform = true, .copy_dst = true },
            .size = @sizeOf(Params),
        });
    }

    var positions = [_]Point{
        .{ -100, 100 },
        .{ 0, 100 },
        .{ 100, 100 },
        .{ -100, 0 },
        .{ 0, 0 },
        .{ 100, 0 },
        .{ -100, -100 },
        .{ 0, -100 },
        .{ 100, -100 },
    };

    app.node_count = positions.len;

    // Position buffer
    {
        app.position_buffer = core.device.createBuffer(&.{
            .label = "position_buffer",
            .usage = .{ .storage = true, .copy_src = true },
            .size = app.node_count * @sizeOf(Point),
            .mapped_at_creation = .true,
        });

        defer app.position_buffer.unmap();

        const map = app.position_buffer.getMappedRange(Point, 0, app.node_count) orelse
            @panic("failed to get position buffer map");

        @memcpy(map, &positions);
    }

    // Node buffer
    {
        app.node_buffer = core.device.createBuffer(&.{
            .label = "node_buffer",
            .usage = .{ .storage = true, .copy_src = true },
            .size = app.node_count * @sizeOf(Body),
            .mapped_at_creation = .true,
        });

        defer app.node_buffer.unmap();

        const map = app.node_buffer.getMappedRange(Body, 0, app.node_count) orelse
            @panic("failed to get node buffer map");

        @memset(map, std.mem.zeroes(Body));
    }

    app.node_bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "node_bind_group_layout",
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, 0),
            gpu.BindGroupLayout.Entry.buffer(2, .{ .vertex = true }, .read_only_storage, false, 0),
        },
    }));

    app.node_bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .label = "node_bind_group",
        .layout = app.node_bind_group_layout,
        .entries = &.{
            // gpu.BindGroup.Entry.buffer(0, app.param_buffer, 0, app.param_buffer.getSize(), @sizeOf(Params)),
            // gpu.BindGroup.Entry.buffer(1, app.position_buffer, 0, app.position_buffer.getSize(), @sizeOf(Point)),
            // gpu.BindGroup.Entry.buffer(2, app.node_buffer, 0, app.node_buffer.getSize(), @sizeOf(Body)),
            gpu.BindGroup.Entry.buffer(0, app.param_buffer, 0, app.param_buffer.getSize()),
            gpu.BindGroup.Entry.buffer(1, app.position_buffer, 0, app.position_buffer.getSize()),
            gpu.BindGroup.Entry.buffer(2, app.node_buffer, 0, app.node_buffer.getSize()),
        },
    }));

    const node_shader_module = core.device.createShaderModuleWGSL("node.wgsl", @embedFile("node.wgsl"));
    defer node_shader_module.release();

    app.node_pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = "node_pipeline_layout",
        .bind_group_layouts = &.{app.node_bind_group_layout},
    }));

    // Fragment state
    const blend = gpu.BlendState{
        .color = .{
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
            .operation = .add,
        },
        .alpha = .{
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
            .operation = .add,
        },
    };

    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Point),
        .step_mode = .vertex,
        .attributes = &.{.{ .format = .float32x2, .offset = 0, .shader_location = 0 }},
    });

    app.node_pipeline = core.device.createRenderPipeline(&.{
        .label = "node_pipeline",
        .layout = app.node_pipeline_layout,
        .vertex = gpu.VertexState.init(.{
            .module = node_shader_module,
            .entry_point = "vertex_main",
            .buffers = &.{vertex_buffer_layout},
        }),
        .fragment = &gpu.FragmentState.init(.{
            .module = node_shader_module,
            .entry_point = "frag_main",
            .targets = &.{color_target},
        }),
    });

    app.sampler = core.device.createSampler(null);
    app.texture = core.device.createTexture(&gpu.Texture.Descriptor.init(.{
        .label = "texture",
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .format = .bgra8_unorm,
        .size = .{ .width = panel_width * device_pixel_ratio, .height = panel_height * device_pixel_ratio },
    }));

    app.panel_bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "panel_bind_group_layout",
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            gpu.BindGroupLayout.Entry.sampler(1, .{ .fragment = true }, .filtering),
            gpu.BindGroupLayout.Entry.texture(2, .{ .fragment = true }, .float, .dimension_2d, false),
        },
    }));

    app.texture_view = app.texture.createView(null);

    app.panel_bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .label = "panel_bind_group",
        .layout = app.panel_bind_group_layout,
        .entries = &.{
            // gpu.BindGroup.Entry.buffer(0, app.param_buffer, 0, app.param_buffer.getSize(), @sizeOf(Params)),
            gpu.BindGroup.Entry.buffer(0, app.param_buffer, 0, app.param_buffer.getSize()),
            gpu.BindGroup.Entry.sampler(1, app.sampler),
            gpu.BindGroup.Entry.textureView(2, app.texture_view),
        },
    }));

    app.panel_pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = "panel_pipeline_layout",
        .bind_group_layouts = &.{app.panel_bind_group_layout},
    }));

    const panel_shader_module = core.device.createShaderModuleWGSL("panel.wgsl", @embedFile("panel.wgsl"));
    defer panel_shader_module.release();

    app.panel_pipeline = core.device.createRenderPipeline(&.{
        .label = "panel_pipeline",
        .layout = app.panel_pipeline_layout,
        .vertex = gpu.VertexState.init(.{
            .module = panel_shader_module,
            .entry_point = "vertex_main",
            .buffers = &.{vertex_buffer_layout},
        }),
        .fragment = &gpu.FragmentState.init(.{
            .module = panel_shader_module,
            .entry_point = "frag_main",
            .targets = &.{color_target},
        }),
    });

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
}

pub fn deinit(app: *App) void {
    app.view.destroy();
    app.view_config.destroy();
    app.renderer.destroy();
    app.config.destroy();

    app.node_pipeline.release();
    app.node_pipeline_layout.release();
    app.node_bind_group.release();
    app.node_bind_group_layout.release();

    app.panel_pipeline.release();
    app.panel_pipeline_layout.release();
    app.panel_bind_group.release();
    app.panel_bind_group_layout.release();

    app.texture.release();
    app.sampler.release();

    app.texture_view.release();

    app.param_buffer.release();
    app.index_buffer.release();
    app.vertex_buffer.release();
    app.node_buffer.release();
    app.position_buffer.release();

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
                var zoom = app.zoom - e.yoffset;
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

    core.queue.writeBuffer(app.param_buffer, 0, @as([]const Params, &.{app.params}));

    const encoder = core.device.createCommandEncoder(null);
    defer encoder.release();

    {
        const texture_view = core.swap_chain.getCurrentTextureView() orelse @panic("failed to get texture view");
        defer texture_view.release();

        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{gpu.RenderPassColorAttachment{
                .view = texture_view,
                .clear_value = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1.0 },
                .load_op = .clear,
                .store_op = .store,
            }},
        });

        const pass = encoder.beginRenderPass(&render_pass_info);
        defer pass.release();

        pass.setPipeline(app.node_pipeline);
        pass.setBindGroup(0, app.node_bind_group, null);
        pass.setVertexBuffer(0, app.vertex_buffer, 0, gpu.whole_size);
        pass.setIndexBuffer(app.index_buffer, .uint16, 0, gpu.whole_size);
        pass.drawIndexed(index_buffer_data.len, app.node_count, 0, 0, 0);

        pass.setPipeline(app.panel_pipeline);
        pass.setBindGroup(0, app.panel_bind_group, null);
        pass.setVertexBuffer(0, app.vertex_buffer, 0, gpu.whole_size);
        pass.setIndexBuffer(app.index_buffer, .uint16, 0, gpu.whole_size);
        pass.drawIndexed(index_buffer_data.len, 1, 0, 0, 0);

        pass.end();
    }

    {
        const command = encoder.finish(null);
        defer command.release();

        core.queue.submit(&[_]*gpu.CommandBuffer{command});
        core.swap_chain.present();
    }

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

pub fn updateMainThread(app: *App) !bool {
    app.renderer.update();
    app.renderer.render();

    const bounds = app.surface.getDirtyBounds();
    if (!bounds.isEmpty()) {
        std.log.info("DIRTY BOUNDS ({any})", .{bounds});
        const pixels = app.surface.lockPixels();
        defer app.surface.unlockPixels();
        defer app.surface.clearDirtyBounds();

        core.queue.writeTexture(
            &.{ .texture = app.texture },
            &.{ .bytes_per_row = 4 * panel_width * device_pixel_ratio, .rows_per_image = panel_height * device_pixel_ratio },
            &.{ .width = panel_width * device_pixel_ratio, .height = panel_height * device_pixel_ratio },
            pixels,
        );
    }

    return false;
}

fn getScale(zoom: f32) f32 {
    return 256 / ((std.math.pow(f32, zoom + 1, 2) - 1) / 256 + 256);
}

fn onDOMReady(app: *App, event: ul.Ultralight.View.DOMReadyEvent) void {
    _ = app;
    _ = event;
    std.log.info("onDOMReady", .{});
}

fn onBeginLoading(app: *App, event: ul.Ultralight.View.BeginLoadingEvent) void {
    _ = app;
    std.log.info("onBeginLoading: {s}", .{event.url});
}

fn onFinishLoading(app: *App, event: ul.Ultralight.View.FinishLoadingEvent) void {
    _ = app;
    _ = event;
    std.log.info("onFinishLoading", .{});
}

fn onFailLoading(app: *App, event: ul.Ultralight.View.FailLoadingEvent) void {
    _ = app;
    std.log.info("onFailLoading: [{s}] {s}", .{ event.error_domain, event.description });
}

fn onConsoleMessage(_: *App, event: ul.Ultralight.View.ConsoleMessageEvent) void {
    const log = std.io.getStdOut().writer();
    const err = switch (event.level) {
        .Log => log.print("[console.log] {s}\n", .{event.message}),
        .Warning => log.print("[console.warn] {s}\n", .{event.message}),
        .Error => log.print("[console.error] {s}\n", .{event.message}),
        .Debug => log.print("[console.debug] {s}\n", .{event.message}),
        .Info => log.print("[console.info] {s}\n", .{event.message}),
    };

    err catch @panic("fjkdls");
}
