extends SceneTree
const STOCK = preload("res://gameplay/v1_handling/V1Handling.gd")
const POWERTRAIN = preload("res://gameplay/desert_cars/DesertHandling.gd")
const EXPECTED_REVERSE_MPS := 20.0 / 3.6
class Car extends CharacterBody3D:
	var horizontal_velocity := Vector3.ZERO
	var speed := 0.0
	func can_rotate(_yaw: float) -> bool: return false
func _initialize() -> void:
	var ids: Array = preload("res://runtime/FleetCatalog.gd").all().keys()
	ids.append_array(preload("res://gameplay/desert_cars/DesertCarCatalog.gd").IDS)
	ids.append_array(["army_tank", "biarticulated_510", "armored_truck", "jessica_jetta_gli", "digo_amarok_2014", "digo_gol_1993"])
	var failures := 0
	for id in ids:
		var spec: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(id)
		var expected_reverse := minf(EXPECTED_REVERSE_MPS, float(spec.get("max_speed", 600.0)) * 0.8 / STOCK.PX)
		for controller in [STOCK.new(), POWERTRAIN.new()]:
			controller.configure(spec)
			var car := Car.new()
			for frame in 3600: controller.step(car, 1.0/60.0, -1.0, 0.0, false, 0.0)
			if absf(car.speed + expected_reverse) > 0.001:
				push_error("Reverse limit failed: %s speed=%f" % [id, car.speed])
				failures += 1
			# An excessive restored reverse speed is bounded on the next step.
			car.horizontal_velocity = Vector3(0, 0, 40)
			controller.step(car, 1.0/60.0, -1.0, 0.0, false, 1.0)
			if car.speed < -EXPECTED_REVERSE_MPS - 0.001: failures += 1
			car.free()
	var vehicle = preload("res://scripts/Vehicle.gd").new()
	vehicle.controlled = true
	vehicle.external_input = true
	vehicle.throttle_input = -1.0
	for frame in 1200: vehicle._drive_player(1.0/60.0)
	if absf(vehicle.speed + EXPECTED_REVERSE_MPS) > 0.001: failures += 1
	vehicle.throttle_input = 1.0
	for frame in 1200: vehicle._drive_player(1.0/60.0)
	if vehicle.speed <= 3.0: failures += 1
	vehicle.free()
	print("REVERSE_LIMIT vehicles=", ids.size(), " controllers=2 simple_control=true failures=", failures)
	quit(1 if failures else 0)
