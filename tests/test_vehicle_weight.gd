extends SceneTree
const HANDLING := preload("res://VehicleMotionSafety.gd")

func _initialize() -> void:
	var light = load("res://PlayerCar.gd").new()
	var heavy = load("res://PlayerCar.gd").new()
	light.vehicle_mass = 0.85
	heavy.vehicle_mass = 4.8
	light.velocity = Vector2(200, 0)
	heavy.velocity = light.velocity
	light._apply_steering_motion(1.0, 0.1)
	heavy._apply_steering_motion(1.0, 0.1)
	assert(heavy.rotation < light.rotation * 0.6, "Heavy yaw must build more slowly")
	assert(HANDLING.drive_mass_scale(4.8) < HANDLING.drive_mass_scale(0.85) * 0.6)
	assert(HANDLING.brake_mass_scale(4.8) < HANDLING.brake_mass_scale(0.85) * 0.65)
	assert(HANDLING.coast_mass_scale(4.8) < HANDLING.coast_mass_scale(0.85) * 0.4)
	assert(HANDLING.steering_rate(1.0, 1.0, 0.0, 3.0, 4.8, 0.1) == 0.0)
	assert(HANDLING.steering_rate(0.0, 1.0, -200.0, 3.0, 4.8, 0.1) < 0.0)
	for mass in [0.5, 1.0, 3.0, 4.8]:
		var a := 0.0
		var b := 0.0
		for i in 60: a = HANDLING.steering_rate(a, 1.0, 200.0, 3.0, mass, 1.0/60.0)
		for i in 120: b = HANDLING.steering_rate(b, 1.0, 200.0, 3.0, mass, 1.0/120.0)
		assert(absf(a-b) < 0.0001, "Handling must not depend on physics frequency")
		var incoming := Vector2(200, 100)
		assert(HANDLING.grip(incoming, 0, 0.8, 0.1, 1.0, true, mass).length() <= incoming.length())
	light.free()
	heavy.free()
	print("VEHICLE WEIGHT PASS")
	quit()
