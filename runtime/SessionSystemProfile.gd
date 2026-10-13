extends Node
## Samples the interval before this early callback, including its physics ticks.
## Inclusive timings overlap. Missing CPU/driver/GPU work is never assigned a cause.
const WORK := preload("res://runtime/StallWorkTrace.gd")
var _previous := 0
var _window_start := 0
var _totals: Dictionary = {}
var _dropped := 0
var _frames := 0
var _render_timing := false
const HISTORY_CAPACITY := 360
var _history: Array[Dictionary] = []
var _history_cursor := 0
var _post_until := 0
var _post: Array[Dictionary] = []
var _post_flush := 0
var _context: Dictionary = {}
var _context_at := 0
var _context_id := 0
var _previous_probe_usec := 0
var _late_process_usec := 0
var _late_process_frame := 0
class EndProbe:
	extends Node
	var recorder: Node
	func _process(_delta: float) -> void:
		recorder._late_process_usec = Time.get_ticks_usec()
		recorder._late_process_frame = Engine.get_process_frames()

var _render_pre_usec := 0
var _render_post_usec := 0
var _render_frame := 0
var _render_cpu_ms := 0.0
var _render_gpu_ms := 0.0
var _physics_begin := 0
var _physics_usec := 0
var _physics_ticks := 0
var _telemetry_total_usec := 0
var _inventory = preload("res://runtime/SessionSceneInventory.gd").new()
var _inventory_at := 0
var _inventory_snapshot: Dictionary = {}
var _last_location := ""
# Janela de 1 s: tempos de quadro e GPU/CPU de render para separar "dirigindo" de "parado"
# e "limitado por GPU" de "limitado por CPU" sem depender só dos spans instrumentados.
var _window_frame_ms := PackedFloat32Array()
var _window_render_cpu := 0.0
var _window_render_gpu := 0.0
var _window_render_samples := 0
var _orphan_at := 0
var _orphan_last := -1
const ORPHAN_INTERVAL_USEC := 15000000
const ORPHAN_SAMPLE_LIMIT := 600
var _lights_at := 0
const LIGHT_REPORT_INTERVAL_USEC := 10000000
class PhysicsBeginProbe:
	extends Node
	var recorder: Node
	func _physics_process(_delta: float) -> void:
		recorder._physics_begin = Time.get_ticks_usec()
class PhysicsEndProbe:
	extends Node
	var recorder: Node
	func _physics_process(_delta: float) -> void:
		recorder._physics_usec += Time.get_ticks_usec() - recorder._physics_begin
		recorder._physics_ticks += 1

func _render_pre() -> void:
	_render_pre_usec = Time.get_ticks_usec()

func _render_post() -> void:
	_render_post_usec = Time.get_ticks_usec()
	_render_frame = Engine.get_process_frames()
	var rid := get_tree().root.get_viewport_rid()
	_render_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_render_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid)

func _sample_context(now: int) -> void:
	if now - _context_at < 250000: return
	_context_at = now
	if now - _inventory_at >= 1000000:
		_inventory_at = now
		_inventory_snapshot = _inventory.snapshot()
	_context = {"sample_usec":now, "runtime":JSON.parse_string(get_parent().call("RuntimeSnapshot")),
		"scene":get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "",
		"inventory":_inventory_snapshot, "inventory_sample_usec":_inventory_at,
		"telemetry_profile_total_usec":_telemetry_total_usec}
	var world := get_tree().root.get_node_or_null("World3D")
	if world != null and "player" in world:
		var player: Variant = world.get("player")
		if is_instance_valid(player) and player is Node3D:
			_context["player_position"] = [player.global_position.x, player.global_position.y, player.global_position.z]
			if "health" in player: _context["player_health"] = player.health
		var session: Variant = world.get("session")
		if is_instance_valid(session):
			var state: Variant = session.get("state")
			if state != null:
				_context["region"] = str(state.region_id)
				_context["place"] = str(state.place_id)
				if "world_state" in state:
					_context["time_of_day"] = state.world_state.get("time", 0.0)
					_context["weather"] = state.world_state.get("weather", 0)
			if "ready_for_play" in session: _context["session_ready"] = session.ready_for_play
		var production: Variant = world.get("production")
		if is_instance_valid(production):
			_context["world_ready"] = production.ready_for_play
			_context["travel_busy"] = production.travel_busy
			_context["vehicles"] = production.vehicles.size()
			_context["population"] = world.people.size()
			_context["density_scale"] = production.density_scale
			var streaming := {}
			for id in production.regions:
				var region: Node = production.regions[id]
				if is_instance_valid(region):
					streaming[id] = {"chunks":region.chunks.size(), "pending":region.pending.size(), "build_jobs":region.build_jobs.size()}
			_context["streaming"] = streaming
		var driving: Variant = world.get("driving")
		if is_instance_valid(driving):
			_context["driving"] = driving.occupied
			var car: Variant = driving.car
			if is_instance_valid(car):
				_context["vehicle"] = {"archetype":car.archetype, "speed":car.speed, "position":[car.global_position.x,car.global_position.y,car.global_position.z]}
	var location := str(_context.get("region", "")) + "/" + str(_context.get("place", ""))
	if location != _last_location:
		_send({"type":"location_changed", "from":_last_location, "to":location, "engine_usec":now,
			"process_frame":Engine.get_process_frames(), "context":_context, "scope":"observed_state_change_not_transition_success"})
		_last_location = location
	_context_id = int(get_parent().call("UpdateContext", JSON.stringify(_context)))

## CPU callback brackets are exact timestamps; GPU values remain asynchronous.
func _phases(now: int) -> Dictionary:
	var valid := _late_process_usec >= _previous and _late_process_usec <= now and _render_pre_usec >= _late_process_usec and _render_post_usec >= _render_pre_usec and _render_post_usec <= now
	var phases := {"valid":valid, "interval_start_usec":_previous, "interval_end_usec":now,
		"late_process_frame":_late_process_frame, "render_frame":_render_frame,
		"physics_callback_ms":float(_physics_usec)/1000.0, "physics_ticks":_physics_ticks,
		"previous_probe_ms":float(_previous_probe_usec)/1000.0,
		"scope":"wall_brackets_overlap_physics; render_bracket_is_not_GPU_time"}
	if valid:
		phases["early_to_late_ms"] = float(_late_process_usec-_previous)/1000.0
		phases["late_to_render_pre_ms"] = float(_render_pre_usec-_late_process_usec)/1000.0
		phases["render_bracket_ms"] = float(_render_post_usec-_render_pre_usec)/1000.0
		phases["post_render_to_next_callback_ms"] = float(now-_render_post_usec)/1000.0
	phases["render_sample_age_ms"] = float(now-_render_post_usec)/1000.0 if _render_post_usec > 0 else -1.0
	return phases

## Only retained synchronous spans, clipped to the interval; no double-counting parents.
## The complement is unobserved time, not proof of engine/driver/GPU cost.
func _coverage(now: int, spans: Array) -> Dictionary:
	var ranges: Array = []
	for span in spans:
		var left := maxi(_previous, int(span.start_usec))
		var right := mini(now, int(span.end_usec))
		if right > left: ranges.append([left, right])
	ranges.sort_custom(func(a: Array,b: Array) -> bool: return a[0] < b[0])
	var covered := 0
	var end := _previous
	for interval in ranges:
		covered += maxi(0, int(interval[1]) - maxi(end, int(interval[0])))
		end = maxi(end, int(interval[1]))
	return {"retained_slow_spans_union_ms":float(covered)/1000.0,
		"unobserved_ms":float(now-_previous-covered)/1000.0,
		"scope":"lower_bound_from_retained_spans_only; excludes_fast_spans; no_causal_attribution"}

func _capture_history(now: int, frame_ms: float, work: Dictionary) -> void:
	_sample_context(now)
	var sample := {"engine_usec":now, "process_frame":Engine.get_process_frames(),
		"physics_frame":Engine.get_physics_frames(), "interval_ms":frame_ms,
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"paused":get_tree().paused, "focused":DisplayServer.window_is_focused(),
		"previous_probe_usec":_previous_probe_usec,
		"late_process_usec":_late_process_usec, "late_process_frame":_late_process_frame,
		"render_pre_usec":_render_pre_usec, "render_post_usec":_render_post_usec,
		"context_id":_context_id,
		"context":{"sample_usec":_context_at, "region":_context.get("region",""), "place":_context.get("place",""),
			"runtime":{"managed_bytes":_context.get("runtime",{}).get("managed_bytes",0)}},
		"phases":_phases(now)}
	if frame_ms >= 33.3:
		if _post_until == 0:
			var ordered: Array[Dictionary] = []
			for i in _history.size():
				var row := _history[(_history_cursor + i) % _history.size()] if _history.size() == HISTORY_CAPACITY else _history[i]
				if _previous - int(row.engine_usec) <= 2000000: ordered.append(row)
			_send({"type":"frame_history", "phase":"before", "trigger_usec":now,
				"frames":ordered, "capacity":HISTORY_CAPACITY, "window_seconds":2,
				"runtime":JSON.parse_string(get_parent().call("RuntimeSnapshot"))})
		_post_until = now + 2000000
		_post_flush = now if _post_flush == 0 else _post_flush
	if _post_until != 0:
		_post.append(sample)
		if now - _post_flush >= 500000 or _post.size() >= HISTORY_CAPACITY or now >= _post_until:
			_send({"type":"frame_history", "phase":"after", "frames":_post,
				"runtime":JSON.parse_string(get_parent().call("RuntimeSnapshot"))})
			_post = []
			_post_flush = now
		if now >= _post_until:
			_post_until = 0
			_post_flush = 0
	if _history.size() < HISTORY_CAPACITY: _history.append(sample)
	else:
		_history[_history_cursor] = sample
		_history_cursor = (_history_cursor + 1) % HISTORY_CAPACITY
	if not work.get("lifecycle_events", []).is_empty():
		_send({"type":"lifecycle_events", "start_usec":_previous, "end_usec":now,
			"events":work.lifecycle_events, "dropped":work.get("lifecycle_dropped", 0)})


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100000
	var end_probe := EndProbe.new()
	end_probe.recorder = self
	end_probe.process_mode = Node.PROCESS_MODE_ALWAYS
	end_probe.process_priority = 100000
	add_child(end_probe)
	_inventory.start(get_tree())
	for index in 2:
		var probe: Node = PhysicsBeginProbe.new() if index == 0 else PhysicsEndProbe.new()
		probe.recorder = self
		probe.process_mode = Node.PROCESS_MODE_ALWAYS
		probe.process_physics_priority = -100000 if index == 0 else 100000
		add_child(probe)
	WORK.take_session()
	WORK.session_enabled = true
	_previous = Time.get_ticks_usec()
	_window_start = _previous
	_render_timing = not "--headless" in OS.get_cmdline_args()
	if _render_timing:
		RenderingServer.frame_pre_draw.connect(_render_pre)
		RenderingServer.frame_post_draw.connect(_render_post)
		RenderingServer.viewport_set_measure_render_time(get_tree().root.get_viewport_rid(), true)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var work := WORK.take_session()
	_frames += 1
	_dropped += int(work.dropped)
	for label in work.systems:
		if not _totals.has(label):
			if _totals.size() >= WORK.MAX_SESSION_LABELS:
				_dropped += int(work.systems[label].calls)
				continue
			_totals[label] = {"calls":0, "total_ms":0.0, "max_ms":0.0, "slow_calls":0}
		var row: Dictionary = _totals[label]
		var sample: Dictionary = work.systems[label]
		row.calls += int(sample.calls)
		row.slow_calls += int(sample.slow_calls)
		row.total_ms += float(sample.total_ms)
		row.max_ms = maxf(float(row.max_ms), float(sample.max_ms))
	var frame_ms := float(now - _previous) / 1000.0
	_window_frame_ms.append(frame_ms)
	if _render_timing:
		_window_render_cpu += _render_cpu_ms
		_window_render_gpu += _render_gpu_ms
		_window_render_samples += 1
	_capture_history(now, frame_ms, work)
	# Detailed work must survive even when the containing frame is below 33.3ms.
	if not work.slow_spans.is_empty():
		_send({"type":"slow_operations", "start_usec":_previous, "end_usec":now,
			"slow_spans":work.slow_spans, "dropped":work.dropped,
			"frame_ms":frame_ms, "threshold_ms":2.0})
	if frame_ms >= 33.3:
		var record := {"type":"frame_spike", "start_usec":_previous, "end_usec":now,
			"process_frame":Engine.get_process_frames(), "physics_frame":Engine.get_physics_frames(),
			"frame_ms":frame_ms, "context":_context, "context_age_ms":float(now-_context_at)/1000.0,
			"phases":_phases(now), "coverage":_coverage(now, work.slow_spans),
			"runtime":JSON.parse_string(get_parent().call("RuntimeSnapshot")),
			"monitor_scope":"latest_available_not_exact_frame",
			"render_pre_usec":_render_pre_usec, "render_post_usec":_render_post_usec, "systems":work.systems, "slow_spans":work.slow_spans,
			"dropped":work.dropped, "paused":get_tree().paused, "focused":DisplayServer.window_is_focused(),
			"process_ms":Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"attribution":"measured_inclusive_spans_only" if not work.systems.is_empty() else "unattributed"}
		if _render_timing:
			record["render_cpu_ms"] = _render_cpu_ms
			record["render_gpu_ms"] = _render_gpu_ms
			record["render_scope"] = "latest_available_viewport_sample_not_exact_spike"
		_send(record)
	_physics_usec = 0
	_physics_ticks = 0
	_previous = now
	if now - _window_start >= 1000000: _flush(now)
	_previous_probe_usec = Time.get_ticks_usec() - now
	_telemetry_total_usec += _previous_probe_usec

func _send(record: Dictionary) -> void:
	get_parent().call("RecordProfile", JSON.stringify(record))

## Resumo de 1 s com percentis exatos, tempo de render CPU/GPU e carga da cena. É o registro para
## comparar rodadas (editor × release, dirigindo × parado) sem reconstruir tudo dos quadros.
func _perf_window(now: int) -> void:
	if _window_frame_ms.is_empty(): return
	var sorted := _window_frame_ms.duplicate()
	sorted.sort()
	var count := sorted.size()
	var total := 0.0
	for value in sorted: total += value
	var driving: Variant = _context.get("driving", false)
	var record := {"type":"perf_window", "start_usec":_window_start, "end_usec":now,
		"frames":count, "fps":float(count) * 1000.0 / maxf(total, 0.001),
		"p50_ms":sorted[count / 2], "p95_ms":sorted[mini(count - 1, int(count * 0.95))],
		"p99_ms":sorted[mini(count - 1, int(count * 0.99))], "max_ms":sorted[count - 1],
		"driving":driving, "region":_context.get("region", ""), "place":_context.get("place", ""),
		"density_scale":_context.get("density_scale", 1.0), "paused":get_tree().paused,
		"focused":DisplayServer.window_is_focused(),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects_drawn":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"physics_3d_active":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"time_process_ms":Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"time_physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"scope":"exact_percentiles_of_frame_intervals_in_window; render_ms_are_window_means_of_async_samples"}
	if _render_timing and _window_render_samples > 0:
		record["render_cpu_ms"] = _window_render_cpu / _window_render_samples
		record["render_gpu_ms"] = _window_render_gpu / _window_render_samples
	_send(record)
	_window_frame_ms = PackedFloat32Array()
	_window_render_cpu = 0.0
	_window_render_gpu = 0.0
	_window_render_samples = 0

## Nós órfãos (criados e nunca postos na árvore nem liberados) ficam contados mas anônimos no
## monitor; agrupar por classe/script/nome aponta o criador. Amostra limitada e rara.
func _orphan_report(now: int) -> void:
	if now - _orphan_at < ORPHAN_INTERVAL_USEC: return
	_orphan_at = now
	var total := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if total < 100 or absi(total - _orphan_last) < 50: return
	_orphan_last = total
	var ids := Node.get_orphan_node_ids()
	var groups := {}
	var sampled := 0
	for id in ids:
		if sampled >= ORPHAN_SAMPLE_LIMIT: break
		var node := instance_from_id(id) as Node
		if node == null: continue
		sampled += 1
		var script: Variant = node.get_script()
		var script_path: String = script.resource_path if script != null else ""
		var base := node.name.rstrip("0123456789@")
		var key := "%s|%s|%s" % [node.get_class(), script_path, base]
		if not groups.has(key):
			groups[key] = {"class":node.get_class(), "script":script_path, "name":base, "count":0, "children":0}
		groups[key].count += 1
		groups[key].children += node.get_child_count()
	var rows := groups.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.count > b.count)
	_send({"type":"orphan_nodes", "engine_usec":now, "total":total, "listed_ids":ids.size(),
		"sampled":sampled, "groups":rows.slice(0, 20),
		"scope":"first_sampled_ids_only; group_by_class_script_name_without_trailing_digits"})

## Donos das luzes visíveis: em 13/10, ao meio-dia, entraram +14 OmniLight com novos chunks e a GPU foi de
## ~3 para 10,8 ms. O inventário só contava a classe; agrupar pelo script mais próximo aponta quem acende.
func _light_report(now: int) -> void:
	if now - _lights_at < LIGHT_REPORT_INTERVAL_USEC: return
	_lights_at = now
	var groups := {}
	var total := 0
	for found in get_tree().root.find_children("*", "Light3D", true, false):
		var light := found as Light3D
		if light == null or not light.is_visible_in_tree() or light.light_energy <= 0.001: continue
		# Viewports com mundo próprio (vitrine da oficina) não iluminam o jogo.
		if light.get_world_3d() != get_tree().root.world_3d: continue
		total += 1
		var owner_name := ""
		var walk: Node = light
		while walk != null:
			if walk.get_script() != null and walk != light:
				owner_name = String(walk.get_script().resource_path).get_file().get_basename()
				break
			walk = walk.get_parent()
		var key := "%s|%s|%s" % [light.get_class(), owner_name, String(light.name).rstrip("0123456789@")]
		if not groups.has(key): groups[key] = {"class": light.get_class(), "owner": owner_name, "name": String(light.name).rstrip("0123456789@"), "count": 0, "shadows": 0}
		groups[key].count += 1
		if light.shadow_enabled: groups[key].shadows += 1
	var rows := groups.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.count > b.count)
	_send({"type":"light_owners", "engine_usec":now, "visible_lit":total, "groups":rows.slice(0, 16),
		"scope":"Light3D visíveis com energia > 0, agrupados pelo script dono mais próximo"})

func _flush(now: int) -> void:
	_perf_window(now)
	_orphan_report(now)
	_light_report(now)
	if _frames == 0 and _totals.is_empty(): return
	_send({"type":"system_metrics", "start_usec":_window_start, "end_usec":now,
		"frames":_frames, "systems":_totals, "dropped":_dropped, "timing":"inclusive_do_not_sum"})
	_totals = {}
	_dropped = 0
	_frames = 0
	_window_start = now

func _exit_tree() -> void:
	# Capture the last interval while the parent writer is still alive.
	_process(0.0)
	if not _post.is_empty():
		_send({"type":"frame_history", "phase":"after_shutdown", "frames":_post})
	if RenderingServer.frame_pre_draw.is_connected(_render_pre): RenderingServer.frame_pre_draw.disconnect(_render_pre)
	if RenderingServer.frame_post_draw.is_connected(_render_post): RenderingServer.frame_post_draw.disconnect(_render_post)
	_inventory.stop()
	WORK.session_enabled = false
	_flush(Time.get_ticks_usec())
