extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	seed(913)
	root.size = Vector2i(1280, 720)
	root.get_node("SaveManager")._save_dir = OS.get_temp_dir().path_join("tire_launch_%d" % Time.get_ticks_usec()) + "/"
	root.get_node("SaveManager")._save_directory_ready = false
	var campaign = root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 120: await process_frame
	if world.campaign_controller: world.campaign_controller.skip_cinematic()
	paused = false
	if not world.get("gameplay_ready"):
		push_error("Tire benchmark unavailable: production scene did not initialize")
		quit(1)
		return
	var car = world.get_node("PlayerCar")
	world.call("_drive")
	car._drive_input_armed = true
	for i in 120: await process_frame
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	var last_cycle := -1
	while Time.get_ticks_usec() - start < 30000000:
		var elapsed := float(Time.get_ticks_usec() - start) / 1000000.0
		var cycle := int(elapsed / 6.0)
		if cycle != last_cycle:
			car.global_position = Vector2(700, 425)
			car.rotation = 0
			car.velocity = Vector2.ZERO
			last_cycle = cycle
		Input.action_press("move_up")
		if fmod(elapsed, 6.0) < 1.5 or fmod(elapsed, 6.0) > 4.0: Input.action_press("handbrake")
		else: Input.action_release("handbrake")
		if fmod(elapsed, 6.0) > 3.0: Input.action_press("move_right")
		else: Input.action_release("move_right")
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	for action in ["move_up", "move_right", "handbrake"]: Input.action_release(action)
	var label := "before" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for ms in samples:
		total += ms
		if ms > 33.3: over33 += 1
		if ms > 66.7: over66 += 1
	var output := {"samples_ms": samples.duplicate(), "fps": samples.size() * 1000.0 / total, "frames": samples.size(), "duration_ms": total, "over33": over33, "over66": over66, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method()}
	samples.sort()
	for q in [50, 95, 99]: output["p%d" % q] = samples[mini(samples.size()-1, int(samples.size()*q/100.0))]
	output["max"] = samples.back()
	FileAccess.open("D:/geteco/artifacts/tire-launch-0913/" + label + ".json", FileAccess.WRITE).store_string(JSON.stringify(output))
	output.erase("samples_ms")
	print("TIRE_LAUNCH_PERF ", output)
	root.get_texture().get_image().save_png("D:/geteco/artifacts/tire-launch-0913/" + label + ".png")
	quit()
