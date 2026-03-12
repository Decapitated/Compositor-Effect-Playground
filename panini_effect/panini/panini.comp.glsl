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

// Our push constant.
// Must be aligned to 16 bytes, just like the push constant we passed from the script.
layout(push_constant, std430) uniform Params {
    vec2 raster_size;
    float view;
    float curvature;
}
params;

// The code we want to execute in each invocation.
void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);

    ivec2 size = ivec2(params.raster_size);
    int view = int(params.view);

    if (uv.x >= size.x || uv.y >= size.y) {
        return;
    }

    vec2 uv_norm = (vec2(uv) * 2.0 - params.raster_size) / params.raster_size.y;

    // Based on: https://www.shadertoy.com/view/X3GcWW
    // Fixed parameter for the Panini projection
    // k controls the "curvature" of the projection
    // Try other values (e.g. 1.5, 0.8, etc.) to see different Panini distortion strengths
    float k = params.curvature;

    // -----------------------------------------------
    // Step 1: Solve for the intersection with the cylinder
    // -----------------------------------------------

    // Quadratic equation coefficients
    float A = uv_norm.x * uv_norm.x + (k + 1.0) * (k + 1.0);
    float B = k * (k + 1.0);
    float C = k * k - 1.0;

    // Solve the quadratic equation for t
    // t is the distance scaling factor to reach the cylinder surface
    float t = (B + sqrt(B * B - A * C)) / A;

    // -----------------------------------------------
    // Step 2: Compute the ray direction
    // -----------------------------------------------

    // The ray direction intersects the virtual cylinder at this point
    vec3 rayDirection = vec3(t * uv_norm, t * (k + 1.0) - k);

    // Normalize the ray direction to ensure proper sampling
    rayDirection = normalize(rayDirection);

    ivec2 new_uv = ivec2((rayDirection.xy * params.raster_size.y + params.raster_size) / 2.0);
    vec4 color = imageLoad(color_image, new_uv);
    // uv_norm = (vec2(new_uv) * 2.0 - params.raster_size) / params.raster_size.y;
    // float mod_ = 0.5;
    // vec4 color = vec4(mod(uv_norm.xy, mod_) / mod_, 0.0, 1.0);
    imageStore(color_image, uv, color);
}