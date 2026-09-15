extends SceneTree

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func block(at: Vector2, size: Vector2, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = layer
	var hull := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	hull.shape = rect
	body.add_child(hull)
	current_scene.add_child(body)
	return body

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var ambulance := preload("res://EmergencyVehicle.gd").new()
	ambulance.type = 1
	world.add_child(ambulance)
	ambulance.set_physics_process(false)
	ambulance.set_process(false)
	var obstacle := block(Vector2(90, 0), Vector2(40, 26), 2)
	await physics_frame
	await physics_frame
	var router := preload("res://world/shared/roads/EmergencyLaneRouter.gd").new()
	check(not router._clear_motion(ambulance, Vector2(140, 0)), "A parked vehicle blocks the ambulance's hull sweep")
	var detour := router._steer_clear(ambulance, Vector2(70, 0))
	check(absf(detour.y) > 20 and router._clear_motion(ambulance, detour), "Ambulance chooses a physically clear detour around the parked car")
	check(ambulance._forward_clearance() < 50, "Ambulance detects bumper clearance before contact")
	# A new obstacle invalidates a previously clear maneuver.
	var wall := block(detour, Vector2(30, 30), 1)
	await physics_frame
	await physics_frame
	check(router._steer_clear(ambulance, Vector2(70, 0)) != detour, "A stale detour is rechecked when traffic changes")
	wall.queue_free()
	await physics_frame
	var response_lane := Path2D.new()
	response_lane.curve = Curve2D.new()
	response_lane.curve.add_point(Vector2.ZERO)
	response_lane.curve.add_point(Vector2(1500, 0))
	world.add_child(response_lane)
	var patient := Node2D.new()
	patient.position = Vector2(1300, 0)
	world.add_child(patient)
	ambulance.target = patient
	ambulance._lane_router.linked_lane = response_lane
	ambulance.set_meta("medical_sequence", null)
	var contacts := 0
	for frame in 420:
		await physics_frame
		ambulance._physics_process(1.0 / 60.0)
		contacts += ambulance.get_slide_collision_count()
		if frame % 120 == 0: print("MANEUVER ", ambulance.global_position, " speed=", ambulance.current_speed, " waypoint=", ambulance._lane_router.avoidance_target, " returning=", ambulance.is_returning_to_base)
	check(ambulance.global_position.x > 250, "Moving ambulance passes the stopped car and continues toward its destination")
	check(contacts == 0, "The avoidance maneuver does not hit the stopped car")
	obstacle.queue_free()
	ambulance.queue_free()
	await physics_frame
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2(0, 300))
	path.curve.add_point(Vector2(700, 300))
	world.add_child(path)
	var cab := ModernTrafficFactory.spawn_moving_vehicle(path, "RecoveryTaxi", "taxi_yellow", .3, 90, 0)
	check(cab != null, "Taxi recovery fixture spawns")
	if cab:
		cab.set_process(false)
		cab.set_physics_process(false)
		var follow := cab.get_parent() as PathFollow2D
		var start := follow.progress
		# A small roadside encroachment clips one side of the hull, leaving
		# enough pavement for the bounded lateral correction.
		var half: Vector2 = cab.collision.shape.size * .5
		block(cab.global_position + Vector2(half.x + 5, half.y + 1), Vector2(8, 8), 1)
		for frame in 360:
			await physics_frame
			cab.advance_on_lane(1.0 / 60.0)
		check(follow.progress > start + 100, "Taxi clears a roadside hull obstruction and resumes its lane")
	print("OBSTACLE_RECOVERY failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
