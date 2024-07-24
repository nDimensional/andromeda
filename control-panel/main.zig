const std = @import("std");
const build_options = @import("build_options");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");
const adw = @import("adw");
const intl = @import("libintl");
const nng = @import("nng");

const c_allocator = std.heap.c_allocator;

const Progress = @import("Progress.zig");
const Store = @import("Store.zig");
const Engine = @import("Engine.zig");
const LogScale = @import("LogScale.zig").LogScale;

pub const application_id = "dev.ianjohnson.Nonograms";
const package = "nonograms";

const TEMPLATE_PATH = "/Users/joelgustafson/Projects/andromeda/control-panel/data/ui/window.xml";
const EXECUTABLE_PATH = "/Users/joelgustafson/Projects/andromeda/zig-out/bin/andromeda-atlas";
const SOCKET_URL = "ipc:///Users/joelgustafson/Projects/andromeda/socket";

pub fn main() !void {
    intl.bindTextDomain(package, build_options.locale_dir ++ "");
    intl.bindTextDomainCodeset(package, "UTF-8");
    intl.setTextDomain(package);

    const app = Application.new();
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

const Application = extern struct {
    parent_instance: Parent,

    pub const Parent = adw.Application;

    pub const getGObjectType = gobject.ext.defineClass(Application, .{
        .name = "NonogramsApplication",
        .classInit = &Class.init,
    });

    pub fn new() *Application {
        return gobject.ext.newInstance(Application, .{
            .application_id = application_id,
            .flags = gio.ApplicationFlags{},
        });
    }

    pub fn as(app: *Application, comptime T: type) *T {
        return gobject.ext.as(T, app);
    }

    fn activateImpl(app: *Application) callconv(.C) void {
        const win = ApplicationWindow.new(app);
        gtk.Window.present(win.as(gtk.Window));
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Application;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.C) void {
            gio.Application.virtual_methods.activate.implement(class, &Application.activateImpl);
        }
    };
};

const Status = enum { Stopped, Started };

const ApplicationWindow = extern struct {
    parent_instance: Parent,

    pub const Parent = adw.ApplicationWindow;

    const Private = struct {
        store: ?*Store,
        engine: ?*Engine,
        child_process: ?*std.process.Child,
        engine_thread: ?std.Thread,
        socket: nng.Socket.PUB,

        status: Status = .Stopped,
        window_title: *adw.WindowTitle,
        stack: *gtk.Stack,

        attraction: *LogScale,
        repulsion: *LogScale,
        temperature: *LogScale,

        save_button: *gtk.Button,
        open_button: *gtk.Button,
        tick_button: *gtk.Button,
        start_button: *gtk.Button,
        stop_button: *gtk.Button,
        view_button: *gtk.Button,
        randomize_button: *gtk.Button,
        progress_bar: *gtk.ProgressBar,

        var offset: c_int = 0;
    };

    pub const getGObjectType = gobject.ext.defineClass(ApplicationWindow, .{
        .name = "NonogramsApplicationWindow",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new(app: *Application) *ApplicationWindow {
        return gobject.ext.newInstance(ApplicationWindow, .{ .application = app });
    }

    pub fn as(win: *ApplicationWindow, comptime T: type) *T {
        return gobject.ext.as(T, win);
    }

    fn init(win: *ApplicationWindow, _: *Class) callconv(.C) void {
        nng.setLogger(.SYSTEM);

        gtk.Widget.initTemplate(win.as(gtk.Widget));

        win.private().child_process = null;
        win.private().engine_thread = null;
        win.private().store = null;
        win.private().engine = null;
        win.private().status = .Stopped;

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
        _ = LogScale.signals.value_changed.connect(win.private().temperature, *ApplicationWindow, &handleTemperatureValueChanged, win, .{});


        const attraction = 0.0001;
        const repulsion = 100.0;
        const temperature = 0.1;

        win.private().attraction.setValue(attraction * 1000);
        win.private().repulsion.setValue(repulsion * 1000);
        win.private().temperature.setValue(temperature * 1000);

        // const attraction_adjustment = gtk.Adjustment.new(0, 0, 100, 1, 10, 0);
        // attraction_range.setAdjustment(attraction_adjustment);
        // win.private().attraction_adjustment = attraction_adjustment;

        // const repulsion_adjustment = gtk.Adjustment.new(0, 0, 100, 1, 10, 0);
        // repulsion_range.setAdjustment(repulsion_adjustment);
        // win.private().repulsion_adjustment = repulsion_adjustment;

        // const temperature_adjustment = gtk.Adjustment.new(0, 0, 100, 1, 10, 0);
        // temperature_range.setAdjustment(temperature_adjustment);
        // win.private().temperature_adjustment = temperature_adjustment;

        win.private().save_button.as(gtk.Widget).setSensitive(0);
        win.private().stop_button.as(gtk.Widget).setSensitive(0);
        win.private().tick_button.as(gtk.Widget).setSensitive(0);
        win.private().start_button.as(gtk.Widget).setSensitive(0);
        win.private().randomize_button.as(gtk.Widget).setSensitive(0);

        gtk.Stack.setVisibleChildName(win.private().stack, "landing");
    }

    fn dispose(win: *ApplicationWindow) callconv(.C) void {
        gtk.Widget.disposeTemplate(win.as(gtk.Widget), getGObjectType());
        gobject.Object.virtual_methods.dispose.call(Class.parent.as(gobject.Object.Class), win.as(gobject.Object));
    }

    fn finalize(win: *ApplicationWindow) callconv(.C) void {
        if (win.private().child_process) |child_process| {
            const status = child_process.kill() catch |e| @panic(@errorName(e));
            std.log.info("terminated child process {any}", .{status});
        }

        win.private().socket.close();
        if (win.private().engine) |engine| engine.deinit();
        if (win.private().store) |store| store.deinit();

        Class.parent.as(gobject.Object.Class).finalize.?(win.as(gobject.Object));
    }

    fn openFile(win: *ApplicationWindow, file: *gio.File) void {
        const path = file.getPath() orelse return;
        std.log.info("got file: {s}", .{path});

        gtk.Stack.setVisibleChildName(win.private().stack, "loading");

        const store = Store.init(c_allocator, .{
            .path = path,
            .progress_bar = win.private().progress_bar,
        }) catch |err| @panic(@errorName(err));

        win.private().open_button.as(gtk.Widget).setSensitive(0);
        win.private().store = store;
        store.load(.{ .callback = &loadResultCallback, .callback_data = win });
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
        std.log.info("handleSaveClicked", .{});
        _ = win;
    }

    fn handleStopClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        std.log.info("handleStopClicked", .{});
        win.private().open_button.as(gtk.Widget).setSensitive(1);
        win.private().save_button.as(gtk.Widget).setSensitive(1);
        win.private().tick_button.as(gtk.Widget).setSensitive(1);
        win.private().start_button.as(gtk.Widget).setSensitive(1);
        win.private().stop_button.as(gtk.Widget).setSensitive(0);
        win.private().randomize_button.as(gtk.Widget).setSensitive(1);

        win.private().status = .Stopped;
        if (win.private().engine_thread) |engine_thread| {
            engine_thread.join();
            win.private().engine_thread = null;
        }
    }

    fn handleTickClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        std.log.info("handleTickClicked", .{});
        const engine = win.private().engine orelse return;

        engine.attraction = @floatCast(win.private().attraction.getValue() / 1000);
        engine.repulsion = @floatCast(win.private().repulsion.getValue() / 1000);
        engine.temperature = @floatCast(win.private().temperature.getValue() / 1000);

        _ = engine.tick() catch |err| @panic(@errorName(err));
        const msg = nng.Message.init(8) catch |err| @panic(@errorName(err));
        std.mem.writeInt(u64, msg.body()[0..8], engine.count, .big);
        win.private().socket.send(msg, .{}) catch |err| @panic(@errorName(err));
    }

    fn handleStartClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        std.log.info("handleStartClicked", .{});

        const engine = win.private().engine orelse return;
        engine.attraction = @floatCast(win.private().attraction.getValue() / 1000);
        engine.repulsion = @floatCast(win.private().repulsion.getValue() / 1000);
        engine.temperature = @floatCast(win.private().temperature.getValue() / 1000);

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

    fn loop(win: *ApplicationWindow) !void {
        const engine = win.private().engine orelse return;
        while (win.private().status == .Started) {
            _ = try engine.tick();
            const msg = try nng.Message.init(8);
            std.mem.writeInt(u64, msg.body()[0..8], engine.count, .big);
            try win.private().socket.send(msg, .{});
        }
    }

    fn handleViewClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        std.log.info("handleViewClicked", .{});
        win.private().child_process = spawn(c_allocator, &.{EXECUTABLE_PATH}, null);
        win.private().view_button.as(gtk.Widget).setSensitive(0);
    }

    fn handleRandomizeClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        std.log.info("handleRandomizeClicked", .{});

        const store = win.private().store orelse return;
        const engine = win.private().engine orelse return;

        const s = std.math.sqrt(@as(f32, @floatFromInt(store.node_count)));
        engine.randomize(s * 100);

        const msg = nng.Message.init(8) catch |err| @panic(@errorName(err));
        std.mem.writeInt(u64, msg.body()[0..8], engine.count, .big);
        win.private().socket.send(msg, .{}) catch |err| @panic(@errorName(err));
    }

    fn handleAttractionValueChanged(_: *LogScale, value: f64, win: *ApplicationWindow) callconv(.C) void {
        const engine = win.private().engine orelse return;
        engine.attraction = @floatCast(value / 1000);
    }

    fn handleRepulsionValueChanged(_: *LogScale, value: f64, win: *ApplicationWindow) callconv(.C) void {
        const engine = win.private().engine orelse return;
        engine.repulsion = @floatCast(value / 1000);
    }

    fn handleTemperatureValueChanged(_: *LogScale, value: f64, win: *ApplicationWindow) callconv(.C) void {
        const engine = win.private().engine orelse return;
        engine.temperature = @floatCast(value / 1000);
    }

    fn handleOpenResponse(chooser: *gtk.FileChooserNative, _: c_int, win: *ApplicationWindow) callconv(.C) void {
        defer chooser.unref();
        const file = gtk.FileChooser.getFile(chooser.as(gtk.FileChooser)) orelse return;
        defer file.unref();
        win.openFile(file);
    }

    fn private(win: *ApplicationWindow) *Private {
        return gobject.ext.impl_helpers.getPrivate(win, Private, Private.offset);
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
            gtk.Widget.Class.setTemplateFromResource(class.as(gtk.Widget.Class), TEMPLATE_PATH);

            class.bindTemplateChildPrivate("window_title", .{});

            class.bindTemplateChildPrivate("save_button", .{});
            class.bindTemplateChildPrivate("open_button", .{});
            class.bindTemplateChildPrivate("tick_button", .{});
            class.bindTemplateChildPrivate("start_button", .{});
            class.bindTemplateChildPrivate("stop_button", .{});
            class.bindTemplateChildPrivate("view_button", .{});
            class.bindTemplateChildPrivate("randomize_button", .{});
            class.bindTemplateChildPrivate("progress_bar", .{});

            class.bindTemplateChildPrivate("attraction", .{});
            class.bindTemplateChildPrivate("repulsion", .{});
            class.bindTemplateChildPrivate("temperature", .{});

            class.bindTemplateChildPrivate("stack", .{});
        }

        fn bindTemplateChildPrivate(class: *Class, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
            gtk.ext.impl_helpers.bindTemplateChildPrivate(class, name, Private, Private.offset, options);
        }
    };
};

fn loadResultCallback(_: ?*gobject.Object, res: *gio.AsyncResult, data: ?*anyopaque) callconv(.C) void {
    std.log.info("loadResultCallback", .{});

    _ = res;

    const win: *ApplicationWindow = @alignCast(@ptrCast(data));

    const store = win.private().store orelse return;
    const engine = Engine.init(c_allocator, store) catch |err| {
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
    gtk.Stack.setVisibleChildName(win.private().stack, "controls");
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
