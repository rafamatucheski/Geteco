extends SceneTree

## Physical bridge crossing, driven for real (car.move_and_collide against the
## actual road/bridge geometry) in both directions. Updated to check the
## current streaming-region contract (world/harbor/ContinuousWorld.gd):
## since the port<->mountain refactor, the two regions coexist as siblings
## under the same running HarborGame scene — current_scene never changes —
## so success is measured via ContinuousWorld.current_region instead of a
## scene swap that no longer happens. The physical driving/collision/vehicle
## identity checks are unchanged.

var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()

## Polls `condition` until true or `timeout_seconds` of real time elapses.
## Returns true/false and appends a specific, actionable message to
## `failures` on timeout instead of a bare/ambiguous failure.
func _wait_until(condition: Callable, timeout_seconds: float, timeout_message: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			failures.append("%s (timeout after %.0fs)" % [timeout_message, timeout_seconds])
			return false
		await process_frame
	return true

func _run() -> void:
	# Generous watchdog: ContinuousWorld's streamed mountain-region prep alone
	# can take ~70-90s+ real time without GPU acceleration (see the 150s wait
	# below); 90s was too tight and could fire before the region ever finished
	# preparing, misreporting a real timeout as a hang.
	create_timer(240).timeout.connect(func(): quit(2))
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 12: await physics_frame
	var harbor := current_scene
	var stream := harbor.get_node("ContinuousWorld")
	for vehicle in get_nodes_in_group("modern_traffic"):
		vehicle.collision_layer = 0
		vehicle.set_physics_process(false)
	var car := preload("res://world/mountain_pass/MountainSUV.gd").new()
	car.position = Vector2(6120,-4100)
	harbor.add_child(car)
	car.enter_vehicle(harbor.get_node("Player"))
	car.set_physics_process(false)
	var points: PackedVector2Array = preload("res://world/harbor/HarborMountainConnector.gd").road_definitions()[0].points
	for destination in points:
		while car.global_position.distance_to(destination)>4 and current_scene==harbor:
			var direction: Vector2 = car.global_position.direction_to(destination)
			car.rotation = direction.angle()
			car.velocity = direction*100
			var collision := car.move_and_collide(direction*minf(14,car.global_position.distance_to(destination)))
			if collision:
				failures.append("Road blocked at %s by %s" %[car.global_position,collision.get_collider().get_path()])
				break
			await physics_frame
		if not failures.is_empty() or current_scene!=harbor: break
	for i in 15: await physics_frame
	# ContinuousWorld's own streamed region prep (interiors + expedition +
	# settlement + traffic, budgeted per-frame) can take a long time on a
	# machine without GPU acceleration (observed ~74s in a clean run on one
	# headless test machine) — wait for the real region flag with a generous,
	# explicit timeout instead of assuming a fixed frame count is enough.
	var region_ready := await _wait_until(
		func(): return current_scene == harbor and String(stream.current_region) == "mountain",
		150.0, "Physical bridge sensor did not transfer to Mountain region (current_region=%s)" % [String(stream.get("current_region"))]
	)
	if root.get_node("RegionTravel").controlled_car()!=car: failures.append("Driver lost the car at the physical crossing")
	if region_ready and failures.is_empty():
		var mountain: Node2D = stream.mountain
		for vehicle in get_nodes_in_group("modern_traffic"):
			if vehicle == car: continue
			vehicle.collision_layer = 0
			vehicle.set_physics_process(false)
		root.get_node("RegionTravel").cooldown = 0
		while String(stream.current_region) == "mountain" and car.global_position.x>2920:
			car.rotation = PI
			car.velocity = Vector2(-100,0)
			var return_collision := car.move_and_collide(Vector2(-12,0))
			if return_collision:
				failures.append("Mountain return blocked by "+str(return_collision.get_collider().get_path()))
				break
			await physics_frame
		for i in 15: await physics_frame
		var returned_to_harbor := await _wait_until(
			func(): return String(stream.get("current_region")) == "harbor",
			10.0, "Physical return sensor did not return to Harbor region (current_region=%s)" % [String(stream.get("current_region"))]
		)
		if returned_to_harbor:
			for vehicle in get_nodes_in_group("modern_traffic"):
				if vehicle == car: continue
				vehicle.collision_layer = 0
				vehicle.set_physics_process(false)
			var inbound: PackedVector2Array = preload("res://world/harbor/HarborMountainConnector.gd").road_definitions()[1].points
			inbound.remove_at(0)
			inbound.append(Vector2(5880,-4000))
			for target in inbound:
				while car.global_position.distance_to(target)>4:
					var direction: Vector2 = car.global_position.direction_to(target)
					car.rotation = direction.angle()
					car.velocity = direction*100
					var collision := car.move_and_collide(direction*minf(14,car.global_position.distance_to(target)))
					if collision:
						failures.append("Inbound bridge blocked by "+str(collision.get_collider().get_path()))
						break
					await physics_frame
				if not failures.is_empty(): break
	print("HARBOR MOUNTAIN DRIVE: ", failures)
	current_scene.queue_free()
	for i in 4: await process_frame
	quit(0 if failures.is_empty() else 1)
