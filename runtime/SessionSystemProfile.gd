extends Node
## Amostra o intervalo antes deste callback antecipado, incluindo os ticks de física.
## Tempos inclusivos se sobrepõem. Trabalho de CPU/driver/GPU que falta nunca recebe uma causa.
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
var _shutting_down := false
var _previous_probe_usec := 0
## Telemetria pesada fora do quadro do pico (auditoria 19/10, §1). Nos logs de 19/10, o callback
## logo depois de um quadro > 33 ms (frame_spike + RuntimeSnapshot + JSON.stringify do histórico de
## até 360 quadros) custava 11–21 ms na thread principal e criava um SEGUNDO pico (36–52 ms em 6
## casos numa sessão). Agora o quadro do pico só guarda referências e pede ao C# um retrato do
## runtime (objeto CLR, serializado na thread de escrita); o JSON sai em fatias de até
## DEFERRED_BUDGET_USEC nos callbacks seguintes. `previous_probe_ms` continua sendo o custo total do
## callback anterior (inclui a fatia), para conferir no log que o segundo pico sumiu.
const DEFERRED_BUDGET_USEC := 1500
const DEFERRED_MAX_JOBS := 64
var _deferred: Array[Dictionary] = []
var _deferred_dropped := 0
var _previous_deferred_usec := 0
var _rich_sink := false
var _late_process_usec := 0
var _late_process_frame := 0
class EndProbe:
	extends Node
	var recorder: Node
	func _process(_delta: float) -> void:
		recorder._late_process_usec = Time.get_ticks_usec()
		recorder._late_process_frame = Engine.get_process_frames()
		# Marca no fim da fila de chamadas diferidas (22/10): divide late_to_render_pre em diferidas
		# (call_deferred da partida, corpos de NPC) e o resto (remoções, sync do RenderingServer).
		recorder._deferred_tail.call_deferred()

var _process_signal_usec := 0
func _on_process_frame_signal() -> void:
	_process_signal_usec = Time.get_ticks_usec()

var _deferred_tail_usec := 0
func _deferred_tail() -> void:
	_deferred_tail_usec = Time.get_ticks_usec()

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
		if is_instance_valid(player) and player is Node3D and player.is_inside_tree():
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
			if is_instance_valid(car) and car.is_inside_tree():
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
		"previous_deferred_ms":float(_previous_deferred_usec)/1000.0, "deferred_pending":_deferred.size(),
		"scope":"wall_brackets_overlap_physics; render_bracket_is_not_GPU_time; previous_probe_includes_deferred"}
	if valid:
		phases["early_to_late_ms"] = float(_late_process_usec-_previous)/1000.0
		phases["late_to_render_pre_ms"] = float(_render_pre_usec-_late_process_usec)/1000.0
		phases["render_bracket_ms"] = float(_render_post_usec-_render_pre_usec)/1000.0
		phases["post_render_to_next_callback_ms"] = float(now-_render_post_usec)/1000.0
		if _process_signal_usec >= _render_post_usec and _process_signal_usec <= now:
			phases["post_render_to_process_signal_ms"] = float(_process_signal_usec-_render_post_usec)/1000.0
			phases["process_signal_to_callback_ms"] = float(now-_process_signal_usec)/1000.0
		if _deferred_tail_usec >= _late_process_usec and _deferred_tail_usec <= _render_pre_usec:
			phases["late_to_deferred_tail_ms"] = float(_deferred_tail_usec-_late_process_usec)/1000.0
			phases["deferred_tail_to_render_pre_ms"] = float(_render_pre_usec-_deferred_tail_usec)/1000.0
	phases["render_sample_age_ms"] = float(now-_render_post_usec)/1000.0 if _render_post_usec > 0 else -1.0
	return phases

## Só spans síncronos retidos, recortados ao intervalo; sem contar pais duas vezes.
## O complemento é tempo não observado, não prova de custo do motor/driver/GPU.
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
	# O contexto (RuntimeSnapshot + JSON do mundo, a cada 250 ms) espera o callback seguinte se este
	# acabou de ver um pico; o registro do pico leva o último publicado e a idade dele (context_age_ms).
	if frame_ms < 33.3: _sample_context(now)
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
			# Só referências no quadro do pico: as linhas do anel nunca são alteradas depois de
			# gravadas (o anel troca o Dictionary inteiro), então o JSON pode sair depois.
			var ordered: Array = []
			for i in _history.size():
				var row := _history[(_history_cursor + i) % _history.size()] if _history.size() == HISTORY_CAPACITY else _history[i]
				if _previous - int(row.engine_usec) <= 2000000: ordered.append(row)
			_defer_rows({"type":"frame_history", "phase":"before", "trigger_usec":now,
				"capacity":HISTORY_CAPACITY, "window_seconds":2, "serialization":"deferred_slices_runtime_at_trigger"},
				ordered, _hold_snapshot())
		_post_until = now + 2000000
		_post_flush = now if _post_flush == 0 else _post_flush
	if _post_until != 0:
		_post.append(sample)
		if now - _post_flush >= 500000 or _post.size() >= HISTORY_CAPACITY or now >= _post_until:
			_defer_rows({"type":"frame_history", "phase":"after", "serialization":"deferred_slices_runtime_at_flush"},
				_post, _hold_snapshot())
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
	# Início do sinal process_frame (22/10): conexão fixa feita cedo vem antes das corrotinas que esperam o
	# sinal a cada quadro. Divide post_render_to_next_callback em física/entrada e corrotinas do sinal.
	get_tree().process_frame.connect(_on_process_frame_signal)
	WORK.take_session()
	WORK.session_enabled = true
	_rich_sink = get_parent().has_method("HoldRuntimeSnapshot") and get_parent().has_method("RecordProfileWithSnapshot")
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
	# O trabalho detalhado precisa sobreviver mesmo quando o quadro que o contém fica abaixo de 33.3ms.
	if not work.slow_spans.is_empty():
		_send({"type":"slow_operations", "start_usec":_previous, "end_usec":now,
			"slow_spans":work.slow_spans, "dropped":work.dropped,
			"frame_ms":frame_ms, "threshold_ms":2.0})
	var spike := frame_ms >= 33.3
	if spike:
		# "context" e "runtime" entram na thread de escrita do C# a partir do retrato tirado aqui
		# (_hold_snapshot); o Dictionary vira JSON num callback seguinte (_drain_deferred).
		var record := {"type":"frame_spike", "start_usec":_previous, "end_usec":now,
			"process_frame":Engine.get_process_frames(), "physics_frame":Engine.get_physics_frames(),
			"frame_ms":frame_ms, "context_age_ms":float(now-_context_at)/1000.0, "context_id":_context_id,
			"phases":_phases(now), "coverage":_coverage(now, work.slow_spans),
			"serialization":"deferred_runtime_and_context_at_spike",
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
		_defer_record(record, _hold_snapshot())
	_physics_usec = 0
	_physics_ticks = 0
	_previous = now
	if now - _window_start >= 1000000: _flush(now)
	# Nada de fatia no callback que acabou de ver o pico: é exatamente o quadro que não pode crescer.
	_previous_deferred_usec = 0
	if not spike and not _deferred.is_empty():
		var drain_start := Time.get_ticks_usec()
		_drain_deferred(DEFERRED_BUDGET_USEC)
		_previous_deferred_usec = Time.get_ticks_usec() - drain_start
	_previous_probe_usec = Time.get_ticks_usec() - now
	_telemetry_total_usec += _previous_probe_usec

func _send(record: Dictionary) -> void:
	get_parent().call("RecordProfile", JSON.stringify(record))

## Retrato do runtime (GC, fila de escrita, monitores, operações ativas) e do último contexto publicado,
## guardado no C# como objeto CLR: custa microssegundos aqui e só é serializado na thread de escrita.
func _hold_snapshot() -> int:
	return int(get_parent().call("HoldRuntimeSnapshot")) if _rich_sink else 0

func _enqueue_deferred(job: Dictionary) -> void:
	# Teto para pico em rajada (carregamento travado): perde o mais antigo e conta, não cresce sem fim.
	if _deferred.size() >= DEFERRED_MAX_JOBS:
		_deferred.pop_front()
		_deferred_dropped += 1
	_deferred.append(job)

func _defer_record(record: Dictionary, snapshot: int) -> void:
	_enqueue_deferred({"record":record, "snapshot":snapshot, "attach_context":true})

## Registro com lista longa (histórico de quadros): cada linha vira JSON separada, dentro do orçamento.
func _defer_rows(header: Dictionary, rows: Array, snapshot: int) -> void:
	_enqueue_deferred({"record":header, "rows":rows, "parts":PackedStringArray(), "cursor":0,
		"snapshot":snapshot, "attach_context":false})

## budget_usec < 0 esvazia tudo (saída do jogo). A checagem de tempo é por linha/registro: uma linha
## custa dezenas de microssegundos, então a fatia passa do orçamento no máximo por uma linha.
func _drain_deferred(budget_usec: int) -> void:
	var started := Time.get_ticks_usec()
	while not _deferred.is_empty():
		var job: Dictionary = _deferred[0]
		if job.has("rows"):
			var rows: Array = job.rows
			var parts: PackedStringArray = job.parts
			var cursor: int = job.cursor
			while cursor < rows.size():
				parts.append(JSON.stringify(rows[cursor]))
				cursor += 1
				if budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec: break
			job.parts = parts
			job.cursor = cursor
			if cursor < rows.size(): return
		_deferred.pop_front()
		_emit_deferred(job)
		if budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec: return

func _emit_deferred(job: Dictionary) -> void:
	var record: Dictionary = job.record
	if _deferred_dropped > 0:
		record["deferred_jobs_dropped"] = _deferred_dropped
		_deferred_dropped = 0
	var json := JSON.stringify(record)
	if job.has("rows"):
		# Cabeçalho + linhas já serializadas: só concatenação aqui, nada de reconverter as linhas.
		json = json.left(-1) + (',' if record.size() > 0 else '') + '"frames":[' + ",".join(job.parts) + "]}"
	if _rich_sink:
		get_parent().call("RecordProfileWithSnapshot", json, int(job.snapshot), bool(job.attach_context))
	else:
		get_parent().call("RecordProfile", json)

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
	# Durante o exit_tree, filhos visíveis podem já ter saído do World3D. Mantém
	# o último inventário completo; o descarte final de tempos/métricas ainda roda.
	if _shutting_down: return
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
	_shutting_down = true
	# Captura o último intervalo enquanto o escritor pai ainda está vivo.
	_process(0.0)
	# Na saída não há quadro seguinte: o que ficou adiado sai inteiro, enquanto o C# ainda escreve.
	_drain_deferred(-1)
	if not _post.is_empty():
		_send({"type":"frame_history", "phase":"after_shutdown", "frames":_post})
	if RenderingServer.frame_pre_draw.is_connected(_render_pre): RenderingServer.frame_pre_draw.disconnect(_render_pre)
	if RenderingServer.frame_post_draw.is_connected(_render_post): RenderingServer.frame_post_draw.disconnect(_render_post)
	_inventory.stop()
	WORK.session_enabled = false
	_flush(Time.get_ticks_usec())
