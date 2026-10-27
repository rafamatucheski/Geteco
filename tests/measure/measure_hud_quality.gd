extends "res://tests/measure/measure.gd"
## Rendered production HUD, same scene/settings and finite samples before/after.
const STARTUP := preload("res://tests/fixtures/TravelBagScene.gd")
var folder := ""
var input_events := {}

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	folder = "res://artifacts/hud-quality-20261027/" + variant
	DirAccess.make_dir_recursive_absolute(folder)
	seed(27102026)
	for action in InputMap.get_actions():
		input_events[action] = InputMap.action_get_events(action)
		InputMap.action_erase_events(action)
	var settings := root.get_node("V2Settings")
	settings.window_mode = 0
	settings.resolution = 0
	settings.vsync = true
	settings.fps_limit = 1
	settings.apply_settings()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	if not await STARTUP.wait_for_startup(world):
		push_error("HUD quality: startup did not finish")
		quit(3)
		return
	world.player.teleport(Vector3(132,.15,72))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(world.player.global_position)
	world.camera.target_size = 38
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	var economy = world.session.state.economy
	economy.grid_equip_bag("backpack")
	for weapon_id in ["pistol", "hunting_rifle", "smg", "shotgun", "assault_rifle", "grenade", "katana"]:
		economy.grant_weapon(weapon_id)
	economy.grant_item("apple",3)
	economy.grant_item("water",2)
	economy.add_ammo("pistol",126)
	world.session.state.equip_weapon("pistol")
	world.gameplay.armor = 65
	world.gameplay.health = 82
	var wheel = world.session.equipment_wheel
	for scenario in ["hud", "weapons", "consumables"]:
		if scenario == "weapons" and not wheel.open():
			push_error("HUD quality: wheel did not open")
			quit(4)
			return
		if scenario == "consumables": wheel.toggle_page()
		var warm: Array[float] = []
		var frames: Array[float] = []
		var begin := Time.get_ticks_usec()
		var last := begin
		var total := 0.0
		var interrupted: Array = []
		while total < 30000:
			await process_frame
			var now := Time.get_ticks_usec()
			if scenario != "hud" and not wheel.active:
				# Alt-tab correctly cancels the real wheel. A cancelled view is
				# never counted as a cheaper rendering of that view.
				interrupted.append({"frames_ms":frames.duplicate(),"warmup_ms":warm.duplicate(),"health":world.gameplay.health})
				if interrupted.size()>1 or world.gameplay.health<82 or not wheel.open():
					push_error("HUD quality: wheel interrupted; timing sample invalid")
					quit(4)
					return
				if scenario == "consumables": wheel.toggle_page()
				frames.clear(); warm.clear(); total=0.0; begin=now; last=now
				continue
			var ms := (now-last)/1000.0
			if now-begin < 8000000: warm.append(ms)
			else:
				frames.append(ms)
				total += ms
			last = now
		var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"time_scale":Engine.time_scale,"population":world.people.size(),"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"scope":"Rendered Main, normal population/directors, fixed clear daytime; 8s warmup + 30s sample. Target 60 FPS; >5% p95/p99 prompts finite confirmation. Scripted scene setup, not manual gameplay."}
		report["interrupted_samples"] = interrupted
		report["wheel_active"] = wheel.active
		FileAccess.open(folder+"/"+scenario+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await capture(scenario+"-1280")
		print("HUD_QUALITY ",variant," ",scenario," ",JSON.stringify(report.summary))
	wheel.close(false)
	# Restore normal hints only after timing is complete; captures show real keys.
	for action in input_events:
		for event in input_events[action]: InputMap.action_add_event(action,event)
	root.get_node("GameInput").bindings_changed.emit()
	world.hud.refresh_from_state()
	await capture("hud-1280-clean")
	wheel.open()
	await capture("weapons-1280-clean")
	wheel.toggle_page()
	await capture("consumables-1280-clean")
	wheel.close(false)
	world.session.show_inventory()
	await capture("inventory-1280")
	world.session.close_menu()
	world.session.show_map()
	await capture("map-1280")
	world.session.close_menu()
	world.pause_panel.pause_game()
	await capture("pause-1280")
	world.pause_panel.open_settings()
	await capture("settings-1280")
	world.pause_panel.settings.close()
	world.pause_panel.resume_game()
	for dimensions in [Vector2i(1920,1080),Vector2i(800,600)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		await capture("hud-"+str(dimensions.x))
		wheel.open()
		await capture("wheel-"+str(dimensions.x))
		wheel.close(false)
		world.pause_panel.pause_game()
		await capture("pause-"+str(dimensions.x))
		world.pause_panel.resume_game()
	Engine.time_scale = 1.0
	world.free()
	await process_frame
	quit()

func capture(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+name+".png")
