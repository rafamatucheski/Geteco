extends SceneTree

## Run normally to test the scene defaults. Set TEST_GUARD_RAILS=true/false
## before launching Godot to compare both physical configurations explicitly.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := (load("res://legacy/Main.tscn") as PackedScene).instantiate()
	var graph := world.get_node("DistrictOneComplete/UnifiedRoadNetwork")
	var rail_mode := OS.get_environment("TEST_GUARD_RAILS")
	if rail_mode in ["true", "false"]:
		graph.set("build_guard_rails", rail_mode == "true")
	root.add_child(world)
	current_scene = world
	for frame in 12:
		await process_frame
	var district := world.get_node("DistrictOneComplete") as Node2D
	var target := world.get_node("PlayerCar") as CharacterBody2D
	target.global_position = district.to_global(Vector2(1480, 3500))
	target.velocity = Vector2.ZERO
	var wanted := root.get_node("WantedManager")
	wanted.set("current_stars", 3)
	wanted.set("police_spawn_timer", 999.0)
	var director := get_first_node_in_group("emergency_depot_director")
	var cruiser := director.call("request_dispatch", "police", target, false) as CharacterBody2D
	if cruiser == null:
		push_error("PURSUIT_FAILED: depot did not dispatch a cruiser")
		quit(1)
		return
	var reached := false
	var recycled := false
	var transitioned := false
	var collisions := {}
	var previous := cruiser.global_position
	var travel := 0.0
	for frame in 3600:
		await physics_frame
		wanted.set("time_hidden", 0.0)
		if not is_instance_valid(cruiser) or not cruiser.visible or cruiser.global_position.x > 9000:
			recycled = true
			break
		travel += previous.distance_to(cruiser.global_position)
		previous = cruiser.global_position
		transitioned = transitioned or int(cruiser.get("_lane_router").leg_index) >= 2
		for index in cruiser.get_slide_collision_count():
			var body := cruiser.get_slide_collision(index).get_collider() as Node
			if body != null:
				if not collisions.has(String(body.name)) and body is Node2D:
					print("FIRST_COLLISION|", body.get_path(), "|", (body as Node2D).global_position)
				collisions[String(body.name)] = int(collisions.get(String(body.name), 0)) + 1
		if frame % 600 == 0:
			print("ROUTE_PROGRESS|", frame, "|", cruiser.global_position, "|leg=", cruiser.get("_lane_router").leg_index, "|legs=", cruiser.get("_lane_router").legs.size())
		if cruiser.global_position.distance_to(target.global_position) <= 140.0:
			reached = true
			break
	print("PURSUIT|rails=", graph.get("build_guard_rails"), "|reached=", reached, "|recycled=", recycled, "|position=", previous, "|distance=", previous.distance_to(target.global_position), "|travel=", travel, "|collisions=", collisions)
	if not reached or recycled:
		push_error("PURSUIT_FAILED: cruiser did not reach the gateway before timeout/recycling")
	var passed := reached and not recycled and transitioned
	if not transitioned:
		push_error("PURSUIT_FAILED: cruiser did not traverse a lane connector")
	world.queue_free()
	await process_frame
	quit(0 if passed else 1)
