extends SceneTree

## Rendered HarborGame comparison at the two ship berths. Saves stay isolated.
## Run with: --script res://tests/visual/measure_port_ships.gd -- out_dir=<path>
const GAME := preload("res://world/harbor/HarborGame.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Port ship measurement needs a real renderer")
		quit(1)
		return
	var output := ProjectSettings.globalize_path("user://tests/port-ships")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			output = arg.trim_prefix("out_dir=")
	if DirAccess.make_dir_recursive_absolute(output.path_join("saves")) != OK:
		quit(1)
		return
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", output.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	seed(22092026)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world := GAME.instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while (not world.gameplay_ready or not world.world_build_ready) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not world.gameplay_ready or not world.world_build_ready or paused:
		push_error("HarborGame did not reach playable state")
		quit(1)
		return
	var camera := Camera2D.new()
	camera.name = "PortShipReviewCamera"
	world.add_child(camera)
	camera.make_current()
	var player: Node2D = world.get_node("Player")
	for berth in [
		{"id": "northstar", "camera": Vector2(3530, 1430), "player": Vector2(3402, 1762), "zoom": 0.56},
		{"id": "south", "camera": Vector2(4790, 3000), "player": Vector2(4250, 3330), "zoom": 0.43},
	]:
		player.global_position = berth.player
		player.reset_physics_interpolation()
		camera.global_position = berth.camera
		camera.zoom = Vector2.ONE * berth.zoom
		camera.reset_physics_interpolation()
		for frame in 120:
			await process_frame
		await RenderingServer.frame_post_draw
		var image_path := output.path_join(str(berth.id) + ".png")
		root.get_texture().get_image().save_png(image_path)
		if OS.get_cmdline_user_args().has("--capture-only"):
			print("PORT_SHIP_CAPTURE ", image_path)
			continue
		if OS.get_cmdline_user_args().has("--compare-scaffolds"):
			await _compare_scaffolds(world, str(berth.id), output)
			continue
		var samples: Array[float] = []
		var started := Time.get_ticks_usec()
		var previous := started
		while Time.get_ticks_usec() - started < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now - previous) / 1000.0)
			previous = now
		samples.sort()
		var total := 0.0
		var over_33 := 0
		var over_66 := 0
		for sample in samples:
			total += sample
			if sample > 33.3: over_33 += 1
			if sample > 66.7: over_66 += 1
		var n := samples.size()
		var report := {
			"berth": berth.id, "frames": n, "duration_ms": total,
			"fps": n * 1000.0 / total, "p50_ms": samples[int((n - 1) * 0.50)],
			"p95_ms": samples[int((n - 1) * 0.95)], "p99_ms": samples[int((n - 1) * 0.99)],
			"max_ms": samples[n - 1], "over_33_ms": over_33, "over_66_ms": over_66,
			"renderer": RenderingServer.get_current_rendering_method(), "image": image_path,
		}
		var file := FileAccess.open(output.path_join(str(berth.id) + ".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
		print("PORT_SHIP_MEASURE ", JSON.stringify(report))
	quit(0)


func _compare_scaffolds(world: Node, berth_id: String, output: String) -> void:
	var scaffold_name := "NorthstarMaintenanceScaffold" if berth_id == "northstar" else "SantaMareMaintenanceScaffold"
	var scaffold := world.find_child(scaffold_name, true, false) as CanvasItem
	if scaffold == null:
		push_error("Scaffold missing for comparison: " + scaffold_name)
		return
	var off: Array[float] = []
	var on: Array[float] = []
	for cycle in 2:
		for enabled in [false, true, true, false]:
			scaffold.visible = enabled
			await process_frame
			var started := Time.get_ticks_usec()
			var previous := started
			while Time.get_ticks_usec() - started < 7500000:
				await process_frame
				var now := Time.get_ticks_usec()
				if enabled: on.append((now - previous) / 1000.0)
				else: off.append((now - previous) / 1000.0)
				previous = now
	scaffold.show()
	var report := {"berth": berth_id, "scaffold_hidden": _summarize(off), "scaffold_visible": _summarize(on)}
	var file := FileAccess.open(output.path_join(berth_id + "_scaffold_ab.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PORT_SCAFFOLD_AB ", JSON.stringify(report))


func _summarize(samples: Array[float]) -> Dictionary:
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	var n := samples.size()
	return {
		"frames": n, "duration_ms": total, "fps": n * 1000.0 / total,
		"p50_ms": samples[int((n - 1) * 0.50)],
		"p95_ms": samples[int((n - 1) * 0.95)],
		"p99_ms": samples[int((n - 1) * 0.99)],
	}
