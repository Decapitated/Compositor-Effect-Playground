#version 450

#define MAX_VIEWS 2

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

layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(set = 0, binding = 3) uniform sampler2D normal_roughness_texture;
layout(set = 0, binding = 4) uniform sampler2D stencil_texture;

// Our push constant.
// Must be aligned to 16 bytes, just like the push constant we passed from the script.
layout(push_constant, std430) uniform Params {
    vec2 raster_size;
    float view;
    float debug;
    float scale;
    float depth_threshold;
    float normal_threshold;
    float depth_normal_threshold;
    float depth_normal_threshold_scale;
}
params;

float saturate(float value) {
    return clamp(value, 0.0, 1.0);
}

float get_depth(vec2 uv) {
    return texture(depth_texture, uv).r;
}

float get_linear_depth(vec2 uv) {
    float depth = get_depth(uv);
    vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
    vec4 view = scene_data_block.data.inv_projection_matrix * vec4(ndc, 1.0);
    view.xyz /= view.w;
    return -view.z;
}

float sample_depth(vec2 uv, vec2 texel_size) {
    float halfScaleFloor = floor(params.scale * 0.5);
    float halfScaleCeil = ceil(params.scale * 0.5);

    vec2 bottomLeftUV = uv - vec2(texel_size.x, texel_size.y) * halfScaleFloor;
    vec2 topRightUV = uv + vec2(texel_size.x, texel_size.y) * halfScaleCeil;  
    vec2 bottomRightUV = uv + vec2(texel_size.x * halfScaleCeil, -texel_size.y * halfScaleFloor);
    vec2 topLeftUV = uv + vec2(-texel_size.x * halfScaleFloor, texel_size.y * halfScaleCeil);

    float depth0 = get_linear_depth(bottomLeftUV);
    float depth1 = get_linear_depth(topRightUV);
    float depth2 = get_linear_depth(bottomRightUV);
    float depth3 = get_linear_depth(topLeftUV);

    float depthFiniteDifference0 = depth1 - depth0;
    float depthFiniteDifference1 = depth3 - depth2;

    float edgeDepth = sqrt(pow(depthFiniteDifference0, 2) + pow(depthFiniteDifference1, 2));
    return edgeDepth;
}

vec4 normal_roughness_compatibility(vec4 p_normal_roughness) {
	float roughness = p_normal_roughness.w;
	if (roughness > 0.5) {
		roughness = 1.0 - roughness;
	}
	roughness /= (127.0 / 255.0);
	return vec4(normalize(p_normal_roughness.xyz * 2.0 - 1.0) * 0.5 + 0.5, roughness);
}

vec4 get_normal(vec2 uv) {
    return normal_roughness_compatibility(texture(normal_roughness_texture, uv));
}

float sample_normal(vec2 uv, vec2 texel_size) {
    float halfScaleFloor = floor(params.scale * 0.5);
    float halfScaleCeil = ceil(params.scale * 0.5);

    vec2 bottomLeftUV = uv - vec2(texel_size.x, texel_size.y) * halfScaleFloor;
    vec2 topRightUV = uv + vec2(texel_size.x, texel_size.y) * halfScaleCeil;  
    vec2 bottomRightUV = uv + vec2(texel_size.x * halfScaleCeil, -texel_size.y * halfScaleFloor);
    vec2 topLeftUV = uv + vec2(-texel_size.x * halfScaleFloor, texel_size.y * halfScaleCeil);

    vec3 normal0 = get_normal(bottomLeftUV).rgb;
    vec3 normal1 = get_normal(topRightUV).rgb;
    vec3 normal2 = get_normal(bottomRightUV).rgb;
    vec3 normal3 = get_normal(topLeftUV).rgb;

    vec3 normalFiniteDifference0 = normal1 - normal0;
    vec3 normalFiniteDifference1 = normal3 - normal2;

    float edgeNormal = sqrt(dot(normalFiniteDifference0, normalFiniteDifference0) + dot(normalFiniteDifference1, normalFiniteDifference1));

    return edgeNormal;
}

float get_stencil(vec2 uv) {
    return texture(stencil_texture, uv).r;
}

float sample_stencil(vec2 uv, vec2 texel_size) {
    float halfScaleFloor = floor(params.scale * 0.5);
    float halfScaleCeil = ceil(params.scale * 0.5);

    vec2 bottomLeftUV = uv - vec2(texel_size.x, texel_size.y) * halfScaleFloor;
    vec2 topRightUV = uv + vec2(texel_size.x, texel_size.y) * halfScaleCeil;  
    vec2 bottomRightUV = uv + vec2(texel_size.x * halfScaleCeil, -texel_size.y * halfScaleFloor);
    vec2 topLeftUV = uv + vec2(-texel_size.x * halfScaleFloor, texel_size.y * halfScaleCeil);

    float stencil0 = get_stencil(bottomLeftUV);
    float stencil1 = get_stencil(topRightUV);
    float stencil2 = get_stencil(bottomRightUV);
    float stencil3 = get_stencil(topLeftUV);

    float stencilFiniteDifference0 = stencil1 - stencil0;
    float stencilFiniteDifference1 = stencil3 - stencil2;

    float edgeStencil = sqrt(pow(stencilFiniteDifference0, 2) + pow(stencilFiniteDifference1, 2));

    return edgeStencil;
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

    vec4 color = imageLoad(color_image, uv);
    float depth = get_depth(uv_norm);
    vec4 normal = get_normal(uv_norm);
    float stencil = get_stencil(uv_norm);

    vec2 ndc = uv_norm * 2.0 - 1.0;
    ndc.y = -ndc.y;

    float normal_sample = sample_normal(uv_norm, scene_data_block.data.screen_pixel_size);
    float normal_edge = stencil == 0.0 && normal_sample > params.normal_threshold ? 1.0 : 0.0;

    vec4 view_pos = scene_data_block.data.inv_projection_matrix * vec4(ndc, -1.0, 1.0);
    vec3 view_dir = normalize(view_pos.xyz);
    float n_dot_v = 1.0 - dot(normal.xyz * 2.0 - 1.0, -view_dir);
    float normal_threshold_1 = saturate((n_dot_v - params.depth_normal_threshold) / (1.0 - params.depth_normal_threshold));
    float normal_threshold = normal_threshold_1 * params.depth_normal_threshold_scale + 1.0;

    float depth_sample = sample_depth(uv_norm, scene_data_block.data.screen_pixel_size);
    float depth_threshold = params.depth_threshold;
    float depth_edge = stencil == 0.0 && ((normal_sample > params.normal_threshold*0.5 && depth_sample * 100.0 > depth_threshold) || (depth_sample * 100.0 > depth_threshold * 4.0)) ? 1.0 : 0.0;

    float stencil_sample = sample_stencil(uv_norm, scene_data_block.data.screen_pixel_size);
    float stencil_edge = stencil_sample > 0.0 ? 1.0 : 0.0;

    float edge = max(max(depth_edge, normal_edge), stencil_edge);

    color = vec4(vec3(edge), 1.0);

    if(params.debug == 1.0) {
        imageStore(color_image, uv, color);
    }
}