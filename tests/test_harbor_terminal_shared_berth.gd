extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)


func run() -> void:
	var opening := OS.get_cmdline_user_args().has("--opening")
	root.get_node("CampaignState").reset_campaign()
	if not opening:
		root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
		root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_call_complete", true)
	root.get_node("SaveManager").clear_pending_save()
	var world: Node2D = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in (60 if opening else 20):
		await process_frame

	var operations: Node2D = world.get_node("ArrivalStop/TerminalOperations")
	var arriving: Node2D = operations.fleet[3]
	var regional: Node2D = world.get_node("HarborMountainCoachService")
	check(arriving.state == "arriving", "The startup coach is exercising the shared terminal street berth")
	check(not regional._harbor_berth_clear(), "Berth admission sees the startup coach occupying the street")
	check(regional.coach == null, "The regional coach waits instead of spawning over the startup coach")
	check(get_nodes_in_group("regional_coach").is_empty(), "No overlapping regional coach body entered the public lane")
	if opening:
		check(paused, "New Game exercises berth admission while the real opening pauses physics")
		world.campaign_controller.skip_cinematic()
		var deadline := Time.get_ticks_msec() + 60000
		var overlap_seen := false
		while arriving.entries == 0 and Time.get_ticks_msec() < deadline:
			await physics_frame
			if regional.coach != null:
				overlap_seen = overlap_seen or arriving.coach_shape.shape.collide(arriving.coach_shape.global_transform, regional.coach.collision.shape, regional.coach.collision.global_transform)
		check(arriving.entries == 1, "Startup coach physically enters through the gate after the opening")
		check(regional.coach != null, "Regional service starts once the first coach vacates the shared berth")
		check(not overlap_seen, "Regional admission and the complete gate maneuver never overlap coach hulls")

	print("HARBOR_TERMINAL_SHARED_BERTH failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
