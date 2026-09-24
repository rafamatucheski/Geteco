extends Camera3D

var target: Node3D
var heading := 0.0
var target_size := 28.0
var focus := Vector3.ZERO
var initialized := false

func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = target_size
	near = 0.1
	far = 180.0
	current = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _process(delta: float) -> void:
	if not is_instance_valid(target): return
	var point := target.get_global_transform_interpolated().origin
	if target.has_method("camera_lookahead"): point += target.camera_lookahead()
	if not initialized:
		focus = point
		initialized = true
	focus = focus.lerp(point, 1.0 - exp(-9.0 * delta))
	size = lerpf(size, target_size, 1.0 - exp(-10.0 * delta))
	global_position = focus + Vector3(0, 28, 22).rotated(Vector3.UP, heading)
	look_at(focus)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: target_size = clampf(target_size - 2, 14, 52)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: target_size = clampf(target_size + 2, 14, 52)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q: heading += PI / 4
		if event.physical_keycode == KEY_E: heading -= PI / 4
