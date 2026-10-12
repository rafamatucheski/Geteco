extends "res://tests/measure/measure_combat.gd"

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
		quit(2)
		return
	gameplay = world.gameplay
	gameplay.state.economy.activate_arsenal_cheat()
	gameplay.state.equip_weapon("pistol")
	var controls = root.get_node("GameInput")
	controls.using_gamepad = true
	controls._aim_stick = Vector2(0.5, -0.5)
	Input.action_press("aim")
	await sample_phase("aim", Callable())
	Input.action_release("aim")
	var folder := "res://output/controller-aim-20261012/"
	var label := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var result := {"aim": summarize("aim"), "samples_ms": samples,
		"gpu": OS.get_video_adapter_driver_info(), "engine": Engine.get_version_info(),
		"window": DisplayServer.window_get_size(), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps}
	var file := FileAccess.open(folder + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print("CONTROLLER_AIM_MEASURE ", result.aim)
	quit()
