const std = @import("std");
const core = @import("mach").core;
const gpu = core.gpu;

pub const App = @This();

pub const mach_core_options = core.ComptimeOptions{
    .use_wgpu = false,
    .use_sysgpu = true,
};

const vertex_buffer_data: []const f32 = &.{ -1.0, 1.0, 1.0, 1.0, 1.0, -1.0, -1.0, -1.0 };
const vertex_buffer_size = vertex_buffer_data.len * @sizeOf(f32);

const index_buffer_data: []const u16 = &.{ 0, 1, 2, 2, 0, 3 };
const index_buffer_size = index_buffer_data.len * @sizeOf(u16);

title_timer: core.Timer,

pipeline: *gpu.RenderPipeline,
pipeline_layout: *gpu.PipelineLayout,

bind_group: *gpu.BindGroup,
bind_group_layout: *gpu.BindGroupLayout,

vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
param_buffer: *gpu.Buffer,
position_buffer: *gpu.Buffer,
node_buffer: *gpu.Buffer,

params: [7]f32 = undefined,

pub fn init(app: *App) !void {
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

        const map = app.vertex_buffer.getMappedRange(f32, 0, vertex_buffer_data.len) orelse
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
            .size = app.params.len * @sizeOf(f32),
        });
    }

    const node_count = 1;

    {
        const position_buffer_size = node_count * 2 * @sizeOf(f32);
        app.position_buffer = core.device.createBuffer(&.{
            .label = "position_buffer",
            .usage = .{ .storage = true, .copy_src = true },
            .size = position_buffer_size,
            .mapped_at_creation = .true,
        });

        defer app.position_buffer.unmap();

        const map = app.position_buffer.getMappedRange(f32, 0, position_buffer_size) orelse
            @panic("failed to get position buffer map");

        @memset(map, 0);
    }

    {
        const node_buffer_size = node_count * 1 * @sizeOf(f32);
        app.node_buffer = core.device.createBuffer(&.{
            .label = "node_buffer",
            .usage = .{ .storage = true, .copy_src = true },
            .size = node_buffer_size,
            .mapped_at_creation = .true,
        });

        defer app.node_buffer.unmap();

        const map = app.node_buffer.getMappedRange(f32, 0, node_buffer_size) orelse
            @panic("failed to get node buffer map");

        @memset(map, 1);
    }

    app.bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "bind_group_layout",
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, 0),
            gpu.BindGroupLayout.Entry.buffer(2, .{ .vertex = true }, .read_only_storage, false, 0),
        },
    }));

    app.bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .label = "bind_group",
        .layout = app.bind_group_layout,
        .entries = &.{
            .{ .binding = 0, .buffer = app.param_buffer, .offset = 0, .size = app.params.len * @sizeOf(f32) },
            .{ .binding = 1, .buffer = app.position_buffer, .offset = 0, .size = node_count * 2 * @sizeOf(f32) },
            .{ .binding = 2, .buffer = app.node_buffer, .offset = 0, .size = node_count * 1 * @sizeOf(f32) },
        },
    }));

    const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    app.pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = "pipeline_layout",
        .bind_group_layouts = &.{app.bind_group_layout},
    }));

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = 2 * @sizeOf(f32),
        .step_mode = .vertex,
        .attributes = &.{.{ .format = .float32x2, .offset = 0, .shader_location = 0 }},
    });

    app.pipeline = core.device.createRenderPipeline(&.{
        .label = "pipeline",
        .layout = app.pipeline_layout,
        .vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vertex_main",
            .buffers = &.{vertex_buffer_layout},
        }),
        .fragment = &gpu.FragmentState.init(.{
            .module = shader_module,
            .entry_point = "frag_main",
            .targets = &.{color_target},
        }),
    });

    app.title_timer = try core.Timer.start();
}

pub fn deinit(app: *App) void {
    app.pipeline.release();
    app.pipeline_layout.release();
    app.bind_group.release();
    app.bind_group_layout.release();

    app.index_buffer.release();
    app.param_buffer.release();
    app.vertex_buffer.release();
    app.node_buffer.release();
    app.position_buffer.release();

    core.deinit();
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            else => {},
        }
    }

    const size = core.size();

    app.params[0] = @floatFromInt(size.width); // width
    app.params[1] = @floatFromInt(size.height); // height
    app.params[2] = 0; // offset_x
    app.params[3] = 0; // offset_y
    app.params[4] = 1; // scale
    app.params[5] = 2; // min_radius
    app.params[6] = 1; // scale_radius
    core.queue.writeBuffer(app.param_buffer, 0, &app.params);

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

        pass.setPipeline(app.pipeline);
        pass.setBindGroup(0, app.bind_group, null);
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
        try core.printTitle("Triangle [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }

    return false;
}
