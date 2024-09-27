const std = @import("std");

const nng = @import("nng");

const Beacon = @This();

seq: u64 = 0,
socket: nng.Socket.PUB,

pub fn init(socket_url: [*:0]const u8) !Beacon {
    const socket = try nng.Socket.PUB.open();
    try socket.listen(socket_url);
    return .{ .socket = socket, .seq = 0 };
}

pub fn deinit(self: *Beacon) void {
    self.socket.close();
    self.seq = std.math.maxInt(u64);
}

pub fn publish(self: *Beacon) !void {
    const msg = nng.Message.init(8) catch |err| @panic(@errorName(err));
    std.mem.writeInt(u64, msg.body()[0..8], self.seq, .big);
    self.socket.send(msg, .{}) catch |err| @panic(@errorName(err));
    self.seq += 1;
}
