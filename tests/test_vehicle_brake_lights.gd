extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var lights := preload("res://cars/VehicleBrakeLights.gd").new()
	root.add_child(lights)
	lights.configure(80.0, 40.0)
	_expect(is_equal_approx(lights.rear_x, -39.2), "fallback lamps must sit at the rear edge")
	_expect(is_equal_approx(lights.lateral_offset, 10.8), "lamp spacing must follow vehicle width")
	_expect(not lights.is_processing() and not lights.is_physics_processing(), "ordinary vehicles must not gain a per-frame callback")

	lights.observe_speed(120.0, 0.1)
	lights.observe_speed(90.0, 0.1)
	_expect(lights.is_braking and lights.visible, "deceleration must switch brake lights on")
	lights.observe_speed(90.0, 0.2)
	_expect(not lights.is_braking and not lights.visible, "steady speed must release brake lights after the short hold")

	lights.observe_speed(40.0, 0.1, true)
	_expect(lights.is_braking, "explicit service or hand brake must switch the lights on")
	lights.set_lamp_damage(true, false)
	_expect(not lights.left_lamp_visible and lights.right_lamp_visible and lights.visible, "a broken lens must disable only its own light")
	lights.set_lamp_damage(true, true)
	_expect(not lights.visible, "two broken rear lenses must not emit brake light")

	lights.set_lamp_damage(false, false)
	var authored_positions := PackedVector2Array([Vector2(-41.0, -11.0), Vector2(-41.0, 11.0)])
	lights.set_lamp_positions(authored_positions)
	_expect(lights._lamp_positions == authored_positions, "authored 3D lens positions must replace proportional fallback anchors")
	lights.configure(52.0, 14.0, true)
	_expect(lights.motorcycle and is_zero_approx(lights.lateral_offset), "motorcycles must use one centered rear lamp")

	if failures.is_empty():
		print("VEHICLE_BRAKE_LIGHTS_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("VEHICLE_BRAKE_LIGHTS_TEST: FAIL count=%d" % failures.size())
		quit(1)
