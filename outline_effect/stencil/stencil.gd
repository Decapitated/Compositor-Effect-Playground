@tool
class_name StencilEffect extends CompositorEffect

var _rd: RenderingDevice = null

var _shader: RID
var _pipeline: RID

var _vertex_format : int
var _vertex_buffer : RID
var _vertex_array : RID

var _clear_colors := PackedColorArray([Color.BLACK])

var _framebuffer: RID
var _framebuffer_format: int

var _texture_format: RDTextureFormat = RDTextureFormat.new()
var _texture: RID
var output_texture: Texture2DRD = Texture2DRD.new()

var _cache_vertex_shader_code := ""
var _cache_fragment_shader_code := ""
var _cache_depth_texture: RID
var _cache_samples: int = 0

enum CallbackError {
    OK = 0,
    INVALID_RENDER_DATA,
    INVALID_DEPTH_TEXTURE,
    INVALID_FRAMEBUFFER,
    INVALID_PIPELINE,
}
var error: CallbackError = CallbackError.OK

func _init() -> void:
    effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT

    _rd = RenderingServer.get_rendering_device()
    
    #region Vertex
    var vertex_attribute = RDVertexAttribute.new()
    vertex_attribute.location = 0
    vertex_attribute.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
    vertex_attribute.stride = 4 * 3
    _vertex_format = _rd.vertex_format_create([vertex_attribute])

    var vertex_data = PackedVector3Array([
        Vector3(-1, -1, 0),
        Vector3(3, -1, 0),
        Vector3(-1, 3, 0),
    ])
    var vertex_bytes = vertex_data.to_byte_array()
    _vertex_buffer = _rd.vertex_buffer_create(vertex_bytes.size(), vertex_bytes)
    _vertex_array = _rd.vertex_array_create(3, _vertex_format, [_vertex_buffer])
    #endregion

func _notification(what):
    if what == NOTIFICATION_PREDELETE:
        if _vertex_array.is_valid():
            _rd.free_rid(_vertex_array)
        if _vertex_buffer.is_valid():
            _rd.free_rid(_vertex_buffer)

func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
    var shader_changed := _check_shader()

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
    if size.x == 0 and size.y == 0:
        return

    var samples := scene_buffers.get_texture_samples()

    var buffers_changed := false
    if !output_texture.texture_rd_rid.is_valid() || \
            _texture_format.width != size.x || _texture_format.height != size.y || \
            _cache_samples != samples:
        _create_output_texture(size.x, size.y, samples)
        buffers_changed = true
    

    var depth_texture: RID = scene_buffers.get_depth_layer(0, samples > 0)
    if !depth_texture.is_valid():
        if error != CallbackError.INVALID_DEPTH_TEXTURE:
            error = CallbackError.INVALID_DEPTH_TEXTURE
            push_error("Depth texture is invalid")
        return
    elif error == CallbackError.INVALID_DEPTH_TEXTURE:
        error = CallbackError.OK

    if depth_texture != _cache_depth_texture:
        _cache_depth_texture = depth_texture
        buffers_changed = true

    var framebuffer_format_changed := false
    if buffers_changed:
        framebuffer_format_changed = _build_framebuffer(samples)
    
    if !_framebuffer.is_valid():
        if error != CallbackError.INVALID_FRAMEBUFFER:
            error = CallbackError.INVALID_FRAMEBUFFER
            push_error("Framebuffer is invalid")
        return
    elif error == CallbackError.INVALID_FRAMEBUFFER:
        error = CallbackError.OK

    if shader_changed || framebuffer_format_changed:
        _build_pipeline()
    
    if !_pipeline.is_valid():
        if error != CallbackError.INVALID_PIPELINE:
            error = CallbackError.INVALID_PIPELINE
            push_error("Pipeline is invalid")
        return
    elif error == CallbackError.INVALID_PIPELINE:
        error = CallbackError.OK

    var draw_list := _rd.draw_list_begin(
        _framebuffer,
        RenderingDevice.DRAW_CLEAR_COLOR_0,
        _clear_colors,
        1.0, 0, Rect2(),
        RenderingDevice.OPAQUE_PASS
    )
    _rd.draw_list_bind_render_pipeline(draw_list, _pipeline)
    _rd.draw_list_bind_vertex_array(draw_list, _vertex_array)
    _rd.draw_list_draw(draw_list, false, 3)
    _rd.draw_list_end()

func _check_shader() -> bool:
    var vertex_shader_code := _get_vertex_shader_code()
    var fragment_shader_code := _get_fragment_shader_code()
    if vertex_shader_code != _cache_vertex_shader_code || fragment_shader_code != _cache_fragment_shader_code:
        _cache_vertex_shader_code = vertex_shader_code
        _cache_fragment_shader_code = fragment_shader_code
        var new_shader := _build_shader(vertex_shader_code, fragment_shader_code)
        if new_shader.is_valid():
            if _shader.is_valid():
                _rd.free_rid(_shader)
            _shader = new_shader
            return true
    return false

func _get_vertex_shader_code() -> String:
    var shader_code: String = FileAccess.get_file_as_string("res://outline_effect/stencil/stencil.vert.glsl")
    assert(!shader_code.is_empty(), "Shader code is empty")
    return shader_code

func _get_fragment_shader_code() -> String:
    var shader_code: String = FileAccess.get_file_as_string("res://outline_effect/stencil/stencil.frag.glsl")
    assert(!shader_code.is_empty(), "Shader code is empty")
    return shader_code

func _build_shader(vertex_shader_code: String, fragment_shader_code: String) -> RID:
    print("Building stencil _shader...")
    var shader_source := RDShaderSource.new()
    shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    shader_source.source_vertex = vertex_shader_code
    shader_source.source_fragment = fragment_shader_code

    print("Compiling spirv...")
    var shader_spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(shader_source)
    if shader_spirv.compile_error_vertex != "":
        push_error(shader_spirv.compile_error_vertex)
        var split_error := shader_spirv.compile_error_vertex.split("ERROR: ")
        var error_offset := split_error[1].split(":")[1]
        push_error(vertex_shader_code.split("\n")[int(error_offset) - 2])
        return RID()
    
    if shader_spirv.compile_error_fragment != "":
        push_error(shader_spirv.compile_error_fragment)
        var split_error := shader_spirv.compile_error_fragment.split("ERROR: ")
        var error_offset := split_error[1].split(":")[1]
        push_error(fragment_shader_code.split("\n")[int(error_offset) - 2])
        return RID()
    
    print("Creating _shader...")
    var new_shader := _rd.shader_create_from_spirv(shader_spirv)
    if not new_shader.is_valid():
        push_error("Shader is invalid")
        return RID()

    return new_shader

func _build_framebuffer(samples: int) -> bool:
    if !_cache_depth_texture.is_valid():
        return false
    
    var attachments: Array[RDAttachmentFormat] = []
    
    var depth_format := _rd.texture_get_format(_cache_depth_texture)

    var draw_attachment_format := RDAttachmentFormat.new()
    draw_attachment_format.format = _texture_format.format
    draw_attachment_format.usage_flags = _texture_format.usage_bits
    draw_attachment_format.samples = depth_format.samples
    attachments.push_back(draw_attachment_format)
    
    var depth_attachment_format := RDAttachmentFormat.new()
    depth_attachment_format.format = depth_format.format
    depth_attachment_format.usage_flags = depth_format.usage_bits
    depth_attachment_format.samples = depth_format.samples
    attachments.push_back(depth_attachment_format)
    
    var new_format := _rd.framebuffer_format_create(attachments)
    _framebuffer = _rd.framebuffer_create([_texture, _cache_depth_texture], new_format)

    var format_changed := new_format != _framebuffer_format
    _framebuffer_format = new_format

    return format_changed

func _build_pipeline() -> void:
    var blend_state := RDPipelineColorBlendState.new()
    var blend_attachment := RDPipelineColorBlendStateAttachment.new()
    blend_state.attachments.append(blend_attachment)

    var stencil_state := RDPipelineDepthStencilState.new()
    stencil_state.enable_stencil = true
    stencil_state.front_op_compare = RenderingDevice.COMPARE_OP_EQUAL
    stencil_state.front_op_compare_mask = 0xFF
    stencil_state.front_op_write_mask = 0
    stencil_state.front_op_reference = 1
    stencil_state.front_op_fail = RenderingDevice.STENCIL_OP_KEEP
    stencil_state.front_op_pass = RenderingDevice.STENCIL_OP_KEEP

    _pipeline = _rd.render_pipeline_create(
        _shader,
        _framebuffer_format,
        _vertex_format,
        RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
        RDPipelineRasterizationState.new(),
        RDPipelineMultisampleState.new(),
        stencil_state,
        blend_state
    )

func _create_output_texture(width: int, height: int, samples: int) -> void:
    _texture_format = RDTextureFormat.new()
    _texture_format.width = width
    _texture_format.height = height
    _texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    _texture_format.samples = samples as RenderingDevice.TextureSamples
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

func _get_msaa_samples_3d(mode: int) -> RenderingDevice.TextureSamples:
    match mode:
        1:
            return RenderingDevice.TEXTURE_SAMPLES_2
        2:
            return RenderingDevice.TEXTURE_SAMPLES_4
        3:
            return RenderingDevice.TEXTURE_SAMPLES_8
        _:
            return RenderingDevice.TEXTURE_SAMPLES_1
