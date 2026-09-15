extends SceneTree
## Observe the unmodified production schedule, with real frame-time samples.
var world: Node2D
var samples: Array[float] = []
var overlaps := {}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var label := args[0] if not args.is_empty() else "baseline"
	var output := "D:/geteco/artifacts/terminal-circuit-0913/" + label
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.get_node("CampaignState").reset_campaign()
	if args.has("--after-arrival"):
		root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
		root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_call_complete", true)
	root.get_node("SaveManager").clear_pending_save()
	world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 20: await process_frame
	world.campaign_controller.skip_cinematic()
	if args.has("--fast"):
		Engine.time_scale = 3.0
		Engine.physics_ticks_per_second = 120
	var camera := Camera2D.new()
	camera.position = Vector2(1940, 1130)
	camera.zoom = Vector2.ONE * 2.0
	world.add_child(camera)
	camera.make_current()
	var operations: Node2D = world.get_node("ArrivalStop/TerminalOperations")
	var started := Time.get_ticks_msec()
	var previous := Time.get_ticks_usec()
	var last_report := -1
	while Time.get_ticks_msec() - started < 120000:
		await process_frame
		var now := Time.get_ticks_usec()
		if Time.get_ticks_msec() - started > 10000: samples.append((now - previous) / 1000.0)
		previous = now
		if world.campaign_controller.phase == "phone":
			world.campaign_controller.answer_phone()
			for line in 4: world.campaign_controller.advance_dialogue()
		var seconds := int((Time.get_ticks_msec() - started) / 1000)
		if seconds / 10 != last_report:
			last_report = seconds / 10
			print("CIRCUIT t=", seconds, " ", operations.get_operation_status())
			var station: Node2D = world.get_node("ArrivalStop")
			print("LOCAL ", station.get_service_status())
			for person in station.passengers:
				if person.transit_state not in ["alighting", "boarding"]: continue
				var nearby := []
				for other in get_nodes_in_group("pedestrian"):
					if other != person and other.global_position.distance_to(person.global_position) < 40:
						nearby.append([str(other.get_path()), other.global_position, other.collision_layer])
				var contact := KinematicCollision2D.new()
				var blocked: bool = person.test_move(person.global_transform, person.global_position.direction_to(person.destination) * 2, contact)
				print("PASSENGER ", person.name, " at=", person.global_position, " to=", person.destination, " nearby=", nearby, " blocked=", str(contact.get_collider().get_path()) if blocked else "")
			for service in operations.fleet:
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = service.coach_shape.shape
				query.transform = service.coach_shape.global_transform
				query.collision_mask = 2
				query.exclude = [service.coach.get_rid()]
				for hit in world.get_world_2d().direct_space_state.intersect_shape(query):
					var key := str(service.platform_index) + ":" + str(hit.collider.get_path())
					overlaps[key] = seconds
					print("COACH_OVERLAP ", key)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("%03d.png" % seconds))
	var elapsed := 0.0
	var slow := 0
	var stalls := 0
	for sample in samples:
		elapsed += sample
		slow += int(sample > 33.3)
		stalls += int(sample > 66.7)
	var raw := FileAccess.open(output.path_join("frames.json"), FileAccess.WRITE)
	raw.store_string(JSON.stringify(samples))
	samples.sort()
	print("FRAME_METRICS gpu=", RenderingServer.get_video_adapter_name(), " frames=", samples.size(), " ms=", elapsed, " fps=", samples.size() * 1000.0 / elapsed, " p50=", samples[int(samples.size() * .50)], " p95=", samples[int(samples.size() * .95)], " p99=", samples[int(samples.size() * .99)], " max=", samples.back(), " above33=", slow, " above66=", stalls)
	print("CIRCUIT_RESULT overlaps=", overlaps, " ", operations.get_operation_status())
	world.queue_free()
	await process_frame
	quit()
