extends MeshInstance3D

@export_range(1.0, 10.0, 0.1, "or_greater") var duration := 5.0

func _process(delta: float) -> void:
	rotation += Vector3(1.0, 0.25, 0.5) * delta;
