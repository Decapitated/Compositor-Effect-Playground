extends Label

func _process(delta: float) -> void:
	var stencil_debug: StencilDebug = get_parent()
	position = stencil_debug._cache_mouse_position
	text = "%s" % stencil_debug._cache_stencil_value
