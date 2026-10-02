extends "res://tests/measure/measure_combat.gd"
## Rendered production session; independent output folders preserve before/after samples.
func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Mouse aim measurement requires a ready session")
		quit(2)
		return
	gameplay = world.gameplay
	gameplay.state.economy.activate_arsenal_cheat()
	gameplay.state.equip_weapon("pistol")
	var controls = root.get_node("GameInput")
	controls.using_gamepad = false
	controls.touch_aim = Vector2.ZERO
	Input.action_press("aim")
	var sweep := func(seconds: float) -> void:
		var point: Vector3 = world.player.global_position + Vector3(cos(seconds * 0.7) * 5.0, 1.0, sin(seconds * 0.7) * 5.0)
		Input.warp_mouse(world.camera.unproject_position(point))
	await sample_phase("mouse_aim", sweep)
	Input.action_release("aim")
	var folder := "res://evidence/mouse-aim-20261001/before"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): folder = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var result := {"mouse_aim": summarize("mouse_aim"), "samples_ms": samples,
		"gpu": OS.get_video_adapter_driver_info(), "engine": Engine.get_version_info(),
		"window": DisplayServer.window_get_size(), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps}
	var file := FileAccess.open(folder + "/measure.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	root.get_texture().get_image().save_png(folder + "/capture.png")
	print("MOUSE_AIM_MEASURE ", result.mouse_aim)
	quit()
