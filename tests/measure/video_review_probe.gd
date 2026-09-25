extends "res://tests/measure/measure_full.gd"
## Rendered production scene. Never run with --headless except --check-only.
## --no-save --skip-arrival --population=40 --scenario=ammunation
## --label=before-ammunation --evidence-dir=res://evidence/video-review-20260924
## Scenarios: street, ammunation, bank, port. Add --drive for the street route.
## 5 seconds of warm-up and 30 seconds of steady sampling; room construction
## and the following 2 seconds are recorded separately as first-entry evidence.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var scenario := "street"
var entry_samples: Array[float] = []
var entry_cpu: Array[float] = []
var entry_recording := false
var entry_previous := 0
var entry_started := 0
var entry_elapsed_ms := 0.0
var entry_success := false
var load_started := 0
var startup_elapsed_ms := 0.0
var sample_start_position := Vector3.ZERO
var sample_start_population := 0
var sample_start_cars := 0

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("Video review probe requires --no-save")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
	if scenario not in ["street", "ammunation", "bank", "port"]:
		push_error("Unknown video review scenario: " + scenario)
		quit(2)
		return
	load_started = Time.get_ticks_usec()
	await super.run()
	started = 0
	if not is_instance_valid(world) or world.session == null or not world.session.ready_for_play: return
	startup_elapsed_ms = float(Time.get_ticks_usec() - load_started) / 1000.0
	# Apply only to this process. Do not persist settings.cfg.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_2X
	Engine.max_fps = 60
	world.session.weather.time_of_day = 0.45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	if scenario in ["ammunation", "bank"]:
		if driving_mode:
			push_error("Room probe cannot run with --drive")
			quit(2)
			return
		var place_id := "harbor_ammunation" if scenario == "ammunation" else "harbor_bank"
		var definition: Dictionary = PLACES.get_definition(place_id)
		world.player.speed = 0.0
		world.player.automatic_direction = Vector3.ZERO
		world.production.region.set_focus(definition.entry_position)
		# A teleport is setup, excluded from the first-entry and steady samples.
		world.player.teleport(definition.entry_position + Vector3.UP * 0.08)
		for frame in 120: await physics_frame
		entry_previous = Time.get_ticks_usec()
		entry_started = entry_previous
		entry_recording = true
		# This invokes the real room admission/physics contract. The exterior
		# walk-up zoom is not measured; it needs a separate end-to-end capture.
		entry_success = await world.session.enter_place(place_id, false, place_id)
		entry_elapsed_ms = float(Time.get_ticks_usec() - entry_started) / 1000.0
		var tail_started := Time.get_ticks_usec()
		while Time.get_ticks_usec() - tail_started < 2000000: await process_frame
		entry_recording = false
		if not entry_success:
			push_error("Video review room admission failed: " + place_id)
			quit(1)
			return
		var point: Vector3 = world.player.position
		route = PackedVector3Array([point, point])
	elif scenario == "port":
		if driving_mode:
			push_error("Port stationary probe cannot run with --drive")
			quit(2)
			return
		var point: Vector3 = world.production.nearest_road(Vector3(299, 0, 183))
		world.production.region.set_focus(point)
		for frame in 300:
			await physics_frame
			if world.production.region.prepare_collision_at(point): break
		world.player.teleport(point + Vector3.UP * 0.08)
		world.player.speed = 0.0
		route = PackedVector3Array([point, point])
		for frame in 120: await physics_frame
	cold.clear()
	samples.clear()
	cpu.clear()
	physics.clear()
	measuring = false
	waypoint = 0
	sample_start_position = world.player.position
	sample_start_population = world.people.size()
	sample_start_cars = world.production.vehicles.size()
	started = Time.get_ticks_usec()
	previous = started

func _process(delta: float) -> bool:
	if entry_recording:
		var now := Time.get_ticks_usec()
		entry_samples.append(float(now - entry_previous) / 1000.0)
		entry_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		entry_previous = now
	return super._process(delta)

func finish() -> void:
	var directory := evidence_dir if not evidence_dir.is_empty() else "res://evidence/video-review-20260924"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var detail := {
		"scenario": scenario,
		"seed": 21092026,
		"scene": "res://Main.tscn",
		"startup_elapsed_ms": startup_elapsed_ms,
		"sample_start_position": str(sample_start_position),
		"sample_end_position": str(world.player.position),
		"sample_start_population": sample_start_population,
		"sample_end_population": world.people.size(),
		"sample_start_cars": sample_start_cars,
		"sample_end_cars": world.production.vehicles.size(),
		"weather_state": world.session.weather.weather_state,
		"time_of_day": world.session.weather.time_of_day,
		"camera_position": str(world.camera.global_position),
		"camera_size": world.camera.size,
		"entry_success": entry_success,
		"entry_admission_elapsed_ms": entry_elapsed_ms,
		"entry_intervals_ms": entry_samples,
		"entry_cpu_ms": entry_cpu,
		"entry_summary": stats(entry_samples) if not entry_samples.is_empty() else {},
		"note": "Room samples use real enter_place but exclude exterior walking/zoom. Port is stationary, not traversal. Process inventory must establish exclusivity externally. CPU monitor is not a GPU profile."
	}
	var file := FileAccess.open(directory.path_join(label + "-context.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write video review evidence: " + directory)
		quit(1)
		return
	file.store_string(JSON.stringify(detail, "\t"))
	file.close()
	evidence_dir = directory
	await super.finish()
