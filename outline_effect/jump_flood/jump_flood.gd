@tool
class_name JumpFloodEffect extends CompositorEffect

@export var extraction_effect: ExtractionEffect

@export_range(1, 10, 1, "or_greater") var distance: int = 10
@export_range(3, 32, 1) var samples: int = 4
@export var debug := false

var _rd: RenderingDevice = null

var _shader: RID
var _pipeline: RID
var _linear_sampler: RID

var _texture_format: RDTextureFormat = RDTextureFormat.new()
var _jump_flood_texture: RID
var _output_texture: RID
var output_texture: Texture2DRD = Texture2DRD.new()

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
        if _jump_flood_texture.is_valid():
            _rd.free_rid(_jump_flood_texture)
        if _output_texture.is_valid():
            _rd.free_rid(_output_texture)

func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
    if extraction_effect == null:
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
    
    if !_output_texture.is_valid() || !_jump_flood_texture.is_valid() || \
            _texture_format.width != size.x || _texture_format.height != size.y:
        _create_textures(size.x, size.y)

    @warning_ignore("integer_division")
    var x_groups: int = (size.x - 1) / 16 + 1
    @warning_ignore("integer_division")
    var y_groups: int = (size.y - 1) / 16 + 1
    var z_groups: int = 1

    var push_constant := PackedFloat32Array([
        size.x, size.y, # Raster Size                  (8) (8)
        0.0,            # View                         (4) (12)
        float(debug),   # Debug                        (4) (16)
        0.0,            # Offset                       (4) (4)
        float(samples), # Samples                      (4) (8)
        0.0,            # Pass                         (4) (12)
        0.0,            # Padding                      (4) (16)
    ])
    var scene_data_uniform_buffer: RID = scene_data.get_uniform_buffer()
    # Run compute for each view.    
    var view_count: int = scene_buffers.get_view_count()
    for view in view_count:
        _rd.texture_clear(_jump_flood_texture, Color(-1.0, -1.0, 0.0, 0.0), 0, 1, 0, 1)
        
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
        # Extraction Image
        var extraction_uniform := RDUniform.new()
        extraction_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        extraction_uniform.binding = 2
        extraction_uniform.add_id(_linear_sampler)
        extraction_uniform.add_id(extraction_effect.output_texture.texture_rd_rid)
        # Jump Flood Image
        var jump_flood_uniform := RDUniform.new()
        jump_flood_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        jump_flood_uniform.binding = 3
        jump_flood_uniform.add_id(_jump_flood_texture)
        # Output Image
        var output_uniform := RDUniform.new()
        output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        output_uniform.binding = 4
        output_uniform.add_id(_output_texture)
        #endregion

        var uniform_set_0: RID = UniformSetCacheRD.get_cache(_shader, 0, [scene_data_uniform, color_uniform, extraction_uniform, jump_flood_uniform, output_uniform])

        var current_offset: float = distance
        while current_offset >= 1.0:
            # Set offset.
            push_constant[4] = current_offset

            # Run compute _shader.
            _run_compute(uniform_set_0, push_constant, x_groups, y_groups, z_groups)

            # If first pass (Seed Pass), set pass mode to 1. (JFA Pass)
            if push_constant[6] == 0.0:
                push_constant[6] = 1.0
            else:
                # Update offset for next pass.
                current_offset /= 2.0
        
        # Set pass mode to 2. (Last Pass)
        push_constant[6] = 2.0
        # Run compute _shader for last pass.
        _run_compute(uniform_set_0, push_constant, x_groups, y_groups, z_groups)

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
    var shader_code: String = FileAccess.get_file_as_string("res://outline_effect/jump_flood/jump_flood.comp.glsl")
    assert(!shader_code.is_empty(), "Shader code is empty")
    return shader_code

func _build_shader(shader_code: String) -> RID:
    print("Building jump flood shader...")
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

func _create_textures(width: int, height: int) -> void:
    _texture_format = RDTextureFormat.new()
    _texture_format.width = width
    _texture_format.height = height
    _texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    _texture_format.usage_bits = \
        RenderingDevice.TEXTURE_USAGE_INPUT_ATTACHMENT_BIT | \
        RenderingDevice.TEXTURE_USAGE_STORAGE_BIT  | \
        RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | \
        RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
        RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT # Allows us to clear the texture.

    # Create Jump Flood Texture
    var new_jump_flood_texture := _rd.texture_create(_texture_format, RDTextureView.new())
    if _jump_flood_texture.is_valid():
        _rd.free_rid(_jump_flood_texture)
    _jump_flood_texture = new_jump_flood_texture

    # Create Output Texture
    var new_output_texture := _rd.texture_create(_texture_format, RDTextureView.new())
    output_texture.texture_rd_rid = new_output_texture
    if _output_texture.is_valid():
        _rd.free_rid(_output_texture)
    _output_texture = new_output_texture

func _run_compute(uniform_set_0: RID, push_constant: PackedFloat32Array, x_groups: int, y_groups: int, z_groups: int) -> void:
    var compute_list: int = _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
    _rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
    var push_constant_bytes := push_constant.to_byte_array()
    _rd.compute_list_set_push_constant(compute_list, push_constant_bytes, push_constant_bytes.size())
    _rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
    _rd.compute_list_end()
