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

layout(set = 0, binding = 2) uniform sampler2D extraction_texture;

layout(rgba16f, set = 0, binding = 3) uniform image2D jump_flood_image;
layout(rgba16f, set = 0, binding = 4) uniform image2D output_image;

// Our push constant.
// Must be aligned to 16 bytes, just like the push constant we passed from the script.
layout(push_constant, std430) uniform Params {
    vec2 raster_size;
    float view;
    float debug;
    float offset;
    float samples;
    float pass;
}
params;

float distance_sqr( vec2 A, vec2 B ) {
    vec2 C = A - B;
    return dot( C, C );
}

vec3 get_extraction(vec2 uv) {
    return texture(extraction_texture, uv).rgb;
}

vec2 get_seed(ivec2 uv) {
    return imageLoad(jump_flood_image, uv).rg;
}

vec2 get_closest_seed(ivec2 uv, ivec2 size) {
    float min_dist = 10000000.0;
    vec2 closest_seed = get_seed(uv);
    if(closest_seed == uv) {
        return uv;
    }
    for(int i = 0; i < int(params.samples); i++) {
        float angle = ((2.0*PI) / params.samples) * i;
        vec2 dir = vec2(cos(angle), sin(angle));
        ivec2 sample_uv = ivec2(uv + dir * params.offset);
        if(sample_uv.x < 0.0 || sample_uv.x >= size.x || sample_uv.y < 0.0 || sample_uv.y >= size.y) {
            continue;
        }
        vec2 seed_sample = get_seed(sample_uv);
        if(seed_sample != vec2(-1.0)) {
            float dist_sqr = distance_sqr(uv, seed_sample);
            if(dist_sqr < min_dist) {
                closest_seed = seed_sample;
                min_dist = dist_sqr;
            }
        }
    }
    return closest_seed;
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
    vec3 extraction_sample = get_extraction(uv_norm);

    vec2 closest_seed_sample = get_seed(uv);
    float css_distance_sqr = closest_seed_sample == vec2(-1.0) ?
        10000000 : distance_sqr(uv, closest_seed_sample);
    
    vec4 color = vec4(closest_seed_sample, 0.0, 1.0);

    float pass = params.pass;
    // Pass 0: Initial Seed
    if(pass == 0.0) {
        if(length(extraction_sample) > 0.0) {
            color.xy = uv;
        }
    }
    // Pass 1 & 4: Jump Flood
    else if(pass == 1.0 || pass == 4.0) {
        vec2 closest_seed = get_closest_seed(uv, size);
        if(closest_seed != vec2(-1.0)) {
            float cs_distance_sqr = distance_sqr(uv, closest_seed);

            if(cs_distance_sqr <= css_distance_sqr) {
                color.xy = closest_seed;
            }
        }
    }
    // Pass 2: Store Result
    else if(pass == 2.0) {
        float dist = sqrt(css_distance_sqr);
        color.rgb = vec3(dist);
    }
    // Pass 3: Inverse Seed
    else if(pass == 3.0) {
        if(length(extraction_sample) == 0.0) {
            color.xy = uv;
        }
    }
    // Pass 5: Store Inverse Result
    else if(pass == 5.0) {
        float dist = sqrt(css_distance_sqr);
        color.rgb = vec3(-dist);
    }

    if(pass == 2.0 || (pass == 5.0 && color.r < 0.0)) {
        imageStore(output_image, uv, color);
    } else {
        imageStore(jump_flood_image, uv, color);
    }

    if(params.debug == 1.0) {
        imageStore(color_image, uv, color / vec4(vec3(1000.0), 1.0));
    }
}