extends SceneTree
## Component diagnostic in the rendered production scene. Switches only the
## parked car's audio selection metadata; it does not certify normal driving.
const BANKS := preload("res://audio/EngineBankCache.gd")
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
var frames: Array[float] = []
var events: Array[Dictionary] = []
var previous := 0
func _initialize() -> void: run.call_deferred()
func arg(name: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(name + "="): return value.trim_prefix(name + "=")
	return ""
func frame(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if previous > 0: frames.append(float(now - previous) / 1000.0)
	previous = now
func legacy_read_and_copy(audio: Node, family: String) -> void:
	# Diagnostic control of the removed hot path, after the common selector.
	# Tank already reused its procedural bank in the original implementation.
	if family == "tank": return
	for index in 7:
		audio.layers[index].stop()
		var source: AudioStreamWAV = load("res://audio/acoustic/engine_%s_%d.wav" % [family, index])
		var stream := source.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = maxi(1, roundi(stream.get_length() * stream.mix_rate) - 8)
		audio.layers[index].stream = stream
func summarize(seconds: float) -> Dictionary:
	var sorted := frames.duplicate()
	sorted.sort()
	var count := sorted.size()
	return {"seconds": seconds, "frames": count, "p50_ms": sorted[int(count * .5)], "p95_ms": sorted[int(count * .95)], "p99_ms": sorted[int(count * .99)], "max_ms": sorted[-1], "over_66_ms": sorted.filter(func(ms): return ms > 66.7).size()}
func run() -> void:
	seed(20261001)
	var output := arg("--out")
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or not output.begins_with("res://evidence/") or FileAccess.file_exists(output): quit(2); return
	create_timer(300.0).timeout.connect(func(): push_error("ENGINE_CACHE timeout"); quit(2))
	root.size = Vector2i(1920, 1080)
	var world: Node3D = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play: await process_frame
	world.session.state.intro.stage = "complete"
	# Nearby audio has already started warming; wait for every real family so
	# this isolates foreground reuse, rather than racing background loading.
	for family in BANKS.all_families():
		while not BANKS._family_loaded(family): await process_frame
		BANKS.bank(family)
	for i in 120: await process_frame
	var car: CharacterBody3D = world.driving.car
	var original: String = car.archetype
	var selected: Dictionary = {}
	for archetype in FLEET.all():
		var family := PROFILE.bank_family(archetype)
		if not selected.has(family) and BANKS.bank(family).size() == 7: selected[family] = archetype
	process_frame.connect(func(): frame(0))
	print("ENGINE_CACHE_READY families=", selected.size())
	var began := Time.get_ticks_usec()
	var compare := "--compare" in OS.get_cmdline_user_args()
	var comparisons: Array[Dictionary] = []
	for legacy: bool in ([true, false, false, true] if compare else [false]):
		frames.clear()
		previous = 0
		var block_began := Time.get_ticks_usec()
		var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var block_events: Array[Dictionary] = []
		for family: String in selected:
			await create_timer(1.0).timeout
			car.archetype = selected[family]
			var cached_paths := 0
			if family != "tank":
				for index in 7:
					if ResourceLoader.has_cached("res://audio/acoustic/engine_%s_%d.wav" % [family, index]): cached_paths += 1
			var started := Time.get_ticks_usec()
			world.production.world_audio._sync_engine_family(car)
			if legacy: legacy_read_and_copy(world.production.world_audio, family)
			var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
			var retained := BANKS.bank(family)
			var reused := 0
			for index in 7:
				if is_same(world.production.world_audio.layers[index].stream, retained[index]): reused += 1
			block_events.append({"family": family, "archetype": selected[family], "cached_source_paths": cached_paths, "sync_ms": elapsed, "reused_bands": reused})
		car.archetype = original
		world.production.world_audio._sync_engine_family(car)
		await create_timer(14.0 if compare else 30.0).timeout
		var block := summarize(float(Time.get_ticks_usec() - block_began) / 1000000.0)
		block.merge({"legacy_read_fixture": legacy, "nodes_before": nodes_before, "nodes_after": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "events": block_events, "frames_ms": frames.duplicate()})
		comparisons.append(block)
		events.append_array(block_events)
	var seconds := float(Time.get_ticks_usec() - began) / 1000000.0
	frames.clear()
	for block in comparisons: frames.append_array(block.frames_ms)
	var summary := summarize(seconds)
	var config := {"component_diagnostic": true, "seed": 20261001, "paired_legacy_fixture": compare, "debugger": EngineDebugger.is_active(), "renderer": RenderingServer.get_current_rendering_method(), "viewport": str(root.size), "gpu": RenderingServer.get_video_adapter_name(), "max_physics_steps": Engine.max_physics_steps_per_frame, "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps}
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"events": events, "summary": summary, "configuration": config, "comparisons": comparisons, "frames_ms": frames}, "\t"))
	file.close()
	print("ENGINE_CACHE_SUMMARY ", JSON.stringify(summary))
	quit(0)
