const std = @import("std");
const mach = @import("mach");
const core = mach.core;
const gpu = mach.gpu;

pub const Point = @Vector(2, f32);
pub const Body = packed struct { mass: f32 };

pub const Params = packed struct {
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

const vertex_buffer_data: []const Point = &.{
    .{ -1.0, 1.0 },
    .{ 1.0, 1.0 },
    .{ 1.0, -1.0 },
    .{ -1.0, -1.0 },
};

const vertex_buffer_size = vertex_buffer_data.len * @sizeOf(Point);

const index_buffer_data: []const u16 = &.{ 0, 1, 2, 2, 0, 3 };
const index_buffer_size = index_buffer_data.len * @sizeOf(u16);

node_count: u32,
node_pipeline: *gpu.RenderPipeline,
node_pipeline_layout: *gpu.PipelineLayout,

node_bind_group: *gpu.BindGroup,
node_bind_group_layout: *gpu.BindGroupLayout,

texture_view: *gpu.TextureView,

vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
param_buffer: *gpu.Buffer,
position_buffer: *gpu.Buffer,
node_buffer: *gpu.Buffer,

params: Params,

const Pipeline = @This();

pub fn init(positions: []const Point) !Pipeline {
    // self.node_count = @intCast(self.reader.map.len / @sizeOf(Point));
    var self: Pipeline = undefined;
    self.node_count = @intCast(positions.len);

    // Vertex buffer
    {
        self.vertex_buffer = core.device.createBuffer(&.{
            .label = "vertex_buffer",
            .usage = .{ .vertex = true },
            .size = vertex_buffer_size,
            .mapped_at_creation = .true,
        });

        defer self.vertex_buffer.unmap();

        const map = self.vertex_buffer.getMappedRange(Point, 0, vertex_buffer_data.len) orelse
            @panic("failed to get vertex buffer map");

        @memcpy(map, vertex_buffer_data);
    }

    // Index buffer
    {
        self.index_buffer = core.device.createBuffer(&.{
            .label = "index_buffer",
            .usage = .{ .index = true },
            .size = index_buffer_size,
            .mapped_at_creation = .true,
        });

        defer self.index_buffer.unmap();

        const map = self.index_buffer.getMappedRange(u16, 0, index_buffer_data.len) orelse
            @panic("failed to get index buffer map");

        @memcpy(map, index_buffer_data);
    }

    // Param buffer
    {
        self.param_buffer = core.device.createBuffer(&.{
            .label = "param_buffer",
            .usage = gpu.Buffer.UsageFlags{ .uniform = true, .copy_dst = true },
            .size = @sizeOf(Params),
        });
    }

    // Position buffer
    {
        self.position_buffer = core.device.createBuffer(&.{
            .label = "position_buffer",
            .usage = .{ .storage = true, .copy_src = true, .copy_dst = true },
            .size = self.node_count * @sizeOf(Point),
            .mapped_at_creation = .true,
        });

        defer self.position_buffer.unmap();

        const map = self.position_buffer.getMappedRange(Point, 0, self.node_count) orelse
            @panic("failed to get position buffer map");

        @memcpy(map, positions);
    }

    // Node buffer
    {
        self.node_buffer = core.device.createBuffer(&.{
            .label = "node_buffer",
            .usage = .{ .storage = true, .copy_src = true },
            .size = self.node_count * @sizeOf(Body),
            .mapped_at_creation = .true,
        });

        defer self.node_buffer.unmap();

        const map = self.node_buffer.getMappedRange(Body, 0, self.node_count) orelse
            @panic("failed to get node buffer map");

        @memset(map, std.mem.zeroes(Body));
    }

    self.node_bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .label = "node_bind_group_layout",
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, 0),
            gpu.BindGroupLayout.Entry.buffer(2, .{ .vertex = true }, .read_only_storage, false, 0),
        },
    }));

    self.node_bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .label = "node_bind_group",
        .layout = self.node_bind_group_layout,
        .entries = &.{
            gpu.BindGroup.Entry.buffer(0, self.param_buffer, 0, self.param_buffer.getSize()),
            gpu.BindGroup.Entry.buffer(1, self.position_buffer, 0, self.position_buffer.getSize()),
            gpu.BindGroup.Entry.buffer(2, self.node_buffer, 0, self.node_buffer.getSize()),
        },
    }));

    const node_shader_module = core.device.createShaderModuleWGSL("node.wgsl", @embedFile("node.wgsl"));
    defer node_shader_module.release();

    self.node_pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .label = "node_pipeline_layout",
        .bind_group_layouts = &.{self.node_bind_group_layout},
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
        // .color = .{
        //     .src_factor = .one,
        //     .dst_factor = .zero,
        //     .operation = .add,
        // },
        // .alpha = .{
        //     .src_factor = .one,
        //     .dst_factor = .zero,
        //     .operation = .add,
        // },
    };

    std.log.info("core.descriptor.format: {any}", .{core.descriptor.format});
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        // .format = .rgba8_unorm_srgb,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Point),
        .step_mode = .vertex,
        .attributes = &.{.{ .format = .float32x2, .offset = 0, .shader_location = 0 }},
    });

    self.node_pipeline = core.device.createRenderPipeline(&.{
        .label = "node_pipeline",
        .layout = self.node_pipeline_layout,
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

    return self;
}

pub fn deinit(self: *Pipeline) void {
    self.node_pipeline.release();
    self.node_pipeline_layout.release();
    self.node_bind_group.release();
    self.node_bind_group_layout.release();

    self.param_buffer.release();
    self.index_buffer.release();
    self.vertex_buffer.release();
    self.node_buffer.release();
    self.position_buffer.release();

    core.deinit();
}

pub fn updatePositions(self: *Pipeline, positions: []const Point) void {
    core.queue.writeBuffer(self.position_buffer, 0, positions);
}

pub fn render(self: *Pipeline, params: *const Params) void {
    core.queue.writeBuffer(self.param_buffer, 0, @as([*]const Params, @ptrCast(params))[0..1]);

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

        pass.setPipeline(self.node_pipeline);
        pass.setBindGroup(0, self.node_bind_group, null);
        pass.setVertexBuffer(0, self.vertex_buffer, 0, gpu.whole_size);
        pass.setIndexBuffer(self.index_buffer, .uint16, 0, gpu.whole_size);
        pass.drawIndexed(index_buffer_data.len, @intCast(self.node_count), 0, 0, 0);

        pass.end();
    }

    {
        const command = encoder.finish(null);
        defer command.release();

        core.queue.submit(&[_]*gpu.CommandBuffer{command});

        core.swap_chain.present();
    }
}

fn getScale(zoom: f32) f32 {
    return 256 / ((std.math.pow(f32, zoom + 1, 2) - 1) / 256 + 256);
}
