extends SceneTree

## Rendered HarborGame A/B: identical gunfire with fleeing-only or mixed witnesses.
## --script res://tests/measure_civilian_incident.gd -- mode=flee|mixed out_dir=<absolute path>
const GAME := preload("res://world/harbor/HarborGame.tscn")
const BULLET := preload("res://guns/Bullet.tscn")
var _world
var _player: Node2D
var _focus: Node2D
var _participants: Array[AnimatedPedestrian3D] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Civilian incident benchmark needs a renderer")
		quit(1)
		return
	var mode := "flee"
	var output := ProjectSettings.globalize_path("user://civilian-incident")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("mode="): mode = arg.trim_prefix("mode=")
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	if mode not in ["flee", "mixed"] or DirAccess.make_dir_recursive_absolute(output.path_join("saves")) != OK:
		push_error("Invalid civilian incident arguments")
		quit(1)
		return
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", output.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	seed(22092026)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	_world = GAME.instantiate()
	root.add_child(_world)
	current_scene = _world
	var deadline := Time.get_ticks_msec() + 120000
	while (not _world.gameplay_ready or not _world.world_build_ready) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _world.gameplay_ready or not _world.world_build_ready or paused:
		push_error("HarborGame did not become ready")
		quit(1)
		return
	paused = true
	await preload("res://cars/VehicleGeometryCache.gd").prepare_common_models(self)
	await preload("res://cars/VehicleGeometryCache.gd").prepare_resident_presentations(self)
	await root.get_node("EmergencyPool").prepare_presentations()
	await preload("res://audio/VehicleEngineSound.gd").prepare_catalog(self)
	paused = false
	_world.weather.is_dynamic_time = false
	_world.weather.time_of_day = 0.45
	_world.weather.set_weather(0)
	_player = _world.get_node("Player")
	var walkers := get_nodes_in_group("authored_sidewalk_pedestrian")
	if walkers.is_empty():
		push_error("Harbor has no authored walkers")
		quit(1)
		return
	_focus = walkers[0]
	var most := -1
	for candidate in walkers:
		var nearby := 0
		for other in walkers:
			if candidate.global_position.distance_squared_to(other.global_position) < 240.0 * 240.0: nearby += 1
		if nearby > most:
			most = nearby
			_focus = candidate
	_player.global_position = _focus.global_position + Vector2(-80, -30)
	_player.reset_physics_interpolation()
	var camera := _player.get_node("Camera") as Camera2D
	camera.global_position = _player.global_position
	camera.reset_smoothing()
	await _warmup(10.0)
	# Keep the controlled witness group beside the shooter after city warmup.
	_player.global_position = _focus.global_position + Vector2(-80, -30)
	_player.reset_physics_interpolation()
	camera.global_position = _player.global_position
	camera.reset_smoothing()
	for candidate in get_nodes_in_group("authored_sidewalk_pedestrian"):
		if candidate is AnimatedPedestrian3D and not candidate.is_gangster and not candidate.is_dead and not candidate.is_incapacitated and candidate.global_position.distance_to(_player.global_position) < 260.0:
			_participants.append(candidate)
	_participants.sort_custom(func(a: AnimatedPedestrian3D, b: AnimatedPedestrian3D): return a.global_position.distance_squared_to(_player.global_position) < b.global_position.distance_squared_to(_player.global_position))
	if _participants.size() < 2:
		push_error("At least two nearby citizens are required for gunfire benchmark")
		quit(1)
		return
	var roles := [AnimatedPedestrian3D.CivilianReaction.FIGHT, AnimatedPedestrian3D.CivilianReaction.ARMED, AnimatedPedestrian3D.CivilianReaction.CALL_POLICE, AnimatedPedestrian3D.CivilianReaction.FLEE]
	for i in _participants.size():
		_participants[i].civilian_reaction_profile = roles[i % roles.size()] if mode == "mixed" else AnimatedPedestrian3D.CivilianReaction.FLEE
	var measured := await _sample(mode, output)
	quit(0 if measured else 1)

func _warmup(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await process_frame

func _fire() -> void:
	var bullet = BULLET.instantiate()
	bullet.owner_body = _player
	bullet.damage = 0
	bullet.direction = Vector2.RIGHT
	_world.add_child(bullet)
	bullet.global_position = _player.global_position + Vector2(18, 0)
	# Guarantee the same nearby people witness each controlled shot even if a
	# traffic body happens to stop the projectile before its hearing ray.
	for citizen in _participants:
		if is_instance_valid(citizen) and not citizen.is_dead and not citizen.is_incapacitated:
			citizen.react_to_gunfire(bullet.global_position, bullet.global_position + Vector2.RIGHT * 500.0, _player)

func _sample(mode: String, output: String) -> bool:
	var samples: Array[float] = []
	var elapsed := 0.0
	var next_shot := 0.0
	var previous := Time.get_ticks_usec()
	var saw_armed := false
	var saw_fight := false
	var saw_call := false
	while elapsed < 30000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - previous) / 1000.0
		previous = now
		elapsed += ms
		samples.append(ms)
		if elapsed >= next_shot:
			_fire()
			next_shot += 4000.0
		for citizen in _participants:
			if not is_instance_valid(citizen): continue
			saw_armed = saw_armed or citizen.civilian_reaction == AnimatedPedestrian3D.CivilianReaction.ARMED
			saw_fight = saw_fight or citizen.civilian_reaction == AnimatedPedestrian3D.CivilianReaction.FIGHT
			saw_call = saw_call or citizen.civilian_reaction == AnimatedPedestrian3D.CivilianReaction.CALL_POLICE or citizen.civilian_called_police
	var ordered := samples.duplicate()
	ordered.sort()
	var report := {"mode": mode, "seconds": elapsed / 1000.0, "frames": samples.size(), "fps": samples.size() * 1000.0 / elapsed, "p50_ms": ordered[int(ordered.size() * 0.5)], "p95_ms": ordered[int(ordered.size() * 0.95)], "p99_ms": ordered[int(ordered.size() * 0.99)], "max_ms": ordered[-1], "over33": samples.filter(func(v): return v > 33.3).size(), "over66": samples.filter(func(v): return v > 66.7).size(), "participants": _participants.size(), "armed": saw_armed, "fight": saw_fight, "call": saw_call, "stars": root.get_node("WantedManager").current_stars, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "cap": Engine.max_fps, "vsync": DisplayServer.window_get_vsync_mode()}
	var file := FileAccess.open(output.path_join(mode + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CIVILIAN_INCIDENT ", JSON.stringify(report))
	if mode == "mixed" and (not saw_armed or not saw_fight):
		push_error("Mixed incident did not exercise both armed and melee reactions")
		return false
	return true
