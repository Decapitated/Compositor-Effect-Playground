shader_type canvas_item;

// Codepage12 is usually a 16x16 grid of characters
const float grid_size = 16.0;
// We only want to draw digits (0-9).
// In ASCII/Codepage12, '0' starts at index 48.
const float char_0_offset = 48.0;

uniform sampler2D codepage: hint_default_white;

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// --- 1. Map current UV to a specific character index ---
// CharUV: Normalized (0-1) coordinates within a SINGLE character square
// AsciiVal: The integer ASCII/Codepage value (e.g., 53 for '5')
vec2 mapToChar(vec2 CharUV, int AsciiVal) {
    // 1. Calculate row/col (integer 0-15)
    float col = mod(float(AsciiVal), grid_size);
    // Usually, codepages start '0,0' at bottom-left
    float row = floor(float(AsciiVal) / grid_size); 

    // 2. Scale UV down to 1/16th and shift to the right tile
    vec2 atlasUV = (CharUV + vec2(col, row)) / grid_size;
    return atlasUV;
}

void fragment() {
	int stencil = int(texture(TEXTURE, UV).r);
	vec3 stencil_color = hsv2rgb(vec3(float(stencil) / 255.0, 1.0, 1.0));
	vec3 text_color = vec3(1.0);
	vec3 highlight_color = vec3(0.0);
	vec3 background_color = stencil_color;
	
	vec3 color = background_color;
	
    int numDigits = 10;
    vec2 tiledUV = SCREEN_UV / SCREEN_PIXEL_SIZE * 0.005;
	tiledUV *= vec2(1.0, float(numDigits));
	
    vec2 cellID = floor(tiledUV);
	vec2 cellUV = fract(tiledUV + vec2(float(cellID.y)*0.333, 0.0));
	
	vec2 mod_uv = vec2(mod(cellUV.x * float(numDigits), 1.0), cellUV.y);
	//color = vec3(mod_uv, 0.0);
	if(mod(cellID.y, 4.0) == 0.0) {
	    float currentDigitPosition = floor(cellUV.x * float(numDigits));
	    
	    // --- Step C: Math out the digits 0-255 ---
	    int hundredDigit = (stencil / 100) % 10;
	    int tenDigit     = (stencil / 10) % 10;
	    int oneDigit     = stencil % 10;
	    
	    // Map the position inside the tile to the correct mathematical digit
	    int selectedCharAscii = int(char_0_offset); // Default '0'
	    
		if(currentDigitPosition < 3.0) {
			// Check which slot this pixel belongs to:
		    if (currentDigitPosition == 0.0) {
		        selectedCharAscii += hundredDigit;
		    } else if (currentDigitPosition == 1.0) {
		        selectedCharAscii += tenDigit;
		    } else {
		        selectedCharAscii += oneDigit;
		    }

		    vec2 charUV = mapToChar(mod_uv, selectedCharAscii);
		    float textShape = texture(codepage, charUV).r;

		    color = mix(highlight_color, text_color, textShape);
		}
	}
    
    // Output
    COLOR = vec4(color, float(bool(stencil)) * COLOR.a);
}
