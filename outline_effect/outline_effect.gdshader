shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float edge = max(max(COLOR.r, COLOR.g), COLOR.b);
	COLOR.rgb = vec3(0.0);
	COLOR.a = edge;
}
