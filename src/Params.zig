const std = @import("std");
const utils = @import("utils.zig");

pub const Point = @Vector(2, f32);
pub const Force = @Vector(2, f32);

const Params = @This();

attraction: f32 = 0.0001,
repulsion: f32 = 100.0,
center: f32 = 1.0,
temperature: f32 = 0.2,
