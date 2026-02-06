shader_type spatial;
render_mode shadows_disabled;

uniform bool use_albedo_texture = false;
uniform vec3 albedo_color : source_color = vec3(1.0);
uniform sampler2D albedo_texture : source_color, repeat_disable, hint_default_white;
uniform sampler2D color_ramp : source_color, repeat_disable;

void fragment() {
	ALBEDO = mix(albedo_color, texture(albedo_texture, UV).rgb, float(use_albedo_texture));
}

void light() {
	float light_dot = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float ramp = texture(color_ramp, vec2(light_dot, 0.0)).r;
	DIFFUSE_LIGHT += ramp * ATTENUATION * LIGHT_COLOR / PI;
}
