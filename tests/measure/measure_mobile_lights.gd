extends "res://tests/measure/measure.gd"
## Main + native routing, fixed night street, three independent mobile sources.
## --label=before/after; --temporal records every rendered frame separately.
const OUT := "res://evidence/mobile-lights-20261015"
var temporal := false
var only := ""

func _process(_delta: float) -> bool: return false

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg == "--temporal": temporal = true
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	create_timer(300).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(OUT)
	seed(15102026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 18000:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	assert(world.session.ready_for_play)
	world.dispatch.router.nearest_edge(world.player.position)
	assert(world.dispatch.router._native != null, "Native C# route backend required")
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day = .93
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 100000
	world.gameplay.state.economy.cheat_infinite_money = true
	world.player.teleport(Vector3(67.5,.1,139))
	world.session.controller.region.set_focus(world.player.global_position)
	world.gameplay.state.equip_weapon("fists")
	assert(world.gameplay.belt_flashlight.purchase())
	var report := {"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "native_csharp": true, "target_ms": 16.67, "regression_confirmation_percent": 5, "cases": []}
	for scenario in ["belt", "weapon", "car"]:
		if not only.is_empty() and scenario != only: continue
		if scenario == "weapon":
			world.gameplay.belt_flashlight.toggle()
			world.gameplay.state.grant_weapon("pistol")
			world.gameplay.state.equip_weapon("pistol")
			world.gameplay.buy_attachment("pistol", "flashlight")
			world.gameplay.toggle_flashlight()
		if scenario == "car":
			world.gameplay.flashlight_enabled = false
			world.gameplay._update_visual()
			var car = world.driving.car
			car.place(Vector3(67.5,.1,139),0)
			world.player.teleport(car.driver_door_anchor(-1))
			assert(world.driving._begin_entry(car,-1))
			for i in 300:
				await physics_frame
				if car.controlled: break
			assert(car.controlled)
			car.input_locked = true
			car.health = 1000000
			car.equipment.headlights_on = true
			car.equipment._refresh()
		await create_timer(5).timeout
		print("MOBILE_LIGHT_BEGIN ", label, " ", scenario)
		var frames: Array[float] = []
		var gpu_ms: Array[float] = []
		var cpu_ms: Array[float] = []
		var archive: ZIPPacker
		var timeline: Array[int] = []
		var source_visibility_failures := 0
		if temporal:
			archive = ZIPPacker.new()
			assert(archive.open(OUT.path_join(label+"-"+scenario+"-frames.zip")) == OK)
		var begin := Time.get_ticks_usec()
		var last := begin
		while Time.get_ticks_usec()-begin < 30000000:
			if temporal:
				var elapsed := float(Time.get_ticks_usec()-begin)/1000000.0
				# Keep the first ten seconds static, then exercise real walking and zoom.
				if scenario != "car" and elapsed > 10.0:
					world.player.automatic_direction = Vector3(sin(elapsed),0,cos(elapsed))
				world.camera.target_size = 32.0 if elapsed < 20.0 else 32.0 + sin(elapsed)*4.0
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now-last)/1000.0)
			gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			cpu_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
			last = now
			if temporal:
				await RenderingServer.frame_post_draw
				if scenario == "car" and not world.driving.car.equipment.lamps.all(func(item): return item.lamp.is_visible_in_tree()): source_visibility_failures += 1
				if scenario == "belt" and not world.gameplay.belt_flashlight.lamp.is_visible_in_tree(): source_visibility_failures += 1
				if scenario == "weapon" and not world.gameplay.flashlight.is_visible_in_tree(): source_visibility_failures += 1
				archive.start_file("%05d.jpg" % timeline.size())
				archive.write_file(root.get_texture().get_image().save_jpg_to_buffer(.85))
				archive.close_file()
				timeline.append(Time.get_ticks_msec())
		if temporal:
			archive.close()
			world.player.automatic_direction = Vector3.ZERO
			FileAccess.open(OUT.path_join(label+"-"+scenario+"-timestamps.json"),FileAccess.WRITE).store_string(JSON.stringify(timeline))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join(label+"-"+scenario+".png"))
		var result := {"scenario": scenario, "summary": stats(frames), "frame_intervals_ms": frames, "gpu_ms": gpu_ms, "process_cpu_ms": cpu_ms, "capture_overhead": temporal, "source_visibility_failures": source_visibility_failures, "vehicle_lights": preload("res://gameplay/lights/LightBudget.gd").counts()}
		report.cases.append(result)
		print("MOBILE_LIGHT_RESULT ", scenario, " ", JSON.stringify(result.summary))
	FileAccess.open(OUT.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	world.queue_free()
	await process_frame
	quit()
