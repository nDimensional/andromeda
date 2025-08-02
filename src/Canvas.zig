const builtin = @import("builtin");
const std = @import("std");
const gtk = @import("gtk");
const gdk = @import("gdk");
const glib = @import("glib");
const gobject = @import("gobject");

const c = @import("epoxy/c.zig");

const allocator = std.heap.c_allocator;

const initial_positions: []const @Vector(2, f32) = &.{};

const TEMPLATE = @embedFile("./data/ui/Canvas.xml");

const MAX_ZOOM = 8192;
const MIN_ZOOM = 0;

const Data = struct {
    shader_program: c.GLuint = 0,
    vao: c.GLuint = 0,
    vbo: c.GLuint = 0,
    positions: c.GLuint = 0,
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
    update_callback: ?*const fn (?*anyopaque) callconv(.C) void = null,
    update_callback_data: ?*anyopaque = null,
    index_buffer: c.GLuint = 0,
    index_permutation: ?[]u32 = null,
    reordered_positions: ?[]@Vector(2, f32) = null,
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
        Class.parent.as(gobject.Object.Class).f_finalize.?(ls.as(gobject.Object));
    }

    fn private(ls: *Canvas) *Private {
        return gobject.ext.impl_helpers.getPrivate(ls, Private, Private.offset);
    }

    pub fn load(self: *Canvas, _: []const f32, position: []const @Vector(2, f32)) !void {
        const area = self.private().area;
        const data = self.private().data orelse return;
        data.count = @intCast(position.len);

        area.makeCurrent();
        if (area.getError()) |err| {
            std.log.err("error rendering GLArea: {any}", .{err});
            return error.Error;
        }

        // Generate index permutation for LOD
        const index_permutation = allocator.alloc(u32, data.count) catch |err| {
            std.log.err("failed to allocate index permutation: {any}", .{err});
            return err;
        };
        errdefer allocator.free(index_permutation);

        const reordered_positions = allocator.alloc(@Vector(2, f32), data.count) catch |err| {
            std.log.err("failed to allocate reordered positions: {any}", .{err});
            return err;
        };
        errdefer allocator.free(reordered_positions);

        for (index_permutation, 0..) |*idx, i| idx.* = @intCast(i);
        var prng = std.Random.Xoshiro256.init(0);
        prng.random().shuffle(u32, index_permutation);

        data.reordered_positions = reordered_positions;
        data.index_permutation = index_permutation;

        // Reorder positions according to permutation
        for (data.index_permutation.?, 0..) |original_idx, new_idx| {
            data.reordered_positions.?[new_idx] = position[original_idx];
        }

        c.glBindBuffer(c.GL_ARRAY_BUFFER, data.positions);
        c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(@sizeOf(@Vector(2, f32)) * reordered_positions.len), reordered_positions.ptr, c.GL_DYNAMIC_DRAW);

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

        // Reorder positions according to permutation
        const index_permutation = data.index_permutation orelse {
            std.log.warn("missing data.index_permutation", .{});
            return;
        };

        const reordered_positions = data.reordered_positions orelse {
            std.log.warn("missing data.reordered_positions", .{});
            return;
        };

        for (index_permutation, 0..) |original_idx, new_idx|
            reordered_positions[new_idx] = positions[original_idx];

        c.glBindBuffer(c.GL_ARRAY_BUFFER, data.positions);
        const byte_len: i64 = @intCast(@sizeOf(@Vector(2, f32)) * reordered_positions.len);
        c.glBufferSubData(c.GL_ARRAY_BUFFER, 0, byte_len, reordered_positions.ptr);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);

        area.queueRender();
    }

    pub fn getCanvasInfo(self: *Canvas) struct { offset: @Vector(2, f32), zoom: f32 } {
        const data = self.private().data orelse return .{ .offset = .{ 0, 0 }, .zoom = 0 };
        return .{ .offset = data.offset, .zoom = data.zoom };
    }

    pub fn setUpdateCallback(self: *Canvas, callback: ?*const fn (?*anyopaque) callconv(.C) void, user_data: ?*anyopaque) void {
        const data = self.private().data orelse return;
        data.update_callback = callback;
        data.update_callback_data = user_data;
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

const vertices: []const @Vector(2, f32) = &.{
    .{ -1.0, -1.0 },
    .{ 1.0, -1.0 },
    .{ 1.0, 1.0 },
    .{ -1.0, 1.0 },
};

fn handleRealize(area: *gtk.GLArea, data: *Data) callconv(.C) void {
    area.setAutoRender(0);

    gtk.GLArea.makeCurrent(area);
    if (area.getError()) |err| {
        std.log.err("error handling GLArea realize signal: {any}", .{err});
        return;
    }

    std.log.info("OpenGL version: {d}", .{c.epoxy_gl_version()});

    const shader_program = createShaderProgram(area);
    const resolution_location = c.glGetUniformLocation(shader_program, "uResolution");
    const offset_location = c.glGetUniformLocation(shader_program, "uOffset");
    const scale_location = c.glGetUniformLocation(shader_program, "uScale");
    const scale_radius_location = c.glGetUniformLocation(shader_program, "uScaleRadius");
    const device_pixel_ratio_location = c.glGetUniformLocation(shader_program, "uDevicePixelRatio");

    var vao: c.GLuint = undefined;
    var vbo: c.GLuint = undefined;
    var positions: c.GLuint = undefined;
    var index_buffer: c.GLuint = undefined;

    // Create VAO and VBO
    c.glGenVertexArrays(1, &vao);
    c.glGenBuffers(1, &vbo);
    c.glGenBuffers(1, &positions);
    c.glGenBuffers(1, &index_buffer);

    c.glBindVertexArray(vao);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@Vector(2, f32)) * vertices.len, vertices.ptr, c.GL_STATIC_DRAW);

    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(@Vector(2, f32)), null);
    c.glEnableVertexAttribArray(0);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, positions);
    c.glBufferData(c.GL_ARRAY_BUFFER, initial_positions.len, initial_positions.ptr, c.GL_DYNAMIC_DRAW);
    c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(@Vector(2, f32)), null);
    c.glEnableVertexAttribArray(1);
    c.glVertexAttribDivisor(1, 1);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    // Enable blending for transparency
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);

    c.glDisable(c.GL_DEPTH_TEST);

    data.shader_program = shader_program;
    data.vao = vao;
    data.vbo = vbo;
    data.positions = positions;
    data.index_buffer = index_buffer;
    data.resolution_location = resolution_location;
    data.offset_location = offset_location;
    data.scale_location = scale_location;
    data.scale_radius_location = scale_radius_location;
    data.device_pixel_ratio_location = device_pixel_ratio_location;

    data.offset = .{ 0, 0 };
    data.anchor = .{ 0, 0 };
    data.cursor = .{ 0, 0 };
    data.zoom = 512;
    data.scale = getScale(data.zoom);
    data.scale_radius = getScaleRadius(data.scale);
    data.count = initial_positions.len;
}

fn handleUnrealize(area: *gtk.GLArea, data: *Data) callconv(.C) void {
    gtk.GLArea.makeCurrent(area);
    if (area.getError()) |err| {
        std.log.err("error handling GLArea unrealize signal: {any}", .{err});
        return;
    }

    // Clean up OpenGL resources
    c.glDeleteVertexArrays(1, &data.vao);
    c.glDeleteBuffers(1, &data.vbo);
    c.glDeleteBuffers(1, &data.positions);
    c.glDeleteBuffers(1, &data.index_buffer);
    c.glDeleteProgram(data.shader_program);

    // Clean up allocated memory
    if (data.index_permutation) |index_permutation| {
        allocator.free(index_permutation);
        data.index_permutation = null;
    }

    if (data.reordered_positions) |reordered_positions| {
        allocator.free(reordered_positions);
        data.reordered_positions = null;
    }
}

fn handleRender(area: *gtk.GLArea, ctx: *gdk.GLContext, data: *Data) callconv(.C) c_int {
    _ = ctx;

    const scale_factor = area.as(gtk.Widget).getScaleFactor();

    const width = gtk.Widget.getWidth(area.as(gtk.Widget));
    const height = gtk.Widget.getHeight(area.as(gtk.Widget));

    c.glViewport(0, 0, width * scale_factor, height * scale_factor);

    c.glClearColor(1.0, 1.0, 1.0, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    // Use the shader program
    c.glUseProgram(data.shader_program);

    c.glUniform2f(data.resolution_location, @floatFromInt(width), @floatFromInt(height));
    c.glUniform2f(data.offset_location, data.offset[0], data.offset[1]);
    c.glUniform1f(data.scale_location, data.scale);
    c.glUniform1f(data.scale_radius_location, data.scale_radius);
    c.glUniform1f(data.device_pixel_ratio_location, @floatFromInt(scale_factor));

    // Calculate LOD and set render count
    const lod_count = getLoD(data.zoom, data.count);

    // Bind the VAO
    c.glBindVertexArray(data.vao);

    // Draw using instanced rendering - render lod_count instances
    c.glDrawArraysInstanced(c.GL_TRIANGLE_FAN, 0, 4, @intCast(lod_count));

    // Unbind the VAO
    c.glBindVertexArray(0);
    c.glUseProgram(0);

    // Flush to ensure all commands are sent to the GPU
    c.glFlush();

    return 1;
}

const shaders = .{
    .vert320es = @embedFile("shaders/node-320-es.vert"),
    .frag320es = @embedFile("shaders/node-320-es.frag"),
    .vert410core = @embedFile("shaders/node-410-core.vert"),
    .frag410core = @embedFile("shaders/node-410-core.frag"),
};

fn getVertexShader(major: i32, minor: i32, api: gdk.GLAPI) [:0]const u8 {
    if (major == 4 and minor >= 1 and api.gl) {
        return shaders.vert410core;
    } else if (major == 3 and minor >= 2 and api.gles) {
        return shaders.vert320es;
    } else {
        @panic("unsupported OpenGL version");
    }
}

fn getFragmentShader(major: i32, minor: i32, api: gdk.GLAPI) [:0]const u8 {
    if (major == 4 and minor >= 1 and api.gl) {
        return shaders.frag410core;
    } else if (major == 3 and minor >= 2 and api.gles) {
        return shaders.frag320es;
    } else {
        @panic("unsupported OpenGL version");
    }
}

var info_log_len: i32 = 0;
var info_log_buffer: [4096]u8 = undefined;

fn createShaderProgram(area: *gtk.GLArea) c.GLuint {
    const ctx = area.getContext() orelse return 0;
    var major: i32 = 0;
    var minor: i32 = 0;
    ctx.getVersion(&major, &minor);
    const api = ctx.getAllowedApis();
    std.log.info("version: {d}.{d}", .{ major, minor });
    std.log.info("apis: [ gl: {any}, es: {any} ]", .{ api.gl, api.gles });

    const vertex_shader_source = getVertexShader(major, minor, api);
    const fragment_shader_source = getFragmentShader(major, minor, api);

    const vertex_shader = c.glCreateShader(c.GL_VERTEX_SHADER);
    defer c.glDeleteShader(vertex_shader);
    c.glShaderSource(vertex_shader, 1, &vertex_shader_source.ptr, null);
    c.glCompileShader(vertex_shader);

    c.glGetShaderInfoLog(vertex_shader, info_log_buffer.len, &info_log_len, &info_log_buffer);
    if (info_log_len > 0) {
        std.log.info("vertex shader info log -------", .{});
        const stderr = std.io.getStdErr();
        const log: [*:0]const u8 = @ptrCast(&info_log_buffer);
        stderr.writeAll(std.mem.span(log)) catch |err| @panic(@errorName(err));
    }

    const fragment_shader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    defer c.glDeleteShader(fragment_shader);
    c.glShaderSource(fragment_shader, 1, &fragment_shader_source.ptr, null);
    c.glCompileShader(fragment_shader);

    c.glGetShaderInfoLog(fragment_shader, info_log_buffer.len, &info_log_len, &info_log_buffer);
    if (info_log_len > 0) {
        std.log.info("fragment shader info log -------", .{});
        const stderr = std.io.getStdErr();
        const log: [*:0]const u8 = @ptrCast(&info_log_buffer);
        stderr.writeAll(std.mem.span(log)) catch |err| @panic(@errorName(err));
    }

    const shader_program = c.glCreateProgram();
    c.glAttachShader(shader_program, vertex_shader);
    c.glAttachShader(shader_program, fragment_shader);
    c.glLinkProgram(shader_program);

    c.glGetProgramInfoLog(shader_program, info_log_buffer.len, &info_log_len, &info_log_buffer);
    if (info_log_len > 0) {
        std.log.info("program info log -------", .{});
        const stderr = std.io.getStdErr();
        const log: [*:0]const u8 = @ptrCast(&info_log_buffer);
        stderr.writeAll(std.mem.span(log)) catch |err| @panic(@errorName(err));
    }

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
    const area: *gtk.GLArea = @ptrCast(gtk.EventController.getWidget(gesture.as(gtk.EventController)));
    const scale_factor: f32 = @floatFromInt(area.as(gtk.Widget).getScaleFactor());

    const offset: @Vector(2, f32) = .{
        @floatCast(offset_x * scale_factor / data.scale),
        @floatCast(-offset_y * scale_factor / data.scale),
    };

    data.offset = data.anchor + offset;
    if (data.update_callback) |callback| callback(data.update_callback_data);
    area.queueRender();
}

fn handleMouseScroll(controller: *gtk.EventControllerScroll, dx: f64, dy: f64, data: *Data) callconv(.C) c_int {
    _ = dx;

    var zoom = data.zoom + 8 * dy;
    zoom = @min(MAX_ZOOM, zoom);
    zoom = @max(MIN_ZOOM, zoom);
    data.zoom = @floatCast(zoom);
    data.scale = getScale(data.zoom);
    data.scale_radius = getScaleRadius(data.scale);

    if (data.update_callback) |callback| callback(data.update_callback_data);
    const area: *gtk.GLArea = @ptrCast(gtk.EventController.getWidget(controller.as(gtk.EventController)));
    area.queueRender();

    return 1;
}

fn handleMouseMotion(controller: *gtk.EventControllerMotion, x: f64, y: f64, data: *Data) callconv(.C) void {
    _ = controller;

    data.cursor = .{ @floatCast(x), @floatCast(y) };
}

fn handleZoom(gesture: *gtk.GestureZoom, scale: f64, data: *Data) callconv(.C) void {
    _ = gesture;
    _ = data;
    _ = scale;
}

inline fn getLoD(zoom: f32, total: usize) usize {
    _ = zoom; // unused for now
    return total; // render all nodes initially
}

inline fn getScale(zoom: f32) f32 {
    const C = 256;
    const BASE = 32;
    const x = std.math.pow(f32, zoom + 1, 2) / C + BASE;
    return C / x;
}

inline fn getScaleRadius(scale: f32) f32 {
    return std.math.sqrt(std.math.sqrt(scale));
}
