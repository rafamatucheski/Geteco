extends SceneTree

func _initialize() -> void:
	var car = preload("res://scripts/Vehicle.gd").new()
	car.controlled = true
	car.external_input = true
	car.engine_disabled = true
	for throttle in [-1.0,1.0]:
		car.throttle_input = throttle
		car.brake_input = false
		car._drive_player(1.0)
		if car.speed != 0:
			push_error("Disabled mission engine moved under throttle: "+str(throttle))
			car.free()
			quit(1)
			return
	car.engine_disabled = false
	car.brake_input = false
	car._drive_player(1.0)
	var restored: bool = car.speed>0 and car.max_forward_speed==car.MAX_SPEED
	car.free()
	print("VEHICLE_ENGINE_LOCK ","PASS" if restored else "FAIL")
	quit(0 if restored else 1)
