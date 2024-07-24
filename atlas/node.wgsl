struct Params {
    width: f32,
    height: f32,
    offset_x: f32,
    offset_y: f32,
    scale: f32,
    min_radius: f32,
    scale_radius: f32,
    pixel_ratio: f32,
};

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read> nodes: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read> z: array<f32>;

fn grid_space_to_ndc(v: vec2<f32>) -> vec4<f32> {
    let x = (v.x + params.offset_x) * params.scale * 2 / params.width;
    let y = (v.y + params.offset_y) * params.scale * 2 / params.height;
    return vec4<f32>(x, y, 0, 1);
}

fn grid_space_to_clip_space(v: vec2<f32>) -> vec2<f32> {
    let p = grid_space_to_ndc(v).xy;
    let x = params.width * (p.x + 1) / 2;
    let y = params.height * (1 - p.y) / 2;
    return vec2<f32>(x, y);
}

struct VSOutput {
    @builtin(position) vertex: vec4<f32>,
    @location(0) center: vec2<f32>,
    @location(1) radius: f32,
}

@vertex fn vertex_main(
    @builtin(instance_index) i: u32,
    @location(0) v: vec2<f32>,
) -> VSOutput {
    var vsOut: VSOutput;

    let r = params.min_radius + z[i];
    let c = nodes[i];
    vsOut.vertex = grid_space_to_ndc(c + (v * r));
    vsOut.center = grid_space_to_clip_space(c) * params.pixel_ratio;
    vsOut.radius = max(r * params.scale * params.pixel_ratio, 2);

    return vsOut;
}

const edgeWidth = 2.0;

@fragment fn frag_main(
    @builtin(position) pixel: vec4<f32>,
    @location(0) center: vec2<f32>,
    @location(1) radius: f32,
) -> @location(0) vec4<f32> {
    let dist = distance(pixel.xy, center);
    let alpha = 1.0 - smoothstep(radius - edgeWidth, radius, dist);
    return vec4<f32>(0.1, 0.1, 0.1, alpha);
}
