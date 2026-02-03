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
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(rgba16f, set = 0, binding = 3) uniform image2D normal_roughness_image;
layout(rgba16f, set = 0, binding = 4) uniform image2D stencil_image;
layout(rgba16f, set = 0, binding = 5) uniform image2D output_image;

// Our push constant.
// Must be aligned to 16 bytes, just like the push constant we passed from the script.
layout(push_constant, std430) uniform Params {
    vec2 raster_size;
    float view;
    float pad;
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
    float depth = texture(depth_texture, uv).r;
    return depth;
    vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
    vec4 view = scene_data_block.data.inv_projection_matrix * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float linear_depth = -view.z;
    return linear_depth / 1000.0;
}

float sample_depth(vec2 uv, vec2 texel_size) {
    float halfScaleFloor = floor(params.scale * 0.5);
    float halfScaleCeil = ceil(params.scale * 0.5);

    vec2 bottomLeftUV = uv - vec2(texel_size.x, texel_size.y) * halfScaleFloor;
    vec2 topRightUV = uv + vec2(texel_size.x, texel_size.y) * halfScaleCeil;  
    vec2 bottomRightUV = uv + vec2(texel_size.x * halfScaleCeil, -texel_size.y * halfScaleFloor);
    vec2 topLeftUV = uv + vec2(-texel_size.x * halfScaleFloor, texel_size.y * halfScaleCeil);

    float depth0 = get_depth(bottomLeftUV);
    float depth1 = get_depth(topRightUV);
    float depth2 = get_depth(bottomRightUV);
    float depth3 = get_depth(topLeftUV);

    float depthFiniteDifference0 = depth1 - depth0;
    float depthFiniteDifference1 = depth3 - depth2;

    float edgeDepth = sqrt(pow(depthFiniteDifference0, 2) + pow(depthFiniteDifference1, 2)) * 100.0;
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

vec4 get_normal(ivec2 uv) {
    return normal_roughness_compatibility(imageLoad(normal_roughness_image, uv));
}

float sample_normal(ivec2 uv) {
    float halfScaleFloor = floor(params.scale * 0.5);
    float halfScaleCeil = ceil(params.scale * 0.5);

    ivec2 bottomLeftUV = ivec2(uv - vec2(halfScaleFloor));
    ivec2 topRightUV = ivec2(uv + vec2(halfScaleCeil));  
    ivec2 bottomRightUV = ivec2(uv + vec2(halfScaleCeil, -halfScaleFloor));
    ivec2 topLeftUV = ivec2(uv + vec2(-halfScaleFloor, halfScaleCeil));

    vec3 normal0 = get_normal(bottomLeftUV).rgb;
    vec3 normal1 = get_normal(topRightUV).rgb;
    vec3 normal2 = get_normal(bottomRightUV).rgb;
    vec3 normal3 = get_normal(topLeftUV).rgb;

    vec3 normalFiniteDifference0 = normal1 - normal0;
    vec3 normalFiniteDifference1 = normal3 - normal2;

    float edgeNormal = sqrt(dot(normalFiniteDifference0, normalFiniteDifference0) + dot(normalFiniteDifference1, normalFiniteDifference1));

    return edgeNormal;
}

float get_stencil(ivec2 uv) {
    return imageLoad(stencil_image, uv).r;
}

float sample_stencil(ivec2 uv, vec2 texel_size) {
    float halfScaleFloor = floor(params.scale * 0.5);
    float halfScaleCeil = ceil(params.scale * 0.5);

    ivec2 bottomLeftUV = ivec2(uv - vec2(halfScaleFloor));
    ivec2 topRightUV = ivec2(uv + vec2(halfScaleCeil));  
    ivec2 bottomRightUV = ivec2(uv + vec2(halfScaleCeil, -halfScaleFloor));
    ivec2 topLeftUV = ivec2(uv + vec2(-halfScaleFloor, halfScaleCeil));

    float stencil0 = get_stencil(bottomLeftUV);
    float stencil1 = get_stencil(topRightUV);
    float stencil2 = get_stencil(bottomRightUV);
    float stencil3 = get_stencil(topLeftUV);

    float stencilFiniteDifference0 = stencil1 - stencil0;
    float stencilFiniteDifference1 = stencil3 - stencil2;

    float edgeStencil = sqrt(pow(stencilFiniteDifference0, 2) + pow(stencilFiniteDifference1, 2));

    return edgeStencil > 0.0 ? 1.0 : 0.0;
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
    float depth = texture(depth_texture, uv_norm).r;
    vec4 normal_roughness = get_normal(uv);
    float stencil = get_stencil(uv);

    float depth_sample = sample_depth(uv_norm, scene_data_block.data.screen_pixel_size);
    float depth_threshold = params.depth_threshold;
    depth_sample = stencil == 0.0 && depth_sample > depth_threshold ? 1.0 : 0.0;

    float normal_sample = sample_normal(uv);
    float normal_threshold = params.normal_threshold;
    normal_sample = stencil == 0.0 && normal_sample > normal_threshold ? 1.0 : 0.0;

    float stencil_sample = sample_stencil(uv, scene_data_block.data.screen_pixel_size);

    float edge = max(max(depth_sample, normal_sample), stencil_sample);
    
    color = vec4(vec3(edge), 1.0);

    imageStore(output_image, uv, color);
    // imageStore(color_image, uv, color);
}