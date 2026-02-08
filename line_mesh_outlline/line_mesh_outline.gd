extends Node3D

@onready var _target: StaticBody3D = %Target
@onready var _line_mesh_instance: MeshInstance3D = %LineMesh

var _mesh: ImmediateMesh = ImmediateMesh.new()
var _points: Array[Vector3] = []

func _ready() -> void:
    _line_mesh_instance.mesh = _mesh
    _target.input_event.connect(_on_target_input_event)

func _on_target_input_event(_camera: Node, event: InputEvent, pos: Vector3, normal: Vector3, _shape_idx: int) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _points.append(pos + normal * 0.01)
        _build_mesh()

func _build_mesh() -> void:
    if _points.size() < 2:
        return
    _mesh.clear_surfaces()
    _mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
    for point in _points:
        _mesh.surface_add_vertex(point)
    _mesh.surface_end()