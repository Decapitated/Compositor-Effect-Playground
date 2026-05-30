#[compute]
#version 450

#define MAX_VIEWS 2

#define PI 3.14159265359

#define INVALID_SEED uvec2(65535)

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
layout(rgba32f, set = 0, binding = 2) uniform image2D output_image;

// Our push constant.
// Must be aligned to 16 bytes, just like the push constant we passed from the script.
layout(push_constant, std430) uniform Params {
    vec2 raster_size;
    float view;
    float pass;      // 0 = Pixelate; 1 = Store result;
    float scale;     // Pixelate
    float pad[3];
}
params;

// The code we want to execute in each invocation.
void main() {
    ivec2 uv_int = ivec2(gl_GlobalInvocationID.xy);

    ivec2 size = ivec2(params.raster_size);
    if (uv_int.x >= size.x || uv_int.y >= size.y) {
        return;
    }

    int view = int(params.view);
    int pass = int(params.pass);

    vec4 color = vec4(vec3(0.0), 1.0);

    if(pass == 0) {
        // Insert pixelate here.
        int pixel_size = max(int(params.scale), 1);
        ivec2 block_coord = (uv_int / pixel_size) * pixel_size;
        color = imageLoad(color_image, block_coord);
        imageStore(output_image, uv_int, color);
    } else if(pass == 1) {
        color = imageLoad(output_image, uv_int);
        imageStore(color_image, uv_int, color);
    }
}