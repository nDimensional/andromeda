const c = @import("c.zig");

pub const Socket = struct {
    pub const PUB = Protocol(c.nng_pub0_open);
    pub const SUB = Protocol(c.nng_sub0_open);
};

fn Protocol(comptime constructor: *const fn (ptr: *c.nng_socket) callconv(.C) c_int) type {
    return struct {
        const Self = @This();

        impl: c.nng_socket,

        pub fn open() !Self {
            var impl: c.nng_socket = undefined;
            try throw(constructor(&impl));
            return .{ .impl = impl };
        }

        pub fn close(self: Self) void {
            throw(c.nng_close(self.impl)) catch |err| @panic(@errorName(err));
        }

        pub fn set(self: Self, opt: [*:0]const u8, val: []const u8) !void {
            try throw(c.nng_socket_set(self.impl, opt, val.ptr, val.len));
        }

        pub fn dial(self: Self, url: [*:0]const u8) !void {
            var dialer: c.nng_dialer = undefined;
            try throw(c.nng_dialer_create(&dialer, self.impl, url));
            try throw(c.nng_dialer_start(dialer, 0));
        }

        pub fn listen(self: Self, url: [*:0]const u8) !void {
            var listener: c.nng_listener = undefined;
            try throw(c.nng_listener_create(&listener, self.impl, url));
            try throw(c.nng_listener_start(listener, 0));
        }

        pub const RecvOptions = struct { NONBLOCK: bool = false };

        pub fn recv(self: Self, options: RecvOptions) !Message {
            var ptr: ?*c.nng_msg = null;

            var flags: c_int = 0;
            if (options.NONBLOCK) flags |= c.NNG_FLAG_NONBLOCK;
            try throw(c.nng_recvmsg(self.impl, &ptr, flags));

            return .{ .ptr = ptr };
        }

        pub const SendOptions = struct { NONBLOCK: bool = false };

        pub fn send(self: Self, msg: Message, options: SendOptions) !void {
            var flags: c_int = 0;
            if (options.NONBLOCK) flags |= c.NNG_FLAG_NONBLOCK;
            try throw(c.nng_sendmsg(self.impl, msg.ptr, flags));
        }
    };
}

pub const Message = struct {
    ptr: ?*c.nng_msg,

    pub fn init(len: usize) !Message {
        var ptr: ?*c.nng_msg = null;
        try throw(c.nng_msg_alloc(&ptr, len));
        return .{ .ptr = ptr };
    }

    pub fn deinit(self: Message) void {
        c.nng_msg_free(self.ptr);
    }

    pub fn body(self: Message) []u8 {
        const ptr = c.nng_msg_body(self.ptr);
        const len = c.nng_msg_len(self.ptr);
        return @as([*]u8, @ptrCast(ptr))[0..len];
    }
};

pub const Logger = enum { NONE, SYSTEM, STDERR };

pub fn setLogger(logger: Logger) void {
    c.nng_log_set_level(c.NNG_LOG_DEBUG);
    switch (logger) {
        .NONE => c.nng_log_set_logger(c.nng_null_logger),
        .SYSTEM => c.nng_log_set_logger(c.nng_stderr_logger),
        .STDERR => c.nng_log_set_logger(c.nng_system_logger),
    }
}

fn throw(rc: c_int) !void {
    try switch (rc) {
        0 => {},
        c.NNG_EINTR => error.INTR,
        c.NNG_ENOMEM => error.NOMEM,
        c.NNG_EINVAL => error.INVAL,
        c.NNG_EBUSY => error.BUSY,
        c.NNG_ETIMEDOUT => error.TIMEDOUT,
        c.NNG_ECONNREFUSED => error.CONNREFUSED,
        c.NNG_ECLOSED => error.CLOSED,
        c.NNG_EAGAIN => error.AGAIN,
        c.NNG_ENOTSUP => error.NOTSUP,
        c.NNG_EADDRINUSE => error.ADDRINUSE,
        c.NNG_ESTATE => error.STATE,
        c.NNG_ENOENT => error.NOENT,
        c.NNG_EPROTO => error.PROTO,
        c.NNG_EUNREACHABLE => error.UNREACHABLE,
        c.NNG_EADDRINVAL => error.ADDRINVAL,
        c.NNG_EPERM => error.PERM,
        c.NNG_EMSGSIZE => error.MSGSIZE,
        c.NNG_ECONNABORTED => error.CONNABORTED,
        c.NNG_ECONNRESET => error.CONNRESET,
        c.NNG_ECANCELED => error.CANCELED,
        c.NNG_ENOFILES => error.NOFILES,
        c.NNG_ENOSPC => error.NOSPC,
        c.NNG_EEXIST => error.EXIST,
        c.NNG_EREADONLY => error.READONLY,
        c.NNG_EWRITEONLY => error.WRITEONLY,
        c.NNG_ECRYPTO => error.CRYPTO,
        c.NNG_EPEERAUTH => error.PEERAUTH,
        c.NNG_ENOARG => error.NOARG,
        c.NNG_EAMBIGUOUS => error.AMBIGUOUS,
        c.NNG_EBADTYPE => error.BADTYPE,
        c.NNG_ECONNSHUT => error.CONNSHUT,
        c.NNG_EINTERNAL => error.INTERNAL,
        c.NNG_ESYSERR => error.SYSERR,
        c.NNG_ETRANERR => error.TRANERR,
        else => @panic("invalid return code"),
    };
}
