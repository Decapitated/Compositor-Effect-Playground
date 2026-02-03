#version 450

#define MAX_VIEWS 2

// Provided by godot "virtually".
// https://github.com/godotengine/godot/blob/98782b6c8c9cabe0fb7c80bc62640735ecb076d3/servers/rendering/renderer_rd/renderer_scene_render_rd.cpp#L1679C6-L1679C7
// "Virtually" talked about here: https://github.com/godotengine/godot-proposals/issues/8366#issuecomment-1800249408
#include "godot/scene_data_inc.glsl"

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
    SceneData data;
    SceneData prev_data;
}
scene_data_block;

layout(rgba16f, set = 0, binding = 1) uniform image2D color_image;
layout(rgba16f, set = 0, binding = 2) uniform image2D seed_image;
layout(rgba16f, set = 0, binding = 3) uniform image2D output_image;

// Our push constant.
// Must be aligned to 16 bytes, just like the push constant we passed from the script.
layout(push_constant, std430) uniform Params {
    vec2 raster_size;
    float view;
}
params;

float get_seed(ivec2 uv) {
    return imageLoad(seed_image, uv).r;
}

float get_seed_distance(ivec2 uv, ivec2 size) {
    float min_distance = 10000000.0;
    for(int y = 0; y < size.y; y++) {
        for(int x = 0; x < size.x; x++) {
            ivec2 seed_uv = ivec2(x, y);
            float seed = get_seed(seed_uv);
            float seed_distance = distance(uv, seed_uv);
            min_distance = min(min_distance, seed_distance);
        }
    }
    return min_distance;
}

// The code we want to execute in each invocation.
void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = ivec2(params.raster_size);
    int view = int(params.view);

    if (uv.x >= size.x || uv.y >= size.y) {
        return;
    }

    vec2 uv_norm = vec2(uv) / params.raster_size;

    float seed = get_seed(uv);
    // float seed_distance = seed == 1.0 ? 0.0 : get_seed_distance(uv, size);

    imageStore(color_image, uv, vec4(vec3(seed), 1.0));
    // imageStore(color_image, uv, color);
}