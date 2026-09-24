extends SceneTree
## Real Main, fixed police encounter; sequential baseline/after, no saves.
var world
var officers: Array = []
var output := "res://evidence/police-0922/before"
var baseline := false
var record := false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output = arg.trim_prefix("output=")
		if arg == "--baseline": baseline = true
		if arg == "--record": record = true
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	for i in 120: await process_frame
	var game = world.gameplay
	var center: Vector3 = world.player.global_position
	game._rng.seed = 7
	for i in 8:
		var officer = preload("res://gameplay/PoliceAgent.gd").new()
		officer.tier = i % 5
		officer.controller = game
		world.add_child(officer)
		officer.global_position = center + Vector3(sin(i * TAU / 8.0), 0, cos(i * TAU / 8.0)) * 5.0
		officer.visual.rotation.y = i * TAU / 8.0
		officer.set_physics_process(false)
		officer._rng.seed = 700 + i
		if baseline:
			officer.visual.scale = Vector3.ONE * 1.28
			officer.visual.torso_node.get_child(0).scale = Vector3.ONE
			officer.visual.right_upper_arm.position.x = 0.185
			officer.visual.left_upper_arm.position.x = -0.185
			officer.visual.weapon.reparent(officer.visual.right_lower_arm)
			officer.visual.weapon.transform = Transform3D(Basis.IDENTITY, Vector3(0, -0.18, 0))
			officer.visual.right_upper_arm.rotation = Vector3(-1.25, 0, 0)
			officer.visual.right_lower_arm.rotation = Vector3.ZERO
			officer.visual.left_upper_arm.rotation = Vector3(-1.1, 0, 0)
			officer.visual.left_lower_arm.rotation = Vector3(0, 0, -0.65)
		officers.append(officer)
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute)
	var frames: Array[float] = []
	var warm := 0.0
	var elapsed := 0.0
	var tick := 0.0
	var capture := 0
	var last := Time.get_ticks_usec()
	while elapsed < (12.0 if record else 30.0):
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		warm += ms / 1000.0
		game.health = 100.0
		tick += ms / 1000.0
		var reload_phase := record and elapsed >= 4.0 and elapsed < 6.0
		if not baseline:
			for officer in officers:
				officer.visual.update_pose(ms / 1000.0, not record or elapsed < 9.0, reload_phase, (elapsed - 4.0) / 2.0, elapsed * 4.0)
		if tick >= 0.85:
			tick = 0.0
			for officer in officers:
				if not baseline and not reload_phase and (not record or elapsed < 9.0):
					game.police_shoot(officer, 6.0, officer.weapon_id)
				elif baseline and game.police_can_see(officer):
					# Exact original police_shoot path, retained only for sequential A/B.
					var origin: Vector3 = officer.global_position + Vector3.UP * 1.1
					game._trace(origin, world.player.global_position + Vector3.UP, 0.08, 0.012)
					game._sound(officer.weapon_id, origin)
					game.damage_player(6.0)
		if warm < 8.0: continue
		frames.append(ms)
		elapsed += ms / 1000.0
		if record and capture < 120 and elapsed >= capture * 0.1:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(absolute.path_join("frame-%03d.jpg" % capture), 0.92)
			capture += 1
	var sorted := frames.duplicate()
	sorted.sort()
	var over33 := 0
	var over66 := 0
	for ms in frames:
		if ms > 33.3: over33 += 1
		if ms > 66.7: over66 += 1
	var report := {"frames": frames.size(), "seconds": elapsed, "fps": frames.size()/elapsed,
		"capture_not_benchmark": record, "reconstructed_original_path": baseline,
		"p50": sorted[int(sorted.size()*0.5)], "p95": sorted[int(sorted.size()*0.95)], "p99": sorted[int(sorted.size()*0.99)],
		"max": sorted.back(), "over33": over33, "over66": over66, "samples_ms": frames,
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"size": root.size, "vsync": DisplayServer.window_get_vsync_mode(), "limit": Engine.max_fps}
	FileAccess.open(absolute.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	report.erase("samples_ms")
	print("POLICE_METRICS ", JSON.stringify(report))
	quit()
