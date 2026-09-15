extends SceneTree

var _frame_times: Array[float] = []
var _last_frame_usec := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(90).timeout.connect(func(): printerr("LIVING_POLICE_CITY TIMEOUT"); quit(2))
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/living-response-0912/test-saves/"
	DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/living-response-0912/test-saves")
	var state := root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_delivery_complete", true)
	state.set_campaign_flag(&"harbor_arrival_seen", true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or current_scene.get("gameplay_ready") != true: await process_frame
	for i in 30: await physics_frame
	var player: CharacterBody2D = current_scene.get_node("Player")
	player.set_physics_process(false)
	player.is_control_disabled = false
	player.is_in_dialogue = false
	player.global_position = Vector2(1540, 1168)
	player.health = 10000 # Observe sustained live combat without ending the fixture.
	player.armor = 0
	player._respawn_grace_active = false
	player.velocity = Vector2.ZERO
	player.show()
	if DisplayServer.get_name() != "headless":
		if "--fixed720" in OS.get_cmdline_user_args():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(1280, 720))
			DisplayServer.window_set_position(Vector2i(-3000, -3000))
			root.size = Vector2i(1280, 720)
		await create_timer(5.0).timeout
		_last_frame_usec = Time.get_ticks_usec()
		process_frame.connect(_sample_frame)
	var wanted := root.get_node("WantedManager")
	wanted.reset_crime()
	wanted.ensure_minimum_wanted_level(4)
	var max_units := 0
	var max_officers := 0
	var min_distance := INF
	var elapsed := 0.0
	var snapshot_clock := 0.0
	while elapsed < 34:
		await physics_frame
		var step := 1.0 / Engine.physics_ticks_per_second
		elapsed += step
		snapshot_clock += step
		var active := 0
		for unit in get_nodes_in_group("emergency_vehicle"):
			if not unit.visible or unit.type != 0 or unit.is_broken or unit.is_returning_to_base: continue
			active += 1
			min_distance = minf(min_distance, unit.global_position.distance_to(player.global_position))
		max_units = maxi(max_units, active)
		max_officers = maxi(max_officers, get_nodes_in_group("police_officer").size())
		if snapshot_clock >= 5:
			snapshot_clock = 0
			print("CITY_RESPONSE t=", roundi(elapsed), " units=", active, " closest=", roundi(min_distance), " health=", player.health, " searching=", wanted.is_searching())
			for officer in get_nodes_in_group("police_officer"):
				if officer.global_position.distance_to(player.global_position) < 500:
					print("OFFICER at=", officer.global_position, " exiting=", officer.service_disembark_active, " returning=", officer.returning_to_service_vehicle, " sight=", officer._has_target_sight(true), " aim=", officer.visible_aim_time)
	print("CITY_RESPONSE result max_units=", max_units, " max_officers=", max_officers, " nearest=", min_distance, " damage=", 10000-player.health)
	var okay: bool = max_units >= 4 and min_distance < 320 and player.health < 10000
	if DisplayServer.get_name() != "headless":
		process_frame.disconnect(_sample_frame)
		_write_frame_report()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/living-response-0912/city-combat.png")
	wanted.dismiss_all_police()
	print("LIVING_POLICE_CITY ", "PASS" if okay else "FAIL")
	quit(0 if okay else 1)

func _sample_frame() -> void:
	var now := Time.get_ticks_usec()
	_frame_times.append((now - _last_frame_usec) / 1000.0)
	_last_frame_usec = now

func _write_frame_report() -> void:
	if _frame_times.is_empty(): return
	var total := 0.0
	var over_33 := 0
	var over_66 := 0
	for value in _frame_times:
		total += value
		if value > 33.3: over_33 += 1
		if value > 66.7: over_66 += 1
	var ordered := _frame_times.duplicate()
	ordered.sort()
	var report := {
		"scenario": "HarborGame four stars, live traffic, stationary player at 1540,1168",
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": str(root.size),
		"max_fps": Engine.max_fps,
		"vsync": DisplayServer.window_get_vsync_mode(),
		"warmup_seconds": 5,
		"frames": ordered.size(), "duration_seconds": total / 1000.0,
		"average_fps": 1000.0 * ordered.size() / total,
		"p50_ms": ordered[int((ordered.size() - 1) * 0.50)],
		"p95_ms": ordered[int((ordered.size() - 1) * 0.95)],
		"p99_ms": ordered[int((ordered.size() - 1) * 0.99)],
		"max_ms": ordered.back(), "over_33_ms": over_33, "over_66_ms": over_66,
		"frame_times_ms": _frame_times,
		"baseline": "Unavailable: earlier workspace state was not fully captured. This is not a before/after certification."
	}
	var suffix := "-720" if "--fixed720" in OS.get_cmdline_user_args() else ""
	var file := FileAccess.open("D:/geteco/artifacts/living-response-0912/city-frame-times%s.json" % suffix, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	report.erase("frame_times_ms")
	print("CITY_FRAME_TIMES ", JSON.stringify(report))
