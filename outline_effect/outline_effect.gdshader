shader_type canvas_item;
render_mode unshaded;

uniform float width = 1.0;
uniform float bias = 1.0;

void fragment() {
	vec3 color = textureLod(TEXTURE, UV, bias).rgb;
	COLOR = vec4(color / 100.0, 1.0);
	//float dist = COLOR.r;
	//COLOR.rgb = vec3(0.0);
	//COLOR.a = float(dist < width);
}
