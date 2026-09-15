extends SceneTree
## GETECO-PERF-01-CLAUDE — coletor de diagnóstico de CPU/simulação.
## Não altera arquivos de produção. Em runtime, só troca o laço do
## PresentationBudget por uma cópia idêntica que cronometra cada
## ensure_presentation() (desligável com --no-budget-timing).
##
## Uso (renderizado, nunca headless; dados de usuário isolados):
##   $env:APPDATA = '<projeto>/tests/perf_audit_claude/results/<run>/appdata'
##   Godot_console.exe --path . --script res://tests/perf_audit_claude/perf_audit_session.gd -- run=<run>
##
## Fases: loading (GameLoading.begin real, rota de save/continuar sem menu e sem
## cutscene) → drive (30 s) → pursuit (30 s, 4+ estrelas) → micro (tempos
## isolados, fora das estatísticas) → 2 ciclos Harbor→Mountain→Harbor por
## teleporte → save/load isolado.

const HARBOR := "res://world/harbor/HarborGame.tscn"
const BUILD_LOG_LIMIT := 4000

var run_name := "session"
var out_dir := ""
var budget_timing := true
var phases: Array[String] = []
var phase_id := 0
var f_phase := PackedInt32Array()
var f_t := PackedFloat32Array()
var f_ms := PackedFloat32Array()
var f_proc := PackedFloat32Array()
var f_phys := PackedFloat32Array()
var f_builds := PackedInt32Array()
var f_build_ms := PackedFloat32Array()
var f_pending := PackedInt32Array()
var _start_us := 0
var _prev_us := 0
var _frame_builds := 0
var _frame_build_us := 0
var _periodic := 0
var budget: Node
var build_log: Array = []
var build_count := 0
var _first_seen := {}
var markers: Array = []
var world: Node
var _world_ready_seen := false
var snapshots: Array = []
var periodic_samples: Array = []
var report := {}
var f_added := PackedInt32Array()
var f_stage := PackedInt32Array()
var f_car_x := PackedFloat32Array()
var f_car_y := PackedFloat32Array()
var f_car_speed := PackedFloat32Array()
var _frame_added := 0
var _frame_added_names: Array[String] = []
var _frame_added_kinds := {}
var spikes: Array = []
var spike_car: Node2D
var _junction_controller: Node
var _last_stage_signature := PackedInt32Array()

# Uma troca de estágio/fase em qualquer junção marca _stage_publication_pending,
# que dispara _synchronize_crossing_consumers no mesmo _process.
func _junction_stage_changed() -> bool:
	if not is_instance_valid(_junction_controller):
		_junction_controller = get_first_node_in_group("junction_traffic_controller")
		if not is_instance_valid(_junction_controller): return false
	var signature := PackedInt32Array()
	for state in _junction_controller._states.values():
		signature.append(int(state.stage) * 1000 + int(state.phase_index))
	var changed := not _last_stage_signature.is_empty() and signature != _last_stage_signature
	_last_stage_signature = signature
	return changed

# Latência da fila por classe de relevância, observada de fora (a cada 3 quadros):
# visible = origem dentro da viewport; near = dentro da margem de 220 px usada pelo
# PresentationBudget; far = fora. A classe registrada é a mais relevante já vista.
var _queue_seen := {}
var queue_done: Array = []
var queue_oldest := {"visible": 0.0, "near": 0.0, "far": 0.0}
const CLASS_RANK := {"far": 0, "near": 1, "visible": 2}

func _queue_class(actor: Node2D) -> String:
	var screen: Vector2 = actor.get_global_transform_with_canvas().origin
	var rect: Rect2 = actor.get_viewport_rect()
	if actor.is_visible_in_tree() and rect.has_point(screen): return "visible"
	if actor.is_visible_in_tree() and rect.grow(220).has_point(screen): return "near"
	return "far"

func _sample_queue() -> void:
	if not is_instance_valid(budget): return
	var now := _now_ms()
	var present := {}
	for actor in budget.pending:
		if not is_instance_valid(actor): continue
		var id: int = actor.get_instance_id()
		present[id] = true
		var kind := _queue_class(actor)
		if not _queue_seen.has(id):
			_queue_seen[id] = {"since": now, "class": kind, "ref": weakref(actor), "phase": phases[phase_id], "relevant_since": -1.0}
		elif CLASS_RANK[kind] > CLASS_RANK[_queue_seen[id].class]:
			_queue_seen[id].class = kind
		# Mesma definição do PresentationBudget 02B, mas medida de fora, para comparar
		# árvores com e sem o patch: relógio começa quando o ator entra na margem.
		if kind != "far" and float(_queue_seen[id].relevant_since) < 0.0:
			_queue_seen[id].relevant_since = now
		var age: float = now - float(_queue_seen[id].since)
		queue_oldest[kind] = maxf(queue_oldest[kind], age)
	for id in _queue_seen.keys():
		if present.has(id): continue
		var entry: Dictionary = _queue_seen[id]
		var actor = entry.ref.get_ref()
		var built := is_instance_valid(actor) and (actor.get("body_viewport") != null or actor.get("viewport") != null or actor.get("render_view") != null)
		var relevant_wait: float = now - float(entry.relevant_since) if float(entry.relevant_since) >= 0.0 else -1.0
		queue_done.append({"class": entry.class, "latency_ms_lower_bound": now - float(entry.since), "wait_since_relevant_ms": relevant_wait, "outcome": "built" if built else "removed", "script": String(actor.get_script().resource_path).get_file() if is_instance_valid(actor) and actor.get_script() != null else "", "phase": entry.phase})
		_queue_seen.erase(id)

func _queue_latency_summary() -> Dictionary:
	var result := {"oldest_pending_age_ms_by_class": queue_oldest.duplicate(), "completed": {}}
	for kind in ["visible", "near", "far"]:
		var values: Array[float] = []
		for item in queue_done:
			if item.class == kind and item.outcome == "built": values.append(float(item.latency_ms_lower_bound))
		values.sort()
		result.completed[kind] = {"built": values.size(), "p50_ms": _pct(values, 0.5) if not values.is_empty() else null, "p95_ms": _pct(values, 0.95) if not values.is_empty() else null, "max_ms": values[-1] if not values.is_empty() else null}
		var relevant: Array[float] = []
		for item in queue_done:
			if item.class == kind and item.outcome == "built" and float(item.get("wait_since_relevant_ms", -1.0)) >= 0.0: relevant.append(float(item.wait_since_relevant_ms))
		relevant.sort()
		result.completed[kind]["since_relevant"] = {"samples": relevant.size(), "p50_ms": _pct(relevant, 0.5) if not relevant.is_empty() else null, "p95_ms": _pct(relevant, 0.95) if not relevant.is_empty() else null, "max_ms": relevant[-1] if not relevant.is_empty() else null}
	var still := {"visible": 0, "near": 0, "far": 0}
	for id in _queue_seen: still[_queue_seen[id].class] += 1
	result["pending_by_class_now"] = still
	return result

func _vehicle_cache_counters() -> Dictionary:
	# Os contadores do 02B não existem na árvore "antes" do A/B: ler por Script.get(),
	# que devolve null quando o membro falta, mantém o mesmo coletor nos dois lados.
	const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
	const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
	var batcher: Script = BATCHER
	var clearance: Script = CLEARANCE
	var result := {"batcher_mesh_cache": BATCHER._mesh_cache.size(), "batcher_mesh_hits": BATCHER.cache_hits,
		"clearance_cut_cache": CLEARANCE._cache.size()}
	for entry in [["batcher_format_cache_hits", batcher, "format_cache_hits"], ["batcher_primitive_format_hits", batcher, "primitive_format_hits"],
			["batcher_mesh_cache_evictions", batcher, "mesh_cache_evictions"], ["batcher_mesh_cache_misses", batcher, "mesh_cache_misses"],
			["batcher_cache_invalidations", batcher, "cache_invalidations"], ["clearance_content_key_hits", clearance, "content_key_hits"],
			["clearance_content_key_invalidations", clearance, "content_key_invalidations"]]:
		var value = (entry[1] as Script).get(String(entry[2]))
		result[entry[0]] = value if value != null else "indisponível"
	for entry in [["batcher_format_entries", batcher, "_format_cache"], ["clearance_content_key_entries", clearance, "_content_keys"]]:
		var value = (entry[1] as Script).get(String(entry[2]))
		result[entry[0]] = (value as Dictionary).size() if value is Dictionary else "indisponível"
	return result

func _car_state() -> Array:
	if not is_instance_valid(spike_car): return [0.0, 0.0, 0.0]
	return [spike_car.global_position.x, spike_car.global_position.y, (spike_car as CharacterBody2D).velocity.length()]

func _initialize() -> void:
	_run.call_deferred()

func _now_ms() -> float:
	return (Time.get_ticks_usec() - _start_us) / 1000.0

func _set_phase(label: String) -> void:
	if not phases.has(label): phases.append(label)
	phase_id = phases.find(label)
	markers.append({"t_ms": _now_ms(), "name": "phase:" + label})

func _run() -> void:
	_start_us = Time.get_ticks_usec()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("run="): run_name = arg.trim_prefix("run=")
	budget_timing = not args.has("--no-budget-timing")
	if DisplayServer.get_name() == "headless":
		push_error("PERF_AUDIT requer renderização real")
		quit(1)
		return
	# Nunca tocar no progresso real: APPDATA precisa apontar para a pasta do run.
	if not OS.get_user_data_dir().replace("\\", "/").contains("perf_audit_claude"):
		push_error("PERF_AUDIT abortado: user data não isolado (%s)" % OS.get_user_data_dir())
		quit(1)
		return
	out_dir = ProjectSettings.globalize_path("res://tests/perf_audit_claude/results/%s" % run_name)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("saves"))
	create_timer(1200.0, true).timeout.connect(func():
		push_error("PERF_AUDIT timeout")
		_write_outputs("timeout")
		quit(2))
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", out_dir.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	seed(15092026)
	root.size = Vector2i(1280, 720)
	report["environment"] = _environment()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	budget = root.get_node("PresentationBudget")
	if budget_timing: budget.set_process(false)
	node_added.connect(_on_node_added)
	process_frame.connect(_on_frame)

	# --- A. carregamento pelo GameLoading real ---
	var loader := root.get_node("GameLoading")
	var failed := [false]
	loader.failed.connect(func(message): failed[0] = true; push_error("PERF_AUDIT loading failed: " + message))
	_set_phase("loading")
	var begin_ms := _now_ms()
	loader.begin(HARBOR)
	while loader.active and not failed[0]:
		await process_frame
		if is_instance_valid(world):
			if not markers.any(func(m): return m.name == "world_build_ready") and bool(world.get("world_build_ready")):
				markers.append({"t_ms": _now_ms(), "name": "world_build_ready"})
			if not markers.any(func(m): return m.name == "gameplay_ready") and bool(world.get("gameplay_ready")):
				markers.append({"t_ms": _now_ms(), "name": "gameplay_ready"})
	if failed[0]:
		_write_outputs("loading_failed")
		quit(1)
		return
	report["loading"] = {"begin_ms": begin_ms, "finished_ms": _now_ms(), "total_ms": _now_ms() - begin_ms, "phase_times_ms": loader.phase_times_ms.duplicate(), "pending_presentations_at_finish": budget.pending.size()}
	world = current_scene
	_snapshot("after_loading")

	_set_phase("settle")
	await _hold(3.0)

	# --- B. trânsito denso: mesmo trajeto de measure_game_frame_stability ---
	var player: Node2D = world.get_node("Player")
	var car: CharacterBody2D = world.get_node("PlayerCar")
	player.global_position = Vector2(2200, 1050)
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	world.call("_drive")
	spike_car = car
	_set_phase("drive_warmup_idle")
	await _hold(5.0)
	_set_phase("drive")
	Input.action_press("move_up")
	await _hold(30.0)
	Input.action_release("move_up")
	_snapshot("after_drive")

	# --- C. perseguição (segunda passagem pelas mesmas ruas) ---
	_set_phase("pursuit_reset")
	_teleport(car, Vector2(700, 425), 0.0)
	await _hold(2.0)
	root.get_node("WantedManager").report_crime(240)
	_set_phase("pursuit")
	Input.action_press("move_up")
	await _hold(30.0)
	Input.action_release("move_up")
	_snapshot("after_pursuit")

	_set_phase("micro")
	report["micro"] = await _micro(car)

	# --- D. travessias Harbor → Mountain → Harbor ---
	root.get_node("WantedManager").reset()
	var stream: Node = world.get_node("ContinuousWorld")
	var outbound: Path2D = null
	for lane in get_nodes_in_group("unified_traffic_lane"):
		if String(lane.get_meta("traffic_road_id", "")).ends_with("mountain_bridge_outbound"):
			outbound = lane
			break
	report["crossing"] = {"cycles": []}
	if outbound == null:
		report.crossing["error"] = "faixa mountain_bridge_outbound não encontrada"
	else:
		for cycle in 2:
			var record := {"cycle": cycle}
			var length := outbound.curve.get_baked_length()
			var seam_pose := outbound.global_transform * outbound.curve.sample_baked_with_rotation(maxf(0.0, length - 150.0), true)
			_set_phase("seam_%d" % cycle)
			_teleport(car, seam_pose.origin, seam_pose.get_rotation())
			var prepare_started := _now_ms()
			await _hold(6.0)
			var wait_started := _now_ms()
			while not stream.ready_for_crossing and _now_ms() - wait_started < 90000.0:
				await process_frame
			record["mountain_ready_after_teleport_ms"] = _now_ms() - prepare_started
			record["ready_for_crossing"] = stream.ready_for_crossing
			if not stream.ready_for_crossing:
				report.crossing.cycles.append(record)
				break
			var mountain_lane: Path2D = stream.mountain.get_node("MountainTraffic").lane
			var offset := minf(600.0, mountain_lane.curve.get_baked_length() * 0.3)
			var mountain_pose := mountain_lane.global_transform * mountain_lane.curve.sample_baked_with_rotation(offset, true)
			_set_phase("mountain_%d" % cycle)
			_teleport(car, mountain_pose.origin, mountain_pose.get_rotation())
			await _hold(1.0)
			record["region_on_mountain"] = stream.current_region
			await _hold(9.0)
			_snapshot("mountain_%d" % cycle)
			_set_phase("harbor_return_%d" % cycle)
			_teleport(car, Vector2(700, 425), 0.0)
			await _hold(1.0)
			record["region_on_return"] = stream.current_region
			await _hold(9.0)
			_snapshot("harbor_return_%d" % cycle)
			record["handoff_max_displacement"] = stream.handoff_max_displacement
			report.crossing.cycles.append(record)

	# --- E. save/load isolados ---
	_set_phase("save_load")
	var saves_node := root.get_node("SaveManager")
	var t0 := Time.get_ticks_usec()
	var save_result: Dictionary = saves_node.save_game("perf_audit_claude")
	var save_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var load_result: Dictionary = saves_node.load_game("perf_audit_claude")
	var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
	saves_node.clear_pending_save()
	report["save_load"] = {"save_game_ms": save_ms, "save_success": save_result.get("success", false), "save_path": saves_node.get_slot_path("perf_audit_claude"), "load_game_parse_ms": load_ms, "load_success": load_result.get("success", false), "note": "load_game só lê/valida o JSON; a troca de cena de um load não foi executada aqui"}
	await _hold(2.0)
	_write_outputs("complete")
	if budget_timing: budget.set_process(true)
	quit(0)

func _hold(seconds: float) -> void:
	var until := _now_ms() + seconds * 1000.0
	while _now_ms() < until:
		await process_frame

func _teleport(car: CharacterBody2D, pos: Vector2, rot: float) -> void:
	Input.action_release("move_up")
	car.global_position = pos
	car.rotation = rot
	car.velocity = Vector2.ZERO
	car.reset_physics_interpolation()
	var camera := car.get_node_or_null("Camera") as Camera2D
	if camera != null: camera.reset_smoothing()
	markers.append({"t_ms": _now_ms(), "name": "teleport", "position": [pos.x, pos.y]})

func _on_node_added(node: Node) -> void:
	_frame_added += 1
	if _frame_added_names.size() < 40:
		var parent := node.get_parent()
		_frame_added_names.append("%s<%s>@%s" % [node.name, node.get_class(), parent.name if parent != null else "-"])
	var kind := node.get_class()
	if node.get_script() != null and String(node.get_script().resource_path) != "":
		kind = String(node.get_script().resource_path).get_file()
	_frame_added_kinds[kind] = int(_frame_added_kinds.get(kind, 0)) + 1
	if world == null and node.get_parent() == root and node.scene_file_path == HARBOR:
		world = node
		markers.append({"t_ms": _now_ms(), "name": "world_enter_tree", "children": node.get_child_count()})
		# Filhos diretos ficam prontos em ordem; o intervalo entre dois sinais
		# ready consecutivos é o custo do _ready da subárvore do segundo filho.
		for child in node.get_children():
			child.ready.connect(_on_child_ready.bind(String(child.name)), CONNECT_ONE_SHOT)
		node.ready.connect(func():
			_world_ready_seen = true
			markers.append({"t_ms": _now_ms(), "name": "world_ready"}), CONNECT_ONE_SHOT)
		return
	if _world_ready_seen and is_instance_valid(world) and node.get_parent() == world:
		markers.append({"t_ms": _now_ms(), "name": "deferred_child_added:" + String(node.name)})

func _on_child_ready(child_name: String) -> void:
	markers.append({"t_ms": _now_ms(), "name": "child_ready:" + child_name})

func _on_frame() -> void:
	var now := Time.get_ticks_usec()
	if _prev_us > 0:
		f_phase.append(phase_id)
		f_t.append((now - _start_us) / 1000.0)
		f_ms.append((now - _prev_us) / 1000.0)
		f_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		f_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		f_builds.append(_frame_builds)
		f_build_ms.append(_frame_build_us / 1000.0)
		f_pending.append(budget.pending.size() if is_instance_valid(budget) else -1)
		f_added.append(_frame_added)
		var stage_changed := _junction_stage_changed()
		f_stage.append(1 if stage_changed else 0)
		var car_state := _car_state()
		f_car_x.append(car_state[0])
		f_car_y.append(car_state[1])
		f_car_speed.append(car_state[2])
		var interval_ms := (now - _prev_us) / 1000.0
		if interval_ms > 250.0 and spikes.size() < 60:
			var kinds: Array = []
			for key in _frame_added_kinds: kinds.append([_frame_added_kinds[key], key])
			kinds.sort_custom(func(a, b): return a[0] > b[0])
			var spike := {"t_ms": (now - _start_us) / 1000.0, "ms": interval_ms, "phase": phases[phase_id], "nodes_added_during_frame": _frame_added, "added_kinds_top": kinds.slice(0, 15), "added_first_names": _frame_added_names.duplicate(), "car": car_state}
			if is_instance_valid(spike_car):
				for property in ["health", "is_broken", "is_exploding", "is_driven_by_player"]:
					spike[property] = spike_car.get(property)
			if is_instance_valid(world) and world.has_node("Player"):
				spike["player_health"] = world.get_node("Player").get("health")
			spikes.append(spike)
	_frame_added = 0
	_frame_added_names.clear()
	_frame_added_kinds.clear()
	_frame_builds = 0
	_frame_build_us = 0
	_periodic += 1
	if _periodic % 15 == 0: _sample_periodic()
	if _periodic % 3 == 0: _sample_queue()
	if budget_timing and is_instance_valid(budget): _budget_tick()
	_prev_us = Time.get_ticks_usec()

func _sample_periodic() -> void:
	var t := _now_ms()
	for actor in budget.pending:
		if is_instance_valid(actor) and not _first_seen.has(actor.get_instance_id()):
			_first_seen[actor.get_instance_id()] = t
	if phases[phase_id] in ["drive", "pursuit"] or phases[phase_id].begins_with("mountain_") or phases[phase_id].begins_with("harbor_return_"):
		var reversing := 0
		var plans := 0
		var visible_units := 0
		for unit in get_nodes_in_group("emergency_vehicle"):
			if not is_instance_valid(unit) or not unit.visible: continue
			visible_units += 1
			if unit.get("is_reversing") == true: reversing += 1
			var router = unit.get("_lane_router")
			if router != null: plans += int(router.plans)
		periodic_samples.append([phases[phase_id], snappedf(t, 0.1), visible_units, reversing, plans])

# Cópia literal de systems/PresentationBudget.gd::_process, com cronômetro.
func _budget_tick() -> void:
	var started := Time.get_ticks_usec()
	for iteration in budget.max_builds_per_frame:
		if Time.get_ticks_usec() - started >= budget.budget_usec:
			return
		var best: Node2D
		var best_distance := INF
		var pending: Array[Node2D] = budget.pending
		for index in range(pending.size() - 1, -1, -1):
			var actor = pending[index]
			if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.is_queued_for_deletion():
				pending.remove_at(index)
				continue
			if not actor.is_visible_in_tree():
				continue
			if actor.get_meta("proximity_sleeping", false):
				continue
			var screen: Vector2 = actor.get_global_transform_with_canvas().origin
			var rect: Rect2 = actor.get_viewport_rect()
			if not rect.grow(220).has_point(screen):
				continue
			var distance := screen.distance_squared_to(rect.get_center())
			if distance < best_distance:
				best = actor
				best_distance = distance
		if best == null:
			return
		pending.erase(best)
		var build_started := Time.get_ticks_usec()
		best.ensure_presentation()
		var build_us := Time.get_ticks_usec() - build_started
		_frame_builds += 1
		_frame_build_us += build_us
		build_count += 1
		if build_log.size() < BUILD_LOG_LIMIT:
			var id := best.get_instance_id() if is_instance_valid(best) else 0
			var script_path := ""
			if is_instance_valid(best) and best.get_script() != null: script_path = String(best.get_script().resource_path).get_file()
			build_log.append({"t_ms": _now_ms(), "phase": phases[phase_id], "script": script_path, "us": build_us, "queued_wait_ms_lower_bound": _now_ms() - float(_first_seen.get(id, _now_ms())), "pending_after": pending.size(), "loop_us": Time.get_ticks_usec() - started})
		if Time.get_ticks_usec() - started >= budget.budget_usec:
			return

func _time_us(callable: Callable, repeats: int) -> Dictionary:
	var samples: Array[float] = []
	for i in repeats:
		var t0 := Time.get_ticks_usec()
		callable.call()
		samples.append(float(Time.get_ticks_usec() - t0))
	samples.sort()
	return {"repeats": repeats, "min_us": samples[0], "median_us": samples[samples.size() / 2], "max_us": samples[-1]}

func _micro(car: Node2D) -> Dictionary:
	var result := {}
	var stream: Node = world.get_node("ContinuousWorld")
	var focus: Vector2 = stream.exterior_position()
	var walkers := get_nodes_in_group("pedestrian")
	var authored := get_nodes_in_group("authored_sidewalk_pedestrian")
	result["population_inputs"] = {"pedestrian": walkers.size(), "authored_sidewalk_pedestrian": authored.size(), "modern_traffic": get_nodes_in_group("modern_traffic").size(), "vehicle": get_nodes_in_group("vehicle").size()}
	result["continuous_world_budget_traffic"] = _time_us(func(): stream._budget_traffic(focus), 10)
	# Parte isolada: a deduplicação com Array.has em _budget_traffic.
	result["walkers_has_dedup_only"] = _time_us(func():
		var merged := get_nodes_in_group("pedestrian")
		for actor in get_nodes_in_group("authored_sidewalk_pedestrian"):
			if not merged.has(actor): merged.append(actor), 10)
	result["active_conflict_actors"] = _time_us(func():
		preload("res://cars/traffic/TrafficSimulationBudget.gd").active_conflict_actors(self, Rect2(focus - Vector2(1500, 1000), Vector2(3000, 2000))), 5)
	result["emergency_responders_with_priority"] = preload("res://cars/traffic/TrafficEmergencyYield.gd").responders(self).size()
	var controllers := []
	for controller in get_nodes_in_group("junction_traffic_controller"):
		var entry := {"path": str(controller.get_path()), "junctions": controller._states.size(), "lanes_indexed": controller._lane_paths_by_id.size(), "projection_cache": controller._lane_projection_cache.size()}
		var graph = controller.graph_source
		entry["graph_revision"] = int(graph.call("get_routing_revision")) if is_instance_valid(graph) and graph.has_method("get_routing_revision") else -1
		entry["synced_revision"] = controller._synced_routing_revision
		entry["sync_from_graph_fast_path"] = _time_us(func(): controller._sync_from_graph(), 20)
		if is_instance_valid(graph) and graph.has_method("get_graph_data"):
			entry["get_graph_data_deep_copy"] = _time_us(func(): graph.get_graph_data(), 3)
			var signature_length := [0]
			entry["legacy_signature_str"] = _time_us(func():
				var data: Dictionary = graph.get_graph_data()
				var values: Array = []
				for junction in data.get("junctions", []):
					values.append([junction.get("id", ""), junction.get("position", Vector2.ZERO), junction.get("radius", 0.0), junction.get("signalized", (junction.get("approaches", []) as Array).size() >= 3), junction.get("roads", []), junction.get("approaches", []), controller._connection_signature(junction.get("lane_connections", []))])
				signature_length[0] = str(values).length(), 3)
			entry["legacy_signature_chars"] = signature_length[0]
		entry["synchronize_crossing_consumers"] = _time_us(func(): controller._synchronize_crossing_consumers(), 10)
		entry["refresh_lane_path_index"] = _time_us(func(): controller._refresh_lane_path_index(), 10)
		entry["refresh_signal_visuals"] = _time_us(func(): controller._refresh_signal_visuals(), 10)
		entry["telemetry"] = controller.get_telemetry_snapshot()
		controllers.append(entry)
	result["junction_controllers"] = controllers
	var wanted := root.get_node("WantedManager")
	result["wanted_stars"] = wanted.current_stars
	result["find_lane_spawn"] = _time_us(func(): wanted._find_lane_spawn(car), 5)
	result["unified_traffic_lane_count"] = get_nodes_in_group("unified_traffic_lane").size()
	var unit: Node2D = null
	for candidate in get_nodes_in_group("emergency_vehicle"):
		if is_instance_valid(candidate) and candidate.visible and candidate.can_process():
			unit = candidate
			break
	if unit != null:
		var router_script := preload("res://geodata/roads/EmergencyLaneRouter.gd")
		result["emergency_lane_router_plan"] = _time_us(func():
			var router = router_script.new()
			router._plan(unit, car.global_position), 3)
		result["emergency_lane_router_unit"] = str(unit.get_path())
	else:
		result["emergency_lane_router_plan"] = "NÃO EXECUTADO: nenhuma unidade visível"
	await process_frame
	return result

func _snapshot(label: String) -> void:
	var counts := {}
	for group in ["vehicle", "modern_traffic", "pedestrian", "authored_sidewalk_pedestrian", "emergency_vehicle", "police_officer", "unified_traffic_lane", "damageable", "ground_blood"]:
		counts[group] = get_nodes_in_group(group).size()
	var stream = world.get_node_or_null("ContinuousWorld") if is_instance_valid(world) else null
	var viewports := root.find_children("*", "SubViewport", true, false)
	# Errata 02A: UPDATE_ONCE continua valendo 1 depois de renderizar; contar por modo.
	# Enum confirmado em runtime (Godot 4.7.2): DISABLED=0 ONCE=1 WHEN_VISIBLE=2
	# WHEN_PARENT_VISIBLE=3 ALWAYS=4. Mapear por constante, nunca por posição.
	var mode_names := {SubViewport.UPDATE_DISABLED: "disabled", SubViewport.UPDATE_ONCE: "once", SubViewport.UPDATE_WHEN_VISIBLE: "when_visible", SubViewport.UPDATE_WHEN_PARENT_VISIBLE: "when_parent_visible", SubViewport.UPDATE_ALWAYS: "always"}
	var by_mode := {"disabled": 0, "once": 0, "when_visible": 0, "when_parent_visible": 0, "always": 0, "unknown": 0}
	for view in viewports:
		by_mode[mode_names.get(view.render_target_update_mode, "unknown")] += 1
	snapshots.append({
		"label": label, "t_ms": _now_ms(),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"static_memory_mib": OS.get_static_memory_usage() / 1048576.0,
		"video_memory_mib": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"presentation_pending": budget.pending.size(),
		"presentation_builds_total": build_count,
		"subviewports": viewports.size(), "subviewports_by_update_mode": by_mode,
		"presentation_budget_stats": budget.get_stats() if budget.has_method("get_stats") else "indisponível nesta revisão",
		"queue_latency": _queue_latency_summary(),
		"vehicle_caches": _vehicle_cache_counters(),
		"groups": counts,
		"streaming": stream.get_streaming_stats() if stream != null else {},
	})

func _environment() -> Dictionary:
	return {
		"engine": Engine.get_version_info(), "executable": OS.get_executable_path(), "debug_build": OS.is_debug_build(),
		"editor_hint": Engine.is_editor_hint(), "display_server": DisplayServer.get_name(),
		"renderer_method": RenderingServer.get_current_rendering_method(), "rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "adapter_vendor": RenderingServer.get_video_adapter_vendor(), "adapter_api": RenderingServer.get_video_adapter_api_version(),
		"cpu": OS.get_processor_name(), "cpu_threads": OS.get_processor_count(),
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(), "screen_size": str(DisplayServer.screen_get_size()),
		"window_size": str(DisplayServer.window_get_size()), "root_size": str(root.size), "vsync_mode": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps, "physics_ticks_per_second": Engine.physics_ticks_per_second, "max_physics_steps_per_frame": Engine.max_physics_steps_per_frame,
		"physics_interpolation": ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"user_data_dir": OS.get_user_data_dir(), "budget_timing_copy": budget_timing, "args": OS.get_cmdline_user_args(),
	}

func _pct(sorted_values: Array[float], p: float) -> float:
	return sorted_values[clampi(ceili(p * sorted_values.size()) - 1, 0, sorted_values.size() - 1)]

func _stats(pid: int) -> Dictionary:
	var values: Array[float] = []
	var total := 0.0
	var proc: Array[float] = []
	var phys: Array[float] = []
	var builds := 0
	var build_ms := 0.0
	var build_max := 0.0
	for i in f_ms.size():
		if f_phase[i] != pid: continue
		values.append(f_ms[i])
		proc.append(f_proc[i])
		phys.append(f_phys[i])
		total += f_ms[i]
		builds += f_builds[i]
		build_ms += f_build_ms[i]
		build_max = maxf(build_max, f_build_ms[i])
	if values.is_empty(): return {"frames": 0}
	var ordered := values.duplicate()
	ordered.sort()
	proc.sort()
	phys.sort()
	var result := {
		"frames": values.size(), "seconds": total / 1000.0, "mean_fps": values.size() * 1000.0 / total,
		"p50_ms": _pct(ordered, 0.5), "p95_ms": _pct(ordered, 0.95), "p99_ms": _pct(ordered, 0.99), "max_ms": ordered[-1],
		"over_16_67": values.filter(func(v): return v > 16.67).size(), "over_20": values.filter(func(v): return v > 20.0).size(),
		"over_33_33": values.filter(func(v): return v > 33.33).size(), "over_50": values.filter(func(v): return v > 50.0).size(),
		"over_100": values.filter(func(v): return v > 100.0).size(),
		"monitor_process_p50_ms": _pct(proc, 0.5), "monitor_process_p99_ms": _pct(proc, 0.99), "monitor_process_max_ms": proc[-1],
		"monitor_physics_p50_ms": _pct(phys, 0.5), "monitor_physics_p99_ms": _pct(phys, 0.99), "monitor_physics_max_ms": phys[-1],
		"presentation_builds": builds, "presentation_build_ms_total": build_ms, "presentation_build_ms_max_frame": build_max,
	}
	if values.size() >= 10000: result["p99_9_ms"] = _pct(ordered, 0.999)
	return result

func _write_outputs(status: String) -> void:
	report["status"] = status
	report["phases"] = {}
	for pid in phases.size():
		report.phases[phases[pid]] = _stats(pid)
	var worst: Array = []
	for i in f_ms.size():
		if f_ms[i] > 50.0:
			worst.append({"phase": phases[f_phase[i]], "t_ms": f_t[i], "ms": f_ms[i], "process_ms": f_proc[i], "physics_ms": f_phys[i], "builds": f_builds[i], "build_ms": f_build_ms[i], "pending": f_pending[i]})
	report["frames_over_50ms"] = worst
	report["spikes_over_250ms"] = spikes
	report["queue_latency_final"] = _queue_latency_summary()
	report["queue_completed_samples"] = queue_done.slice(0, 400)
	report["presentation_budget_stats_final"] = budget.get_stats() if is_instance_valid(budget) and budget.has_method("get_stats") else "indisponível nesta revisão"
	var stage_frames := {}
	for i in f_ms.size():
		var key := phases[f_phase[i]]
		if not stage_frames.has(key): stage_frames[key] = 0
		stage_frames[key] += f_stage[i]
	report["frames_with_junction_stage_change"] = stage_frames
	report["markers"] = markers
	report["snapshots"] = snapshots
	report["periodic_emergency_samples"] = periodic_samples
	var slow_builds := build_log.filter(func(b): return b.us >= 2000)
	var by_script := {}
	for b in build_log:
		var key := String(b.script)
		if not by_script.has(key): by_script[key] = {"count": 0, "total_us": 0, "max_us": 0, "over_2ms": 0, "max_wait_ms_lower_bound": 0.0}
		by_script[key].count += 1
		by_script[key].total_us += int(b.us)
		by_script[key].max_us = maxi(by_script[key].max_us, int(b.us))
		if int(b.us) >= 2000: by_script[key].over_2ms += 1
		by_script[key].max_wait_ms_lower_bound = maxf(by_script[key].max_wait_ms_lower_bound, float(b.queued_wait_ms_lower_bound))
	report["presentation_builds"] = {"total": build_count, "logged": build_log.size(), "by_script": by_script, "slow_builds_over_2ms": slow_builds.slice(0, 200)}
	var file := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var csv := FileAccess.open(out_dir.path_join("frames.csv"), FileAccess.WRITE)
	csv.store_line("phase,t_ms,frame_ms,process_ms,physics_ms,builds,build_ms,pending,nodes_added,junction_stage_changed,car_x,car_y,car_speed")
	for i in f_ms.size():
		csv.store_line("%s,%.2f,%.3f,%.3f,%.3f,%d,%.3f,%d,%d,%d,%.1f,%.1f,%.1f" % [phases[f_phase[i]], f_t[i], f_ms[i], f_proc[i], f_phys[i], f_builds[i], f_build_ms[i], f_pending[i], f_added[i], f_stage[i], f_car_x[i], f_car_y[i], f_car_speed[i]])
	csv.close()
	var summary := {}
	for key in report.phases: summary[key] = report.phases[key]
	print("PERF_AUDIT_STATUS ", status)
	print("PERF_AUDIT_PHASES ", JSON.stringify(summary))
	print("PERF_AUDIT_LOADING ", JSON.stringify(report.get("loading", {})))
