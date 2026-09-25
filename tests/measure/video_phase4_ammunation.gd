extends SceneTree
## Real Main, physical walk-up admission, first visit, 30 s steady room, revisit.
## --no-save --skip-arrival --benchmark --population=40 --label=before --evidence-dir=ABSOLUTE
## --causal-headless is construction diagnosis only; never certifies FPS.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SOURCE_PATHS := ["runtime/FullSession.gd", "world/places/NativePlace.gd", "world/places/AmmunationModel.gd", "assets/regions/source/guns/ammunation/AmmunationArt.gd", "assets/regions/source/scripts/player/WeaponFinish3D.gd", "runtime/WeaponShopEntrance.gd"]
const COLUMNS := ["interval_ms", "process_ms", "physics_ms", "main_render_cpu_ms", "main_render_gpu_ms", "render_setup_cpu_ms", "draw_calls", "nodes"]
var world: Node3D
var label := "before"
var directory := ""
var causal_headless := false
var uncapped := false
var execution_condition := "unspecified_exclusivity"
var phase := ""
var phase_started := 0
var previous := 0
var current_rows: Array = []
var segments: Dictionary = {}
var events: Array = []
var construction: Array = []
var failures: Array[String] = []
var source_hashes: Dictionary = {}
var room_started := 0
var model_started := 0
var model_finished := 0
var room_construction: Dictionary = {}
var room_walk := false
var waypoint := 0
var route := [Vector3(-1.0, 0, 1.7), Vector3(1.0, 0, 1.7), Vector3(1.0, 0, -.7), Vector3(-1.0, 0, -.7)]
var context: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--evidence-dir="): directory = arg.trim_prefix("--evidence-dir=")
		if arg.begins_with("--condition="): execution_condition = arg.trim_prefix("--condition=")
	causal_headless = "--causal-headless" in args
	uncapped = "--uncapped" in args
	if "--no-save" not in args or "--skip-arrival" not in args or "--benchmark" not in args or directory.is_empty():
		push_error("Requires --no-save --skip-arrival --benchmark --evidence-dir=ABSOLUTE")
		quit(2)
		return
	if DisplayServer.get_name() == "headless" and not causal_headless:
		push_error("FPS benchmark requires rendered Main")
		quit(2)
		return
	for path in SOURCE_PATHS: source_hashes[path] = FileAccess.get_sha256("res://" + path)
	seed(21092026)
	Engine.max_fps = 0 if uncapped else 60
	if not causal_headless:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(2560, 1440))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if uncapped else DisplayServer.VSYNC_ENABLED)
		root.size = Vector2i(2560, 1440)
	root.msaa_3d = Viewport.MSAA_2X
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("benchmark_trace", true)
	root.add_child(world)
	if not await _wait_until(func(): return world.session != null and world.session.ready_for_play and world.people.size() >= world.production.requested_population, 80.0):
		failures.append("Main readiness/population timeout")
		await _finish()
		return
	if not await _wait_until(_curtain_finished, 10.0): failures.append("Startup curtain did not finish")
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.speed = 3.5
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .38
	world.session.state.world_state.time = .38
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.session.weather._update()
	world.child_entered_tree.connect(_world_child_entered)
	var definition: Dictionary = PLACES.get_definition("harbor_ammunation")
	var door: Vector3 = world.session.weapon_shop_entrance._door_position("harbor_ammunation", definition)
	world.production.region.set_focus(door)
	world.player.teleport(door + Vector3(0, .08, 2.8))
	world.camera.heading = 0
	world.camera.target_size = 28
	world.camera.initialized = false
	if not await _wait_until(func(): return world.people.size() >= world.production.requested_population, 45.0):
		failures.append("Target area did not restore normal population before capture")
		await _finish()
		return
	await _seconds(5.0)
	context = _context()
	context["exterior_inventory"] = _inventory()
	if not await _entry("first_entry"):
		await _finish()
		return
	context["interior_inventory"] = _inventory()
	if not causal_headless:
		# Save the screenshot before warm-up; disk readback is not a frame sample.
		await _capture("first-inside")
		room_walk = true
		_begin("interior_warmup")
		await _seconds(5.0)
		_end()
		_begin("interior_steady_30s")
		await _seconds(30.0)
		_end()
		room_walk = false
		world.player.automatic_direction = Vector3.ZERO
		await _capture("steady-inside")
	# Use the same exit flow as gameplay, then retreat before walking back in.
	world.player.teleport(world.session.room.exit_position + Vector3(0, .08, -.95))
	for _i in 3: await physics_frame
	_begin("exit")
	world.player.automatic_direction = Vector3.BACK
	if not await _wait_until(func(): return world.session.state.place_id.is_empty(), 8.0): failures.append("Automatic exit failed")
	world.player.automatic_direction = Vector3.ZERO
	await _wait_until(func(): return not world.session.weapon_shop_entrance._leaving, 3.0)
	await _seconds(1.0)
	_end()
	if not failures.is_empty():
		await _finish()
		return
	world.player.teleport(door + Vector3(0, .08, 2.8))
	await _seconds(1.0)
	await _entry("second_entry")
	await _finish()

func _entry(name: String) -> bool:
	_begin(name)
	_event("walking_start")
	world.player.automatic_direction = Vector3.FORWARD
	var ok := await _wait_until(func(): return world.session.state.place_id == "harbor_ammunation", 8.0)
	world.player.automatic_direction = Vector3.ZERO
	_event("admitted" if ok else "admission_failed")
	await _seconds(2.0)
	_end()
	if not ok: failures.append(name + " did not reach interior")
	return ok

func _world_child_entered(node: Node) -> void:
	if node.get_script() == null or node.get_script().resource_path != "res://world/places/NativePlace.gd": return
	room_started = Time.get_ticks_usec()
	model_started = 0
	model_finished = 0
	room_construction = {"phase":phase, "room_start_usec":room_started, "definition":str(node.definition.id)}
	node.child_entered_tree.connect(_room_child_entered)
	node.ready.connect(func():
		var ended := Time.get_ticks_usec()
		room_construction["native_ready_ms"] = (ended-room_started)/1000.0
		room_construction["load_before_model_ms"] = (model_started-room_started)/1000.0 if model_started > 0 else -1
		room_construction["art_ready_ms"] = (model_finished-model_started)/1000.0 if model_finished > 0 else -1
		room_construction["adapter_after_art_ms"] = (ended-model_finished)/1000.0 if model_finished > 0 else -1
		construction.append(room_construction.duplicate())
		_event("room_ready")
	, CONNECT_ONE_SHOT)

func _room_child_entered(node: Node) -> void:
	if node.get_script() == null or node.get_script().resource_path != "res://world/places/AmmunationModel.gd": return
	model_started = Time.get_ticks_usec()
	node.ready.connect(func(): model_finished = Time.get_ticks_usec(), CONNECT_ONE_SHOT)

func _process(_delta: float) -> bool:
	if phase.is_empty(): return false
	var now := Time.get_ticks_usec()
	current_rows.append([
		(now-previous)/1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		RenderingServer.get_frame_setup_time_cpu(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	])
	previous = now
	if room_walk and is_instance_valid(world.session.room):
		var destination: Vector3 = world.session.room.to_global(route[waypoint])
		var direction: Vector3 = destination - world.player.global_position
		direction.y = 0
		if direction.length() < .25: waypoint = (waypoint+1)%route.size()
		world.player.automatic_direction = direction.normalized()
	return false

func _begin(name: String) -> void:
	phase = name
	phase_started = Time.get_ticks_usec()
	previous = phase_started
	current_rows = []

func _end() -> void:
	if phase.is_empty(): return
	var summaries := {}
	for column in COLUMNS.size():
		var values: Array[float] = []
		for row in current_rows: values.append(float(row[column]))
		summaries[COLUMNS[column]] = _stats(values, column == 0)
	segments[phase] = {"started_usec":phase_started,"ended_usec":Time.get_ticks_usec(),"columns":COLUMNS,"rows":current_rows,"summary":summaries,"end_position":str(world.player.global_position)}
	print("PHASE4 ", phase, " ", JSON.stringify(summaries.get("interval_ms", {})))
	phase = ""

func _event(name: String) -> void:
	events.append({"name":name,"phase":phase,"usec":Time.get_ticks_usec(),"position":str(world.player.global_position)})

func _stats(values: Array[float], frames := false) -> Dictionary:
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
	var result := {"samples":values.size(),"mean":total/values.size(),"p50":sorted[int((sorted.size()-1)*.50)],"p95":sorted[int((sorted.size()-1)*.95)],"p99":sorted[int((sorted.size()-1)*.99)],"max":sorted[-1]}
	if frames:
		result["seconds"] = total/1000.0
		result["fps"] = values.size()*1000.0/total if total > 0 else 0.0
		result["over_33_3_ms"] = slow
		result["over_66_7_ms"] = very_slow
	return result

func _context() -> Dictionary:
	return {"scene":"res://Main.tscn","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"msaa":root.msaa_3d,"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"seed":21092026,"requested_population":world.production.requested_population,"population":world.people.size(),"vehicles":world.production.vehicles.size(),"weather":world.session.weather.weather_state,"time":world.session.weather.time_of_day,"camera_size":world.camera.size,"causal_headless":causal_headless,"normal_settings":not uncapped,"notes":"Main render CPU/GPU exclude unrelated viewports. TIME_PROCESS includes engine work and is not pure GDScript CPU. Wall intervals include pacing/waits; do not subtract overlapping monitors to infer wait time. First entry caches are process-cold, OS/driver caches may already be warm. Execution condition recorded explicitly; no personal save writes."}

func _inventory() -> Dictionary:
	var counts := {"meshes":0,"materials":0,"lights":0,"visible_lights":0,"shadow_lights":0,"viewports":[]}
	var materials := {}
	for node in world.find_children("*", "", true, false):
		if node is MeshInstance3D:
			counts.meshes += 1
			if node.material_override != null: materials[node.material_override.get_instance_id()] = true
		if node is Light3D:
			counts.lights += 1
			if node.is_visible_in_tree(): counts.visible_lights += 1
			if node.shadow_enabled: counts.shadow_lights += 1
		if node is SubViewport: counts.viewports.append({"path":str(node.get_path()),"size":str(node.size),"update_mode":node.render_target_update_mode})
	counts.materials = materials.size()
	if is_instance_valid(world.session.room):
		counts["room_meshes"] = world.session.room.find_children("*", "MeshInstance3D", true, false).size()
		counts["room_lights"] = world.session.room.find_children("*", "Light3D", true, false).size()
	return counts

func _curtain_finished() -> bool:
	for child in world.get_children():
		if child.get_script() == preload("res://runtime/StartupCurtain.gd"): return false
	return true

func _wait_until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_usec() + int(seconds*1000000)
	while Time.get_ticks_usec() < deadline:
		if predicate.call(): return true
		await physics_frame
	return false

func _seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds*1000000)
	while Time.get_ticks_usec() < deadline: await process_frame

func _capture(suffix: String) -> void:
	if causal_headless: return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join(label + "-" + suffix + ".png")) != OK: failures.append("Capture failed: " + suffix)

func _finish() -> void:
	_end()
	DirAccess.make_dir_recursive_absolute(directory)
	var report := {"label":label,"execution_condition":execution_condition,"fps_certified":false,"context":context,"source_hashes":source_hashes,"segments":segments,"construction":construction,"events":events,"failures":failures,"runtime_costs":world.get_meta("perf_costs",[]) if is_instance_valid(world) else []}
	var file := FileAccess.open(directory.path_join(label + ".json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write phase4 evidence")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PHASE4 CONSTRUCTION ", JSON.stringify(construction))
	print("PHASE4 FAILURES ", JSON.stringify(failures))
	if is_instance_valid(world): world.queue_free()
	for _i in 6: await process_frame
	quit(0 if failures.is_empty() else 1)
