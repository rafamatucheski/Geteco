extends SceneTree
## Main renderizado .NET: --no-save --benchmark --output=<diretorio novo> [--uncapped]
## --scenario=all|foot_portal|foot_inside|bike_portal|bike_inside|walk_transition
## Cada pose mede 8 s de aquecimento + 30 s; capturas ficam fora da amostra.
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const SOURCES := ["tests/measure/measure_mountain_tunnel_camera.gd", "scripts/CameraRig.gd", "world/regions/WorldConnection3D.gd", "scripts/Actor.gd", "scripts/Vehicle.gd", "scripts/Driving.gd", "gameplay/VehicleInterior.gd", "world/regions/NativeRegion.gd", "runtime/ProductionWorld.gd", "gameplay/dispatch/RoadGraphSearch.cs", "project.godot"]
var world
var bike: CharacterBody3D
var output := ""
var scenario := "all"
var report := {"scenarios": [], "failures": [], "source_sha256": {}}

func _initialize() -> void:
	run.call_deferred()

func fail(message: String) -> void:
	report.failures.append(message)
	push_error(message)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or "--benchmark" not in args or output.is_empty():
		push_error("Requires Godot .NET rendered, --no-save --benchmark and unique --output")
		quit(2)
		return
	output = ProjectSettings.globalize_path(output)
	if FileAccess.file_exists(output.path_join("report.json")):
		push_error("Output already has report.json; select a new directory")
		quit(2)
		return
	if scenario not in ["all", "foot_portal", "foot_inside", "bike_portal", "bike_inside", "walk_transition"]:
		push_error("Unknown tunnel scenario")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	for path in SOURCES: report.source_sha256[path] = FileAccess.get_sha256("res://" + path)
	seed(6102026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save:
		fail("Main startup/no-save admission failed")
		await finish()
		return
	# Verify a native graph operation; a mono executable alone cannot exclude fallback.
	var router := preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
	router.configure(world.production.traffic_routes)
	var vertices: Array = world.production.traffic_routes.vertices
	if vertices.size() > 1: router.plan(vertices[0], vertices[vertices.size() / 2])
	report["native_route_backend"] = router._native != null
	if router._native == null:
		fail("C# road graph unavailable; refusing silent GDScript fallback")
		await finish()
		return
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world.camera.set_process_unhandled_input(false)
	var intro: Dictionary = world.session.state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	if not world.session.state.intro.restore_snapshot(intro):
		fail("Completed intro fixture refused")
		await finish()
		return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.session.weather._update()
	if "--uncapped" in args:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	report["environment"] = environment()
	for label in ["foot_portal", "foot_inside", "bike_portal", "bike_inside"]:
		if scenario != "all" and scenario != label: continue
		var point := Vector3(CONNECTION.TUNNEL_START_X - 3.0, .2, CONNECTION.CENTER_Z + 5.7)
		if label.ends_with("inside"): point.x = (CONNECTION.TUNNEL_START_X + CONNECTION.TUNNEL_END_X) * .5
		if not await stage(point, label.begins_with("bike")): break
		print("TUNNEL_MEASURE_BEGIN ", label)
		var row := {"label": label, "requested_pose": str(point), "before": state()}
		row["warmup"] = await sample(8.0)
		await shot(label + "_start")
		row["start"] = state()
		row["steady"] = await sample(30.0)
		row["end"] = state()
		await shot(label + "_end")
		report.scenarios.append(row)
		print("TUNNEL_MEASURE ", label, " ", JSON.stringify(row.steady.summary))
		write_report()
	if scenario in ["all", "walk_transition"]: await walk_transition()
	await finish()

func stage(point: Vector3, riding: bool) -> bool:
	if world.driving.occupied and not riding:
		if not world.driving.leave():
			fail("Cannot leave motorcycle for walking scenario")
			return false
		if not await wait_boarding(): return false
	world.player.set_physics_process(false)
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(point)
	if riding and is_instance_valid(bike): bike.place(point, 0.0)
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	world.production.region.set_focus(point)
	# Stage only: do not let an actor fall before the real streamed pavement arrives.
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production.region.pending.is_empty() and world.production.region.build_jobs.is_empty(): break
	if not world.production.region.pending.is_empty() or not world.production.region.build_jobs.is_empty():
		fail("Terrain streaming did not settle at tunnel")
		return false
	if riding:
		if not is_instance_valid(bike):
			bike = preload("res://scripts/Vehicle.gd").new()
			bike.archetype = "bike_urban"
			bike.vehicle_id = "tunnel_camera_measure_bike"
			bike.position = point
			world.add_child(bike)
			world.production.vehicles.append(bike)
		bike.place(point, 0.0)
		bike.set_physics_process(true)
		if not world.driving.occupied:
			world.player.teleport(bike.driver_door_anchor(-1))
			for frame in 3: await physics_frame
			if not world.driving._begin_entry(bike, -1):
				fail("Motorcycle entry admission failed")
				return false
			if not await wait_boarding(): return false
		bike.external_input = true
		bike.throttle_input = 0.0
		bike.steer_input = 0.0
		bike.brake_input = true
	else:
		world.player.visual.rotation.y = 0.0
		world.player.set_physics_process(true)
	world.camera.initialized = false
	world.session.weather._update()
	return true

func wait_boarding() -> bool:
	for frame in 300:
		await physics_frame
		if not world.driving.is_body_transition_active(): return true
	fail("Motorcycle body transition timeout")
	return false

func sample(seconds: float) -> Dictionary:
	var intervals: Array[float] = []
	var cpu: Array[float] = []
	var physics: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	return {"summary": stats(intervals), "frame_intervals_ms": intervals, "cpu_process_ms": cpu, "physics_ms": physics}

func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	return {"frames": values.size(), "seconds": total / 1000.0, "fps": values.size() * 1000.0 / total, "p50_ms": sorted[int((sorted.size()-1)*.5)], "p95_ms": sorted[int((sorted.size()-1)*.95)], "p99_ms": sorted[int((sorted.size()-1)*.99)], "max_ms": sorted[-1], "over_33_3_ms": slow, "over_66_7_ms": very_slow}

func state() -> Dictionary:
	var player: CharacterBody3D = world.player
	var point: Vector3 = bike.global_position if world.driving.occupied else player.global_position
	var exclude: Array[RID] = [player.get_rid()]
	if is_instance_valid(bike): exclude.append(bike.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .4, point - Vector3.UP * 2.0, 1, exclude)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	return {"position": str(point), "player_position": str(player.global_position), "player_on_floor": player.is_on_floor(), "occupied": world.driving.occupied, "floor_position": str(hit.get("position", Vector3.INF)), "floor_body": str(hit.get("collider", "")), "camera_position": str(world.camera.global_position), "camera_projection": world.camera.projection, "camera_fov": world.camera.fov, "camera_size": world.camera.size, "camera_heading": world.camera.heading, "tunnel_blend": world.camera._tunnel_chase_blend, "camera_z_from_corridor": world.camera.global_position.z - CONNECTION.CENTER_Z, "population": world.people.size(), "vehicles": world.production.vehicles.size(), "chunks": world.production.region.chunks.size(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(label + ".png")) != OK: fail("Screenshot failed: " + label)

func walk_transition() -> void:
	var start := Vector3(CONNECTION.TUNNEL_START_X - 6.0, .2, CONNECTION.CENTER_Z + 5.7)
	if not await stage(start, false): return
	await sample(3.0)
	var row := {"label": "walk_transition", "start": state(), "trace": []}
	await shot("walk_transition_start")
	world.player.automatic_direction = Vector3.RIGHT
	world.player.speed = 3.5
	var began := Time.get_ticks_usec()
	var next_trace := began
	while Time.get_ticks_usec() - began < 6000000:
		await physics_frame
		if Time.get_ticks_usec() >= next_trace:
			var pose := state()
			pose["elapsed_ms"] = float(Time.get_ticks_usec() - began) / 1000.0
			row.trace.append(pose)
			next_trace += 100000
	world.player.automatic_direction = Vector3.ZERO
	row["end"] = state()
	row["crossed_portal"] = world.player.global_position.x > CONNECTION.TUNNEL_START_X + 3.0
	row["distance_x"] = world.player.global_position.x - start.x
	await shot("walk_transition_end")
	report.scenarios.append(row)
	print("TUNNEL_WALK crossed=", row.crossed_portal, " distance_x=", row.distance_x)

func environment() -> Dictionary:
	var settings := root.get_node_or_null("V2Settings")
	var selected := {}
	if settings != null:
		for key in ["resolution", "vsync", "msaa", "render_scale", "fps_limit", "shadow_quality", "brightness", "camera_view"]: selected[key] = settings.get(key)
	return {"scene": "Main.tscn", "engine": Engine.get_version_info().string, "executable": OS.get_executable_path(), "os": OS.get_name(), "os_version": OS.get_version(), "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "msaa": root.msaa_3d, "render_scale": root.scaling_3d_scale, "settings": selected, "seed": 6102026, "requested_population": world.production.requested_population, "population": world.people.size(), "vehicles": world.production.vehicles.size(), "weather": world.session.weather.weather_state, "time_of_day": world.session.weather.time_of_day, "no_save": world.production.no_save, "args": OS.get_cmdline_user_args(), "notes": "Production scene and camera, live traffic/NPC/physics. Stationary poses are staged before warmup. Walking trace uses real physics. CPU and physics monitors overlap; GPU/wait attribution unavailable. Screenshots excluded from frame samples; visual review required. Provisional target 60 FPS/16.67 ms; >5% p95/p99 regression requires an equivalent confirmation sample."}

func write_report() -> void:
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))

func finish() -> void:
	report["source_sha256_end"] = {}
	for path in SOURCES: report.source_sha256_end[path] = FileAccess.get_sha256("res://" + path)
	report["sources_stable"] = report.source_sha256 == report.source_sha256_end
	if not report.sources_stable: fail("Runtime or harness sources changed during measurement; comparison is invalid")
	write_report()
	print("TUNNEL_MEASURE_DONE output=", output, " failures=", report.failures.size())
	if is_instance_valid(world):
		world.queue_free()
		await process_frame
	quit(0 if report.failures.is_empty() else 1)
