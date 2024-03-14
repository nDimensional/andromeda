const std = @import("std");
const core = @import("mach").core;
const gpu = core.gpu;

pub const App = @This();

const vertex_buffer_data: []const f32 = &.{ -1.0, 1.0, 1.0, 1.0, 1.0, -1.0, -1.0, -1.0 };
const vertex_buffer_size = vertex_buffer_data.len * @sizeOf(f32);

const index_buffer_data: []const u16 = &.{ 0, 1, 2, 2, 0, 3 };
const index_buffer_size = index_buffer_data.len * @sizeOf(u16);

title_timer: core.Timer,
pipeline: *gpu.RenderPipeline,

render_pipeline: *gpu.RenderPipeline,
vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
bind_group: *gpu.BindGroup,
param_buffer: *gpu.Buffer,
params: [7]f32 = undefined,

pub fn init(app: *App) !void {
    try core.init(.{});

    const vertex_buffer = core.device.createBuffer(&.{
        .label = "vertex_buffer",
        .usage = .{ .vertex = true },
        .size = vertex_buffer_size,
        .mapped_at_creation = .true,
    });

    {
        defer vertex_buffer.unmap();
        if (vertex_buffer.getMappedRange(f32, 0, vertex_buffer_size)) |range| {
            @memcpy(range, vertex_buffer_data);
        }
    }

    const index_buffer = core.device.createBuffer(&.{
        .label = "index_buffer",
        .usage = .{ .index = true },
        .size = index_buffer_size,
        .mapped_at_creation = .true,
    });

    {
        defer index_buffer.unmap();
        if (index_buffer.getMappedRange(u16, 0, index_buffer_size)) |range| {
            @memcpy(range, index_buffer_data);
        }
    }

    const param_buffer = core.device.createBuffer(&.{
        .label = "param_buffer",
        .usage = gpu.Buffer.UsageFlags{ .uniform = true, .copy_src = true },
        .size = app.params.len * @sizeOf(f32),
    });

    const node_count = 1;

    const position_buffer_size = node_count * 2 * @sizeOf(f32);
    const position_buffer = core.device.createBuffer(&.{
        .label = "position_buffer",
        .usage = .{ .storage = true, .copy_src = true },
        .size = position_buffer_size,
        .mapped_at_creation = .true,
    });

    {
        const map = position_buffer.getMappedRange(f32, 0, position_buffer_size);
        defer position_buffer.unmap();

        if (map) |range| {
            range[0] = 0;
            range[1] = 0;
        }
    }

    const node_buffer_size = node_count * 1 * @sizeOf(f32);
    const node_buffer = core.device.createBuffer(&.{
        .label = "node_buffer",
        .usage = .{ .storage = true, .copy_src = true },
        .size = node_buffer_size,
        .mapped_at_creation = .true,
    });

    {
        const map = node_buffer.getMappedRange(f32, 0, node_buffer_size);
        defer node_buffer.unmap();

        if (map) |range| {
            range[0] = 1;
        }
    }

    const bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "bind_group_layout",
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, 0),
            gpu.BindGroupLayout.Entry.buffer(2, .{ .vertex = true }, .read_only_storage, false, 0),
        },
    }));

    const bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .label = "bind_group",
        .layout = bind_group_layout,
        .entries = &.{
            .{ .binding = 0, .buffer = param_buffer, .offset = 0, .size = app.params.len * @sizeOf(f32) },
            .{ .binding = 1, .buffer = position_buffer, .offset = 0, .size = node_count * 2 * @sizeOf(f32) },
            .{ .binding = 2, .buffer = node_buffer, .offset = 0, .size = node_count * 1 * @sizeOf(f32) },
        },
    }));

    const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };

    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState{
            .module = shader_module,
            .entry_point = "vertex_main",
        },
    };

    const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    const shader_module2 = core.device.createShaderModuleWGSL("nodes.wgsl", @embedFile("nodes.wgsl"));
    defer shader_module2.release();

    const render_pipeline_layout = &gpu.PipelineLayout.Descriptor.init(.{
        .label = "pipeline_layout",
        .bind_group_layouts = &.{bind_group_layout},
    });

    const render_pipeline = core.device.createRenderPipeline(&.{
        .label = "render_pipeline",
        .layout = core.device.createPipelineLayout(render_pipeline_layout),
        .vertex = gpu.VertexState{
            .module = shader_module2,
            .entry_point = "vert_node",
        },
        .fragment = &gpu.FragmentState.init(.{
            .module = shader_module2,
            .entry_point = "frag_node",
            .targets = &.{color_target},
        }),
    });

    const title_timer = try core.Timer.start();
    app.* = .{
        .title_timer = title_timer,
        .pipeline = pipeline,
        .render_pipeline = render_pipeline,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .bind_group = bind_group,
        .param_buffer = param_buffer,
    };
}

pub fn deinit(app: *App) void {
    defer core.deinit();
    _ = app;
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .close => return true,
            else => {},
        }
    }

    const queue = core.queue;
    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.draw(3, 1, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.present();
    back_buffer_view.release();

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
