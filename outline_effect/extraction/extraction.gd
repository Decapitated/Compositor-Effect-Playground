@tool
class_name ExtractionEffect extends CompositorEffect

@export var stencil_effect: StencilEffect
@export_range(1, 10, 1, "or_greater") var scale := 1
@export_range(0.0, 10.0, 0.001, "or_greater") var depth_threshold := 0.05
@export_range(0.0, 10.0, 0.001, "or_greater") var normal_threshold := 0.5
@export var debug := false

var _rd: RenderingDevice = null

var _shader: RID
var _pipeline: RID
var _linear_sampler: RID

var _texture_format: RDTextureFormat = RDTextureFormat.new()
var _texture: RID
var output_texture: Texture2DRD = Texture2DRD.new()

var _cache_shader_code := ""

enum CallbackError {
    OK = 0,
    INVALID_PIPELINE,
    INVALID_RENDER_DATA,
    INVALID_COLOR_TEXTURE,
    INVALID_DEPTH_TEXTURE,
    INVALID_NORMAL_TEXTURE
}
var error: CallbackError = CallbackError.OK

func _init() -> void:
    effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT

    _rd = RenderingServer.get_rendering_device()

    var linear_sampler_state: RDSamplerState = RDSamplerState.new()
    linear_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
    linear_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
    _linear_sampler = _rd.sampler_create(linear_sampler_state)

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if _shader.is_valid():
            _rd.free_rid(_shader)
        if _pipeline.is_valid():
            _rd.free_rid(_pipeline)
        if _linear_sampler.is_valid():
            _rd.free_rid(_linear_sampler)

func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
    if stencil_effect == null:
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

    if !output_texture.texture_rd_rid.is_valid() || \
            _texture_format.width != size.x || _texture_format.height != size.y:
        _create_output_texture(size.x, size.y)

    @warning_ignore("integer_division")
    var x_groups: int = (size.x - 1) / 16 + 1
    @warning_ignore("integer_division")
    var y_groups: int = (size.y - 1) / 16 + 1
    var z_groups: int = 1

    var push_constant := PackedFloat32Array([
        size.x, size.y,               # Raster Size                  (8) (8)
        0.0,                          # View                         (4) (12)
        float(debug),                 # Debug                        (4) (16)
        float(scale),                 # Scale                        (4) (4)
        depth_threshold,              # Depth Theshold               (4) (8)
        normal_threshold,             # Normal Threshold             (4) (12)
        0.0,                          # Padding                     (4) (16)
    ])
    var scene_data_uniform_buffer: RID = scene_data.get_uniform_buffer()
    # Run compute for each view.    
    var view_count: int = scene_buffers.get_view_count()
    for view in view_count:
        # Set view.
        push_constant[2] = view

        #region Retrieve & Check Textures
        var color_image: RID = scene_buffers.get_color_layer(view)
        if !color_image.is_valid():
            if error != CallbackError.INVALID_COLOR_TEXTURE:
                error = CallbackError.INVALID_COLOR_TEXTURE
                push_error("Color texture is invalid")
            return
        elif error == CallbackError.INVALID_COLOR_TEXTURE:
            error = CallbackError.OK

        var depth_image: RID = scene_buffers.get_depth_layer(view)
        if !depth_image.is_valid():
            if error != CallbackError.INVALID_DEPTH_TEXTURE:
                error = CallbackError.INVALID_DEPTH_TEXTURE
                push_error("Depth texture is invalid")
            return
        elif error == CallbackError.INVALID_DEPTH_TEXTURE:
            error = CallbackError.OK

        var normal_image: RID = scene_buffers.get_texture("forward_clustered", "normal_roughness")
        if !normal_image.is_valid():
            if error != CallbackError.INVALID_NORMAL_TEXTURE:
                error = CallbackError.INVALID_NORMAL_TEXTURE
                push_error("Normal texture is invalid")
            return
        elif error == CallbackError.INVALID_NORMAL_TEXTURE:
            error = CallbackError.OK
        #endregion

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
        # Depth Image
        var depth_uniform := RDUniform.new()
        depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        depth_uniform.binding = 2
        depth_uniform.add_id(_linear_sampler)
        depth_uniform.add_id(depth_image)
        # Normal Image
        var normal_uniform := RDUniform.new()
        normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        normal_uniform.binding = 3
        normal_uniform.add_id(_linear_sampler)
        normal_uniform.add_id(normal_image)
        # Stencil Image
        var stencil_uniform := RDUniform.new()
        stencil_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        stencil_uniform.binding = 4
        stencil_uniform.add_id(_linear_sampler)
        stencil_uniform.add_id(stencil_effect.output_texture.texture_rd_rid)
        # Output Image
        var output_uniform := RDUniform.new()
        output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        output_uniform.binding = 5
        output_uniform.add_id(_texture)
        #endregion

        var uniform_set_0: RID = UniformSetCacheRD.get_cache(_shader, 0, [scene_data_uniform, color_uniform, depth_uniform, normal_uniform, stencil_uniform, output_uniform])

        # Run compute _shader.
        var compute_list: int = _rd.compute_list_begin()
        _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
        _rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
        var push_constant_bytes := push_constant.to_byte_array()
        _rd.compute_list_set_push_constant(compute_list, push_constant_bytes, push_constant_bytes.size())
        _rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
        _rd.compute_list_end()

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
    var shader_code: String = FileAccess.get_file_as_string("res://outline_effect/extraction/extraction.comp.glsl")
    assert(!shader_code.is_empty(), "Shader code is empty")
    return shader_code

func _build_shader(shader_code: String) -> RID:
    print("Building extraction _shader...")
    var shader_source := RDShaderSource.new()
    shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    shader_source.source_compute = shader_code

    print("Compiling spirv...")
    var shader_spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(shader_source)
    if shader_spirv.compile_error_compute != "":
        push_error(shader_spirv.compile_error_compute)
        var split_error := shader_spirv.compile_error_compute.split("ERROR: ")
        var error_offset := split_error[1].split(":")[1]
        push_error(shader_code.split("\n")[int(error_offset) - 2])
        return RID()
    
    print("Creating _shader...")
    var new_shader := _rd.shader_create_from_spirv(shader_spirv)
    if not new_shader.is_valid():
        push_error("Shader is invalid")
        return RID()

    return new_shader

func _create_output_texture(width: int, height: int) -> void:
    _texture_format = RDTextureFormat.new()
    _texture_format.width = width
    _texture_format.height = height
    _texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    _texture_format.usage_bits = \
        RenderingDevice.TEXTURE_USAGE_INPUT_ATTACHMENT_BIT | \
        RenderingDevice.TEXTURE_USAGE_STORAGE_BIT  | \
        RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | \
        RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

    var new_texture := _rd.texture_create(_texture_format, RDTextureView.new())
    output_texture.texture_rd_rid = new_texture

    if _texture.is_valid():
        _rd.free_rid(_texture)
    _texture = new_texture
