extends SceneTree

const DOOR := preload("res://cars/VehicleDoorVisual.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var door = DOOR.new()
	door.configure(Vector2(13, -15), 32)
	root.add_child(door)
	await process_frame
	_check(door.get_node_or_null("DoorContactShadow") == null, "door has no duplicated offset panel")
	_check(door.get_node_or_null("PaintedDoorPanel") is Polygon2D, "door keeps one painted body panel")
	for side in [-1.0, 1.0]:
		door.play(Color("#3c6382"), side, 0.0)
		await create_timer(0.34).timeout
		_check(door.visible and signf(door.rotation) == -side, "door opens outward on side %s" % side)
		await create_timer(0.30).timeout
		_check(not door.visible and is_zero_approx(door.rotation), "door closes on side %s" % side)
	print("VEHICLE_DOOR_VISUAL failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)
