shader_type canvas_item;

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	int stencil = int(texture(TEXTURE, UV).r);
	vec3 stencil_color = hsv2rgb(vec3(float(stencil) / 255.0, 1.0, 1.0));
	COLOR = vec4(stencil_color, float(bool(stencil)));
}
