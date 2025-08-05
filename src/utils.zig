pub inline fn norm(f: @Vector(2, f32)) f32 {
    return @sqrt(@reduce(.Add, f * f));
}

pub inline fn getMass(incoming_degree: usize) f32 {
    const d: f32 = @floatFromInt(incoming_degree);
    return @sqrt(d) + 1;
}
