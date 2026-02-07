shader_type spatial;

uniform float subdivisions : hint_range(2, 2048, 2.0) = 32;
uniform float grid_width : hint_range(0.0, 1.0, 0.01) = 0.02;
uniform vec3 background_color : source_color = vec3(0.2, 0.2, 0.2);
uniform vec3 background_color_two : source_color = vec3(0.1, 0.1, 0.1);
uniform vec3 grid_color : source_color = vec3(0.5, 0.5, 0.5);
uniform float dashed_scale_x : hint_range(0.0, 0.99, 0.01) = 0.02;
uniform float dashed_scale_y : hint_range(0.0, 0.99, 0.01) = 0.02;
uniform float dashed_count_x : hint_range(0.0, 16.0, 1.0) = 1.0;
uniform float dashed_count_y : hint_range(0.0, 16.0, 1.0) = 1.0;

group_uniforms Point;
uniform float point_width : hint_range(0.0, 1.0, 0.01) = 0.021;
uniform vec3 point_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float point_scale_x : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float point_scale_y : hint_range(0.0, 1.0, 0.01) = 0.05;

group_uniforms InsideGrid;
uniform float inside_width : hint_range(0.0, 1.0, 0.01) = 0.01;
uniform float inside_subdivisions : hint_range(1, 9, 1) = 6;
uniform vec3  inside_color : source_color = vec3(0.4, 0.4, 0.4);
uniform float in_dashed_scale_x : hint_range(0.0, 0.99, 0.01) = 0.3;
uniform float in_dashed_scale_y : hint_range(0.0, 0.99, 0.01) = 0.3;
uniform float in_dashed_count_x : hint_range(0.0, 18.0, 1.0) = 6.0;
uniform float in_dashed_count_y : hint_range(0.0, 18.0, 1.0) = 6.0;

//TriPlanar Stuff
group_uniforms TriPlanar;
varying vec3 uv1_triplanar_pos;
varying vec3 uv1_power_normal;
uniform bool use_uv = true;
uniform bool world_triplanar = false;
uniform bool screen_triplanar = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
const float uv1_blend_sharpness = 1.0;

void vertex() {
	vec3 normal = MODEL_NORMAL_MATRIX * NORMAL;
	TANGENT = vec3(0.0,0.0,-1.0) * abs(normal.x);
	TANGENT+= vec3(1.0,0.0,0.0) * abs(normal.y);
	TANGENT+= vec3(1.0,0.0,0.0) * abs(normal.z);
	TANGENT = inverse(MODEL_NORMAL_MATRIX) * normalize(TANGENT);
	BINORMAL = vec3(0.0,1.0,0.0) * abs(normal.x);
	BINORMAL+= vec3(0.0,0.0,-1.0) * abs(normal.y);
	BINORMAL+= vec3(0.0,1.0,0.0) * abs(normal.z);
	BINORMAL = inverse(MODEL_NORMAL_MATRIX) * normalize(BINORMAL);
	uv1_power_normal=pow(abs(normal),vec3(uv1_blend_sharpness));
	if(use_uv)
	{
		uv1_triplanar_pos = vec3(UV, 0.0) * uv1_scale + uv1_offset;
	}else if(world_triplanar)
	{
		uv1_triplanar_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0f)).xyz * uv1_scale + uv1_offset;
	}else if(screen_triplanar)
	{
		uv1_triplanar_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0f)).xyz * uv1_scale + uv1_offset;
	}else
	{
		uv1_triplanar_pos = VERTEX * uv1_scale + uv1_offset;
	}
	uv1_power_normal/=dot(uv1_power_normal,vec3(1.0));
	uv1_triplanar_pos *= vec3(1.0,-1.0, 1.0);
}

float grid(vec2 uv, vec2 lineWidth,bool check) {
	vec4 uvDDXY = vec4(dFdx(uv), dFdy(uv));
	vec2 uvDeriv = vec2(length(uvDDXY.xz), length(uvDDXY.yw));
	
	bvec2 invertLine = bvec2(lineWidth.x > 0.5, lineWidth.y > 0.5); //RV
	vec2 targetWidth = vec2(
		invertLine.x ? 1.0 - lineWidth.x : lineWidth.x,
		invertLine.y ? 1.0 - lineWidth.y : lineWidth.y
		);
	
	
	vec2 lineAA = uvDeriv * 1.5;
	vec2 gridUV = abs((fract(uv)) * 2.0 - 1.0);
	
	
	if (check == true){
		targetWidth = vec2(1.0);
		lineAA *= 1.5;
		
		float index = 0.0;
		index += step(1.0, mod(uv.x, 2.0));
		index += step(1.0, mod(uv.y, 2.0)) * 2.0;
		
		if (index == 1.0 || index == 2.0) {
			lineAA = -lineAA;
		}
	} else  {
		gridUV = vec2(
			invertLine.x ? gridUV.x : 1.0 - gridUV.x,
			invertLine.y ? gridUV.y : 1.0 - gridUV.y 
		);
	}
	
	vec2 drawWidth = clamp(targetWidth, uvDeriv, vec2(1.0));
	vec2 gridBase = smoothstep(drawWidth + lineAA, drawWidth - lineAA, gridUV);
	
	
	gridBase *= clamp(targetWidth / drawWidth, 0.0, 1.0);
	gridBase = mix(gridBase , targetWidth , clamp((uvDeriv * 2.0 - 1.0) , 0.0, 1.0));
	gridBase.x = invertLine.x ? 1.0 - gridBase.x : gridBase.x; 
	gridBase.y = invertLine.y ? 1.0 - gridBase.y : gridBase.y; 
	
	
	return mix(gridBase.x, 1.0, gridBase.y);
}

float dashed_grid(vec2 uv, vec2 lineWidth, vec2 dot_width, vec2 count, float add){
	//Inverts the width values
	lineWidth = 1.0 - lineWidth;
	//Create two "masks", one for X and one for Y
	float gridX = 1.0 - grid(vec2(uv.x * count.x, uv.y + add), vec2(dot_width.x, lineWidth.x), false);
	float gridY = 1.0 - grid(vec2(uv.y * count.y, uv.x + add), vec2(dot_width.y, lineWidth.y), false);
	
	float grid = mix(gridX, 1.0, gridY);
	return grid;
}

float triplanar_grid(vec3 p_weights,vec3 p_triplanar_pos){
	float samp = 0.0;
	samp+= grid(p_triplanar_pos.xy, vec2(0.5), true) * p_weights.z;
	samp+= grid(p_triplanar_pos.xz, vec2(0.5), true) * p_weights.y;
	samp+= grid(p_triplanar_pos.zy * vec2(-1.0,1.0), vec2(0.5), true) * p_weights.x;
	return samp;
}

float triplanar_dashed_grid(vec3 p_weights, vec3 p_triplanar_pos, vec2 lineWidth, vec2 dot_width, vec2 count, float add){
	float samp = 0.0;
	samp+= dashed_grid(p_triplanar_pos.xy, lineWidth, dot_width, count, add) * p_weights.z;
	samp+= dashed_grid(p_triplanar_pos.xz, lineWidth, dot_width, count, add) * p_weights.y;
	samp+= dashed_grid(p_triplanar_pos.zy * vec2(-1.0,1.0), lineWidth, dot_width, count, add) * p_weights.x;
	return samp;
}

void fragment() {
	//CheckerBoard
	//float checkeredGrid = grid(uv , vec2(0.5), true);
	float checkeredGrid = triplanar_grid(uv1_power_normal, uv1_triplanar_pos);
	
	//Grid
	//float mainGrid = dashed_grid(
			//uv , vec2(grid_width), vec2(dashed_scale_x, dashed_scale_y),
			//vec2(dashed_count_x, dashed_count_y), 0.5);
	float mainGrid = triplanar_dashed_grid(
		uv1_power_normal, uv1_triplanar_pos, 
		vec2(grid_width),
		vec2(dashed_scale_x, dashed_scale_y),
		vec2(dashed_count_x, dashed_count_y),
		0.5);
			
	//Inside Grid
	//float insideGrid = dashed_grid(
			//uv * inside_subdivisions, vec2(inside_width),
			//vec2(in_dashed_scale_x, in_dashed_scale_y),
			//vec2(in_dashed_count_x, in_dashed_count_y), 0.5);
	float insideGrid = triplanar_dashed_grid(
			uv1_power_normal, uv1_triplanar_pos * inside_subdivisions,
			vec2(inside_width),
			vec2(in_dashed_scale_x, in_dashed_scale_y),
			vec2(in_dashed_count_x, in_dashed_count_y),
			0.5);

	//Points
	//float pointGrid = dashed_grid(
			//uv + 0.5, vec2(point_width),
			//1.0 - vec2(point_scale_x , point_scale_y),
			//vec2(1.0), 0.0);
	float pointGrid = triplanar_dashed_grid(
			uv1_power_normal, uv1_triplanar_pos + 0.5,
			vec2(point_width),
			1.0 - vec2(point_scale_x,
			point_scale_y),
			vec2(1.0),
			0.0);
	
	//Add final color
	vec3 grid = mix(background_color, background_color_two, checkeredGrid);
	if (insideGrid != 0.0) grid = mix(grid, inside_color, insideGrid);
	if (mainGrid != 0.0) grid = mix(grid, grid_color, mainGrid);
	if (pointGrid != 0.0) grid = mix(grid, point_color, pointGrid);
	
	ALBEDO = grid;
}

//void fragment() {
	////Subdividing uv
	//vec2 uv = mod(UV, 1.0) * subdivisions;
	//
	////CheckerBoard
	//float checkeredGrid = grid(uv , vec2(0.5), true);
	//
	////Grid
	//float mainGrid = dashed_grid(
			//uv , vec2(grid_width), vec2(dashed_scale_x, dashed_scale_y),
			//vec2(dashed_count_x, dashed_count_y), 0.5);
			//
	////Inside Grid
	//float insideGrid = dashed_grid(
			//uv * inside_subdivisions, vec2(inside_width),
			//vec2(in_dashed_scale_x, in_dashed_scale_y),
			//vec2(in_dashed_count_x, in_dashed_count_y), 0.5);
//
	////Points
	//float pointGrid = dashed_grid(
			//uv + 0.5, vec2(point_width),
			//1.0 - vec2(point_scale_x , point_scale_y),
			//vec2(1.0), 0.0);
	//
	////Add final color
	//vec3 grid = mix(background_color, background_color_two, checkeredGrid);
	//if (insideGrid != 0.0) grid = mix(grid, inside_color, insideGrid);
	//if (mainGrid != 0.0) grid = mix(grid, grid_color, mainGrid);
	//if (pointGrid != 0.0) grid = mix(grid, point_color, pointGrid);
	//
	//ALBEDO = grid;
//}