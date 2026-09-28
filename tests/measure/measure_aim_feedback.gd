extends "res://tests/measure/measure_combat.gd"

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	# Reconstruct only this change's previous behavior in memory; never rewrite shared files.
	if "--baseline" in OS.get_cmdline_user_args():
		var replacements := {
			"res://runtime/GameInput.gd": [["AIM_TURN_SPEED_MIN := 3.0", "AIM_TURN_SPEED_MIN := 1.20"], ["AIM_TURN_SPEED_MAX := 20.0", "AIM_TURN_SPEED_MAX := 5.50"], ["AIM_RESPONSE_CURVE := 1.25", "AIM_RESPONSE_CURVE := 1.65"]],
			"res://scripts/Actor.gd": [["lerpf(2.3, 2.4 if alignment < 0.0 else 3.2", "lerpf(1.35, 1.65 if alignment < 0.0 else 2.5"], ["combat_facing, delta * 24.0", "combat_facing, delta * 9.0"]],
			"res://scripts/CameraRig.gd": [["if not _is_vehicle_target() and combat != null and combat.has_method", "if false and not _is_vehicle_target() and combat != null and combat.has_method"]],
			"res://gameplay/Gameplay.gd": [["\taim_layer.add_child(reticle)", "\treticle.free()"]],
		}
		for path in replacements:
			var script: GDScript = load(path)
			for pair in replacements[path]:
				if not script.source_code.contains(pair[0]):
					push_error("Baseline replacement no longer matches " + path)
					quit(3)
					return
				script.source_code = script.source_code.replace(pair[0], pair[1])
			if script.reload(true) != OK:
				quit(3)
				return
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Aim measurement requires a ready production session")
		quit(2)
		return
	gameplay = world.gameplay
	gameplay.state.economy.activate_arsenal_cheat()
	gameplay.state.equip_weapon("pistol")
	root.get_node("GameInput").touch_aim = Vector2.RIGHT
	Input.action_press("aim")
	await sample_phase("aim", Callable())
	Input.action_release("aim")
	var label := "baseline" if "--baseline" in OS.get_cmdline_user_args() else "after"
	var folder := "res://evidence/aim-feedback/"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): folder = argument.trim_prefix("--output=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var result := {"aim": summarize("aim"), "samples_ms": samples, "gpu": OS.get_video_adapter_driver_info(),
		"engine": Engine.get_version_info(), "window": DisplayServer.window_get_size(),
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps}
	print("AIM MEASURE ", summarize("aim"))
	var file := FileAccess.open(folder + label + ".json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write measurement to " + folder)
		quit(2)
		return
	file.store_string(JSON.stringify(result, "  "))
	root.get_texture().get_image().save_png(folder + label + ".png")
	quit()
