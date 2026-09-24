extends "res://scripts/Vehicle.gd"
## Original native M8 geometry with inherited swept driving and full hull.
var model: Node3D
var _last_distance := 0.0
func _ready() -> void:
	super._ready()
	remove_from_group("drivable")
	visual.queue_free()
	wheels.clear()
	model = preload("res://assets/gameplay/MaciotaM8SedanModel.gd").new()
	add_child(model)
	visual = model
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var relative: Transform3D = model.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = relative * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	shape.shape = BoxShape3D.new()
	shape.shape.size = bounds.size
	shape.position = bounds.get_center()
	half_width = maxf(absf(bounds.position.x), absf(bounds.end.x))
	half_length = maxf(absf(bounds.position.z), absf(bounds.end.z))
	rotation_shape.size = bounds.size
	sensor_shape.size = Vector3(bounds.size.x + .07, 1.2, 1)
	external_input = true
	max_forward_speed = 4

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	model.roll(distance_travelled - _last_distance)
	model.steer(steering)
	_last_distance = distance_travelled

func door_point(side: int) -> Vector3:
	return to_global(Vector3(side * (half_width + .62), .04, -.2))

func show_occupants(value: bool) -> void:
	for person in model.occupants: person.visible = value
