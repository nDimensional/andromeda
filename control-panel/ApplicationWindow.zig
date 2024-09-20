const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const intl = @import("libintl");

const nng = @import("nng");

const build_options = @import("build_options");

const c_allocator = std.heap.c_allocator;

const Progress = @import("Progress.zig");
const Store = @import("Store.zig");
const Engine = @import("Engine.zig");
const LogScale = @import("LogScale.zig").LogScale;
const Params = @import("Params.zig");

const TEMPLATE = @embedFile("./data/ui/ApplicationWindow.xml");
const EXECUTABLE_PATH = build_options.atlas_path;
const SOCKET_URL = "ipc://" ++ build_options.socket_path;

const Status = enum { Stopped, Started };

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

    const Metrics = struct {
        count: u64,
        energy: f32,
        time: u64,
    };

    const Private = struct {
        store: ?*Store,
        engine: ?*Engine,
        child_process: ?*std.process.Child,
        engine_thread: ?std.Thread,
        socket: nng.Socket.PUB,
        status: Status = .Stopped,
        timer: std.time.Timer,

        stack: *gtk.Stack,

        attraction: *LogScale,
        repulsion: *LogScale,
        center: *LogScale,
        temperature: *LogScale,

        save_button: *gtk.Button,
        open_button: *gtk.Button,
        tick_button: *gtk.Button,
        start_button: *gtk.Button,
        stop_button: *gtk.Button,
        view_button: *gtk.Button,
        randomize_button: *gtk.Button,
        progress_bar: *gtk.ProgressBar,

        ticker: *gtk.Label,
        energy: *gtk.Label,
        speed: *gtk.Label,

        params: Params,
        metrics: Metrics,
        metrics_timer: u32,

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

        win.private().child_process = null;
        win.private().engine_thread = null;
        win.private().store = null;
        win.private().engine = null;
        win.private().status = .Stopped;
        win.private().timer = std.time.Timer.start() catch |err| @panic(@errorName(err));

        const socket = nng.Socket.PUB.open() catch |err| @panic(@errorName(err));
        socket.listen(SOCKET_URL) catch |err| @panic(@errorName(err));
        win.private().socket = socket;

        _ = gtk.Button.signals.clicked.connect(win.private().open_button, *ApplicationWindow, &handleOpenClicked, win, .{});
        _ = gtk.Button.signals.clicked.connect(win.private().save_button, *ApplicationWindow, &handleSaveClicked, win, .{});
        _ = gtk.Button.signals.clicked.connect(win.private().stop_button, *ApplicationWindow, &handleStopClicked, win, .{});
        _ = gtk.Button.signals.clicked.connect(win.private().tick_button, *ApplicationWindow, &handleTickClicked, win, .{});
        _ = gtk.Button.signals.clicked.connect(win.private().start_button, *ApplicationWindow, &handleStartClicked, win, .{});
        _ = gtk.Button.signals.clicked.connect(win.private().view_button, *ApplicationWindow, &handleViewClicked, win, .{});
        _ = gtk.Button.signals.clicked.connect(win.private().randomize_button, *ApplicationWindow, &handleRandomizeClicked, win, .{});

        _ = LogScale.signals.value_changed.connect(win.private().attraction, *ApplicationWindow, &handleAttractionValueChanged, win, .{});
        _ = LogScale.signals.value_changed.connect(win.private().repulsion, *ApplicationWindow, &handleRepulsionValueChanged, win, .{});
        _ = LogScale.signals.value_changed.connect(win.private().center, *ApplicationWindow, &handleCenterValueChanged, win, .{});
        _ = LogScale.signals.value_changed.connect(win.private().temperature, *ApplicationWindow, &handleTemperatureValueChanged, win, .{});

        win.private().params = initial_params;

        win.private().attraction.setValue(initial_params.attraction * attraction_scale);
        win.private().repulsion.setValue(initial_params.repulsion * repulsion_scale);
        win.private().center.setValue(initial_params.center * center_scale);
        win.private().temperature.setValue(initial_params.temperature * temperature_scale);

        win.private().save_button.as(gtk.Widget).setSensitive(0);
        win.private().stop_button.as(gtk.Widget).setSensitive(0);
        win.private().tick_button.as(gtk.Widget).setSensitive(0);
        win.private().start_button.as(gtk.Widget).setSensitive(0);
        win.private().randomize_button.as(gtk.Widget).setSensitive(0);
        win.private().view_button.as(gtk.Widget).setSensitive(0);

        gtk.Stack.setVisibleChildName(win.private().stack, "landing");

        win.private().metrics_timer = glib.timeoutAddSeconds(1, &handleMetricsUpdate, win);
        win.private().metrics.count = 0;
        win.private().metrics.energy = 0;
        win.private().metrics.time = 0;
    }

    fn dispose(win: *ApplicationWindow) callconv(.C) void {
        gtk.Widget.disposeTemplate(win.as(gtk.Widget), getGObjectType());
        gobject.Object.virtual_methods.dispose.call(Class.parent.as(gobject.Object.Class), win.as(gobject.Object));
    }

    fn finalize(win: *ApplicationWindow) callconv(.C) void {
        if (win.private().child_process) |child_process| {
            const status = child_process.kill() catch |e| @panic(@errorName(e));
            std.log.warn("terminated child process {any}", .{status});
        }

        win.private().socket.close();
        if (win.private().engine) |engine| engine.deinit();
        if (win.private().store) |store| store.deinit();

        Class.parent.as(gobject.Object.Class).finalize.?(win.as(gobject.Object));
    }

    fn private(win: *ApplicationWindow) *Private {
        return gobject.ext.impl_helpers.getPrivate(win, Private, Private.offset);
    }

    fn updateMetrics(win: *ApplicationWindow) !void {
        const metrics = win.private().metrics;

        const ticker_markup = try std.fmt.bufPrintZ(&label_buffer, "Ticks: {d}", .{metrics.count});
        win.private().ticker.setMarkup(ticker_markup);

        const energy_markup = try std.fmt.bufPrintZ(&label_buffer, "Energy: {e:.3}", .{metrics.energy});
        win.private().energy.setMarkup(energy_markup);

        const speed_markup = try std.fmt.bufPrintZ(&label_buffer, "Time: {d}ms", .{metrics.time});
        win.private().speed.setMarkup(speed_markup);
    }

    fn handleOpenClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
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

    fn handleSaveClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        const writer = std.io.getStdOut().writer();
        writer.print("Saving...\n", .{}) catch |err| @panic(@errorName(err));
        if (win.private().store) |store| store.save() catch |err| @panic(@errorName(err));
        writer.print("Saved.\n", .{}) catch |err| @panic(@errorName(err));
    }

    fn handleStopClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        const writer = std.io.getStdOut().writer();
        writer.print("Stopping...\n", .{}) catch |err| @panic(@errorName(err));

        win.private().status = .Stopped;
        win.private().stop_button.as(gtk.Widget).setSensitive(0);
        if (win.private().engine_thread) |engine_thread| engine_thread.detach();
    }

    fn handleTickClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        win.tick() catch |err| @panic(@errorName(err));
        win.updateMetrics() catch |err| @panic(@errorName(err));
    }

    fn handleStartClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        const writer = std.io.getStdOut().writer();
        writer.print("Starting...\n", .{}) catch |err| @panic(@errorName(err));

        win.private().open_button.as(gtk.Widget).setSensitive(0);
        win.private().save_button.as(gtk.Widget).setSensitive(0);
        win.private().tick_button.as(gtk.Widget).setSensitive(0);
        win.private().start_button.as(gtk.Widget).setSensitive(0);
        win.private().stop_button.as(gtk.Widget).setSensitive(1);
        win.private().randomize_button.as(gtk.Widget).setSensitive(0);

        win.private().status = .Started;
        win.private().engine_thread = std.Thread.spawn(.{}, loop, .{win}) catch |err| {
            std.log.err("failed to spawn engine thread: {s}", .{@errorName(err)});
            return;
        };
    }

    fn handleViewClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        const writer = std.io.getStdOut().writer();
        writer.print("Opening atlas\n", .{}) catch |err| @panic(@errorName(err));

        win.private().child_process = spawn(c_allocator, &.{EXECUTABLE_PATH}, null);
        win.private().view_button.as(gtk.Widget).setSensitive(0);
    }

    fn handleRandomizeClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        const writer = std.io.getStdOut().writer();
        writer.print("Randomizing...\n", .{}) catch |err| @panic(@errorName(err));

        const store = win.private().store orelse return;
        const engine = win.private().engine orelse return;

        const s = std.math.sqrt(@as(f32, @floatFromInt(store.node_count)));
        engine.randomize(s * 100);

        const msg = nng.Message.init(8) catch |err| @panic(@errorName(err));
        std.mem.writeInt(u64, msg.body()[0..8], engine.count, .big);
        win.private().socket.send(msg, .{}) catch |err| @panic(@errorName(err));
        writer.print("Randomized.\n", .{}) catch |err| @panic(@errorName(err));
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
        // const engine = win.private().engine orelse return;
        while (win.private().status == .Started) {
            try win.tick();
        }

        const writer = std.io.getStdOut().writer();
        try writer.print("Stopped.\n", .{});

        win.private().open_button.as(gtk.Widget).setSensitive(1);
        win.private().save_button.as(gtk.Widget).setSensitive(1);
        win.private().tick_button.as(gtk.Widget).setSensitive(1);
        win.private().start_button.as(gtk.Widget).setSensitive(1);
        win.private().stop_button.as(gtk.Widget).setSensitive(0);
        win.private().randomize_button.as(gtk.Widget).setSensitive(1);
    }

    fn tick(win: *ApplicationWindow) !void {
        const engine = win.private().engine orelse return;

        const start = win.private().timer.read();
        const energy = try engine.tick();
        const time = win.private().timer.read() - start;
        win.private().metrics = .{
            .count = engine.count,
            .energy = energy,
            .time = time / 1_000_000,
        };

        const msg = try nng.Message.init(8);
        std.mem.writeInt(u64, msg.body()[0..8], engine.count, .big);
        try win.private().socket.send(msg, .{});
    }

    fn openFile(win: *ApplicationWindow, file: *gio.File) void {
        const path = file.getPath() orelse return;

        const writer = std.io.getStdOut().writer();
        writer.print("Loading {s}\n", .{path}) catch |err| @panic(@errorName(err));

        gtk.Stack.setVisibleChildName(win.private().stack, "loading");

        const store = Store.init(c_allocator, .{
            .path = path,
            .progress_bar = win.private().progress_bar,
        }) catch |err| @panic(@errorName(err));

        win.private().open_button.as(gtk.Widget).setSensitive(0);
        win.private().store = store;
        store.load(.{ .callback = &loadResultCallback, .callback_data = win });
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
            class.bindTemplateChildPrivate("speed", .{});

            class.bindTemplateChildPrivate("save_button", .{});
            class.bindTemplateChildPrivate("open_button", .{});
            class.bindTemplateChildPrivate("tick_button", .{});
            class.bindTemplateChildPrivate("start_button", .{});
            class.bindTemplateChildPrivate("stop_button", .{});
            class.bindTemplateChildPrivate("view_button", .{});
            class.bindTemplateChildPrivate("randomize_button", .{});

            class.bindTemplateChildPrivate("attraction", .{});
            class.bindTemplateChildPrivate("repulsion", .{});
            class.bindTemplateChildPrivate("center", .{});
            class.bindTemplateChildPrivate("temperature", .{});
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
    win.openFile(file);
}

fn loadResultCallback(_: ?*gobject.Object, res: *gio.AsyncResult, data: ?*anyopaque) callconv(.C) void {
    const writer = std.io.getStdOut().writer();
    writer.print("Finished loading.\n", .{}) catch |err| @panic(@errorName(err));

    _ = res;

    const win: *ApplicationWindow = @alignCast(@ptrCast(data));

    const store = win.private().store orelse return;
    const engine = Engine.init(c_allocator, store, &win.private().params) catch |err| {
        std.log.err("failed to initialize engine: {s}", .{@errorName(err)});
        return;
    };

    win.private().engine = engine;

    win.private().open_button.as(gtk.Widget).setSensitive(1);
    win.private().save_button.as(gtk.Widget).setSensitive(1);
    win.private().tick_button.as(gtk.Widget).setSensitive(1);
    win.private().start_button.as(gtk.Widget).setSensitive(1);
    win.private().stop_button.as(gtk.Widget).setSensitive(0);
    win.private().view_button.as(gtk.Widget).setSensitive(1);
    win.private().randomize_button.as(gtk.Widget).setSensitive(1);
    gtk.Stack.setVisibleChildName(win.private().stack, "status");
}

fn handleMetricsUpdate(user_data: ?*anyopaque) callconv(.C) c_int {
    const win: *ApplicationWindow = @alignCast(@ptrCast(user_data));
    win.updateMetrics() catch |err| @panic(@errorName(err));
    return 1;
}

fn spawn(allocator: std.mem.Allocator, argv: []const []const u8, env_map: ?*const std.process.EnvMap) ?*std.process.Child {
    const child_process = allocator.create(std.process.Child) catch |err| {
        std.log.err("failed to create child process: {s}", .{@errorName(err)});
        return null;
    };

    child_process.* = std.process.Child.init(argv, allocator);
    child_process.env_map = env_map;

    child_process.spawn() catch |err| {
        std.log.err("failed to spawn child process: {s}", .{@errorName(err)});
        allocator.destroy(child_process);
        return null;
    };

    return child_process;
}
