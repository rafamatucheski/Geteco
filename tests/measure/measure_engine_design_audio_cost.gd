extends SceneTree
## Microbenchmark de áudio renderizado: doze fontes espaciais e depois uma em primeiro plano.
## Os dois bancos e todos os nós ficam residentes. A/B/B/A reproduz a mesma curva de RPM/carga
## por 31s depois de 3s de aquecimento por fase. Isto NÃO aprova o FPS do Main.
## Godot .NET --path . --script res://tests/measure/measure_engine_design_audio_cost.gd
##   -- --no-save
const LEGACY_BANKS := preload("res://audio/EngineBankCache.gd")
const LEGACY_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const DESIGN_BANKS := preload("res://audio/EngineDesignBanks.gd")
const DESIGN_CATALOG := preload("res://audio/FleetEngineDesign.gd")
const DESIGN_VOICE := preload("res://audio/EngineDesignVoice.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const ARCHETYPES := ["sport_coupe", "monaliza", "metro_hatch", "union_sedan", "police_cruiser", "police_suv",
	"police_transport", "medic_box", "rescue_pumper", "station_wagon", "route_city", "boxrunner"]
const ORDER := ["legacy", "design", "design", "legacy"]
const SCENARIOS := ["spatial_twelve", "foreground_one"]
const WARMUP_SECONDS := 3.0
const MEASURE_SECONDS := 31.0
const SOURCE_PATHS := ["res://tests/measure/measure_engine_design_audio_cost.gd", "res://audio/EngineBankCache.gd",
	"res://audio/VehicleEngineProfile.gd", "res://audio/EngineDesignBanks.gd", "res://audio/EngineDesignVoice.gd",
	"res://audio/FleetEngineDesign.gd", "res://audio/engine_design/manifest.json", "res://project.godot"]
var scene: Node3D
var sources: Array[Dictionary] = []
var foreground_source: Dictionary = {}
var active_sources: Array[Dictionary] = []
var records: Array[Dictionary] = []
var frame_ms := PackedFloat64Array()
var mix_us := PackedFloat64Array()
var physics_ms := PackedFloat64Array()
var process_ms := PackedFloat64Array()
var voice_samples: Array[Dictionary] = []
var failures: Array[String] = []
var mode := ""
var scenario := ""
var phase_started := 0
var previous_frame := 0
var next_sample := 0.0
var sampling := false
var active := false
var finishing := false
var output := ""
var initial_fingerprint := {}
var prior_cap := 0
var prior_vsync := 0

func _initialize() -> void:
	create_timer(420.0).timeout.connect(func():
		if not finishing:
			failures.append("bounded microbenchmark timeout")
			finish.call_deferred())
	run.call_deferred()

func fingerprint() -> Dictionary:
	var result := {}
	for path in SOURCE_PATHS:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or not DESIGN_BANKS.enabled():
		push_error("Audio cost comparison requires rendered Godot .NET, --no-save and design banks enabled")
		quit(2)
		return
	output = FIXTURE.output_dir("engine-audio-cost-abba")
	if output.is_empty(): quit(2); return
	initial_fingerprint = fingerprint()
	prior_cap = Engine.max_fps
	prior_vsync = DisplayServer.window_get_vsync_mode()
	# Este diagnóstico remove de propósito o limite de quadros no próprio processo.
	# Estas configurações não são persistidas e não são benchmark de jogo do Main.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280, 720)
	await LEGACY_BANKS.prewarm(self)
	await DESIGN_BANKS.prewarm(self)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	build_scene()
	if not failures.is_empty(): finish(); return
	for next_scenario in SCENARIOS:
		scenario = next_scenario
		active_sources.clear()
		if scenario == "spatial_twelve": active_sources.assign(sources)
		else: active_sources.append(foreground_source)
		for index in ORDER.size():
			stop_all()
			mode = ORDER[index]
			phase_started = Time.get_ticks_usec()
			active = true
			await create_timer(WARMUP_SECONDS).timeout
			frame_ms = PackedFloat64Array()
			mix_us = PackedFloat64Array()
			physics_ms = PackedFloat64Array()
			process_ms = PackedFloat64Array()
			voice_samples = []
			previous_frame = 0
			next_sample = WARMUP_SECONDS
			var memory_start := int(Performance.get_monitor(Performance.MEMORY_STATIC))
			sampling = true
			print("ENGINE_AUDIO_COST_PHASE ", scenario, " ", index, " ", mode)
			await create_timer(MEASURE_SECONDS).timeout
			sampling = false
			active = false
			var frame_stats := stats(frame_ms)
			if float(frame_stats.get("seconds", 0.0)) < 30.0:
				failures.append("%s phase %d has less than thirty seconds of frame intervals" % [scenario, index])
			var record := {"scenario": scenario, "index": index, "mode": mode, "frames": frame_stats,
				"mix_update_us": stats(mix_us, false), "physics_monitor_ms": stats(physics_ms, false),
				"process_monitor_ms": stats(process_ms, false), "memory_start": memory_start,
				"memory_end": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
				"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				"voice_samples": voice_samples.duplicate(true), "frame_ms": frame_ms, "mix_us": mix_us}
			records.append(record)
			print("ENGINE_AUDIO_COST_RESULT ", JSON.stringify({"scenario": scenario, "index": index, "mode": mode,
				"frames": frame_stats, "mix_update_us": record.mix_update_us, "physics_monitor_ms": record.physics_monitor_ms}))
	finish()

func build_scene() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 23, 25)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var listener := AudioListener3D.new()
	scene.add_child(listener)
	listener.position = Vector3(0, 2, 7)
	listener.make_current()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(.19, .25, .29)
	for index in ARCHETYPES.size():
		var archetype: String = ARCHETYPES[index]
		var profile := DESIGN_CATALOG.profile(archetype)
		var bank: Array[AudioStreamWAV] = LEGACY_BANKS.bank(LEGACY_PROFILE.bank_family(archetype))
		if bank.size() != 7 or not DESIGN_BANKS.is_ready(profile):
			failures.append("incomplete resident banks for " + archetype)
			continue
		var at := Vector3(float(index % 4) * 6.0 - 9.0, .7, float(index / 4) * 6.0 - 6.0)
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2, 1.4, 4)
		box.mesh = mesh
		box.material_override = material
		box.position = at
		scene.add_child(box)
		var legacy: Array[AudioStreamPlayer3D] = []
		for layer in 2:
			var player := AudioStreamPlayer3D.new()
			player.name = "Legacy%d_%d" % [index, layer]
			player.max_polyphony = 1
			player.max_distance = 45.0
			player.unit_size = 8.0
			player.position = at
			player.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
			scene.add_child(player)
			legacy.append(player)
		var design := DESIGN_VOICE.new()
		design.name = "Design%d" % index
		scene.add_child(design)
		if not design.configure(archetype): failures.append("unable to bind design source " + archetype)
		sources.append({"archetype": archetype, "profile": profile, "bank": bank,
			"anchors": DESIGN_CATALOG.rpm_bands(profile), "legacy": legacy, "design": design, "at": at})
	if sources.size() != 12: failures.append("expected twelve complete audio sources")
	if sources.is_empty(): return
	# O motor legado do WorldAudio usa AudioStreamPlayers 2D (sete residentes,
	# faixas adjacentes audíveis). O motor novo tem quatro players 3D com a
	# atenuação de primeiro plano desligada. O turbo fica de fora para isolar o motor.
	var legacy_foreground: Array[AudioStreamPlayer] = []
	for index in 7:
		var player := AudioStreamPlayer.new()
		player.name = "ForegroundLegacy%d" % index
		player.max_polyphony = 1
		player.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
		scene.add_child(player)
		legacy_foreground.append(player)
	var foreground_design := DESIGN_VOICE.new()
	foreground_design.name = "ForegroundDesign"
	scene.add_child(foreground_design)
	if not foreground_design.configure(ARCHETYPES[0]): failures.append("unable to bind foreground source")
	foreground_source = {"archetype": ARCHETYPES[0], "profile": sources[0].profile, "bank": sources[0].bank,
		"anchors": sources[0].anchors, "legacy": legacy_foreground, "design": foreground_design, "at": Vector3.ZERO}

func stop_all() -> void:
	for source in sources:
		for player in source.legacy: player.stop()
		source.design.stop()
	if not foreground_source.is_empty():
		for player in foreground_source.legacy: player.stop()
		foreground_source.design.stop()

func _process(delta: float) -> bool:
	if not active or finishing: return false
	var now := Time.get_ticks_usec()
	var elapsed := float(now - phase_started) / 1000000.0
	var began := Time.get_ticks_usec()
	for index in active_sources.size():
		var source: Dictionary = active_sources[index]
		# Identical continuous trajectory per phase, staggered across the twelve
		# sources. Every source crosses band boundaries and loaded/coast states.
		var band := 2.7 + sin(elapsed * .65 + float(index) * .4) * 2.3
		var load_value := .5 + .5 * sin(elapsed * 1.1 + float(index) * .6)
		var lower := mini(5, floori(band))
		var blend := band - lower
		if mode == "design":
			var anchors: Array = source.anchors
			var rpm := exp(lerpf(log(float(anchors[lower])), log(float(anchors[lower + 1])), blend))
			source.design.update_mix(rpm, load_value, delta, -30.0, source.at, scenario == "foreground_one", false)
		else:
			# O banco de primeiro plano mantém um player por faixa, como o WorldAudio faz.
			if scenario == "foreground_one":
				for layer in 7:
					if layer != lower and layer != lower + 1: source.legacy[layer].stop()
			for layer in [lower, lower + 1]:
				var player: Variant = source.legacy[layer] if scenario == "foreground_one" else source.legacy[layer % 2]
				var weight := 1.0 - blend if layer == lower else blend
				if weight <= .001:
					player.stop()
					continue
				var stream: AudioStreamWAV = source.bank[layer]
				if player.stream != stream:
					player.stop()
					player.stream = stream
				player.volume_db = -30.0 + linear_to_db(sqrt(weight))
				player.pitch_scale = 1.0 + load_value * .05
				if not player.playing: player.play()
	var update_us := float(Time.get_ticks_usec() - began)
	if sampling:
		if previous_frame > 0:
			frame_ms.append(float(now - previous_frame) / 1000.0)
			mix_us.append(update_us)
			physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		previous_frame = now
		if elapsed >= next_sample:
			next_sample += 1.0
			var legacy_count := 0
			var design_count := 0
			for source in sources:
				for player in source.legacy:
					if player.playing: legacy_count += 1
				design_count += int(source.design.snapshot().motor_voices)
			for player in foreground_source.legacy:
				if player.playing: legacy_count += 1
			design_count += int(foreground_source.design.snapshot().motor_voices)
			if (mode == "legacy" and design_count != 0) or (mode == "design" and legacy_count != 0):
				failures.append("inactive mixer overlapped phase " + mode)
			if (legacy_count if mode == "legacy" else design_count) < active_sources.size():
				failures.append("an active source produced no engine voice in phase " + mode)
			var legacy_limit := 24 if scenario == "spatial_twelve" else 2
			var design_limit := 48 if scenario == "spatial_twelve" else 4
			if legacy_count > legacy_limit or design_count > design_limit:
				failures.append("bounded audio voice count exceeded")
			voice_samples.append({"elapsed": elapsed, "legacy": legacy_count, "design": design_count})
	return false

func stats(values: PackedFloat64Array, frame_units := true) -> Dictionary:
	if values.is_empty(): return {"count": 0}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	var count := ordered.size()
	var result := {"count": count, "mean": total / count, "p50": ordered[int((count - 1) * .5)],
		"p95": ordered[int((count - 1) * .95)], "p99": ordered[int((count - 1) * .99)], "max": ordered[-1]}
	if frame_units:
		result.seconds = total / 1000.0
		result.fps = count * 1000.0 / total
		result.over_33_3_ms = slow
		result.over_66_7_ms = very_slow
	return result

func finish() -> void:
	if finishing: return
	finishing = true
	sampling = false
	active = false
	stop_all()
	var final_fingerprint := fingerprint()
	if initial_fingerprint != final_fingerprint: failures.append("sources changed during comparison")
	if records.size() != 8: failures.append("eight complete ABBA phases required across the two scenarios")
	var report := {"kind": "rendered_audio_microbenchmark_not_gameplay", "failures": failures,
		"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"resolution": str(root.size), "max_fps": Engine.max_fps, "vsync": DisplayServer.window_get_vsync_mode(),
		"order_per_scenario": ORDER, "scenarios": SCENARIOS, "warmup_seconds_per_phase": WARMUP_SECONDS, "requested_seconds_per_phase": MEASURE_SECONDS,
		"archetypes": ARCHETYPES, "resident_nodes": {"spatial_legacy_players": 24, "spatial_design_players": 48,
			"foreground_legacy_players": 7, "foreground_design_players": 4, "turbo_players": 0},
		"phases": records, "source_start": initial_fingerprint, "source_end": final_fingerprint,
		"scope": "Fixed native 3D render and listener, no artificial physics areas; twelve spatial sources then one foreground source (legacy AudioStreamPlayer versus design AudioStreamPlayer3D without attenuation); both banks and all nodes resident; one mix update per frame, no turbo; no traffic or gameplay. Standalone helper/native playback cost and script update time, not Main FPS, route selection, audio thread CPU attribution or audible quality. Godot process/physics monitors are sampled, not per-call attribution. Report buffers grow between phases. External process exclusivity is the caller's responsibility."}
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t"))
		else: failures.append("unable to write microbenchmark report")
	print("ENGINE_AUDIO_COST_COMPLETE output=", output, " phases=", records.size(), " failures=", failures.size())
	Engine.max_fps = prior_cap
	DisplayServer.window_set_vsync_mode(prior_vsync)
	if is_instance_valid(scene): scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
