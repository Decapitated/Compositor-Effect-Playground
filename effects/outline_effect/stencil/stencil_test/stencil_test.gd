@tool
class_name StencilTest extends Control

@export var debug_stencil: bool = false:
	set(value):
		debug_stencil = value
		queue_redraw()

var _stencil_effect: StencilEffect
var _cache_stencil_value: float = 0.0
var _cache_mouse_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	var effects := get_viewport().get_camera_3d().compositor.compositor_effects
	for effect in effects:
		if effect is StencilEffect:
			_stencil_effect = effect
			break
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if _stencil_effect:
		if event is InputEventMouseMotion:
			_cache_mouse_position = event.position
			var stencil_image := _stencil_effect.output_texture.get_image()
			if stencil_image:
				_cache_stencil_value = stencil_image.get_pixelv(_cache_mouse_position).r

func _draw() -> void:
	if debug_stencil:
		draw_texture(_stencil_effect.output_texture, Vector2.ZERO)
		queue_redraw()
