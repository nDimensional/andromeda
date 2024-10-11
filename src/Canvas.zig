const builtin = @import("builtin");
const std = @import("std");
const gtk = @import("gtk");
const gdk = @import("gdk");
const glib = @import("glib");
const gobject = @import("gobject");

const c = @import("epoxy/c.zig");

const allocator = std.heap.c_allocator;

const device_pixel_ratio = if (builtin.os.tag.isDarwin()) 2 else 1;

const TEMPLATE = @embedFile("./data/ui/Canvas.xml");

const MAX_ZOOM = 8192;
const MIN_ZOOM = 0;

const Data = struct {
    shader_program: c.GLuint = 0,
    vao: c.GLuint = 0,
    vbo: c.GLuint = 0,
    positions: c.GLuint = 0,
    sizes: c.GLuint = 0,
    resolution_location: c.GLint = 0,
    offset_location: c.GLint = 0,
    scale_location: c.GLint = 0,
    scale_radius_location: c.GLint = 0,
    device_pixel_ratio_location: c.GLint = 0,
    offset: @Vector(2, f32) = .{ 0, 0 },
    anchor: @Vector(2, f32) = .{ 0, 0 },
    cursor: @Vector(2, f32) = .{ 0, 0 },
    count: u32 = 0,
    zoom: f32 = 0,
    scale: f32 = 1,
    scale_radius: f32 = 1,
};

pub const Canvas = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Widget;

    const Private = struct {
        area: *gtk.GLArea,
        data: ?*Data,
        var offset: c_int = 0;
    };

    pub const getGObjectType = gobject.ext.defineClass(Canvas, .{
        .name = "Canvas",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub const signals = struct {};

    pub fn new() *Canvas {
        return Canvas.newWith(.{});
    }

    pub fn as(canvas: *Canvas, comptime T: type) *T {
        return gobject.ext.as(T, canvas);
    }

    fn init(canvas: *Canvas, _: *Class) callconv(.C) void {
        gtk.Widget.initTemplate(canvas.as(gtk.Widget));
        gtk.Widget.setLayoutManager(canvas.as(gtk.Widget), gtk.BinLayout.new().as(gtk.LayoutManager));

        const area = canvas.private().area;
        const data = allocator.create(Data) catch |err| @panic(@errorName(err));
        data.* = Data{};

        canvas.private().data = data;

        _ = gtk.GLArea.signals.render.connect(area, *Data, &handleRender, data, .{});
        _ = gtk.Widget.signals.realize.connect(area, *Data, &handleRealize, data, .{});
        _ = gtk.Widget.signals.unrealize.connect(area, *Data, &handleUnrealize, data, .{});

        // Set up mouse event controllers
        const click_gesture = gtk.GestureClick.new();
        gtk.GestureSingle.setButton(click_gesture.as(gtk.GestureSingle), gdk.BUTTON_PRIMARY);
        gtk.Widget.addController(area.as(gtk.Widget), click_gesture.as(gtk.EventController));
        _ = gtk.GestureClick.signals.pressed.connect(click_gesture, *Data, &handleMousePress, data, .{});
        _ = gtk.GestureClick.signals.released.connect(click_gesture, *Data, &handleMouseRelease, data, .{});

        const drag_gesture = gtk.GestureDrag.new();
        gtk.Widget.addController(area.as(gtk.Widget), drag_gesture.as(gtk.EventController));
        _ = gtk.GestureDrag.signals.drag_update.connect(drag_gesture, *Data, &handleMouseDrag, data, .{});

        const scroll_controller = gtk.EventControllerScroll.new(.{ .vertical = true });
        gtk.Widget.addController(area.as(gtk.Widget), scroll_controller.as(gtk.EventController));
        _ = gtk.EventControllerScroll.signals.scroll.connect(scroll_controller, *Data, &handleMouseScroll, data, .{});

        const motion_controller = gtk.EventControllerMotion.new();
        gtk.Widget.addController(area.as(gtk.Widget), motion_controller.as(gtk.EventController));
        _ = gtk.EventControllerMotion.signals.motion.connect(motion_controller, *Data, &handleMouseMotion, data, .{});

        // Set up zoom gesture controller
        const zoom_gesture = gtk.GestureZoom.new();
        gtk.Widget.addController(area.as(gtk.Widget), zoom_gesture.as(gtk.EventController));
        _ = gtk.GestureZoom.signals.scale_changed.connect(zoom_gesture, *Data, &handleZoom, data, .{});
    }

    fn dispose(ls: *Canvas) callconv(.C) void {
        if (ls.private().data) |data| allocator.destroy(data);

        gtk.Widget.disposeTemplate(ls.as(gtk.Widget), getGObjectType());
        gobject.Object.virtual_methods.dispose.call(Class.parent.as(gobject.Object.Class), ls.as(gobject.Object));
    }

    fn finalize(ls: *Canvas) callconv(.C) void {
        Class.parent.as(gobject.Object.Class).finalize.?(ls.as(gobject.Object));
    }

    fn private(ls: *Canvas) *Private {
        return gobject.ext.impl_helpers.getPrivate(ls, Private, Private.offset);
    }

    pub fn load(self: *Canvas, sizes: []const f32, positions: []const @Vector(2, f32)) void {
        const area = self.private().area;
        const data = self.private().data orelse return;
        data.count = @intCast(positions.len);

        if (data.count != sizes.len) {
            std.log.warn("expected data.count == sizes.len ({d} != {d})", .{ data.count, sizes.len });
        }

        area.makeCurrent();
        if (area.getError()) |err| {
            std.log.err("error rendering GLArea: {any}", .{err});
            return;
        }

        c.glBindBuffer(c.GL_ARRAY_BUFFER, data.sizes);
        c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(@sizeOf(f32) * sizes.len), sizes.ptr, c.GL_DYNAMIC_DRAW);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, data.positions);
        c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(@sizeOf(@Vector(2, f32)) * positions.len), positions.ptr, c.GL_DYNAMIC_DRAW);

        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
        area.queueRender();
    }

    pub fn update(self: *Canvas, positions: []const @Vector(2, f32)) void {
        const area = self.private().area;
        const data = self.private().data orelse return;
        if (data.count != positions.len) {
            std.log.warn("expected data.count == positions.len ({d} != {d})", .{ data.count, positions.len });
        }

        area.makeCurrent();
        if (area.getError()) |err| {
            std.log.err("error rendering GLArea: {any}", .{err});
            return;
        }

        c.glBindBuffer(c.GL_ARRAY_BUFFER, data.positions);

        const byte_len: i64 = @intCast(@sizeOf(@Vector(2, f32)) * positions.len);
        c.glBufferSubData(c.GL_ARRAY_BUFFER, 0, byte_len, positions.ptr);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
        area.queueRender();
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;

        pub const Instance = Canvas;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.C) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
            gobject.Object.virtual_methods.finalize.implement(class, &finalize);
            const template = glib.Bytes.newStatic(TEMPLATE.ptr, TEMPLATE.len);
            class.as(gtk.Widget.Class).setTemplate(template);
            class.bindTemplateChildPrivate("area", .{});
        }

        fn bindTemplateChildPrivate(class: *Class, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
            gtk.ext.impl_helpers.bindTemplateChildPrivate(class, name, Private, Private.offset, options);
        }
    };
};

const vertices: []const f32 = &.{
    // zig fmt: off
    -1.0, -1.0,
     1.0, -1.0,
     1.0,  1.0,
    -1.0,  1.0,
    // zig fmt: on
};

fn handleRealize(area: *gtk.GLArea, data: *Data) callconv(.C) void {
    std.log.info("handleRealize", .{});

    area.setAutoRender(0);

    gtk.GLArea.makeCurrent(area);
    if (area.getError()) |err| {
        std.log.err("error handling GLArea realize signal: {any}", .{err});
        return;
    }

    std.log.info("OpenGL version: {d}", .{c.epoxy_gl_version()});

    const shader_program = createShaderProgram();
    const resolution_location = c.glGetUniformLocation(shader_program, "uResolution");
    const offset_location = c.glGetUniformLocation(shader_program, "uOffset");
    const scale_location = c.glGetUniformLocation(shader_program, "uScale");
    const scale_radius_location = c.glGetUniformLocation(shader_program, "uScaleRadius");
    const device_pixel_ratio_location = c.glGetUniformLocation(shader_program, "uDevicePixelRatio");

    var vao: c.GLuint = undefined;
    var vbo: c.GLuint = undefined;
    var positions: c.GLuint = undefined;
    var sizes: c.GLuint = undefined;

    // Create VAO and VBO
    c.glGenVertexArrays(1, &vao);
    c.glGenBuffers(1, &vbo);
    c.glGenBuffers(1, &positions);
    c.glGenBuffers(1, &sizes);

    c.glBindVertexArray(vao);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(f32) * vertices.len, vertices.ptr, c.GL_STATIC_DRAW);

    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(@Vector(2, f32)), null);
    c.glEnableVertexAttribArray(0);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, positions);
    c.glBufferData(c.GL_ARRAY_BUFFER, 0, null, c.GL_DYNAMIC_DRAW);
    c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(@Vector(2, f32)), null);
    c.glEnableVertexAttribArray(1);
    c.glVertexAttribDivisor(1, 1);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, sizes);
    c.glBufferData(c.GL_ARRAY_BUFFER, 0, null, c.GL_DYNAMIC_DRAW);
    c.glVertexAttribPointer(2, 1, c.GL_FLOAT, c.GL_FALSE, @sizeOf(f32), null);
    c.glEnableVertexAttribArray(2);
    c.glVertexAttribDivisor(2, 1);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    // Enable blending for transparency
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

    data.shader_program = shader_program;
    data.vao = vao;
    data.vbo = vbo;
    data.positions = positions;
    data.sizes = sizes;
    data.resolution_location = resolution_location;
    data.offset_location = offset_location;
    data.scale_location = scale_location;
    data.scale_radius_location = scale_radius_location;
    data.device_pixel_ratio_location = device_pixel_ratio_location;
    data.offset = .{ 0, 0};
    data.anchor = .{ 0, 0};
    data.cursor = .{ 0, 0};
    data.count = 0;
    data.zoom = 512;
    data.scale = getScale(data.zoom);
    data.scale_radius = getScaleRadius(data.scale);
}

fn handleUnrealize(area: *gtk.GLArea, data: *Data) callconv(.C) void {
    std.log.info("handleUnrealize", .{});

    gtk.GLArea.makeCurrent(area);
    if (area.getError()) |err| {
        std.log.err("error handling GLArea unrealize signal: {any}", .{err});
        return;
    }

    // Clean up OpenGL resources
    c.glDeleteVertexArrays(1, &data.vao);
    c.glDeleteBuffers(1, &data.vbo);
    c.glDeleteBuffers(1, &data.positions);
    c.glDeleteBuffers(1, &data.sizes);
    c.glDeleteProgram(data.shader_program);
}

fn handleRender(area: *gtk.GLArea, ctx: *gdk.GLContext, data: *Data) callconv(.C) c_int {
    _ = ctx;

    const width = gtk.Widget.getWidth(area.as(gtk.Widget));
    const height = gtk.Widget.getHeight(area.as(gtk.Widget));

    c.glViewport(0, 0, width * device_pixel_ratio, height * device_pixel_ratio);

    c.glClearColor(1.0, 1.0, 1.0, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    // Use the shader program
    c.glUseProgram(data.shader_program);

    c.glUniform2f(data.resolution_location, @floatFromInt(width), @floatFromInt(height));
    c.glUniform2f(data.offset_location, data.offset[0], data.offset[1]);
    c.glUniform1f(data.scale_location, data.scale);
    c.glUniform1f(data.scale_radius_location, data.scale_radius);
    c.glUniform1f(data.device_pixel_ratio_location, device_pixel_ratio);

    // Bind the VAO
    c.glBindVertexArray(data.vao);

    // Draw the triangle
    c.glDrawArraysInstanced(c.GL_TRIANGLE_FAN, 0, 4, @intCast(data.count));

    // Unbind the VAO
    c.glBindVertexArray(0);
    c.glUseProgram(0);

    // Flush to ensure all commands are sent to the GPU
    c.glFlush();

    return 1;
}

const vertex_shader_source =
    \\ #version 410 core
    \\ layout (location = 0) in vec2 aPos;
    \\ layout (location = 1) in vec2 aOffset;
    \\ layout (location = 2) in float aDegree;
    \\ uniform vec2 uResolution;
    \\ uniform vec2 uOffset;
    \\ uniform float uScale;
    \\ uniform float uScaleRadius;
    \\ uniform float uDevicePixelRatio;
    \\ out vec2 vCenter;
    \\ out float vRadius;
    \\ void main() {
    \\     vec2 vPos = (aPos * vec2(100.0) + uOffset + aOffset) * vec2(uScale) / uResolution;
    \\     gl_Position = vec4(vPos, 0.0, 1.0);
    \\     vCenter = (uResolution * uDevicePixelRatio / 2) + (uOffset + aOffset) * uScale;
    \\     vRadius = max(2, uScale * (10 + sqrt(aDegree)) / uScaleRadius);
    \\ }
;

const fragment_shader_source =
    \\ #version 410 core
    \\ in vec2 vCenter;
    \\ in float vRadius;
    \\ out vec4 FragColor;
    \\ uniform vec2 uResolution;
    \\ void main() {
    \\     vec2 pixelPos = gl_FragCoord.xy;
    \\     float dist = distance(pixelPos, vCenter);
    \\     float alpha = 1.0 - smoothstep(vRadius - 2.0, vRadius, dist);
    \\     FragColor = vec4(0.0, 0.0, 0.0, alpha);
    \\ }
;

fn createShaderProgram() c.GLuint {
    const vertex_shader = c.glCreateShader(c.GL_VERTEX_SHADER);
    defer c.glDeleteShader(vertex_shader);

    c.glShaderSource(vertex_shader, 1, &vertex_shader_source.ptr, null);
    c.glCompileShader(vertex_shader);

    const fragment_shader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    defer c.glDeleteShader(fragment_shader);

    c.glShaderSource(fragment_shader, 1, &fragment_shader_source.ptr, null);
    c.glCompileShader(fragment_shader);

    const shader_program = c.glCreateProgram();
    c.glAttachShader(shader_program, vertex_shader);
    c.glAttachShader(shader_program, fragment_shader);
    c.glLinkProgram(shader_program);

    return shader_program;
}

fn handleMousePress(gesture: *gtk.GestureClick, n_press: i32, x: f64, y: f64, data: *Data) callconv(.C) void {
    _ = gesture;
    _ = n_press;
    _ = x;
    _ = y;
    data.anchor = data.offset;
}

fn handleMouseRelease(gesture: *gtk.GestureClick, n_press: i32, x: f64, y: f64, data: *Data) callconv(.C) void {
    _ = gesture;
    _ = n_press;
    _ = x;
    _ = y;
    data.anchor = data.offset;
}

fn handleMouseDrag(gesture: *gtk.GestureDrag, offset_x: f64, offset_y: f64, data: *Data) callconv(.C) void {
    const offset: @Vector(2, f32) = .{
        @floatCast(offset_x * device_pixel_ratio / data.scale),
        @floatCast(-offset_y * device_pixel_ratio  / data.scale),
    };

    const area: *gtk.GLArea = @ptrCast(gtk.EventController.getWidget(gesture.as(gtk.EventController)));

    data.offset = data.anchor + offset;
    area.queueRender();
}

fn handleMouseScroll(controller: *gtk.EventControllerScroll, dx: f64, dy: f64, data: *Data) callconv(.C) c_int {
    std.log.info("handleMouseScroll: ({d}, {d})", .{ dx, dy });

    var zoom = data.zoom + (dy);
    zoom = @min(MAX_ZOOM, zoom);
    zoom = @max(MIN_ZOOM, zoom);
    data.zoom = @floatCast(zoom);
    data.scale = getScale(data.zoom);
    data.scale_radius = getScaleRadius(data.scale);

    const area: *gtk.GLArea = @ptrCast(gtk.EventController.getWidget(controller.as(gtk.EventController)));
    area.queueRender();

    return 1;
}

fn handleMouseMotion(controller: *gtk.EventControllerMotion, x: f64, y: f64, data: *Data) callconv(.C) void {
    _ = controller;

    data.cursor = .{@floatCast(x), @floatCast(y)};
}

fn handleZoom(gesture: *gtk.GestureZoom, scale: f64, data: *Data) callconv(.C) void {
    _ = gesture;
    _ = data;
    _ = scale;
}

inline fn getScale(zoom: f32) f32 {
    return 256 / ((std.math.pow(f32, zoom + 1, 2) - 1) / 256 + 256);
}

inline fn getScaleRadius(scale: f32) f32 {
    return std.math.sqrt(std.math.sqrt(scale));
}
