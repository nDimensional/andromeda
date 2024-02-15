const std = @import("std");

const ul = @import("ul");

const Config = ul.Ultralight.Config;
const View = ul.Ultralight.View;
const App = ul.AppCore.App;
const Window = ul.AppCore.Window;
const Overlay = ul.AppCore.Overlay;
const Settings = ul.AppCore.Settings;
const Context = ul.JavaScriptCore.Context;
const ValueRef = ul.JavaScriptCore.ValueRef;

const File = @import("File.zig");
const Listener = @import("Listener.zig");
const Store = @import("Store.zig");

const Environment = @This();

config: Config,
settings: Settings,

app: App,
window: Window,
overlay: Overlay,
view: View,

html: File,
store: Store,
timer: std.time.Timer,

listener: Listener,
running: bool = false,
runner: ?std.Thread = null,

pub fn init(env: *Environment, allocator: std.mem.Allocator, path: [*:0]const u8) !void {
    env.store = try Store.init(allocator, path);
    env.store.randomize(200);

    env.timer = try std.time.Timer.start();

    env.config = Config.init();
    env.config.setResourcePathPrefix("SDK/resources/");

    env.settings = Settings.init();
    env.settings.setDeveloperName("nDimensional");
    env.settings.setAppName("Andromeda");

    env.app = App.init(env.settings, env.config);

    env.window = Window.init(
        env.app.getMainMonitor(),
        .{ .width = 1200, .height = 800, .tilted = true, .resizable = true },
    );

    env.window.setResizeCallback(Environment, env, &onWindowResize);

    env.overlay = Overlay.init(env.window, env.window.getWidth(), env.window.getHeight(), 0, 0);

    env.view = env.overlay.getView();
    env.view.setDOMReadyCallback(Environment, env, &onDOMReady);
    env.view.setConsoleMessageCallback(Environment, env, &onConsoleMessage);

    env.html = try File.init("assets/app.html");
    env.listener = Listener.init("dist/index.js");
    env.runner = null;
    env.running = false;
}

pub fn deinit(self: Environment) void {
    self.app.deinit();
    self.config.deinit();
    self.settings.deinit();
    self.store.deinit();
    self.window.deinit();
    self.overlay.deinit();

    self.html.deinit();
    self.listener.deinit();
}

pub fn run(self: *Environment) void {
    self.view.loadHTML(self.html.data);
    self.app.setUpdateCallback(Environment, self, &onUpdate);
    self.app.run();
}

fn onDOMReady(env: *Environment, event: View.DOMReadyEvent) void {
    {
        const ctx = event.view.lock();
        defer event.view.unlock();

        ctx.evaluateScript("window.foo = 233232") catch @panic("ctx.evaluateScript failed");
        ctx.evaluateScript("window.bar = window") catch @panic("ctx.evaluateScript failed");
        env.store.inject(ctx) catch @panic("store.inject failed");

        const global = ctx.getGlobal();

        const class = ctx.createClass(Environment, "Environment", &.{
            .{ .name = "refresh", .exec = &refresh },
            // .{ .name = "tick", .exec = &tick },
            .{ .name = "save", .exec = &save },
            .{ .name = "start", .exec = &start },
            .{ .name = "stop", .exec = &stop },
            .{ .name = "setAttraction", .exec = &setAttraction },
            .{ .name = "setRepulsion", .exec = &setRepulsion },
            .{ .name = "setTemperature", .exec = &setTemperature },
        });

        ctx.setProperty(global, "env", class.make(env));
    }

    const js = File.init("dist/index.js") catch @panic("failed to open file");
    defer js.deinit();

    env.view.evaluateScript(js.data) catch |err| {
        std.log.err("failed to evaluate script: {any}", .{err});
        return;
    };
}

fn onConsoleMessage(_: *Environment, event: View.ConsoleMessageEvent) void {
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

fn onWindowResize(env: *Environment, event: Window.ResizeEvent) void {
    env.overlay.resize(event.window.getWidth(), event.window.getHeight());
}

fn onUpdate(env: *Environment) void {
    var result = env.listener.poll() catch return;
    while (result) |event| {
        if (event.fflags & std.os.darwin.NOTE_WRITE != 0) {
            std.log.info("reloading...", .{});
            env.view.loadHTML(env.html.data);
            return;
        }

        result = env.listener.poll() catch return;
    }
}

fn refresh(env: *Environment, ctx: Context, args: []const ValueRef) !ValueRef {
    if (args.len != 5) {
        return error.ARGC;
    }

    const area = Store.AreaParams{
        .minX = @floatCast(ctx.getNumber(args[0])),
        .maxX = @floatCast(ctx.getNumber(args[1])),
        .minY = @floatCast(ctx.getNumber(args[2])),
        .maxY = @floatCast(ctx.getNumber(args[3])),
        .minZ = @floatCast(ctx.getNumber(args[4])),
    };

    std.log.info("refresh({any})", .{area});
    const ids = try env.store.refresh(area);
    return try ctx.makeTypedArray(u32, ids);
}

fn start(env: *Environment, _: Context, _: []const ValueRef) !ValueRef {
    if (env.runner == null) {
        env.running = true;
        env.runner = try std.Thread.spawn(.{}, loop, .{env});
    }

    return null;
}

fn loop(env: *Environment) void {
    const stdout = std.io.getStdOut().writer();
    env.timer.reset();
    while (env.running) {
        const energy = env.store.tick() catch continue;
        stdout.print("tick: {d}ms ({d})\n", .{ env.timer.lap() / 1_000_000, energy }) catch continue;
    }
}

fn stop(env: *Environment, _: Context, _: []const ValueRef) !ValueRef {
    env.running = false;
    if (env.runner) |t| {
        t.join();
        env.runner = null;
    }

    return null;
}

// fn tick(env: *Environment, _: Context, args: []const ValueRef) !ValueRef {
//     if (args.len != 0) {
//         return error.ARGC;
//     }

//     env.timer.reset();
//     const avg = try env.store.tick();

//     try std.io.getStdOut().writer().print("tick: {d}ms ({d})\n", .{ env.timer.lap() / 1_000_000, avg });

//     return null;
// }

fn save(env: *Environment, _: Context, args: []const ValueRef) !ValueRef {
    if (args.len != 0) {
        return error.ARGC;
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("saving...\n", .{});
    try env.store.save();
    try stdout.print("saved!\n", .{});

    return null;
}

fn setAttraction(env: *Environment, ctx: Context, args: []const ValueRef) !ValueRef {
    if (args.len != 1) {
        return error.ARGC;
    }

    env.store.attraction = @floatCast(ctx.getNumber(args[0]));
    return null;
}

fn setRepulsion(env: *Environment, ctx: Context, args: []const ValueRef) !ValueRef {
    if (args.len != 1) {
        return error.ARGC;
    }

    env.store.repulsion = @floatCast(ctx.getNumber(args[0]));
    return null;
}

fn setTemperature(env: *Environment, ctx: Context, args: []const ValueRef) !ValueRef {
    if (args.len != 1) {
        return error.ARGC;
    }

    env.store.temperature = @floatCast(ctx.getNumber(args[0]));
    return null;
}
