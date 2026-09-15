extends SceneTree

## Regression for a real bug found reproducing the 2026-09-06 gameplay
## recording ("long strip coming out of the car" around 2:32-2:36):
## CobraBossReward.gd reassigns reward_car.global_transform to teleport the
## boss's car into its garage bay, then immediately calls repair_vehicle()
## (see world/harbor/campaign/CobraBossReward.gd, both the
## restore-on-load and claim-in-garage paths). TrafficVehicle.skid_line is
## top_level (its points are plain world-space coordinates), and
## repair_vehicle() reset every other damage-visual property (deformation,
## smoke, flame, rim sparks, flat tires) but never touched skid_line. Any
## skid/bloody-tire trail the car had accumulated before the teleport stayed
## in the Line2D; the next point added after the move drew one long straight
## segment spanning the entire teleport distance -- a stray strip trailing
## out of the car, not a rendering glitch in the skid system itself.
##
## This does not disable or weaken the skid/bloody-tire system (the task
## explicitly rules that out as a fix) -- it only proves repair_vehicle() now
## clears stale trail history instead of dragging it across a teleport.

const VEHICLE_SCENE := preload("res://cars/traffic/TrafficVehicle.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []

	var car := VEHICLE_SCENE.instantiate()
	root.add_child(car)
	car.global_position = Vector2(500.0, 500.0)
	await process_frame

	# Production allocates this lazily, at the first actual skid.
	var skid_line: Line2D = car._ensure_skid_line()
	if skid_line == null:
		failures.append("TrafficVehicle has no skid_line -- fixture changed?")
		_finish(car, failures)
		return
	if not skid_line.top_level:
		failures.append("skid_line is expected to be top_level (world-space points) -- test assumption changed")

	# Simulate a real skid/blood trail accumulated at the car's old location.
	for i in 5:
		skid_line.add_point(Vector2(500.0 + i * 10.0, 500.0))
	skid_line.default_color = Color(0.72, 0.05, 0.05, 0.85)
	car.set("bloody_tires_timer", 4.0)
	car.set("is_skidding", true)
	if skid_line.get_point_count() < 2:
		failures.append("Setup failed to seed a real trail on skid_line")

	# CobraBossReward's exact sequence: teleport the car, then repair it.
	var far_away := Vector2(500.0, 500.0) + Vector2(4000.0, 0.0)
	car.global_transform = Transform2D(0.0, far_away)
	car.call("repair_vehicle")
	await process_frame

	print("AFTER_REPAIR point_count=%d bloody_timer=%s is_skidding=%s" % [
		skid_line.get_point_count(), str(car.get("bloody_tires_timer")), str(car.get("is_skidding"))
	])
	if skid_line.get_point_count() != 0:
		var oldest: Vector2 = skid_line.get_point_position(0)
		failures.append(
			"repair_vehicle() left %d stale skid_line point(s) after a teleport -- oldest point %s is %.0fpx from the car's new position %s, exactly the stray-strip bug" % [
				skid_line.get_point_count(), str(oldest), oldest.distance_to(far_away), str(far_away)
			]
		)
	if float(car.get("bloody_tires_timer")) != 0.0:
		failures.append("repair_vehicle() should also clear bloody_tires_timer, found %s" % str(car.get("bloody_tires_timer")))

	_finish(car, failures)

func _finish(car: Node, failures: Array[String]) -> void:
	car.queue_free()
	await process_frame
	if failures.is_empty():
		print("TRAFFIC_VEHICLE_REPAIR_CLEARS_SKID: PASS")
		quit(0)
	else:
		for f in failures:
			printerr("  - %s" % f)
		print("TRAFFIC_VEHICLE_REPAIR_CLEARS_SKID: FAIL (%d)" % failures.size())
		quit(1)
