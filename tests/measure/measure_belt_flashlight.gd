extends "res://tests/measure/measure.gd"
## Same integrated sewer, camera and population before/after; no personal save.
var site := "sewer_port"
var combat := false

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--site="): site = arg.trim_prefix("--site=")
		if arg == "--combat": combat = true
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 18000:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: push_error("Sewer refresh benchmark: startup or entry unavailable"); quit(1); return
	var definition: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition(site)
	world.session.controller.region.set_focus(definition.entry_position)
	world.player.teleport(definition.entry_position + Vector3(-1.2, .08, 1.0))
	for i in 90: await physics_frame
	if not await world.session.enter_place(site, false): push_error("Sewer refresh benchmark: entry unavailable"); quit(1); return
	world.player.controlled_automatically = true
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day = .32
	world.session.weather.weather_state = 0
	var point: Vector3 = world.player.global_position
	route = PackedVector3Array([point])
	if combat:
		world.gameplay.state.equipped_weapon = "fists"
		for actor in world.session.room_npcs:
			actor.receive_damage(9, world.player)
			actor.receive_damage(9, world.player)
	world.gameplay.state.economy.cheat_infinite_money = true
	assert(world.gameplay.belt_flashlight.purchase())
	started = Time.get_ticks_usec()
	previous = started

func _process(delta: float) -> bool:
	if is_instance_valid(world) and combat:
		world.gameplay.health = 100
	return super._process(delta)

func finish() -> void:
	var report := {"label": label, "site": site, "combat": combat,
		"engine": Engine.get_version_info().string, "scene": "Main.tscn",
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"population": world.people.size(), "residents": world.session.room_npcs.size(),
		"summary": stats(samples), "warmup": stats(cold), "cpu_process": stats(cpu), "physics": stats(physics),
		"frame_intervals_ms": samples, "warmup_intervals_ms": cold}
	DirAccess.make_dir_recursive_absolute("res://output/belt-flashlight")
	FileAccess.open("res://output/belt-flashlight/" + label + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/belt-flashlight/" + label + ".png")
	print("SEWER_BENCHMARK ", JSON.stringify(report.summary))
	world.free()
	await process_frame
	quit(0)

