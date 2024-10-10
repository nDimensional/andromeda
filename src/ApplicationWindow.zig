const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gdk = @import("gdk");
const gtk = @import("gtk");
const intl = @import("libintl");

const gl = @import("gl");

const build_options = @import("build_options");

const c_allocator = std.heap.c_allocator;

const Progress = @import("Progress.zig");
const Store = @import("Store.zig");
const Graph = @import("Graph.zig");

const LogScale = @import("LogScale.zig").LogScale;
const Canvas = @import("Canvas.zig").Canvas;
const Params = @import("Params.zig");

const Engine = @import("engines/ForceAtlas2.zig");

const TEMPLATE = @embedFile("./data/ui/ApplicationWindow.xml");

const Status = enum { Initial, Loading, Stopped, Starting, Running, Stopping };

const attraction_scale = 100000;
const repulsion_scale = 1;
const center_scale = 1;
const temperature_scale = 1000;

const initial_params = Params{
    .attraction = 0.0001,
    .repulsion = 100.0,
    .center = 0.00002,
    .temperature = 0.1,
};

var label_buffer: [128]u8 = undefined;

pub const ApplicationWindow = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.ApplicationWindow;

    const Metrics = struct { count: u64, energy: f32, time: u64, swing: f32 };

    const Private = struct {
        path: ?[*:0]const u8,
        store: ?*Store,
        graph: ?*Graph,
        dirty: bool,

        engine_thread: ?std.Thread,
        status: Status = .Stopped,
        stdout: std.fs.File,
        timer: std.time.Timer,

        stack: *gtk.Stack,

        attraction: *LogScale,
        repulsion: *LogScale,
        center: *LogScale,
        temperature: *LogScale,

        tick_button: *gtk.Button,
        start_button: *gtk.Button,
        stop_button: *gtk.Button,
        progress_bar: *gtk.ProgressBar,

        ticker: *gtk.Label,
        energy: *gtk.Label,

        canvas: *Canvas,

        params: Params,
        metrics: Metrics,
        metrics_source_id: u32,
        render_source_id: u32,

        open_action: *gio.SimpleAction,
        open_action_id: u64,
        save_action: *gio.SimpleAction,
        save_action_id: u64,
        randomize_action: *gio.SimpleAction,
        randomize_action_id: u64,

        stop_action: *gio.SimpleAction,
        start_action: *gio.SimpleAction,

        var offset: c_int = 0;
    };

    pub const getGObjectType = gobject.ext.defineClass(ApplicationWindow, .{
        .name = "AndromedaApplicationWindow",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new(app: *gtk.Application) *ApplicationWindow {
        return gobject.ext.newInstance(ApplicationWindow, .{ .application = app });
    }

    pub fn as(win: *ApplicationWindow, comptime T: type) *T {
        return gobject.ext.as(T, win);
    }

    fn init(win: *ApplicationWindow, _: *Class) callconv(.C) void {
        gtk.Widget.initTemplate(win.as(gtk.Widget));

        win.private().engine_thread = null;
        win.private().store = null;
        win.private().status = .Initial;
        win.private().stdout = std.io.getStdOut();
        win.private().timer = std.time.Timer.start() catch |err| @panic(@errorName(err));
        win.private().dirty = false;

        _ = gtk.Button.signals.clicked.connect(win.private().stop_button, *ApplicationWindow, &handleStopClicked, win, .{});
        _ = gtk.Button.signals.clicked.connect(win.private().tick_button, *ApplicationWindow, &handleTickClicked, win, .{});
        _ = gtk.Button.signals.clicked.connect(win.private().start_button, *ApplicationWindow, &handleStartClicked, win, .{});

        _ = LogScale.signals.value_changed.connect(win.private().attraction, *ApplicationWindow, &handleAttractionValueChanged, win, .{});
        _ = LogScale.signals.value_changed.connect(win.private().repulsion, *ApplicationWindow, &handleRepulsionValueChanged, win, .{});
        _ = LogScale.signals.value_changed.connect(win.private().center, *ApplicationWindow, &handleCenterValueChanged, win, .{});
        _ = LogScale.signals.value_changed.connect(win.private().temperature, *ApplicationWindow, &handleTemperatureValueChanged, win, .{});

        const open_action = gio.SimpleAction.new("open", null);
        gio.ActionMap.addAction(win.as(gio.ActionMap), open_action.as(gio.Action));
        win.private().open_action = open_action;
        win.private().open_action_id = gio.SimpleAction.signals.activate.connect(open_action, *ApplicationWindow, &handleOpen, win, .{});

        const save_action = gio.SimpleAction.new("save", null);
        win.as(gio.ActionMap).addAction(save_action.as(gio.Action));
        win.private().save_action = save_action;
        win.private().save_action_id = gio.SimpleAction.signals.activate.connect(save_action, *ApplicationWindow, &handleSave, win, .{});

        save_action.setEnabled(0);

        const randomize_action = gio.SimpleAction.new("randomize", null);
        win.as(gio.ActionMap).addAction(randomize_action.as(gio.Action));
        win.private().randomize_action = randomize_action;
        win.private().randomize_action_id = gio.SimpleAction.signals.activate.connect(randomize_action, *ApplicationWindow, &handleRandomize, win, .{});

        randomize_action.setEnabled(0);

        const start_action = gio.SimpleAction.new("start", null);
        win.as(gio.ActionMap).addAction(start_action.as(gio.Action));
        win.private().start_action = start_action;
        start_action.setEnabled(0);

        const stop_action = gio.SimpleAction.new("stop", null);
        win.as(gio.ActionMap).addAction(stop_action.as(gio.Action));
        win.private().stop_action = stop_action;
        stop_action.setEnabled(0);

        win.private().params = initial_params;

        win.private().attraction.setValue(initial_params.attraction * attraction_scale);
        win.private().repulsion.setValue(initial_params.repulsion * repulsion_scale);
        win.private().center.setValue(initial_params.center * center_scale);
        win.private().temperature.setValue(initial_params.temperature * temperature_scale);

        win.private().stop_button.as(gtk.Widget).setSensitive(0);
        win.private().tick_button.as(gtk.Widget).setSensitive(0);
        win.private().start_button.as(gtk.Widget).setSensitive(0);

        win.private().attraction.as(gtk.Widget).setSensitive(0);
        win.private().repulsion.as(gtk.Widget).setSensitive(0);
        win.private().temperature.as(gtk.Widget).setSensitive(0);
        win.private().center.as(gtk.Widget).setSensitive(0);

        gtk.Stack.setVisibleChildName(win.private().stack, "landing");

        win.private().render_source_id = 0;
        win.private().metrics_source_id = glib.timeoutAddSeconds(1, &handleMetricsUpdate, win);
        win.private().metrics.count = 0;
        win.private().metrics.energy = 0;
        win.private().metrics.time = 0;
    }

    fn dispose(win: *ApplicationWindow) callconv(.C) void {
        win.private().open_action.unref();
        win.private().save_action.unref();
        win.private().randomize_action.unref();

        gtk.Widget.disposeTemplate(win.as(gtk.Widget), getGObjectType());
        gobject.Object.virtual_methods.dispose.call(Class.parent.as(gobject.Object.Class), win.as(gobject.Object));
    }

    fn finalize(win: *ApplicationWindow) callconv(.C) void {
        if (win.private().graph) |graph| graph.deinit();
        if (win.private().store) |store| store.deinit();

        Class.parent.as(gobject.Object.Class).finalize.?(win.as(gobject.Object));
    }

    fn private(win: *ApplicationWindow) *Private {
        return gobject.ext.impl_helpers.getPrivate(win, Private, Private.offset);
    }

    fn handleStopClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        win.log("Stopping...", .{});
        win.private().status = .Stopping;
        win.private().stop_button.as(gtk.Widget).setSensitive(0);
        if (win.private().engine_thread) |engine_thread| engine_thread.detach();

        const ctx = glib.MainContext.default();
        ctx.findSourceById(win.private().render_source_id).destroy();
        ctx.findSourceById(win.private().metrics_source_id).destroy();
    }

    fn handleTickClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        const graph = win.private().graph orelse return;
        const params = &win.private().params;

        const engine = Engine.init(c_allocator, graph, params) catch |err| @panic(@errorName(err));
        defer engine.deinit();

        win.tick(engine) catch |err| @panic(@errorName(err));
        win.updateMetrics() catch |err| @panic(@errorName(err));

        win.private().canvas.update(graph.positions);
    }

    fn handleStartClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        win.log("Starting...", .{});

        win.private().open_action.setEnabled(0);
        win.private().save_action.setEnabled(0);
        win.private().randomize_action.setEnabled(0);
        win.private().tick_button.as(gtk.Widget).setSensitive(0);
        win.private().start_button.as(gtk.Widget).setSensitive(0);
        win.private().stop_button.as(gtk.Widget).setSensitive(1);

        win.private().status = .Starting;
        win.private().engine_thread = std.Thread.spawn(.{}, loop, .{win}) catch |err| {
            std.log.err("failed to spawn engine thread: {s}", .{@errorName(err)});
            return;
        };

        win.private().render_source_id = glib.idleAdd(&handleRender, win);
        win.private().metrics_source_id = glib.timeoutAddSeconds(1, &handleMetricsUpdate, win);
    }

    fn handleAttractionValueChanged(_: *LogScale, value: f64, win: *ApplicationWindow) callconv(.C) void {
        win.private().params.attraction = @floatCast(value / attraction_scale);
    }

    fn handleRepulsionValueChanged(_: *LogScale, value: f64, win: *ApplicationWindow) callconv(.C) void {
        win.private().params.repulsion = @floatCast(value / repulsion_scale);
    }

    fn handleCenterValueChanged(_: *LogScale, value: f64, win: *ApplicationWindow) callconv(.C) void {
        win.private().params.center = @floatCast(value / center_scale);
    }

    fn handleTemperatureValueChanged(_: *LogScale, value: f64, win: *ApplicationWindow) callconv(.C) void {
        win.private().params.temperature = @floatCast(value / temperature_scale);
    }

    fn loop(win: *ApplicationWindow) !void {
        const graph = win.private().graph orelse return;
        const params = &win.private().params;

        const engine = Engine.init(c_allocator, graph, params) catch |err| @panic(@errorName(err));
        defer engine.deinit();

        win.private().status = .Running;
        while (win.private().status == .Running) {
            try win.tick(engine);
        }

        if (win.private().status != .Stopping) {
            std.log.warn("unexpected state", .{});
        }

        win.log("Stopped.", .{});

        _ = glib.idleAdd(&handleLoopStop, win);
    }

    fn tick(win: *ApplicationWindow, engine: *Engine) !void {
        const start = win.private().timer.read();
        try engine.tick();
        const time = win.private().timer.read() - start;
        const total: f32 = @floatFromInt(engine.graph.node_count);
        win.private().metrics = .{
            .count = engine.count,
            .time = time / 1_000_000,
            .swing = engine.stats.swing / total,
            .energy = engine.stats.energy / total,
        };

        win.private().dirty = true;
    }

    fn openFile(win: *ApplicationWindow, path: [*:0]const u8) !void {
        win.private().status = .Loading;
        win.private().path = path;

        if (win.private().store) |store| {
            store.deinit();
            win.private().store = null;
        }

        const store = try Store.init(c_allocator, .{
            .path = path,
            .progress_bar = win.private().progress_bar,
        });

        win.private().store = store;

        const filename = std.fs.path.basename(std.mem.span(path));
        const title = try std.fmt.bufPrintZ(&label_buffer, "Andromeda - {s}", .{filename});
        win.as(gtk.Window).setTitle(title);

        gtk.Stack.setVisibleChildName(win.private().stack, "loading");

        const graph = try Graph.init(c_allocator, store, .{
            .progress_bar = win.private().progress_bar,
        });

        win.private().open_action.setEnabled(0);
        win.private().graph = graph;
        graph.load(.{ .callback = &loadResultCallback, .callback_data = win });
    }

    fn updateMetrics(win: *ApplicationWindow) !void {
        const metrics = win.private().metrics;

        const ticker_markup = try std.fmt.bufPrintZ(&label_buffer, "Ticks: {d}, Time: {d}ms", .{ metrics.count, metrics.time });
        win.private().ticker.setMarkup(ticker_markup);

        const energy_markup = try std.fmt.bufPrintZ(&label_buffer, "Energy: {e:.3}, Swing: {e:.3}", .{ metrics.energy, metrics.swing });
        win.private().energy.setMarkup(energy_markup);
    }

    fn log(win: *ApplicationWindow, comptime format: []const u8, args: anytype) void {
        const writer = win.private().stdout.writer();
        writer.print(format, args) catch |err| @panic(@errorName(err));
        writer.writeByte('\n') catch |err| @panic(@errorName(err));
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;

        pub const Instance = ApplicationWindow;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.C) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
            gobject.Object.virtual_methods.finalize.implement(class, &finalize);
            const template = glib.Bytes.newStatic(TEMPLATE.ptr, TEMPLATE.len);
            class.as(gtk.Widget.Class).setTemplate(template);

            class.bindTemplateChildPrivate("stack", .{});
            class.bindTemplateChildPrivate("progress_bar", .{});
            class.bindTemplateChildPrivate("ticker", .{});
            class.bindTemplateChildPrivate("energy", .{});

            class.bindTemplateChildPrivate("tick_button", .{});
            class.bindTemplateChildPrivate("start_button", .{});
            class.bindTemplateChildPrivate("stop_button", .{});
            // class.bindTemplateChildPrivate("view_button", .{});

            class.bindTemplateChildPrivate("attraction", .{});
            class.bindTemplateChildPrivate("repulsion", .{});
            class.bindTemplateChildPrivate("center", .{});
            class.bindTemplateChildPrivate("temperature", .{});

            class.bindTemplateChildPrivate("canvas", .{});
        }

        fn bindTemplateChildPrivate(class: *Class, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
            gtk.ext.impl_helpers.bindTemplateChildPrivate(class, name, Private, Private.offset, options);
        }
    };
};

fn handleOpenResponse(chooser: *gtk.FileChooserNative, _: c_int, win: *ApplicationWindow) callconv(.C) void {
    defer chooser.unref();
    const file = chooser.as(gtk.FileChooser).getFile() orelse return;
    defer file.unref();
    const path = file.getPath() orelse return;
    win.openFile(path) catch |err| @panic(@errorName(err));
}

fn loadResultCallback(_: ?*gobject.Object, res: *gio.AsyncResult, data: ?*anyopaque) callconv(.C) void {
    _ = res;

    const win: *ApplicationWindow = @alignCast(@ptrCast(data));

    const graph = win.private().graph orelse return;
    win.private().canvas.load(graph.positions);

    win.log("Finished loading.", .{});
    win.private().status = .Stopped;
    win.private().open_action.setEnabled(1);
    win.private().save_action.setEnabled(1);
    win.private().randomize_action.setEnabled(1);
    win.private().tick_button.as(gtk.Widget).setSensitive(1);
    win.private().start_button.as(gtk.Widget).setSensitive(1);
    win.private().stop_button.as(gtk.Widget).setSensitive(0);

    win.private().attraction.as(gtk.Widget).setSensitive(1);
    win.private().repulsion.as(gtk.Widget).setSensitive(1);
    win.private().temperature.as(gtk.Widget).setSensitive(1);
    win.private().center.as(gtk.Widget).setSensitive(1);

    gtk.Stack.setVisibleChildName(win.private().stack, "status");
}

fn handleMetricsUpdate(user_data: ?*anyopaque) callconv(.C) c_int {
    const win: *ApplicationWindow = @alignCast(@ptrCast(user_data));
    win.updateMetrics() catch |err| @panic(@errorName(err));
    return 1;
}

fn handleLoopStop(user_data: ?*anyopaque) callconv(.C) c_int {
    const win: *ApplicationWindow = @alignCast(@ptrCast(user_data));

    win.private().status = .Stopped;

    win.private().open_action.setEnabled(1);
    win.private().save_action.setEnabled(1);
    win.private().randomize_action.setEnabled(1);
    win.private().tick_button.as(gtk.Widget).setSensitive(1);
    win.private().start_button.as(gtk.Widget).setSensitive(1);
    win.private().stop_button.as(gtk.Widget).setSensitive(0);

    return 0;
}

fn handleRender(user_data: ?*anyopaque) callconv(.C) c_int {
    const win: *ApplicationWindow = @alignCast(@ptrCast(user_data));

    if (win.private().graph) |graph| {
        if (win.private().dirty) {
            win.private().dirty = false;
            win.private().canvas.update(graph.positions);
        }
    }

    if (win.private().status == .Running) {
        return 1;
    } else {
        return 0;
    }
}

fn handleOpen(_: *gio.SimpleAction, variant: ?*glib.Variant, win: *ApplicationWindow) callconv(.C) void {
    _ = variant;

    const chooser = gtk.FileChooserNative.new(
        intl.gettext("Open graph"),
        win.as(gtk.Window),
        .open,
        intl.gettext("_Open"),
        intl.gettext("_Cancel"),
    );

    const filter = gtk.FileFilter.new();
    gtk.FileFilter.setName(filter, "SQLite");
    gtk.FileFilter.addPattern(filter, "*.sqlite");
    gtk.FileChooser.addFilter(chooser.as(gtk.FileChooser), filter);

    _ = gtk.NativeDialog.signals.response.connect(chooser, *ApplicationWindow, &handleOpenResponse, win, .{});
    gtk.NativeDialog.show(chooser.as(gtk.NativeDialog));
}

fn handleSave(_: *gio.SimpleAction, variant: ?*glib.Variant, win: *ApplicationWindow) callconv(.C) void {
    _ = variant;

    win.log("Saving...", .{});

    if (win.private().graph) |graph| graph.save() catch |err| {
        std.log.err("failed to save graph: {any}", .{err});
    };

    win.log("Saved.", .{});
}

fn handleRandomize(_: *gio.SimpleAction, variant: ?*glib.Variant, win: *ApplicationWindow) callconv(.C) void {
    _ = variant;

    win.log("Randomizing...", .{});
    const graph = win.private().graph orelse return;

    const s = std.math.sqrt(@as(f32, @floatFromInt(graph.node_count)));
    graph.randomize(s * 100);
    win.private().canvas.update(graph.positions);
    win.log("Randomized.", .{});
}
