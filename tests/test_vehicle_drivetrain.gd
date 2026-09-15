extends SceneTree
const DRIVE := preload("res://VehicleDrivetrain.gd")

func _initialize() -> void:
	for spec in VehicleCatalog.get_all_specs():
		assert(spec.get("drivetrain", "") in ["fwd", "rwd", "4x4", "awd", "motorcycle_rear"], str(spec.id))
	var front := DRIVE.new()
	var rear := DRIVE.new()
	var utility := DRIVE.new()
	var awd := DRIVE.new()
	front.update("fwd", 180, 1, 1, 0.7)
	rear.update("rwd", 180, 1, 1, 0.7)
	utility.update("4x4", 180, 1, 1, 0.7)
	awd.update("awd", 180, 1, 1, 0.7)
	assert(front.steer_scale < awd.steer_scale, "Front drive pushes wide under power")
	assert(rear.steer_scale > awd.steer_scale and rear.drift_bias > front.drift_bias, "Rear drive loosens the rear axle")
	assert(utility.force_scale > front.force_scale and awd.force_scale > rear.force_scale, "Four driven wheels retain wet traction")
	assert(utility.steer_scale < awd.steer_scale, "Utility 4x4 turns more conservatively than road AWD")
	for kind in ["fwd", "rwd", "4x4", "awd", "motorcycle_rear"]:
		for speed in [-200.0, 0.0, 200.0]:
			for pedal in [-1.0, 0.0, 1.0]:
				rear.update(kind, speed, pedal, 1, 1)
				assert(rear.force_scale > 0 and rear.force_scale <= 1, "Traction cannot add engine energy")
	rear.update("rwd", 200, -1, 1, 1)
	assert(rear.drift_bias == 0 and rear.steer_scale == 1, "Service braking must not trigger power oversteer")
	var car = load("res://PlayerCar.gd").new()
	car.velocity = Vector2(200,0)
	car._drivetrain.update("fwd", 200, 1, 1, 0)
	car._apply_steering_motion(1, 0.1)
	var front_yaw: float = car.rotation
	car.rotation = 0
	car._handling_yaw_rate = 0
	car._drivetrain.update("rwd", 200, 1, 1, 0)
	car._apply_steering_motion(1, 0.1)
	assert(car.rotation > front_yaw, "Player controller must use axle handling")
	car.free()
	print("VEHICLE DRIVETRAIN PASS")
	quit()
