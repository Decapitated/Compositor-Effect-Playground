@tool
class_name OutlineEffect extends CompositorEffect

const SHADER_PATH := "res://outline_effect/outline/outline.comp.glsl"
const FAST_NOISE_LITE_PATH := "res://outline_effect/outline/FastNoiseLite.glsl"

@export var jump_flood_effect: JumpFloodEffect

@export_range(0, 10, 0.01, "or_greater") var outside_width: float = 0.0
@export_range(0, 10, 0.01, "or_greater") var inside_width: float = 3.0
@export_range(0, 10, 0.01, "or_greater") var outside_offset: float = 0
@export_range(0, 10, 0.01, "or_greater") var inside_offset: float = 0
@export var outside_line_color: Color = Color.BLACK
@export var inside_line_color: Color = Color.BLACK

var _rd: RenderingDevice = null

var _shader: RID
var _pipeline: RID
var _linear_sampler: RID

var _cache_shader_code := ""

enum CallbackError {
    OK = 0,
    INVALID_PIPELINE,
    INVALID_RENDER_DATA,
    INVALID_COLOR_TEXTURE,
}
var error: CallbackError = CallbackError.OK

func _init() -> void:
    effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT

    _rd = RenderingServer.get_rendering_device()

    var linear_sampler_state: RDSamplerState = RDSamplerState.new()
    linear_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
    linear_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
    _linear_sampler = _rd.sampler_create(linear_sampler_state)

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if _shader.is_valid():
            _rd.free_rid(_shader)
        if _linear_sampler.is_valid():
            _rd.free_rid(_linear_sampler)

func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
    if jump_flood_effect == null:
        return

    _check_shader()
    # Check if the _pipeline is valid.
    if !_pipeline.is_valid():
        if error != CallbackError.INVALID_PIPELINE:
            error = CallbackError.INVALID_PIPELINE
            push_error("Pipeline is invalid")
        return
    elif error == CallbackError.INVALID_PIPELINE:
        error = CallbackError.OK

    var scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
    var scene_data: RenderSceneData = render_data.get_render_scene_data()
    
    # Check if the render data is valid.
    if !scene_buffers || !scene_data:
        if error != CallbackError.INVALID_RENDER_DATA:
            error = CallbackError.INVALID_RENDER_DATA
            push_error("Render data is invalid")
        return
    elif error == CallbackError.INVALID_RENDER_DATA:
        error = CallbackError.OK

    # Get our render size, this is the 3D render resolution!
    var size: Vector2i = scene_buffers.get_internal_size()
    if size.x == 0 && size.y == 0:
        return

    @warning_ignore("integer_division")
    var x_groups: int = (size.x - 1) / 16 + 1
    @warning_ignore("integer_division")
    var y_groups: int = (size.y - 1) / 16 + 1
    var z_groups: int = 1

    var push_constant := PackedFloat32Array([
        size.x, size.y,        # Raster Size                  (8) (8)
        0.0,                   # View                         (4) (12)
        outside_width,         # Outisde Width                (4) (16)
        outside_line_color.r,  # Outside Color                (16)(16)
        outside_line_color.g,
        outside_line_color.b,
        outside_line_color.a,
        inside_width,          # Inside Width                 (4) (4)
        outside_offset,        # Outside Offset               (4) (8)
        inside_offset,         # Inside Offset                (4) (12)
        0.0,                   # Padding                      (4) (16)
        inside_line_color.r,   # Inside Color                 (16)(16)
        inside_line_color.g,
        inside_line_color.b,
        inside_line_color.a,
    ])
    var scene_data_uniform_buffer: RID = scene_data.get_uniform_buffer()
    # Run compute for each view.    
    var view_count: int = scene_buffers.get_view_count()
    for view in view_count:
        # Set view.
        push_constant[2] = view

        var color_image: RID = scene_buffers.get_color_layer(view)
        if !color_image.is_valid():
            if error != CallbackError.INVALID_COLOR_TEXTURE:
                error = CallbackError.INVALID_COLOR_TEXTURE
                push_error("Color texture is invalid")
            return
        elif error == CallbackError.INVALID_COLOR_TEXTURE:
            error = CallbackError.OK
        
        #region Set 0 Uniforms
        # Scene Data
        var scene_data_uniform := RDUniform.new()
        scene_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
        scene_data_uniform.binding = 0
        scene_data_uniform.add_id(scene_data_uniform_buffer)
        # Color Image
        var color_uniform := RDUniform.new()
        color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        color_uniform.binding = 1
        color_uniform.add_id(color_image)
        # Jump Flood Image
        var jump_flood_uniform := RDUniform.new()
        jump_flood_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        jump_flood_uniform.binding = 2
        jump_flood_uniform.add_id(_linear_sampler)
        jump_flood_uniform.add_id(jump_flood_effect.output_texture.texture_rd_rid)
        #endregion

        var uniform_set_0: RID = UniformSetCacheRD.get_cache(_shader, 0, [scene_data_uniform, color_uniform, jump_flood_uniform])

         # Run compute _shader for last pass.
        var compute_list: int = _rd.compute_list_begin()
        _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
        _rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
        var push_constant_bytes := push_constant.to_byte_array()
        _rd.compute_list_set_push_constant(compute_list, push_constant_bytes, push_constant_bytes.size())
        _rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
        _rd.compute_list_end()

#region Shader
func _check_shader() -> void:
    var shader_code := _get_shader_code()
    if shader_code != _cache_shader_code:
        _cache_shader_code = shader_code
        var new_shader := _build_shader(shader_code)
        if new_shader.is_valid():
            if _shader.is_valid():
                _rd.free_rid(_shader)
            _shader = new_shader
            _pipeline = _rd.compute_pipeline_create(_shader)

func _get_shader_code() -> String:
    var shader_code: String = FileAccess.get_file_as_string(SHADER_PATH)
    assert(!shader_code.is_empty(), "Shader code is empty")
    var fast_noise_code: String = FileAccess.get_file_as_string(FAST_NOISE_LITE_PATH)
    assert(!fast_noise_code.is_empty(), str(FileAccess.get_open_error()))
    shader_code = shader_code.replace("#[FastNoiseLite]", fast_noise_code)
    return shader_code

func _build_shader(shader_code: String) -> RID:
    print("Building outline shader...")
    var shader_source := RDShaderSource.new()
    shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    shader_source.source_compute = shader_code

    var shader_spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(shader_source)
    if shader_spirv.compile_error_compute != "":
        push_error(shader_spirv.compile_error_compute)
        return RID()
    
    var new_shader := _rd.shader_create_from_spirv(shader_spirv)
    if not new_shader.is_valid():
        push_error("Shader is invalid")
        return RID()

    return new_shader
#endregion
