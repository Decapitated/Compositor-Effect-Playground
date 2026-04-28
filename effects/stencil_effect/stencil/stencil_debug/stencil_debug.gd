@tool
class_name StencilDebug extends TextureRect

@export var debug_stencil: bool = false

var _stencil_effect: StencilEffect
var _cache_stencil_value: int = 0
var _cache_mouse_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	var effects := get_viewport().get_camera_3d().compositor.compositor_effects
	for effect in effects:
		if effect is StencilEffect:
			_stencil_effect = effect
			if debug_stencil:
				texture = _stencil_effect.output_texture
			break

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		if texture != null:
			texture = null

func _process(_delta: float) -> void:
	if debug_stencil && _stencil_effect:
		texture = _stencil_effect.output_texture
	elif texture != null:
		texture = null

func _gui_input(event: InputEvent) -> void:
	if _stencil_effect:
		if event is InputEventMouseMotion:
			_cache_mouse_position = event.position
			var stencil_image := _stencil_effect.output_texture.get_image()
			if stencil_image:
				_cache_stencil_value = int(stencil_image.get_pixelv(_cache_mouse_position).r)
