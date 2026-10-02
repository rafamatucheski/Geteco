extends Node
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const LOG_WRITER := preload("res://runtime/StallLogWriter.gd")
## Registro de quadros lentos para quem joga e depois manda o arquivo. Só liga com a variável de
## ambiente HARBOR_STALL_LOG=1 (o Jogar.cmd define); fora disso o nó se remove e não custa nada.
##
## Grava em evidence/stall-logs/stalls-AAAAMMDD-HHMMSS.log, uma linha JSON por registro:
##  - "header": versão, GPU, renderizador, resolução e as chaves de A/B ativas (C#, bake);
##  - "window": a cada 10 s, FPS e p50/p95/p99/máx do tempo de quadro em MILISSEGUNDOS, mais as
##    contagens de quadros acima de 33,3/50/100 ms (a média de FPS sozinha esconde os engasgos);
##  - "slow": cada quadro acima de HARBOR_STALL_MS (padrão 40 ms) com o que o motor e o jogo tinham
##    naquele instante: passos de física no quadro, monitores do motor, nós/objetos, unidades de
##    despacho, chunks e, com o rastro ligado, os trechos lentos (>= 2 ms) que caíram dentro do quadro.
## O tempo de quadro é o intervalo real entre dois _process seguidos, o mesmo critério do FrameStallRecorder.
## Não decide causa: registra o contexto para a causa ser lida depois, sem repetir a rodada.

const WINDOW_SECONDS := 10.0
const MAX_SLOW_RECORDS := 1500
const SPAN_KEEP_USEC := 5000000
const SPANS_PER_RECORD := 8
const CENSUS_BUDGET_USEC := 400

var _enabled := false
var _threshold_ms := 40.0
var _writer: RefCounted
var _path := ""
var _world: Node
var _previous_usec := 0
var _previous_physics_frames := 0
var _frames: PackedFloat32Array = PackedFloat32Array()
var _window_clock := 0.0
var _started_usec := 0
var _slow_records := 0
var _last_nodes := 0
var _last_objects := 0
var _last_chunks := 0
var _last_units := 0
var _last_prune_usec := 0
var _warned_world := false
var _census_clock := 0.0
var _last_sample_usec := 0
var _last_pipelines: Dictionary = {}
var _work_summary: Dictionary = {}
var _profile_self := false
var _self_ms := PackedFloat32Array()
var _census_pending: Array[Node] = []
var _census_classes: Dictionary = {}
var _census_scripts: Dictionary = {}
var _census_seen: Dictionary = {}
var _census_started_usec := 0
var _census_ready: Dictionary = {}
## Saídas da árvore desde o callback anterior, inclusive destaque para cache.
## Guarda até 24 raízes marcadas com queue_free; não prova causa nem liberação de objetos.
var _removed_roots: Array[Dictionary] = []
var _removed_total := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("HARBOR_STALL_LOG") != "1" or "--headless" in OS.get_cmdline_args():
		queue_free()
		return
	var requested := OS.get_environment("HARBOR_STALL_MS")
	if requested.is_valid_float() and float(requested) > 0.0: _threshold_ms = float(requested)
	# Chave de A/B: teto de passos de física por quadro (padrão do motor: 8). Com 8, um quadro lento vira
	# até 8 passos de catch-up, cada um caro, e o quadro seguinte fica pior (espiral medida em 2026-10-01).
	var steps_text := OS.get_environment("HARBOR_MAX_PHYSICS_STEPS")
	if steps_text.is_valid_int() and int(steps_text) >= 1: Engine.max_physics_steps_per_frame = int(steps_text)
	var folder := ProjectSettings.globalize_path("res://evidence/stall-logs")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		folder = ProjectSettings.globalize_path("user://stall-logs")
		DirAccess.make_dir_recursive_absolute(folder)
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "-")
	_path = "%s/stalls-%s.log" % [folder, stamp]
	_writer = LOG_WRITER.new()
	if _writer.start(_path) != OK:
		queue_free()
		return
	_enabled = true
	_profile_self = OS.get_environment("HARBOR_STALL_SELF_PROFILE") == "1"
	STALL_WORK.enabled = OS.get_environment("HARBOR_STALL_WORK") != "0"
	_started_usec = Time.get_ticks_usec()
	get_tree().node_removed.connect(_on_node_removed)
	# Tempo de render por quadro (CPU e GPU) para separar "engasgou na simulação" de "engasgou no desenho".
	RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)
	_write({"type": "header", "log": _path, "threshold_ms": _threshold_ms,
		"format_version": 2, "delta_scope": "nodes_objects_chunks_previous_process_sample", "work_trace": STALL_WORK.enabled,
		"allow_background": OS.get_environment("HARBOR_STALL_BACKGROUND") == "1",
		"profile_logger": _profile_self,
		"pid": OS.get_process_id(), "clock_start_usec": _started_usec, "system_start_unix": Time.get_unix_time_from_system(),
		"version": str(ProjectSettings.get_setting("application/config/version")),
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"viewport": str(get_viewport().size), "msaa": get_viewport().msaa_3d, "render_scale": get_viewport().scaling_3d_scale,
		"max_fps": Engine.max_fps, "max_physics_steps": Engine.max_physics_steps_per_frame, "physics_hz": Engine.physics_ticks_per_second, "vsync": DisplayServer.window_get_vsync_mode(), "godot": Engine.get_version_info().string,
		"csharp_build": ClassDB.class_exists(&"CSharpScript"), "env_no_csharp": OS.get_environment("HARBOR_NO_CSHARP"),
		"env_bake_source": OS.get_environment("HARBOR_PLAN_BAKE_SOURCE"), "env_bake_result": OS.get_environment("HARBOR_PLAN_BAKE_RESULT"),
		"trace": OS.get_environment("HARBOR_STALL_TRACE") != "0"})
	print("StallLog: gravando quadros lentos (> %.0f ms) em %s" % [_threshold_ms, _path])

func _process(delta: float) -> void:
	if not _enabled: return
	var now := Time.get_ticks_usec()
	var physics_frames := Engine.get_physics_frames()
	var work := STALL_WORK.take()
	# Só conta com a partida pronta, sem pausa e com a janela em foco: carregamento e Alt-Tab não são engasgo do jogo.
	if _previous_usec > 0 and _playing():
		var ms := float(now - _previous_usec) / 1000.0
		_frames.append(ms)
		_summarize_work(work)
		if ms >= _threshold_ms and _slow_records < MAX_SLOW_RECORDS: _record_slow(ms, now, physics_frames - _previous_physics_frames, work)
	_previous_usec = now
	if now - _last_prune_usec > 2000000:
		_last_prune_usec = now
		_prune_spans()
	_previous_physics_frames = physics_frames
	_removed_roots.clear()
	_removed_total = 0
	_window_clock += delta
	if _window_clock >= WINDOW_SECONDS: _flush_window()
	_ensure_world()
	if not _census_pending.is_empty() and _playing(): _advance_census()
	# A amostra anterior precisa avançar em TODO quadro, inclusive os rápidos.
	# Antes, nodes_delta/objects_delta comparavam dois registros lentos distantes.
	_last_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_last_objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_last_chunks = _chunk_total()
	_last_pipelines = _pipeline_counts()
	_last_sample_usec = Time.get_ticks_usec()
	if _profile_self: _self_ms.append(float(_last_sample_usec - now) / 1000.0)

func _chunk_total() -> int:
	if not is_instance_valid(_world): return 0
	var production: Variant = _world.get("production")
	if production == null: return 0
	var regions: Variant = production.get("regions")
	if not regions is Dictionary: return 0
	var total := 0
	for region_node in regions.values():
		if not is_instance_valid(region_node): continue
		var resident_chunks: Variant = region_node.get("chunks")
		if resident_chunks is Dictionary: total += resident_chunks.size()
	return total

func _pipeline_counts() -> Dictionary:
	# Contadores cumulativos do motor, não duração de compilação. O cache do
	# driver pode esconder o custo mesmo quando surgem combinações novas.
	return {"canvas": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)),
		"mesh": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)),
		"surface": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)),
		"draw": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)),
		"specialization": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))}

func _summarize_work(work: Array[Dictionary]) -> void:
	for event in work:
		var label := str(event.label)
		if not event.has("ms"): continue
		var stats: Dictionary = _work_summary.get(label, {"count": 0, "total_ms": 0.0, "max_ms": 0.0})
		stats.count += 1
		stats.total_ms += float(event.ms)
		stats.max_ms = maxf(float(stats.max_ms), float(event.ms))
		_work_summary[label] = stats

func _on_node_removed(node: Node) -> void:
	_removed_total += 1
	# Só a raiz marcada: os filhos saem junto e entrariam às centenas.
	if not node.is_queued_for_deletion() or _removed_roots.size() >= 24: return
	var script: Variant = node.get_script()
	var parent := node.get_parent()
	_removed_roots.append({"name": str(node.name), "class": node.get_class(),
		"script": str(script.resource_path).get_file() if script != null else "",
		"children": node.get_child_count(), "parent": str(parent.name) if parent != null else ""})

func _start_census() -> void:
	_census_pending = [get_tree().root]
	_census_classes.clear()
	_census_scripts.clear()
	_census_seen.clear()
	_census_started_usec = Time.get_ticks_usec()

func _advance_census() -> void:
	var began := Time.get_ticks_usec()
	while not _census_pending.is_empty() and Time.get_ticks_usec() - began < CENSUS_BUDGET_USEC:
		# Nós podem sair, morrer ou mudar de pai entre as fatias.
		# Não converter para Node antes de validar: uma referência já liberada
		# gera erro na própria atribuição tipada, antes do is_instance_valid.
		var candidate: Variant = _census_pending.pop_back()
		if not is_instance_valid(candidate): continue
		var node: Node = candidate
		if not node.is_inside_tree(): continue
		var instance_id := node.get_instance_id()
		if _census_seen.has(instance_id): continue
		_census_seen[instance_id] = true
		var kind := node.get_class()
		_census_classes[kind] = int(_census_classes.get(kind, 0)) + 1
		var script: Variant = node.get_script()
		if script != null:
			var file := str(script.resource_path).get_file()
			if file.is_empty(): file = "<embedded>"
			_census_scripts[file] = int(_census_scripts.get(file, 0)) + 1
		_census_pending.append_array(node.get_children())
	if not _census_pending.is_empty(): return
	var ended := Time.get_ticks_usec()
	# É uma amostra ao longo de um intervalo, não uma fotografia de um quadro.
	_census_ready = {"classes": _top(_census_classes, 12), "scripts": _top(_census_scripts, 14),
		"nodes_visited": _census_seen.size(), "sampling_ms": float(ended - _census_started_usec) / 1000.0,
		"started_t": float(_census_started_usec - _started_usec) / 1000000.0,
		"finished_t": float(ended - _started_usec) / 1000000.0, "budget_ms": CENSUS_BUDGET_USEC / 1000.0}
	_census_seen.clear()

func _top(counts: Dictionary, limit: int) -> Dictionary:
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	var result := {}
	for key in keys.slice(0, limit): result[key] = counts[key]
	return result

func _playing() -> bool:
	if get_tree().paused or not is_instance_valid(_world): return false
	# Sondas renderizadas automatizadas podem medir sem roubar o foco do usuário.
	if not DisplayServer.window_is_focused() and OS.get_environment("HARBOR_STALL_BACKGROUND") != "1": return false
	var session: Variant = _world.get("session")
	return session != null and bool(session.get("ready_for_play"))

func _ensure_world() -> void:
	if is_instance_valid(_world): return
	var scene := get_tree().current_scene
	if scene == null or scene.get("session") == null:
		_world = null
		return
	_world = scene
	_warned_world = false
	# Liga o rastro do despacho (custo de microssegundos por gancho) para os trechos lentos aparecerem.
	if OS.get_environment("HARBOR_STALL_TRACE") != "0": _world.set_meta("benchmark_trace", true)

func _flush_window() -> void:
	_window_clock = 0.0
	if _frames.is_empty(): return
	var began := STALL_WORK.begin()
	var sorted := _frames.duplicate()
	sorted.sort()
	STALL_WORK.finish("logger.window_sort", began)
	began = STALL_WORK.begin()
	var count := sorted.size()
	var total := 0.0
	var over33 := 0
	var over50 := 0
	var over100 := 0
	for value in sorted:
		total += value
		if value > 33.3: over33 += 1
		if value > 50.0: over50 += 1
		if value > 100.0: over100 += 1
	var record := {"type": "window", "t": snappedf(float(Time.get_ticks_usec() - _started_usec) / 1000000.0, 0.1),
		"frames": count, "fps": snappedf(1000.0 * count / maxf(total, 0.001), 0.1),
		"p50_ms": snappedf(sorted[int(count * 0.5)], 0.01), "p95_ms": snappedf(sorted[mini(count - 1, int(count * 0.95))], 0.01),
		"p99_ms": snappedf(sorted[mini(count - 1, int(count * 0.99))], 0.01), "max_ms": snappedf(sorted[count - 1], 0.01),
		"over_33_ms": over33, "over_50_ms": over50, "over_100_ms": over100}
	STALL_WORK.finish("logger.window_stats", began)
	began = STALL_WORK.begin()
	record.merge(_game_state(false))
	record["pipelines"] = _pipeline_counts()
	record["work_trace"] = STALL_WORK.enabled
	if _writer != null: record["writer"] = _writer.stats()
	STALL_WORK.finish("logger.window_state", began)
	began = STALL_WORK.begin()
	if _profile_self and not _self_ms.is_empty():
		var self_sorted := _self_ms.duplicate()
		self_sorted.sort()
		var self_count := self_sorted.size()
		record["logger_ms"] = {"frames": self_count, "p50": self_sorted[int(self_count * .5)],
			"p95": self_sorted[mini(self_count - 1, int(self_count * .95))],
			"p99": self_sorted[mini(self_count - 1, int(self_count * .99))], "max": self_sorted[-1]}
		_self_ms.clear()
	if not _work_summary.is_empty():
		record["work_summary"] = _work_summary.duplicate(true)
		_work_summary.clear()
	STALL_WORK.finish("logger.window_summaries", began)
	began = STALL_WORK.begin()
	# Censo por fatias: a varredura inteira custou até 19 ms num callback.
	# Publicar somente o resultado completo, com seu intervalo de amostragem.
	if not _census_ready.is_empty():
		record["census"] = _census_ready
		_census_ready = {}
	_census_clock += WINDOW_SECONDS
	if _census_clock >= 30.0 and _playing() and _census_pending.is_empty():
		_census_clock = 0.0
		_start_census()
	STALL_WORK.finish("logger.window_census", began)
	_write(record)
	began = STALL_WORK.begin()
	_frames.clear()
	STALL_WORK.finish("logger.window_clear", began)

func _record_slow(ms: float, now: int, physics_steps: int, work: Array[Dictionary] = []) -> void:
	_slow_records += 1
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var rid := get_tree().root.get_viewport_rid()
	var record := {"type": "slow", "t": snappedf(float(now - _started_usec) / 1000000.0, 0.01), "frame_ms": snappedf(ms, 0.01),
		"process_frame": Engine.get_process_frames(), "delta_interval_ms": snappedf(float(now - _last_sample_usec) / 1000.0, 0.01),
		"focused": DisplayServer.window_is_focused(),
		"physics_steps": physics_steps,
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"render_cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(rid), 0.01),
		"render_gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(rid), 0.01),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"nodes": nodes, "nodes_delta": nodes - _last_nodes, "objects": objects, "objects_delta": objects - _last_objects,
		"phys_active": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"phys_pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)}
	record.merge(_game_state(true))
	var pipelines := _pipeline_counts()
	var pipeline_delta := {}
	for key in pipelines:
		if _last_pipelines.has(key): pipeline_delta[key] = pipelines[key] - int(_last_pipelines[key])
	record["pipelines"] = pipelines
	record["pipelines_delta"] = pipeline_delta
	if not work.is_empty(): record["work"] = work
	record["removed_nodes"] = _removed_total
	if not _removed_roots.is_empty(): record["removed_roots"] = _removed_roots.duplicate(true)
	var spans := _spans_in_frame(now - int(ms * 1000.0), now)
	if not spans.is_empty(): record["spans"] = spans
	_write(record)

## Quadro a quadro os contadores abaixo só entram nos registros lentos e nas janelas; nada roda por quadro.
func _game_state(with_deltas: bool) -> Dictionary:
	var state := {}
	if not is_instance_valid(_world): return state
	var gameplay: Variant = _world.get("gameplay")
	if gameplay != null:
		state["stars"] = int(gameplay.get("stars"))
		if with_deltas:
			# Arma na mão e o que os efeitos de combate têm ligado agora: chama/explosão custam GPU (partículas
			# translúcidas + luzes) e a primeira vez de cada luz pode recompilar pipelines no Mobile.
			var equipped: Variant = gameplay.call("equipped") if gameplay.has_method("equipped") else null
			if equipped != null: state["weapon"] = str(equipped)
			var effects: Variant = gameplay.get("effects")
			if effects != null and is_instance_valid(effects):
				var emitting := 0
				var lights := 0
				for child in effects.get_children():
					if child is CPUParticles3D and child.emitting: emitting += 1
					elif child is Light3D and child.visible: lights += 1
				state["effects_emitting"] = emitting
				state["effects_lights"] = lights
			# Fogo vivo agora: focos no chão (lança-chamas/explosão), pessoas queimando e carros com vida 0 ainda em cena.
			var tree := get_tree()
			state["fires_ground"] = tree.get_nodes_in_group("ground_fire").size()
			state["burning_people"] = tree.get_nodes_in_group("v2_burning_actor").size()
			state["wrecks"] = _count_wrecks()
	var driving: Variant = _world.get("driving")
	if driving != null: state["driving"] = bool(driving.get("occupied"))
	var dispatch: Variant = _world.get("dispatch")
	if dispatch != null:
		var census := {}
		var units: Array = dispatch.get("units")
		for unit in units:
			var key := "%s:%s" % [unit.get("service"), unit.get("state")]
			census[key] = int(census.get(key, 0)) + 1
		state["units"] = census
		# Perseguição: cada viatura de polícia com estado, distância ao alvo (m) e velocidade (m/s), e a velocidade do alvo.
		var target: Variant = gameplay.call("pursuit_target") if gameplay != null and gameplay.has_method("pursuit_target") else null
		var chase: Array = []
		for unit in units:
			if not unit.is_police() or not is_instance_valid(unit.vehicle): continue
			var gap := -1
			if is_instance_valid(target): gap = int(unit.vehicle.global_position.distance_to((target as Node3D).global_position))
			chase.append([str(unit.state), gap, snappedf(float(unit.vehicle.get("speed")), 0.1)])
		state["police_chase"] = chase
		if is_instance_valid(target) and target.get("speed") != null: state["target_speed"] = snappedf(float(target.get("speed")), 0.1)
		var router: Variant = dispatch.get("router")
		if router != null: state["router_native"] = router.get("_native") != null
		if with_deltas:
			state["units_delta"] = units.size() - _last_units
		_last_units = units.size()
	var production: Variant = _world.get("production")
	if production != null:
		var regions: Variant = production.get("regions")
		var chunks := {}
		var jobs := 0
		var total := 0
		if regions is Dictionary:
			for key in regions:
				var region: Variant = regions[key]
				if not is_instance_valid(region): continue
				var region_chunks: Variant = region.get("chunks")
				if region_chunks is Dictionary:
					chunks[str(key)] = region_chunks.size()
					total += region_chunks.size()
				var region_jobs: Variant = region.get("build_jobs")
				if region_jobs is Array: jobs += region_jobs.size()
		state["chunks"] = chunks
		state["build_jobs"] = jobs
		if with_deltas: state["chunks_delta"] = total - _last_chunks
	return state

func _count_wrecks() -> int:
	var production: Variant = _world.get("production") if is_instance_valid(_world) else null
	var vehicles: Variant = production.get("vehicles") if production != null else null
	var count := 0
	if vehicles is Array:
		for car in vehicles:
			if is_instance_valid(car) and float(car.get("health")) <= 0.0: count += 1
	return count

## Trechos lentos do rastro (perf_costs) que COMEÇARAM dentro do quadro lento, os mais longos primeiro.
func _spans_in_frame(from_usec: int, to_usec: int) -> Array:
	if not is_instance_valid(_world): return []
	var costs: Variant = _world.get_meta("perf_costs", null)
	if not costs is Array: return []
	var found: Array = []
	for entry in costs:
		if not entry is Dictionary or not entry.has("start_usec"): continue
		var started := int(entry.start_usec)
		if started < from_usec or started > to_usec: continue
		found.append({"label": str(entry.get("label", "?")), "ms": snappedf(float(entry.get("duration_usec", 0)) / 1000.0, 0.01)})
	found.sort_custom(func(a, b): return a.ms > b.ms)
	return found.slice(0, SPANS_PER_RECORD)

## perf_costs tem teto: sem poda o buffer enche em minutos e os trechos novos deixam de ser gravados.
func _prune_spans() -> void:
	if not is_instance_valid(_world): return
	var costs: Variant = _world.get_meta("perf_costs", null)
	if not costs is Array or costs.is_empty(): return
	var limit := Time.get_ticks_usec() - SPAN_KEEP_USEC
	var kept: Array = []
	for entry in costs:
		if entry is Dictionary and int(entry.get("start_usec", limit)) >= limit: kept.append(entry)
	_world.set_meta("perf_costs", kept)

func _write(record: Dictionary) -> void:
	if _writer == null: return
	var began := STALL_WORK.begin()
	var line := JSON.stringify(record)
	STALL_WORK.finish("logger.serialize", began)
	began = STALL_WORK.begin()
	_writer.enqueue(line)
	STALL_WORK.finish("logger.enqueue", began)

func _exit_tree() -> void:
	if _enabled: _flush_window()
	if _writer != null: _writer.stop()
