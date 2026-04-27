@tool
class_name PaniniEffect extends CompositorEffect

const SHADER_UID_PATH := "uid://cyq8de800ya26"

@export_range(0.0, 1.0, 0.001, "or_greater") var curvature: float = 1.0
@export_range(0.0, 1.0, 0.001, "or_greater") var crop: float = 1.0
@export_range(0.0, 1.0, 0.001, "or_greater") var squash: float = 1.0

var _rd: RenderingDevice = null

var _shader: RID
var _pipeline: RID
var _linear_sampler: RID

var _texture_format: RDTextureFormat = RDTextureFormat.new()
var _texture: RID
var output_texture: Texture2DRD = Texture2DRD.new()

var _shader_uid: int = -1

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

    _shader_uid = ResourceLoader.get_resource_uid(SHADER_UID_PATH)
    _check_shader()
    if Engine.is_editor_hint():
        EditorInterface.get_resource_filesystem().resources_reimported.connect(_on_resources_reimported)

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if _shader.is_valid():
            _rd.free_rid(_shader)
        if _linear_sampler.is_valid():
            _rd.free_rid(_linear_sampler)
        if _texture.is_valid():
            _rd.free_rid(_texture)

func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
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

    var push_constant := PackedVector4Array([
        Vector4(size.x, size.y, # Raster Size
                0.0,            # View
                0.0),           # Pass
        Vector4(curvature, crop, squash, 0.0)
    ])
    var scene_data_uniform_buffer: RID = scene_data.get_uniform_buffer()
    # Run compute for each view.    
    var view_count: int = scene_buffers.get_view_count()
    for view in view_count:
        # Set view.
        push_constant[0].z = view

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
        # Output Image
        var output_uniform := RDUniform.new()
        output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        output_uniform.binding = 2
        output_uniform.add_id(_texture)
        #endregion

        var uniform_set_0: RID = UniformSetCacheRD.get_cache(_shader, 0, [scene_data_uniform, color_uniform, output_uniform])
        
        # Pass 0
        _run_compute(uniform_set_0, push_constant, x_groups, y_groups, z_groups)

        # Pass 1
        push_constant[0].w = 1.0
        _run_compute(uniform_set_0, push_constant, x_groups, y_groups, z_groups)

#region Shader
func _on_resources_reimported(resource_paths: PackedStringArray) -> void:
    for path in resource_paths:
        if ResourceLoader.get_resource_uid(path) == _shader_uid:
            _check_shader()
            break

func _check_shader() -> void:
    var new_shader := _build_shader()
    if new_shader.is_valid():
        if _shader.is_valid():
            _rd.free_rid(_shader)
        _shader = new_shader
        _pipeline = _rd.compute_pipeline_create(_shader)

func _build_shader() -> RID:
    print("Building panini shader...")
    var shader_file: RDShaderFile = load(SHADER_UID_PATH)
    var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
    if shader_spirv.compile_error_compute != "":
        push_error(shader_spirv.compile_error_compute)
        return RID()
    
    var new_shader := _rd.shader_create_from_spirv(shader_spirv)
    if not new_shader.is_valid():
        push_error("Shader is invalid")
        return RID()

    return new_shader
#endregion

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

func _run_compute(uniform_set_0: RID, push_constant: PackedVector4Array, x_groups: int, y_groups: int, z_groups: int) -> void:
    var compute_list: int = _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
    _rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
    var push_constant_bytes := push_constant.to_byte_array()
    _rd.compute_list_set_push_constant(compute_list, push_constant_bytes, push_constant_bytes.size())
    _rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
    _rd.compute_list_end()
