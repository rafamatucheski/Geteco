extends SceneTree
## Main renderizado real. Viagens medem lifecycle, não FPS de condução.
const STARTUP_SECONDS := 80.0 # measure_full: 4800 physics frames a 60 Hz.
const TRAVEL_SECONDS := 15.0 # test_persistent_vehicle_support: conclusão da API.
const WALK_SECONDS := 30.0
const SOURCES := ["Main.tscn", "project.godot", "runtime/ProductionWorld.gd", "world/regions/NativeRegion.gd", "world/editing/world_edits.json", "audio/VehicleCrashAudio.gd", "gameplay/vehicle_effects/VehicleImpactEffects.gd", "gameplay/street_physics/StreetPhysics.gd"]
var world
var label := "lifecycle"
var isolated_root := ""
var sample_ram := false
var report := {"phases": [], "snapshots": [], "failures": []}
var phase := ""
var phase_started := 0
var previous_frame := 0
var frame_ms: Array[float] = []
var walk_origin := Vector3.ZERO
var walk_direction := 1.0
var walking := false
var finishing := false
var weak_observations: Array[Dictionary] = []


func _initialize() -> void:
	run.call_deferred()


func _process(_delta: float) -> bool:
	if phase.is_empty(): return false
	var now := Time.get_ticks_usec()
	if previous_frame > 0: frame_ms.append(float(now - previous_frame) / 1000.0)
	previous_frame = now
	if walking and is_instance_valid(world) and is_instance_valid(world.player):
		if absf(world.player.position.x - walk_origin.x) >= 3.0: walk_direction = -signf(world.player.position.x - walk_origin.x)
		world.player.automatic_direction = Vector3(walk_direction, 0, 0)
	return false


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pilot-label="): label = arg.get_slice("=", 1).validate_filename()
		if arg.begins_with("--isolated-save-root="): isolated_root = arg.trim_prefix("--isolated-save-root=")
		if arg == "--pilot-process-ram": sample_ram = true
	report.started_utc = Time.get_datetime_string_from_system(true)
	report.sources_before = _source_hashes()
	report.config = {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "resolution": str(root.size), "max_fps": Engine.max_fps, "vsync": DisplayServer.window_get_vsync_mode(), "msaa": root.msaa_3d, "user_data_dir": OS.get_user_data_dir(), "pid": OS.get_process_id(), "args": OS.get_cmdline_user_args()}
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or isolated_root.is_empty():
		_fail("Exige renderização, --no-save e --isolated-save-root explícito")
		await _finish()
		return
	var save_path := isolated_root.path_join("pilot-progress.json")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix):
			_fail("Root de progresso do piloto já contém save; não sobrescrever nem reutilizar")
			await _finish()
			return
	report.isolated_progress_path = save_path
	_snapshot("before_world")
	_begin("startup")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", save_path)
	world.set_meta("skip_arrival", true)
	world.set_meta("benchmark_trace", true)
	root.add_child(world)
	if not await _wait_ready("harbor", STARTUP_SECONDS):
		_fail("Startup não atingiu pronto/povoamento/streaming dentro de 80 s")
		await _finish()
		return
	_end()
	_snapshot("startup_ready")
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	for child in world.hud.get_children():
		if child.get_script() == preload("res://scripts/PauseInput.gd"): child.set_process_unhandled_input(false)
	world.player.controlled_automatically = true
	world.player.speed = 1.5 # Mesma caminhada de measure_full, sem alterar NPCs/tráfego.
	walk_origin = world.player.position
	var distance_before: float = world.player.travelled
	walking = true
	_begin("walking_warmup_5s")
	while float(Time.get_ticks_usec() - phase_started) / 1000000.0 < 5.0:
		await physics_frame
		if not _alive():
			_fail("Warmup interrompido por morte/transição; saúde não é restaurada")
			await _finish()
			return
	_end()
	var sampled_distance_before: float = world.player.travelled
	_begin("walking_30s")
	while float(Time.get_ticks_usec() - phase_started) / 1000000.0 < WALK_SECONDS:
		await physics_frame
		if not _alive():
			_fail("Caminhada interrompida por morte/transição; saúde não é restaurada")
			await _finish()
			return
	walking = false
	world.player.automatic_direction = Vector3.ZERO
	_end()
	report.walk_distance = world.player.travelled - distance_before
	report.walking_30s_distance = world.player.travelled - sampled_distance_before
	if report.walking_30s_distance < 1.0:
		_fail("Fixture de caminhada não percorreu 1 m; amostra não é caminhada válida")
		await _finish()
		return
	_snapshot("after_walking")
	for cycle in 3:
		for destination in ["mountain", "harbor"]:
			_begin("travel_%d_%s" % [cycle + 1, destination])
			if not _alive() or not world.production.travel(destination):
				_fail("API de viagem recusou pedido, sem retry: " + destination)
				await _finish()
				return
			var deadline := Time.get_ticks_usec() + int(TRAVEL_SECONDS * 1000000.0)
			while world.production.travel_busy and Time.get_ticks_usec() < deadline: await physics_frame
			if world.production.travel_busy or world.session.state.region_id != destination:
				_fail("Viagem não concluiu em 15 s: " + destination)
				await _finish()
				return
			_end()
			_begin("repopulate_%d_%s" % [cycle + 1, destination])
			if not await _wait_ready(destination, STARTUP_SECONDS):
				_fail("Destino não recompôs população/streaming em 80 s: " + destination)
				await _finish()
				return
			_end()
			_snapshot("visit_%d_%s" % [cycle + 1, destination])
	await _finish()


func _alive() -> bool:
	return is_instance_valid(world) and world.session != null and is_instance_valid(world.gameplay) and world.gameplay.health > 0 and not world.session.modal


func _wait_ready(destination: String, seconds: float) -> bool:
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	var ready_at := -1.0
	var population_at := -1.0
	var ready_utc := ""
	var population_utc := ""
	while Time.get_ticks_usec() < deadline:
		await physics_frame
		if world.session == null or not is_instance_valid(world.gameplay): continue
		var elapsed_ms := float(Time.get_ticks_usec() - phase_started) / 1000.0
		if world.session.ready_for_play and ready_at < 0:
			ready_at = elapsed_ms
			ready_utc = Time.get_datetime_string_from_system(true)
		if world.people.size() >= world.production.requested_population and population_at < 0:
			population_at = elapsed_ms
			population_utc = Time.get_datetime_string_from_system(true)
		if world.gameplay.health <= 0: return false
		var streams_idle := true
		for region in world.production.regions.values(): streams_idle = streams_idle and region.is_streaming_idle()
		if world.session.ready_for_play and not world.session.modal and world.session.state.region_id == destination and world.people.size() >= world.production.requested_population and streams_idle:
			report.phases_ready = report.get("phases_ready", []) + [{"phase": phase, "ready_ms": ready_at, "ready_utc": ready_utc, "population_ms": population_at, "population_utc": population_utc, "requested_population": world.production.requested_population}]
			return true
	return false


func _begin(name: String) -> void:
	phase = name
	phase_started = Time.get_ticks_usec()
	previous_frame = phase_started
	frame_ms.clear()


func _end() -> void:
	if phase.is_empty(): return
	report.phases.append({"name": phase, "wall_ms": float(Time.get_ticks_usec() - phase_started) / 1000.0, "summary": _stats(frame_ms), "frame_intervals_ms": frame_ms.duplicate()})
	phase = ""


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"frames": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var slow := 0
	var very_slow := 0
	for ms in values:
		if ms > 33.3: slow += 1
		if ms > 66.7: very_slow += 1
	# Mesma posição de percentis usada pelo medidor existente measure.gd.
	return {"frames": values.size(), "p50_ms": sorted[int((sorted.size() - 1) * .50)], "p95_ms": sorted[int((sorted.size() - 1) * .95)], "p99_ms": sorted[int((sorted.size() - 1) * .99)], "max_ms": sorted[-1], "over_33_3_ms": slow, "over_66_7_ms": very_slow}


func _owners() -> Array:
	var owners: Array = []
	if not is_instance_valid(world) or not is_instance_valid(world.production): return owners
	for region in world.production.regions.values() + world.production._region_cache.values():
		if is_instance_valid(region) and not owners.has(region): owners.append(region)
	return owners


func _snapshot(name: String) -> void:
	var rows: Array = []
	var first_cache: Dictionary = {}
	var have_first := false
	for region in _owners():
		var cache: Dictionary = region._record_cache
		var nodes := 0
		var detached := 0
		var invalid := 0
		for group in cache.values():
			for node in group:
				if not is_instance_valid(node): invalid += 1; continue
				nodes += 1
				if node.get_parent() == null: detached += 1
		rows.append({"id": region.region_id, "instance_id": region.get_instance_id(), "live": world.production.regions.values().has(region), "cache_keys": cache.size(), "cached_roots": nodes, "detached_roots": detached, "invalid_refs": invalid, "resource_paths": region._held_resources.size(), "cache_aliases_first_owner": have_first and is_same(cache, first_cache), "chunks": region.chunks.size(), "pending": region.pending.size(), "build_jobs": region.build_jobs.size()})
		if not have_first: first_cache = cache; have_first = true
	var row := {"name": name, "utc": Time.get_datetime_string_from_system(true), "owners": rows, "engine_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "process_ram_bytes": null}
	if sample_ram and OS.get_name() == "Windows":
		var output: Array = []
		var began := Time.get_ticks_usec()
		var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "(Get-Process -Id %d).WorkingSet64" % OS.get_process_id()], output, true)
		row.ram_collector_ms = float(Time.get_ticks_usec() - began) / 1000.0
		if code == 0 and not output.is_empty() and str(output[0]).strip_edges().is_valid_int(): row.process_ram_bytes = int(str(output[0]).strip_edges())
	if is_instance_valid(world) and world.session != null:
		row.population = world.people.size()
		row.cars = world.production.vehicles.size()
		row.health = world.gameplay.health
		row.region = world.session.state.region_id
	report.snapshots.append(row)


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path in SOURCES: hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes


func _fail(message: String) -> void:
	report.failures.append(message)
	push_error("REGION_LIFECYCLE: " + message)


func _collect_weak_observations() -> void:
	# Escopo termina antes de free/await: não reter Resource do último loop.
	var seen := {}
	for owner in _owners():
		for object in [owner]:
			weak_observations.append({"kind": "region", "instance_id": object.get_instance_id(), "weak": weakref(object)})
		for group in owner._record_cache.values():
			for node in group:
				if is_instance_valid(node) and not seen.has(node.get_instance_id()):
					seen[node.get_instance_id()] = true
					weak_observations.append({"kind": "cached_root", "instance_id": node.get_instance_id(), "parentless_before": node.get_parent() == null, "weak": weakref(node)})
		for resource in owner._held_resources.values():
			if resource is Resource and not seen.has(resource.get_instance_id()):
				seen[resource.get_instance_id()] = true
				weak_observations.append({"kind": "resource", "instance_id": resource.get_instance_id(), "path": resource.resource_path, "weak": weakref(resource)})


func _finish() -> void:
	if finishing: return
	finishing = true
	walking = false
	_end()
	_snapshot("before_destroy")
	_collect_weak_observations()
	var world_weak = weakref(world) if is_instance_valid(world) else null
	if is_instance_valid(world):
		report.runtime_costs = world.get_meta("perf_costs", [])
		world.free()
	world = null
	paused = false
	for tick in 3: await process_frame
	_snapshot("after_destroy_3_frames")
	report.world_destroyed = world_weak == null or world_weak.get_ref() == null
	report.post_destroy_refs = []
	for item in weak_observations:
		var row := item.duplicate()
		row.alive_after = is_instance_valid(item.weak.get_ref())
		row.erase("weak")
		report.post_destroy_refs.append(row)
	report.sources_after = _source_hashes()
	report.sources_stable = report.sources_before == report.sources_after
	if not report.sources_stable: _fail("Fontes rastreadas mudaram durante o piloto")
	report.notes = "Lifecycle via travel API, não condução contínua; sem ablação/restauração de saúde. Recursos sobreviventes não provam leak, RAM não prova MB liberados. Settings autoload não são isolados pelo argumento de progresso."
	var path := "res://evidence/region-lifecycle-pilot/" + label + ".json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("REGION_LIFECYCLE: não foi possível gravar relatório")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("%s REGION_LIFECYCLE label=%s phases=%d failures=%d report=%s" % ["PASS" if report.failures.is_empty() else "FAIL", label, report.phases.size(), report.failures.size(), path])
	quit(0 if report.failures.is_empty() else 1)
