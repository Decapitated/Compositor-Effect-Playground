@tool
class_name StencilDataMaterial extends ShaderMaterial

@export_range(0, 63, 1) var id: int = 0:
    set(value):
        id = value
        _update_shader()
@export var highlighted: bool = false:
    set(value):
        highlighted = value
        _update_shader()
@export var selected: bool = false:
    set(value):
        selected = value
        _update_shader()

func _update_shader() -> void:
    if shader == null:
        shader = Shader.new()
    shader.code = _shader_code()

func _shader_code() -> String:
    var data: int = id
    data += int(highlighted) << 6
    data += int(selected) << 7
    return \
"""shader_type spatial;
stencil_mode write, %d;
render_mode unshaded;

void fragment() {
    ALPHA = 0.0;
}""" % data
