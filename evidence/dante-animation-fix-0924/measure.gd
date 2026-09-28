extends SceneTree
## Real Main, no saves. Run -- --no-save --skip-arrival --population=24
## --dante-label=before [--dante-capture]. Capture runs are NOT benchmarks.
const IDS = ["smg", "pistol", "magnum", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "grenade", "knife", "axe", "bat", "knuckles", "fists"]
var world
var output := "res://evidence/dante-animation-fix-0924/"
var label := "before"
var capture := false
var baseline_scripts: Array[Script] = []
var samples: Array[float] = []
var max_scale := 0.0
var first_bad := -1
var shot_count := 0
var sampling := false
var last_frame_usec := 0

func measure_frame() -> void:
	var now := Time.get_ticks_usec()
	if sampling and last_frame_usec > 0: samples.append(float(now - last_frame_usec) / 1000.0)
	last_frame_usec = now

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dante-label="): label = arg.trim_prefix("--dante-label=")
		if arg == "--dante-capture": capture = true
		if arg == "--dante-baseline":
			# Frozen pre-fix Actor, registered before Main loads its preloads.
			# Never replace or roll back the shared working-tree file.
			for name in ["WeaponRigPose", "Actor", "VehicleBoardingPresentation", "Gameplay"]:
				var frozen: Script = load("res://evidence/dante-animation-fix-0924/" + name + ".before.gd")
				frozen.take_over_path(("res://scripts/" if name == "Actor" else "res://gameplay/") + name + ".gd")
				baseline_scripts.append(frozen)
	output += label + ("-capture" if capture else "-measure")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await process_frame
		if world.production != null and world.production.ready_for_play: break
	if world.production == null or not world.production.ready_for_play:
		quit(3)
		return
	var player = world.player
	var gameplay = world.gameplay
	gameplay._rng.seed = 7
	# Keep the presentation route alive while real NPCs/traffic/combat run.
	# The original reproduction reached the hospital modal after police damage;
	# comparing that modal with gameplay would not be a valid frame-time pair.
	gameplay.health = 1000000.0
	gameplay.state.economy.activate_arsenal_cheat()
	world.camera.target_size = 12.0
	player.controlled_automatically = true
	for frame in 180: await physics_frame
	var anchor: Vector3 = player.global_position
	var controls = root.get_node("GameInput")
	process_frame.connect(measure_frame)
	var previous_id := ""
	print("DANTE_ACTOR_SOURCE ", player.get_script().source_code.sha256_text())
	for tick in 3840:
		sampling = tick >= 480
		if not capture and world.session.weather != null:
			world.session.weather.time_of_day = 0.36
		var index := mini(tick / 240, IDS.size() - 1)
		var id: String = IDS[index]
		var local_tick := tick % 240
		if id != previous_id:
			gameplay.state.equip_weapon(id)
			previous_id = id
			player.teleport(anchor)
			print("DANTE_SEQUENCE ", tick, " ", id)
		var angle := float((local_tick / 30) % 8) * TAU / 8.0
		var facing := Vector3(sin(angle), 0, -cos(angle))
		var right: Vector3 = world.camera.global_basis.x
		var down: Vector3 = world.camera.global_basis.z
		right.y = 0
		down.y = 0
		controls.touch_aim = Vector2(facing.dot(right.normalized()), facing.dot(down.normalized()))
		Input.action_press("aim")
		player.speed = 6.5 if local_tick >= 180 else 3.5
		player.automatic_direction = Vector3.ZERO if local_tick < 60 else (-facing if local_tick < 120 else facing.rotated(Vector3.UP, PI * 0.5))
		if local_tick % 30 == 5:
			if gameplay.fire_at(player.global_position + facing * 15.0): shot_count += 1
		if local_tick == 145: gameplay.reload_weapon()
		await physics_frame
		for side in ["Right", "Left"]:
			for bone_name in ["Arm", "ForeArm"]:
				var bone: int = player.skeleton.find_bone(side + bone_name)
				var error: float = (player.skeleton.get_bone_pose_scale(bone) - Vector3.ONE).length()
				max_scale = maxf(max_scale, error)
				if first_bad < 0 and error > 0.1: first_bad = tick
		if capture and tick % 6 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("frame-%05d.png" % (tick / 6)))
		if capture: await process_frame
	sampling = false
	Input.action_release("aim")
	controls.touch_aim = Vector2.ZERO
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in samples:
		total += value
		if value > 33.3: over33 += 1
		if value > 66.7: over66 += 1
	var report := {"label":label,"capture_not_benchmark":capture,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"population":world.population,"frames":samples.size(),"seconds":total/1000.0,"fps":samples.size()*1000.0/total,"p50_ms":sorted[int(sorted.size()*0.5)],"p95_ms":sorted[int(sorted.size()*0.95)],"p99_ms":sorted[int(sorted.size()*0.99)],"max_ms":sorted.back(),"over33":over33,"over66":over66,"max_arm_scale_error":max_scale,"first_bad_tick":first_bad,"shots":shot_count,"samples_ms":samples}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	report.erase("samples_ms")
	print("DANTE_MAIN ", JSON.stringify(report))
	quit()
