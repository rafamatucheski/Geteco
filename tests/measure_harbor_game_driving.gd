extends SceneTree

## Production-game checkpoint benchmark, not a campaign-completion test.
## Same 1920x1080 route and 600-frame sample as sustained-driving preview QA.
## --post-boss measures the settled epilogue/reward checkpoint in memory only.
const GAME := preload("res://world/harbor/HarborGame.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world := GAME.instantiate()
	root.add_child(world)
	current_scene = world
	for i in 90:
		await process_frame
	if not world.gameplay_ready or paused:
		push_error("Production benchmark checkpoint did not become playable")
		quit(1)
		return
	var post_boss := OS.get_cmdline_user_args().has("--post-boss")
	if post_boss:
		var ledger = world.get_node("CobraCampaign").ledger
		ledger.data.aftermath = {"call_complete": true, "works_complete": true}
		for id in ledger.MISSION_IDS:
			ledger.rest_until_next_day(false)
			if not ledger.start_mission(id) or not ledger.complete_mission(id):
				push_error("Invalid post-boss benchmark fixture: " + str(id))
				quit(1)
				return
	var player: Node2D = world.get_node("Player")
	player.global_position = Vector2(2200, 1050)
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	world.call("_drive")
	for i in 30:
		await process_frame
	var samples: Array[float] = []
	var distance := 0.0
	var previous := car.global_position
	Input.action_press("ui_up")
	for i in 600:
		var start := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
		distance += car.global_position.distance_to(previous)
		previous = car.global_position
	Input.action_release("ui_up")
	var total := 0.0
	var over_budget := 0
	for duration in samples:
		total += duration
		if duration > 16.67:
			over_budget += 1
	samples.sort()
	print("HARBOR_GAME_DRIVING checkpoint=%s renderer=%s travelled_px=%.1f avg_fps=%.1f avg_ms=%.2f p50_ms=%.2f p90_ms=%.2f p99_ms=%.2f worst_ms=%.2f over_budget=%d/600" % [
		"post_boss" if post_boss else "post_arrival", RenderingServer.get_current_rendering_method(), distance,
		600000.0 / total, total / 600.0, samples[300], samples[540], samples[594], samples[599], over_budget])
	world.queue_free()
	await process_frame
	quit(0 if distance > 300.0 else 1)
