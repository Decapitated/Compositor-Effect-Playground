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
	
	// --- Step A: Tiling Logic ---
    // Number of number-tiles across the screen
    float numTiles = 25.0; 
    vec2 tiledUV = UV * numTiles;
    // Separate into integer grid-cell ID and normalized UV inside that cell
    vec2 cellID = floor(tiledUV);
    vec2 cellUV = fract(tiledUV); 

    // --- Step B: Digit Selection Logic ---
    // We need 3 slots: [Hundreds] [Tens] [Ones]
    int numDigits = 3;
    float currentDigitPosition = floor(cellUV.x * float(numDigits));
    
    // --- Step C: Math out the digits 0-255 ---
    int hundredDigit = (stencil / 100) % 10;
    int tenDigit     = (stencil / 10) % 10;
    int oneDigit     = stencil % 10;
    
    // Map the position inside the tile to the correct mathematical digit
    int selectedCharAscii = int(char_0_offset); // Default '0'
    
    // Check which slot this pixel belongs to:
    if (currentDigitPosition == 0.0) {
        selectedCharAscii += hundredDigit;
    } else if (currentDigitPosition == 1.0) {
        selectedCharAscii += tenDigit;
    } else {
        selectedCharAscii += oneDigit;
    }
    
    // --- Step D: Recalculate UVs inside the single digit slot ---
    vec2 finalDigitUV = fract(vec2(cellUV.x * float(numDigits), cellUV.y));

    // --- Step E: Sample Texture ---
    vec2 finalAtlasUV = mapToChar(finalDigitUV, selectedCharAscii);
    
    // Assuming codepage12 is in iChannel0
    // Standard codepage12 usually only uses the RED channel
    vec4 tex = texture(codepage, finalAtlasUV);
    float textShape = tex.r;

    // Optional: Add some color or background
	vec3 stencil_color = hsv2rgb(vec3(float(stencil) / 255.0, 1.0, 1.0));
	vec3 text_color = vec3(0.0);
    vec3 col = mix(stencil_color, text_color, textShape);
    
    // Output
    COLOR = vec4(col, float(bool(stencil)));
}

//void fragment() {
	//int stencil = int(texture(TEXTURE, UV).r);
	//vec3 stencil_color = hsv2rgb(vec3(float(stencil) / 255.0, 1.0, 1.0));
	//COLOR = vec4(stencil_color, float(bool(stencil)));
//}
