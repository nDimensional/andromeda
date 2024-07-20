const std = @import("std");
const gio = @import("gio");
const gobject = @import("gobject");

const Store = @import("Store.zig");
const Progress = @import("Progress.zig");

const Worker = @This();

const EXECUTABLE_PATH = "/Users/joelgustafson/Projects/andromeda/zig-out/bin/andromeda-atlas";

allocator: std.mem.Allocator,
child_process: std.process.Child,
store: Store,
progress: Progress,

pub fn init(allocator: std.mem.Allocator, path: [*:0]const u8) !Worker {
    const store = try Store.init(allocator, path);

    // const size = @sizeOf(Store.Point) * store.node_count;
    // const writer = try sho.Writer(SHM_NAME).init(size);

    // @memcpy(writer.data, @as([*]const u8, @ptrCast(store.positions)));

    const child_process = std.process.Child.init(&.{EXECUTABLE_PATH}, allocator);
    // try child_process.spawn();

    return .{
        .allocator = allocator,
        .child_process = child_process,
        .store = store,
    };
}

pub fn deinit(self: *Worker) void {
    const status = self.child_process.kill() catch |e| @panic(@errorName(e));
    std.log.info("terminated child process {any}", .{status});

    self.store.deinit();
    // self.writer.deinit();
}

// pub fn load(self: *Worker) void {
//     const task = gio.Task.new(null, null, &loadReadyCallback, self);
//     defer task.unref();

//     task.setTaskData(self, null);
//     task.runInThread(&loadTask);
//     // const task = c.g_task_new(null, null, &loadReadyCallback, self);
//     // c.g_task_set_task_data(task, self, null);
//     // c.g_task_run_in_thread(task, &loadTask);
// }

// fn loadTask(task: *gio.Task, source_object: *gobject.Object, task_data: ?*anyopaque, cancellable: ?*gio.Cancellable) callconv(.C) void {
//     _ = source_object; // autofix
//     _ = cancellable; // autofix
//     std.log.info("loadTask", .{});

//     const self: *Worker = @alignCast(@ptrCast(task_data));
//     _ = self;

//     std.posix.nanosleep(5, 0);
//     task.returnPointer(null, null);
// }

// fn loadReadyCallback(_: ?*gobject.Object, res: *gio.AsyncResult, data: ?*anyopaque) callconv(.C) void {
//     const task: *gio.Task = @ptrCast(res);
//     const ptr = task.propagatePointer(null);
//     _ = ptr;

//     const self: *Worker = @alignCast(@ptrCast(data));
//     _ = self; // autofix

//     std.log.info("loadReadyCallback", .{});
// }
