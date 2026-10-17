extends "res://tests/measure/measure.gd"
## Rendered Main, .NET build required BEFORE launching (never builds itself).
## --script res://tests/measure/measure_lightning_storm.gd -- --no-save --benchmark
## --out-dir=<NEW exclusive directory> --order=before
## Run that baseline BEFORE changing StormPresentation; then use a NEW directory
## with --order=after. Default order: before,after. Optional --include-movement,
## --seconds=30 (minimum 30), --capture-temporal (outside all timing samples).
## Forced strikes every six seconds are DIAGNOSTIC, not natural storm cadence.

const FIXED_SEED := 16102026
const NIGHT := 0.93
const ORIGIN := Vector3(35, 0.04, 25)
const STRIKE_INTERVAL := 6.0
const WARMUP_SECONDS := 8.0
const SOURCES := [
	"res://Main.tscn", "res://runtime/Weather.gd",
	"res://runtime/atmosphere/StormPresentation.gd",
	"res://runtime/atmosphere/LightningBolt3D.gd",
	"res://tests/measure/measure_lightning_storm.gd",
]

var weather
var storm
var folder := ""
var order := "before,after"
var seconds := 30.0
var include_movement := false
var capture_temporal := false
var temporal_only := false
var report: Dictionary = {}
var active_scenario := "night-stationary"
var probe: MotionProbe

class MotionProbe extends Node:
	var harness
	var elapsed := 0.0
	var moving := false
	func _physics_process(delta: float) -> void:
		if not is_instance_valid(harness.world): return
		elapsed += delta
		# Same real character physics and 12s outbound/return schedule per case.
		var direction := Vector3.ZERO
		if moving: direction = Vector3.RIGHT if fmod(elapsed, 24.0) < 12.0 else Vector3.LEFT
		harness.world.player.automatic_direction = direction

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or "--benchmark" not in args:
		fail("Rendered Main requires --no-save --benchmark; headless is invalid.", 2)
		return
	var version := Engine.get_version_info()
	if version["major"] != 4 or version["minor"] != 7 or version["patch"] != 2 or not ClassDB.class_exists("CSharpScript"):
		fail("Launch with Godot 4.7.2 .NET after building Harbor.csproj.", 2)
		return
	for arg in args:
		if arg.begins_with("--out-dir="): folder = arg.trim_prefix("--out-dir=")
		if arg.begins_with("--order="): order = arg.trim_prefix("--order=")
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		if arg == "--include-movement": include_movement = true
		if arg == "--capture-temporal": capture_temporal = true
		if arg == "--temporal-only": temporal_only = true
	if not is_finite(seconds) or seconds < 30.0:
		fail("--seconds must be finite and >=30.", 2)
		return
	for variant in order.split(",", true):
		if variant not in ["before", "after"]:
			fail("--order accepts before and after only.", 2)
			return
	if folder.is_empty():
		fail("Supply --out-dir=<exclusive empty directory>; baseline is never overwritten.", 2)
		return
	folder = ProjectSettings.globalize_path(folder)
	if DirAccess.dir_exists_absolute(folder):
		var existing := DirAccess.open(folder)
		if existing == null or not existing.get_files().is_empty() or not existing.get_directories().is_empty():
			fail("Output directory must be empty: " + folder, 2)
			return
	elif DirAccess.make_dir_recursive_absolute(folder) != OK:
		fail("Cannot create output directory: " + folder, 2)
		return
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_move_to_foreground()
	report = {
		"status":"running", "scene":"res://Main.tscn", "order":order,
		"out_dir":folder, "start_unix":Time.get_unix_time_from_system(),
		"seed":FIXED_SEED, "seconds_per_case":seconds, "warmup_seconds":WARMUP_SECONDS,
		"target_ms":16.67, "regression_confirmation_percent":5,
		"cadence":"DIAGNOSTIC: forced production trigger_lightning every ~6s; natural timer suppressed equally in both variants",
		"comparison":"before removes only visible bolt; production flash, rain, thunder, traffic and NPCs remain active",
		"load_control":"Fresh Main and equal seeds per case; living traffic/NPC trajectories remain frame-rate dependent. Inspect counts and route distance before comparison.",
		"notes":"No automatic FPS or flicker approval. External process isolation and driver version must be checked by operator. GPU timing may be unavailable/zero on this renderer.",
		"source_hashes":source_hashes(), "cases":[], "temporal":{},
	}
	if not save_report(): return
	var scenarios := ["night-stationary"]
	if include_movement: scenarios.append("night-moving")
	if temporal_only: scenarios.clear()
	for scenario in scenarios:
		active_scenario = scenario
		var round_index := 0
		for variant in order.split(",", true):
			if not await prepare_case(variant): return
			print("LIGHTNING_SAMPLE_BEGIN ", scenario, " ", variant, " #", round_index)
			var warmup := await sample_storm(WARMUP_SECONDS)
			reset_phase()
			var before := snapshot()
			var data := await sample_storm(seconds)
			var item := {
				"scenario":scenario, "variant":variant, "round":round_index,
				"environment":environment_config(), "start":before, "end":snapshot(),
				"warmup":warmup, "sample":data,
				"legacy_storm_without_bolt_api":not has_property(storm, &"bolts_enabled"),
			}
			item["distance_m"] = float(world.player.travelled) - float(before["player_travelled"])
			item["valid_window"] = data["summary"]["seconds"] >= 30.0
			item["needs_review"] = data["unfocused_frames"] > 0 or data["rejected_triggers"] > 0 or data["paused_frames"] > 0
			if scenario == "night-moving" and item["distance_m"] < seconds:
				item["needs_review"] = true
				item["movement_warning"] = "Less than 1 m/s average; inspect obstruction before comparing."
			report["cases"].append(item)
			if not save_report(): return
			print("LIGHTNING_SAMPLE_END ", scenario, " ", variant, " ", JSON.stringify(data["summary"]))
			await dispose_world()
			round_index += 1
	if capture_temporal or temporal_only:
		active_scenario = "night-stationary"
		# Explicit before-only invocation must also work before the patch exists.
		var capture_variant := "after" if "after" in order.split(",") else "before"
		if not await prepare_case(capture_variant): return
		await sample_storm(WARMUP_SECONDS)
		reset_phase()
		if not await capture_strike(capture_variant): return
		await dispose_world()
	report["source_hashes_end"] = source_hashes()
	report["sources_unchanged"] = report["source_hashes"] == report["source_hashes_end"]
	report["status"] = "collected_requires_review"
	report["end_unix"] = Time.get_unix_time_from_system()
	if not save_report(): return
	print("LIGHTNING_REPORT ", folder.path_join("report.json"))
	quit()

func prepare_case(variant: String) -> bool:
	seed(FIXED_SEED)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		fail("Main session readiness timeout.", 3)
		return false
	world.dispatch.router.nearest_edge(world.player.position)
	if not OS.get_environment("HARBOR_NO_CSHARP").is_empty() or world.dispatch.router._native == null:
		fail("Requires Godot 4.7.2 .NET and compiled Harbor.csproj with actual native C# router.", 3)
		return false
	weather = world.session.weather
	storm = weather.storm
	if not is_instance_valid(storm) or not storm.has_method("trigger_lightning"):
		fail("Production StormPresentation is unavailable.", 3)
		return false
	var modern := has_property(storm, &"bolts_enabled")
	if variant == "after" and (not modern or not has_property(storm, &"bolt")):
		fail("after needs the new bolt API. Record --order=before before patching StormPresentation.", 3)
		return false
	if modern: storm.set("bolts_enabled", variant == "after")
	var bolt: Variant = storm.get("bolt") if has_property(storm, &"bolt") else null
	if variant == "after" and (not is_instance_valid(bolt) or not bolt is Node3D or not bolt.has_method("clear") or not bolt.has_method("set_strength")):
		fail("after requires a live Node3D bolt with clear/set_strength.", 3)
		return false
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.5
	world.player.teleport(ORIGIN)
	world.camera.set_process_unhandled_input(false)
	world.camera.set_process_input(false)
	world.driving.set_process_unhandled_input(false)
	# Keep Main's actual gameplay Camera3D, orthographic, standard top-down offset.
	world.camera.target = world.player
	world.camera.locked = true
	world.camera.preview_view = false
	world.camera.heading = 0.0
	world.camera.offset = Vector3(0, 25.3, 25.3)
	world.camera.target_size = 32.0
	world.camera.size = 32.0
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.initialized = false
	var controls := root.get_node("GameInput")
	controls.using_gamepad = false
	controls.touch_move = Vector2.ZERO
	weather.weather_state = 2
	weather.weather_locked = true
	weather.weather_timer = 100000.0
	weather.time_of_day = NIGHT
	weather.rain_level = 1.0
	weather.coastal_wetness = 1.0
	weather._update()
	probe = MotionProbe.new()
	probe.harness = self
	probe.process_physics_priority = -10
	root.add_child(probe)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	reset_phase()
	await physics_frame
	return true

func reset_phase() -> void:
	probe.elapsed = 0.0
	probe.moving = active_scenario == "night-moving"
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(ORIGIN)
	world.camera.initialized = false
	storm.cancel()
	storm.lightning_timer = 100000.0
	storm.flashes = 0
	var bolt: Variant = storm.get("bolt") if has_property(storm, &"bolt") else null
	if is_instance_valid(bolt) and bolt.has_method("clear"): bolt.call("clear")
	for target in [storm, weather]:
		var key := &"_rng" if target == storm else &"_weather_rng"
		if has_property(target, key):
			var rng: Variant = target.get(key)
			if rng is RandomNumberGenerator: rng.seed = FIXED_SEED
	weather._update()

func sample_storm(duration: float) -> Dictionary:
	var frames: Array[float] = []
	var result := {"frames_ms":frames, "cpu_ms":[], "physics_ms":[], "gpu_ms":[], "render_cpu_ms":[], "draw_calls":[], "frame_elapsed_ms":[], "strikes":[], "unfocused_frames":0, "paused_frames":0, "rejected_triggers":0}
	reset_phase()
	result["start_unix"] = Time.get_unix_time_from_system()
	var start := Time.get_ticks_usec()
	var previous := start
	var next_strike := 1.0
	while Time.get_ticks_usec() - start < int(duration * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - start) / 1000000.0
		result["frames_ms"].append(float(now - previous) / 1000.0)
		result["frame_elapsed_ms"].append(float(now - start) / 1000.0)
		previous = now
		result["cpu_ms"].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		result["physics_ms"].append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		result["gpu_ms"].append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		result["render_cpu_ms"].append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		result["draw_calls"].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if not DisplayServer.window_is_focused(): result["unfocused_frames"] += 1
		if paused: result["paused_frames"] += 1
		if elapsed >= next_strike:
			var accepted: bool = storm.trigger_lightning()
			var bolt: Variant = storm.get("bolt") if has_property(storm,&"bolt") else null
			result["strikes"].append({"elapsed_ms":elapsed * 1000.0, "scheduled_ms":next_strike * 1000.0, "accepted":accepted,"bolt_visible":is_instance_valid(bolt) and bolt.visible,"point":str(storm.get("strike_position")) if has_property(storm,&"strike_position") else "legacy", "frame":Engine.get_process_frames()})
			if not accepted: result["rejected_triggers"] += 1
			next_strike += STRIKE_INTERVAL
		# Prevent additional natural triggers; leave production envelope/audio intact.
		storm.lightning_timer = 100000.0
	result["end_unix"] = Time.get_unix_time_from_system()
	result["summary"] = stats(frames)
	probe.moving = false
	world.player.automatic_direction = Vector3.ZERO
	return result

func capture_strike(variant: String) -> bool:
	# Continuous post-draw readbacks are deliberately AFTER all benchmark windows.
	# Bounded 30s sequence, every rendered frame; capture cost is never FPS evidence.
	var timeline: Array[Dictionary] = []
	var triggers: Array[Dictionary] = []
	var previous_draw := -1
	var skipped_draws := 0
	var next_strike := 1.0
	var peak_strength := 0.0
	var peak_image: Image
	var original_cap := Engine.max_fps
	Engine.max_fps = 60
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 30000000 and timeline.size() < 2400:
		var elapsed := (Time.get_ticks_usec()-start)/1000000.0
		probe.moving = elapsed >= 10.0 and elapsed < 20.0
		weather.time_of_day = NIGHT if elapsed < 20.0 else .45
		if elapsed >= next_strike:
			var accepted: bool = storm.trigger_lightning()
			triggers.append({"seconds":elapsed,"accepted":accepted,"point":str(storm.get("strike_position")) if has_property(storm,&"strike_position") else "legacy"})
			next_strike += 7.0
		storm.lightning_timer = 100000.0
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var draw := Engine.get_frames_drawn()
		if previous_draw >= 0: skipped_draws += maxi(0,draw-previous_draw-1)
		previous_draw = draw
		var image := root.get_texture().get_image()
		image.resize(960, 540)
		var filename := "strike-%04d.jpg" % timeline.size()
		if image.save_jpg(folder.path_join(filename),.88) != OK:
			Engine.max_fps = original_cap
			fail("Cannot write temporal JPEG.",4)
			return false
		var strength: float = storm.envelope(storm.flash_age)
		if strength > peak_strength:
			peak_strength = strength
			peak_image = image.duplicate() as Image
		var bolt: Variant = storm.get("bolt") if has_property(storm,&"bolt") else null
		timeline.append({"elapsed_ms":float(now - start) / 1000.0, "unix":Time.get_unix_time_from_system(), "monotonic_us":now, "frame":draw, "flash_age":storm.flash_age, "strength":strength, "bolt_visible":is_instance_valid(bolt) and bolt.visible,"file":filename,"phase":"night-static" if elapsed < 10 else "night-moving" if elapsed < 20 else "day-static"})
	Engine.max_fps = original_cap
	probe.moving = false
	world.player.automatic_direction = Vector3.ZERO
	if peak_image != null: peak_image.save_png(folder.path_join("strike-peak.png"))
	var largest_gap_ms := 0.0
	for i in timeline.size():
		if i > 0: largest_gap_ms = maxf(largest_gap_ms, timeline[i]["elapsed_ms"] - timeline[i - 1]["elapsed_ms"])
	report["temporal"] = {"variant":variant, "separate_from_benchmark":true,"triggers":triggers,"duration_seconds":(Time.get_ticks_usec()-start)/1000000.0,"skipped_rendered_frames":skipped_draws,"capture_fps_cap":60,"original_fps_cap":original_cap,"frames":timeline,"max_gap_ms":largest_gap_ms,"resolution":"960x540","frame_limit_hit":timeline.size() >= 2400,"notes":"Continuous rendered post-draw frames; readback/resize/JPEG can slow capture. Every drawn frame is recorded, with timestamps. Forced 7s strike cadence for visual inspection only. Night static/moving and day static; no FPS approval from capture."}
	return save_report()

func has_property(object: Object, key: StringName) -> bool:
	if not is_instance_valid(object): return false
	for property in object.get_property_list():
		if property["name"] == key: return true
	return false

func snapshot() -> Dictionary:
	return {"player_position":str(world.player.global_position), "player_travelled":world.player.travelled, "camera_position":str(world.camera.global_position), "camera_rotation":str(world.camera.global_rotation), "camera_size":world.camera.size, "population":world.people.size(), "traffic_children":world.traffic.get_child_count(), "time_of_day":weather.time_of_day, "weather_state":weather.weather_state, "rain_level":weather.rain_level, "wetness":weather.coastal_wetness, "flashes":storm.flashes, "thunder_count":storm.thunder_count, "paused":paused}

func environment_config() -> Dictionary:
	var settings := root.get_node("V2Settings")
	return {"engine":Engine.get_version_info(), "executable":OS.get_executable_path(), "native_csharp":true, "gpu":RenderingServer.get_video_adapter_name(), "gpu_vendor":RenderingServer.get_video_adapter_vendor(), "renderer":RenderingServer.get_current_rendering_method(), "rendering_driver":RenderingServer.get_current_rendering_driver_name(), "display_server":DisplayServer.get_name(), "resolution":str(root.size), "viewport_resolution":str(root.get_visible_rect().size), "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "physics_ticks":Engine.physics_ticks_per_second, "time_scale":Engine.time_scale, "msaa":root.msaa_3d, "render_scale":root.scaling_3d_scale, "shadow_quality":settings.shadow_quality, "driver_version":"not queried; record externally", "command_line":OS.get_cmdline_args(), "user_args":OS.get_cmdline_user_args()}

func source_hashes() -> Dictionary:
	var hashes := {}
	for path in SOURCES:
		hashes[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent (legacy baseline allowed)"
	return hashes

func save_report() -> bool:
	var file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report in " + folder)
		quit(4)
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return true

func fail(message: String, code: int) -> void:
	push_error(message)
	if not report.is_empty():
		report["status"] = "failed"
		report["error"] = message
		save_report()
	quit(code)

func dispose_world() -> void:
	probe.queue_free()
	world.queue_free()
	await process_frame
	world = null
	weather = null
	storm = null
