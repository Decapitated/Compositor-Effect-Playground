@tool
class_name ExtractionCompositorEffect extends CompositorEffect

const ExtractionShaderPath: String = "res://sophisticated_outline/outline/extraction.comp.glsl"

@export var stencil_effect: StencilCompositorEffect
@export_range(1.0, 10.0, 1.0, "or_greater") var scale: float = 1.0
@export_range(0.0, 10.0, 0.001, "or_greater") var depth_threshold: float = 0.2
@export_range(0.0, 10.0, 0.001, "or_greater") var normal_threshold: float = 0.2
@export_range(0.0, 10.0, 0.001, "or_greater") var depth_normal_threshold: float = 0.1
@export_range(0.0, 10.0, 0.001, "or_greater") var depth_normal_threshold_scale: float = 0.1

var rd: RenderingDevice
var shader: RID
var pipeline: RID
var nearest_sampler: RID

var texture: RID
var texture_format := RDTextureFormat.new()
var clear_colors := PackedColorArray([Color.BLACK])

@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "Texture2DRD", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) var output_texture := Texture2DRD.new()

var mutex := Mutex.new()

var _last_shader_code: String = ""

func _init() -> void:
    effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    rd = RenderingServer.get_rendering_device()

# System notifications, we want to react on the notification that
# alerts us we are about to be destroyed.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if shader.is_valid():
            # Freeing our shader will also free any dependents such as the pipeline!
            RenderingServer.free_rid(shader)
        if nearest_sampler.is_valid():
            rd.free_rid(nearest_sampler)
        if pipeline.is_valid():
            rd.free_rid(pipeline)
        if texture.is_valid():
            rd.free_rid(texture)

## Create a new color texture to use as the output for our render pipeline.
## Note: this texture must be the same size as the depth texture, so we create
## it on demand.
func _build_texture(width: int, height: int):
    # create our output texture
    texture_format = RDTextureFormat.new()
    texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
    texture_format.width = width
    texture_format.height = height
    texture_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
    texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
    var new_texture = rd.texture_create(texture_format, RDTextureView.new())
    assert(new_texture.is_valid())

    # we change this before freeing the old texture to prevent visual flicker
    # in a TextureRect using the output texture while resizing.
    output_texture.texture_rd_rid = new_texture

    # free the old texture if there was one
    if texture.is_valid():
        rd.free_rid(texture)
        texture = RID()

    # save the new texture rid
    texture = new_texture

#region Code in this region runs on the rendering thread.
# Check if our shader has changed and needs to be recompiled.
func _check_shader() -> bool:
    if not rd:
        return false

    var new_shader_code: String = FileAccess.get_file_as_string(ExtractionShaderPath)

    # We don't have a (new) shader?
    assert(!new_shader_code.is_empty(), "Shader code is empty")

    _last_shader_code = new_shader_code
    # Out with the old. (Free RIDs if they are valid.)
    if shader.is_valid():
        rd.free_rid(shader)
        shader = RID()
        pipeline = RID()

    # In with the new.
    var shader_source := RDShaderSource.new()
    shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
    shader_source.source_compute = new_shader_code
    var shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_source)

    if shader_spirv.compile_error_compute != "" and _last_shader_code != new_shader_code:
        push_error(shader_spirv.compile_error_compute)
        # push_error("In: " + new_shader_code)
        return false

    shader = rd.shader_create_from_spirv(shader_spirv)
    if not shader.is_valid():
        return false

    pipeline = rd.compute_pipeline_create(shader)

    return pipeline.is_valid()

# Called by the rendering thread every frame.
func _render_callback(_p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
    if rd and _check_shader():
        # Get our render scene buffers object, this gives us access to our render buffers.
        # Note that implementation differs per renderer hence the need for the cast.
        var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
        var scene_data: RenderSceneData = p_render_data.get_render_scene_data()
        if render_scene_buffers and scene_data:
            # Get our render size, this is the 3D render resolution!
            var size: Vector2i = render_scene_buffers.get_internal_size()
            if size.x == 0 and size.y == 0:
                return

            # Build the output texture the same size as the render resolution.
            # Note: the output texture must be the same size as the render resolution
            #       because the texture and depth texture must be the same resolution
            #       to create a framebuffer later.  If they are not the same size, we
            #       get an error in _build_framebuffer()
            if not texture.is_valid() or \
                    texture_format.width != size.x or \
                    texture_format.height != size.y:
                _build_texture(size.x, size.y)

            # We can use a compute shader here.
            @warning_ignore("integer_division")
            var x_groups: int = (size.x - 1) / 8 + 1
            @warning_ignore("integer_division")
            var y_groups: int = (size.y - 1) / 8 + 1
            var z_groups: int = 1

            # Create push constant.
            # Must be aligned to 16 bytes and be in the same order as defined in the shader.
            var push_constant := PackedFloat32Array([
                    size.x,
                    size.y,
                    0.0,
                    0.0,
                    scale,
                    depth_threshold,
                    normal_threshold,
                    depth_normal_threshold,
                    depth_normal_threshold_scale,
                    0.0, 0.0, 0.0 # Padding
                ])

            # Make sure we have a sampler.
            if not nearest_sampler.is_valid():
                var sampler_state: RDSamplerState = RDSamplerState.new()
                sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
                sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
                nearest_sampler = rd.sampler_create(sampler_state)

            # Loop through views just in case we're doing stereo rendering. No extra cost if this is mono.
            var view_count: int = render_scene_buffers.get_view_count()
            for view in view_count:
                # Get the RID for our scene data buffer.
                var scene_data_buffers: RID = scene_data.get_uniform_buffer()

                # Get the RID for our color image, we will be reading from and writing to it.
                var color_image: RID = render_scene_buffers.get_color_layer(view)

                # Get the RID for our depth image, we will be reading from it.
                var depth_image: RID = render_scene_buffers.get_depth_layer(view)

                # render_buffers
                var normal_image: RID = render_scene_buffers.get_texture("forward_clustered", "normal_roughness")

                var stencil_image: RID = stencil_effect.output_texture.texture_rd_rid

                # Create a uniform set, this will be cached, the cache will be cleared if our viewports configuration is changed.
                # Scene Data
                var scene_data_uniform := RDUniform.new()
                scene_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
                scene_data_uniform.binding = 0
                scene_data_uniform.add_id(scene_data_buffers)
                # Color Image
                var color_uniform := RDUniform.new()
                color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
                color_uniform.binding = 1
                color_uniform.add_id(color_image)
                # Depth Image
                var depth_uniform := RDUniform.new()
                depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
                depth_uniform.binding = 2
                depth_uniform.add_id(nearest_sampler)
                depth_uniform.add_id(depth_image)
                # Normal Image
                var normal_uniform := RDUniform.new()
                normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
                normal_uniform.binding = 3
                normal_uniform.add_id(normal_image)
                # Stencil Image
                var stencil_uniform := RDUniform.new()
                stencil_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
                stencil_uniform.binding = 4
                stencil_uniform.add_id(stencil_image)
                # Output Image
                var output_uniform := RDUniform.new()
                output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
                output_uniform.binding = 5
                output_uniform.add_id(texture)
                var uniform_set_rid: RID = UniformSetCacheRD.get_cache(shader, 0, [scene_data_uniform, color_uniform, depth_uniform, normal_uniform, stencil_uniform, output_uniform])

                # Set our view.
                push_constant[2] = view

                # Run our compute shader.
                var compute_list: int = rd.compute_list_begin()
                rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
                rd.compute_list_bind_uniform_set(compute_list, uniform_set_rid, 0)
                var bytes := push_constant.to_byte_array()
                rd.compute_list_set_push_constant(compute_list, bytes, bytes.size())
                rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
                rd.compute_list_end()
#endregion