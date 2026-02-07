#version 450

#define MAX_VIEWS 2

#define PI 3.14159265359

// #define NOISE

// Provided by godot "virtually".
// https://github.com/godotengine/godot/blob/98782b6c8c9cabe0fb7c80bc62640735ecb076d3/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp#L1679C6-L1679C7
// "Virtually" talked about here: https://github.com/godotengine/godot-proposals/issues/8366#issuecomment-1800249408
#include "godot/scene_data_inc.glsl"

// Included by compositor effect.
#ifdef NOISE
#[FastNoiseLite]
#endif

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
    SceneData data;
    SceneData prev_data;
}
scene_data_block;

layout(rgba16f, set = 0, binding = 1) uniform image2D color_image;

layout(set = 0, binding = 2) uniform sampler2D jump_flood_texture;

// Our push constant.
// Must be aligned to 16 bytes, just like the push constant we passed from the script.
layout(push_constant, std430) uniform Params {
    vec2 raster_size;
    float view;
    float outside_width;
    vec4 outside_line_color;
    float inside_width;
    float outside_offset;
    float inside_offset;
    vec4 inside_line_color;
}
params;

float get_distance(vec2 uv) {
    return texture(jump_flood_texture, uv).r;
}

// The code we want to execute in each invocation.
void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

    ivec2 size = ivec2(params.raster_size);
    int view = int(params.view);

    if (uv.x >= size.x || uv.y >= size.y) {
        return;
    }
    
    vec2 uv_norm = vec2(uv) / size;

    float distance_sample = get_distance(uv_norm);

    vec4 color = imageLoad(color_image, uv);

    float outside_width = params.outside_width;
    float outside_offset = params.outside_offset;

    float inside_width = params.inside_width;
    float inside_offset = params.inside_offset;

    float outside_edge = float(outside_width > 0.0 && distance_sample >= outside_offset && distance_sample <= outside_offset + outside_width);
    float inside_edge = float(inside_width > 0.0 && distance_sample <= -inside_offset && distance_sample >= -inside_offset - inside_width);

    vec4 line_color = mix(params.outside_line_color, params.inside_line_color, inside_edge);

    #ifdef NOISE
    fnl_state noise_state = fnlCreateState(0);
    noise_state.noise_type = FNL_NOISE_OPENSIMPLEX2;
    noise_state.fractal_type = FNL_FRACTAL_FBM;
	noise_state.octaves = 8;
	noise_state.lacunarity = 4.f;
	noise_state.gain = .75f;
    noise_state.frequency = 0.01;

    float noise = fnlGetNoise2D(noise_state, uv.x, uv.y) * 0.5 + 0.5;
    noise = ceil(noise - 0.5);
    outside_edge *= noise;
    inside_edge *= noise;
    #endif

    color.rgb = mix(color.rgb, line_color.rgb, line_color.a * max(outside_edge, inside_edge));

    imageStore(color_image, uv, color);
}