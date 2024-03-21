@vertex fn vertex_main(
    @builtin(vertex_index) VertexIndex : u32,
    @location(0) v: vec2<f32>
) -> @builtin(position) vec4<f32> {
    return vec4<f32>(v.x / 3, v.y / 3, 0, 1);
}

@fragment fn frag_main() -> @location(0) vec4<f32> {
    return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
