extends SceneTree
## Main real, input normal e física intacta. Uma colocação inicial na rua e
## embarque normal; depois não reposiciona o carro durante a medição de direção.
## Uso: Godot .NET --path . --script res://tests/measure/measure_engine_design_drive.gd
##   -- --no-save --skip-arrival --label=engine-before --car=sport_coupe
## Acrescentar --legacy-engine-design para o comparativo do caminho anterior.
## --fixed-audio-abba mantém o carro em lenta/freio de mão e alterna somente
## o caminho de áudio no mesmo Main vivo; é diagnóstico local, não direção.
## O chamador compila Harbor.csproj e garante ausência de runtimes concorrentes.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const LEGACY_BANKS := preload("res://audio/EngineBankCache.gd")
const DESIGN_BANKS := preload("res://audio/EngineDesignBanks.gd")
const FIXED_AUDIO_MODES := ["legacy", "design", "design", "legacy"]
const INPUT_ACTIONS := ["accelerate", "brake", "handbrake", "move_left", "move_right", "move_up", "move_down"]
const SOURCE_PATHS := [
	"res://tests/measure/measure_engine_design_drive.gd", "res://project.godot", "res://Harbor.csproj",
	"res://.godot/mono/temp/bin/Debug/Harbor.dll", "res://scripts/Vehicle.gd", "res://runtime/ProductionWorld.gd",
	"res://audio/WorldAudio.gd", "res://audio/EngineBankCache.gd", "res://audio/VehicleEngineProfile.gd",
	"res://audio/FleetEngineDesign.gd", "res://audio/EngineDesignBanks.gd", "res://audio/EngineDesignVoice.gd",
	"res://audio/vehicle_ambience/NearbyVehicleAudio.gd", "res://audio/service_vehicles/ServiceVehicleAudio.gd",
	"res://audio/desert_cars/DesertCarAudio.gd", "res://audio/engine_design/manifest.json",
	"res://gameplay/NativeTrafficRoutes.gd", "res://tests/fixtures/NorthGatewayFixtures.gd",
]
var world: Variant
var car: CharacterBody3D
var route: Curve3D
var output := ""
var label := "engine-design"
var archetype := "sport_coupe"
var phase := "startup"
var phase_started := 0
var previous_frame := 0
var session_started := 0
var capturing := false
var finishing := false
var checks := 0
var failures: Array[String] = []
var frames: Array[Dictionary] = []
var events: Array[Dictionary] = []
var voice_samples: Array[Dictionary] = []
var voice_clock := 0.0
var initial_fingerprint := {}
var record_bus := -1
var recorder: AudioEffectRecord
var captured_voices: Array[Node] = []
var start_distance := 0.0
var measured_distance := 0.0
var peak_db := -100.0
var route_points: Array = []
var fixed_audio_abba := false
var previous_design_enabled := true
var design_flag_overridden := false
var fixed_phase_results: Array[Dictionary] = []

class ClearanceProbe extends CharacterBody3D:
	var half_width := 1.0
	var half_length := 2.0
	var shape: CollisionShape3D

func _initialize() -> void:
	create_timer(480.0 if "--fixed-audio-abba" in OS.get_cmdline_user_args() else 360.0).timeout.connect(func():
		if not finishing:
			check(false, "bounded session timeout")
			finish.call_deferred())
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("ENGINE_DRIVE ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func fingerprint() -> Dictionary:
	var result := {}
	for path in SOURCE_PATHS:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return result

func set_phase(next: String) -> void:
	phase = next
	phase_started = Time.get_ticks_usec()
	previous_frame = 0
	events.append({"phase": phase, "seconds": float(phase_started-session_started)/1000000.0,
		"memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"position": str(car.global_position) if is_instance_valid(car) else "none"})
	print("ENGINE_DRIVE_PHASE ", phase)

func release_inputs() -> void:
	for action in INPUT_ACTIONS: Input.action_release(action)

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Engine driving measurement requires rendered Main and --no-save")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=").validate_filename()
		if argument.begins_with("--car="): archetype = argument.trim_prefix("--car=")
		if argument == "--fixed-audio-abba": fixed_audio_abba = true
	if FLEET.spec(archetype).is_empty():
		push_error("Unknown measurement car: " + archetype)
		quit(2)
		return
	output = FIXTURE.output_dir(label)
	if output.is_empty(): quit(2); return
	initial_fingerprint = fingerprint()
	root.size = Vector2i(1280, 720)
	seed(20261016)
	# Erase external key bindings only in this measurement process; action_press
	# still goes through GameInput and the real controller/gearbox.
	for action in INPUT_ACTIONS: InputMap.action_erase_events(action)
	var initial := Vector3(64, .12, 82)
	var snapshot: Dictionary = FIXTURE.full_snapshot(initial, false)
	var checkpoint := FIXTURE.write_fixture(output, "checkpoint.json", snapshot)
	check(not checkpoint.is_empty(), "isolated validated checkpoint")
	if not failures.is_empty(): finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", checkpoint)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session != null and world.session.ready_for_play, "Main session ready")
	if not failures.is_empty(): finish(); return
	check(world.session.controller.no_save and world.production.store.path == checkpoint and not world.production.save_invalid, "personal saves remain isolated")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null, "native C# route backend active")
	if world.session.modal: world.session.close_menu()
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600.0
	world.session.weather._update()
	route = world.production.traffic_routes.route_near(initial)
	check(route != null and route.get_baked_length() > 30.0, "production road graph supplies a driving route")
	if not failures.is_empty(): finish(); return
	for index in route.point_count: route_points.append(str(route.get_point_position(index)))
	# Query an unspawned hull first: the checkpoint player/traffic may occupy
	# the route origin. A conservative 15% margin covers Fleet variant scales;
	# spawn_vehicle still applies its exact production clearance check afterward.
	var probe := ClearanceProbe.new()
	var dimensions: Array = FLEET.spec(archetype).bounds_size
	var hull := BoxShape3D.new()
	hull.size = Vector3(maxf(.65, float(dimensions[0])*1.15), clampf(float(dimensions[1])*1.15, 1.1, 3.6), float(dimensions[2])*1.15)
	probe.half_width = hull.size.x*.5
	probe.half_length = hull.size.z*.5
	probe.shape = CollisionShape3D.new()
	probe.shape.shape = hull
	probe.shape.position.y = hull.size.y*.5
	probe.add_child(probe.shape)
	var initial_offset := route.get_closest_offset(initial)
	var placed := false
	var spawn_at := Vector3.ZERO
	var spawn_yaw := 0.0
	for attempt in 24:
		var offset := fposmod(initial_offset+attempt*6.0, route.get_baked_length())
		var point := route.sample_baked(offset, true)
		var forward := route.sample_baked(fposmod(offset+1.0, route.get_baked_length()), true)-point
		var yaw := atan2(-forward.x, -forward.z)
		world.production.region.prepare_collision_at(point)
		await physics_frame
		if world.production.vehicle_position_clear(probe, point+Vector3.UP*.12, yaw):
			spawn_at = point+Vector3.UP*.12
			spawn_yaw = yaw
			placed = true
			break
	probe.free()
	check(placed, "clear route start found before measurement")
	if not failures.is_empty(): finish(); return
	car = world.production.spawn_vehicle(archetype, spawn_at, spawn_yaw)
	check(is_instance_valid(car), "requested real vehicle spawned at preflighted position")
	if not failures.is_empty(): finish(); return
	car.set_meta("radio_index", -1)
	check(await board(), "normal initial boarding completes")
	if not failures.is_empty(): finish(); return
	setup_capture()
	session_started = Time.get_ticks_usec()
	capturing = true
	if fixed_audio_abba:
		await run_fixed_audio_abba()
		finish()
		return
	set_phase("idle")
	await wait_seconds(4.0)
	check(peak_db > -65.0, "driver engine reaches recording bus")
	set_phase("warmup")
	await wait_seconds(8.0)
	start_distance = float(car.distance_travelled)
	set_phase("drive")
	# One extra second ensures at least thirty full frame intervals are retained.
	await wait_seconds(31.0)
	measured_distance = float(car.distance_travelled)-start_distance
	check(measured_distance > 60.0, "measured route advances through real vehicle physics")
	check(car.health > 0 and car.controlled and world.player.seated, "driver remains alive and seated during route")
	set_phase("coast")
	await wait_seconds(3.0)
	set_phase("brake")
	var brake_deadline := Time.get_ticks_msec()+8000
	while absf(float(car.speed)) > .15 and Time.get_ticks_msec() < brake_deadline: await physics_frame
	release_inputs()
	check(absf(float(car.speed)) < .4, "real brakes stop the vehicle")
	# Fault-state injection is deliberately outside the measured driving window.
	set_phase("disabled_engine_diagnostic")
	car.engine_disabled = true
	await wait_seconds(2.0)
	check(active_driver_voices() == 0, "disabled motor stops all driver engine voices")
	car.engine_disabled = false
	set_phase("restarted_engine")
	await wait_seconds(2.0)
	check(active_driver_voices() > 0, "clearing disabled state restores idle")
	set_phase("exit")
	check(world.driving.interact(), "normal exit starts")
	var exit_deadline := Time.get_ticks_msec()+12000
	while world.driving.occupied and Time.get_ticks_msec() < exit_deadline: await physics_frame
	await wait_seconds(2.0)
	check(not world.driving.occupied and active_driver_voices() == 0, "normal exit releases driver engine voices")
	set_phase("reentry")
	check(await board(), "normal reentry completes")
	await wait_seconds(3.0)
	check(active_driver_voices() > 0, "normal reentry restores driver engine")
	finish()

func run_fixed_audio_abba() -> void:
	previous_design_enabled = DESIGN_BANKS.enabled()
	design_flag_overridden = true
	DESIGN_BANKS._enabled = true
	set_phase("audio_prepare")
	# Both caches remain resident across all four phases. Enable design during
	# preparation so the normal mixers can allocate their bounded voice slots.
	await LEGACY_BANKS.prewarm(self)
	await DESIGN_BANKS.prewarm(self)
	var legacy_resident := true
	for family in LEGACY_BANKS.all_families():
		if LEGACY_BANKS.bank(family).size() != 7: legacy_resident = false
	var design_resident := true
	for profile_id in DESIGN_BANKS.CATALOG.all_profile_ids():
		if not DESIGN_BANKS.is_ready(profile_id): design_resident = false
	check(legacy_resident and design_resident, "both complete bank caches are resident before fixed phases")
	if not failures.is_empty(): return
	await wait_seconds(4.0)
	check(absf(float(car.speed)) < .4, "normal handbrake holds the fixed audio vehicle")
	if not failures.is_empty(): return
	var initial_position: Vector3 = car.global_position
	start_distance = float(car.distance_travelled)
	for index in FIXED_AUDIO_MODES.size():
		var audio_mode: String = FIXED_AUDIO_MODES[index]
		var key := "audio_%s_%d" % [audio_mode, index]
		DESIGN_BANKS._enabled = audio_mode == "design"
		set_phase(key + "_warmup")
		await wait_seconds(3.0)
		route_capture_voices()
		check(active_driver_voices() > 0, key + " has audible engine players")
		check(selected_driver_audio_active(), key + " uses only the selected engine path")
		var phase_position: Vector3 = car.global_position
		var phase_distance := float(car.distance_travelled)
		set_phase(key)
		await wait_seconds(31.0)
		var displacement := phase_position.distance_to(car.global_position)
		var phase_travelled := float(car.distance_travelled) - phase_distance
		fixed_phase_results.append({"phase": key, "design_enabled": DESIGN_BANKS.enabled(),
			"position_start": str(phase_position), "position_end": str(car.global_position),
			"displacement_m": displacement, "distance_m": phase_travelled,
			"driver_voices": active_driver_voices(), "driver_design_voices": active_design_driver_voices()})
		check(displacement < .5 and phase_travelled < .5 and absf(float(car.speed)) < .4, key + " remains stationary without repositioning")
		check(car.health > 0 and car.controlled and world.player.seated, key + " retains the living seated driver")
		check(selected_driver_audio_active(), key + " retains only the selected active engine path")
	measured_distance = float(car.distance_travelled) - start_distance
	check(initial_position.distance_to(car.global_position) < .75 and measured_distance < .75, "fixed audio comparison has no material total movement")
	check(peak_db > -65.0, "fixed audio engine reaches the recording bus")

func board() -> bool:
	for side in [-1, 1]:
		var approach: Vector3 = car.driver_door_anchor(side)+car.global_basis.x*float(side)*.25+Vector3.UP*.08
		if not world.session.position_clear(approach): continue
		world.player.teleport(approach)
		await physics_frame
		if world.driving.interact():
			var deadline := Time.get_ticks_msec()+15000
			while Time.get_ticks_msec() < deadline:
				await physics_frame
				if car.controlled and not car.input_locked and not world.driving.is_body_transition_active():
					return world.driving.car == car and world.player.seated
			return false
	return false

func setup_capture() -> void:
	AudioServer.add_bus()
	record_bus = AudioServer.bus_count-1
	AudioServer.set_bus_name(record_bus, "EngineDriveCapture")
	AudioServer.set_bus_send(record_bus, "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master")
	recorder = AudioEffectRecord.new()
	AudioServer.add_bus_effect(record_bus, recorder)
	recorder.set_recording_active(true)
	route_capture_voices()

func route_capture_voices() -> void:
	var pending: Array[Node] = []
	if world != null and is_instance_valid(world.production.world_audio):
		for node in world.production.world_audio.get_children():
			if str(node.name).begins_with("PlayerEngine") or str(node.name).begins_with("PlayerTurbo") or str(node.name).begins_with("PlayerSupercharger") or str(node.name).contains("EngineDesign"):
				pending.append(node)
	if is_instance_valid(car):
		for node in car.get_children():
			if str(node.name).contains("CarAudio") or str(node.name).contains("EngineDesign"): pending.append(node)
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			if str(node.name) != "Wheelspin":
				node.bus = "EngineDriveCapture"
				if node not in captured_voices: captured_voices.append(node)
		else:
			pending.append_array(node.get_children())

func active_driver_voices() -> int:
	var count := 0
	for node in captured_voices:
		if is_instance_valid(node) and node.playing: count += 1
	return count

func active_design_driver_voices() -> int:
	var count := 0
	for node in captured_voices:
		if is_instance_valid(node) and node.playing and str(node.name).begins_with("Design"): count += 1
	return count

func selected_driver_audio_active() -> bool:
	var total := active_driver_voices()
	var designed := active_design_driver_voices()
	return designed > 0 and designed == total if DESIGN_BANKS.enabled() else total > 0 and designed == 0

func _physics_process(_delta: float) -> bool:
	if not capturing or not is_instance_valid(car): return false
	release_inputs()
	if fixed_audio_abba:
		# Equal player inputs in every phase; no throttle or direct velocity writes.
		Input.action_press("handbrake", 1.0)
		return false
	if phase in ["warmup", "drive", "coast"]:
		var offset := route.get_closest_offset(car.global_position)
		var ahead := route.sample_baked(fposmod(offset+maxf(3.0, absf(float(car.speed))*.65), route.get_baked_length()), true)-car.global_position
		var desired := atan2(-ahead.x, -ahead.z)
		var turn := clampf(angle_difference(car.rotation.y, desired)*1.8, -1.0, 1.0)
		if turn > .01: Input.action_press("move_left", turn)
		elif turn < -.01: Input.action_press("move_right", -turn)
		var target_speed := lerpf(12.0, 4.0, clampf(absf(turn)*1.7, 0.0, 1.0))
		var seconds := float(Time.get_ticks_usec()-phase_started)/1000000.0
		var lift := phase == "coast" or (phase == "drive" and fposmod(seconds, 10.0) > 7.5)
		if car.obstacle_ahead():
			Input.action_press("brake", 1.0 if absf(float(car.speed)) > .5 else 0.0)
		elif not lift and float(car.speed) < target_speed:
			Input.action_press("accelerate", 1.0)
		elif float(car.speed) > target_speed+1.5:
			Input.action_press("brake", .45)
	elif phase == "brake":
		Input.action_press("brake", 1.0 if float(car.speed) > .2 else 0.0)
	return false

func _process(delta: float) -> bool:
	if not capturing or finishing: return false
	var now := Time.get_ticks_usec()
	if previous_frame > 0:
		frames.append({"phase": phase, "ms": float(now-previous_frame)/1000.0,
			"seconds": float(now-session_started)/1000000.0,
			"speed": float(car.speed), "throttle": float(car.throttle_input),
			"cpu_ms": Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
			"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0})
	previous_frame = now
	peak_db = maxf(peak_db, AudioServer.get_bus_peak_volume_left_db(record_bus, 0))
	voice_clock -= delta
	if voice_clock <= 0.0:
		voice_clock = .5
		route_capture_voices()
		var nearby := get_first_node_in_group("nearby_vehicle_engine_mixer")
		var service := get_first_node_in_group("service_vehicle_engine_mixer")
		var sample := {"phase": phase, "seconds": float(now-session_started)/1000000.0,
			"driver_voices": active_driver_voices(), "driver_voice_nodes": captured_voices.size(),
			"driver_design_voices": active_design_driver_voices(), "design_enabled": DESIGN_BANKS.enabled(),
			"memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"population": world.people.size(), "vehicles": world.production.vehicles.size(),
			"nearby": nearby.snapshot() if nearby != null and nearby.has_method("snapshot") else {},
			"service": service.snapshot() if service != null and service.has_method("snapshot") else {"snapshot_available": false}}
		voice_samples.append(sample)
	return false

func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"frames": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	var count := sorted.size()
	return {"frames": count, "seconds": total/1000.0, "fps": count*1000.0/total,
		"p50_ms": sorted[int((count-1)*.5)], "p95_ms": sorted[int((count-1)*.95)],
		"p99_ms": sorted[int((count-1)*.99)], "max_ms": sorted[-1],
		"over_33_3_ms": slow, "over_66_7_ms": very_slow}

func finish() -> void:
	if finishing: return
	finishing = true
	capturing = false
	release_inputs()
	if recorder != null:
		recorder.set_recording_active(false)
		var recording := recorder.get_recording()
		if recording != null: recording.save_to_wav(output.path_join("engine.wav"))
	var groups := {}
	for sample in frames:
		if not groups.has(sample.phase): groups[sample.phase] = [] as Array[float]
		groups[sample.phase].append(float(sample.ms))
	var summaries := {}
	for key in groups: summaries[key] = stats(groups[key])
	if fixed_audio_abba:
		for index in FIXED_AUDIO_MODES.size():
			var key := "audio_%s_%d" % [FIXED_AUDIO_MODES[index], index]
			check(float(summaries.get(key, {}).get("seconds", 0.0)) >= 30.0, key + " retains at least thirty seconds of frame intervals")
	else:
		check(float(summaries.get("drive", {}).get("seconds", 0.0)) >= 30.0, "at least thirty seconds of measured frame intervals")
	if design_flag_overridden:
		DESIGN_BANKS._enabled = previous_design_enabled
		design_flag_overridden = false
	var final_fingerprint := fingerprint()
	check(initial_fingerprint == final_fingerprint, "measurement sources unchanged during execution")
	var report := {"label": label, "car": archetype, "checks": checks, "failures": failures,
		"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"args": OS.get_cmdline_user_args(), "summaries": summaries, "frames": frames, "events": events,
		"voice_samples": voice_samples, "route_points": route_points, "measured_distance": measured_distance,
		"fixed_audio_abba": fixed_audio_abba, "fixed_audio_phases": fixed_phase_results,
		"peak_db": peak_db, "source_start": initial_fingerprint, "source_end": final_fingerprint,
		"scope": "Main rendered, normal boarding/camera and live population. Fixed audio ABBA diagnostic: same stationary car under ordinary handbrake input, zero throttle, both bank caches resident, only audio enabled flag alternates legacy/design/design/legacy, 3s warmup then 31s measured per phase. No physics edits or repositioning; live traffic/population remain a source of variation. This local idle comparison does not certify global Main FPS, loaded-engine driving, fleet-wide performance or audible quality. C# required; process exclusivity is the caller's responsibility." if fixed_audio_abba else "Main rendered, ordinary input and live drivetrain/population. One initial placement, 8s warmup and 31s driving with at least 30s retained intervals. Engine-disabled injection is a separate diagnostic. C# required; external process exclusivity is the caller's responsibility. No claim of complete fleet, all regions or audible quality."}
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("ENGINE_DRIVE_COMPLETE output=", output, " checks=", checks, " failures=", failures.size(), " drive=", JSON.stringify(summaries.get("drive", {})))
	if world != null and is_instance_valid(world): world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
