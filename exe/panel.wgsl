const panel_width = 640;
const panel_height = 480;

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
@group(0) @binding(1) var ourSampler: sampler;
@group(0) @binding(2) var ourTexture: texture_2d<f32>;

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

@vertex fn vertex_main(
    @builtin(instance_index) i: u32,
    @location(0) v: vec2<f32>,
) -> @builtin(position) vec4<f32> {
    let x = ((v.x + 1) / 2) * panel_width / params.width;
    let y = ((1 - v.y) / 2) * panel_height / params.height;
    return vec4<f32>(2 * x - 1, 1 - 2 * y, 0, 1);
}

@fragment fn frag_main(
    @builtin(position) pixel: vec4<f32>,
) -> @location(0) vec4<f32> {
    let p = pixel.xy / vec2<f32>(panel_width, panel_height) / params.pixel_ratio;
    let s = textureSample(ourTexture, ourSampler, p);
    return s;
    // return vec4<f32>(1.0, 1.0, 1.0, 1.0);
}
