const std = @import("std");

const sqlite = @import("sqlite");

pub fn main() !void {
    var iter = std.process.ArgIterator.init();
    _ = iter.next();

    const command = iter.next() orelse {
        std.log.err("missing command", .{});
        std.log.err("usage: edgelist [import|export] path/to/input path/to/output", .{});
        return error.MissingArgument;
    };

    const input_path = iter.next() orelse {
        std.log.err("missing input path", .{});
        std.log.err("usage: edgelist [import|export] path/to/input path/to/output", .{});
        return error.MissingArgument;
    };

    const output_path = iter.next() orelse {
        std.log.err("missing output path", .{});
        std.log.err("usage: edgelist [import|export] path/to/input path/to/output", .{});
        return error.MissingArgument;
    };

    if (std.mem.eql(u8, command, "import")) {
        try importEdgelist(input_path, output_path);
    } else if (std.mem.eql(u8, command, "export")) {
        try exportEdgelist(input_path, output_path);
    } else {
        std.log.err("invalid command", .{});
        std.log.err("usage: edgelist [import|export] path/to/input path/to/output", .{});
        return error.InvalidArgument;
    }
}

const batch_size = 10000;

pub const InsertNodeParams = struct { id: u32 };
pub const InsertEdgeParams = struct { source: u32, target: u32 };

var edge_buffer: [1024]u8 = undefined;

fn importEdgelist(input_path: [:0]const u8, output_path: [:0]const u8) !void {
    const db = try sqlite.Database.open(.{ .path = output_path.ptr });
    defer db.close();

    try db.exec(
        \\ CREATE TABLE IF NOT EXISTS nodes (
        \\   x FLOAT NOT NULL DEFAULT 0,
        \\   y FLOAT NOT NULL DEFAULT 0
        \\ );
    , .{});

    try db.exec(
        \\ CREATE TABLE IF NOT EXISTS edges (
        \\   source INTEGER NOT NULL,
        \\   target INTEGER NOT NULL
        \\ );
    , .{});

    try db.exec("DELETE FROM nodes", .{});
    try db.exec("DELETE FROM edges", .{});

    const insert_node = try db.prepare(InsertNodeParams, void,
        \\ INSERT INTO nodes(rowid) VALUES (:id) ON CONFLICT (rowid) DO NOTHING;
    );
    defer insert_node.finalize();

    const insert_edge = try db.prepare(InsertEdgeParams, void,
        \\ INSERT INTO edges(source, target) VALUES (:source, :target)
    );
    defer insert_edge.finalize();

    var dir = std.fs.cwd();

    var input_file = try dir.openFileZ(input_path, .{});
    defer input_file.close();

    const reader = input_file.reader();

    var i: usize = 0;
    while (try reader.readUntilDelimiterOrEof(&edge_buffer, '\n')) |edge| : (i += 1) {
        var iter = std.mem.splitScalar(u8, edge, ' ');
        const source = iter.next() orelse return error.InvalidFile;
        const target = iter.next() orelse return error.InvalidFile;
        const s = try std.fmt.parseInt(u32, source, 10);
        const t = try std.fmt.parseInt(u32, target, 10);

        try insert_node.exec(.{ .id = s });
        try insert_node.exec(.{ .id = t });
        try insert_edge.exec(.{ .source = s, .target = t });

        if (i % batch_size == 0) {
            std.log.info("imported {d} edges", .{i});
        }
    }
}

const SelectEdgeParams = struct {};
const SelectEdgeResult = struct { source: u32, target: u32 };

fn exportEdgelist(input_path: [:0]const u8, output_path: [:0]const u8) !void {
    const db = try sqlite.Database.open(.{ .path = input_path.ptr, .create = false });
    defer db.close();

    const select_edges = try db.prepare(SelectEdgeParams, SelectEdgeResult,
        \\ SELECT source, target FROM edges
    );
    defer select_edges.finalize();

    var dir = std.fs.cwd();

    var output_file = try dir.createFileZ(output_path, .{ .truncate = true });
    defer output_file.close();

    var writer = output_file.writer();

    try select_edges.bind(.{});

    var i: usize = 0;
    while (try select_edges.step()) |edge| : (i += 1) {
        try writer.print("{d} {d}\n", .{ edge.source, edge.target });
        if (i % batch_size == 0) {
            std.log.info("exported {d} edges", .{i});
        }
    }
}
