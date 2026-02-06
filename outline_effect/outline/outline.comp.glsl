#version 450

#define MAX_VIEWS 2

#define PI 3.14159265359

// Provided by godot "virtually".
// https://github.com/godotengine/godot/blob/98782b6c8c9cabe0fb7c80bc62640735ecb076d3/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp#L1679C6-L1679C7
// "Virtually" talked about here: https://github.com/godotengine/godot-proposals/issues/8366#issuecomment-1800249408
#include "godot/scene_data_inc.glsl"

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
    vec4 line_color;
    float inside_width;
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

    vec4 line_color = params.line_color;
    // float edge = 1.0 - clamp(ceil(abs(distance_sample) - params.outside_width), 0.0, 1.0);
    float edge = -params.inside_width < distance_sample && distance_sample < params.outside_width ? 1.0 : 0.0;

    color.rgb = mix(color.rgb, line_color.rgb, line_color.a * edge);

    imageStore(color_image, uv, color);
}