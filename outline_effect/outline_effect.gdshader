shader_type canvas_item;
render_mode unshaded;

uniform float width = 1.0;

void fragment() {
	float dist = COLOR.r;
	COLOR.rgb = vec3(0.0);
	COLOR.a = float(dist < width);
}
