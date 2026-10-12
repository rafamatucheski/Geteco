extends RefCounted
## Cronometragem opt-in do descarte. Sem StallLog ativo, nÃ£o guarda eventos.
## Os tempos sÃ£o aninhados: nÃ£o somar pai e filho para estimar o custo do quadro.
const MAX_EVENTS := 256
static var enabled := false
static var events: Array[Dictionary] = []
static var dropped := 0
## Independent diagnostic sink; selecting a stage-cost runner opts in explicitly.
## Logger take() never consumes these totals. No source/details records per call.
const MAX_AGGREGATE_LABELS := 512
static var aggregate_enabled := false
static var aggregate_totals: Dictionary = {}
static var aggregate_dropped := 0
## Separate session consumer; never steals StallLog events or benchmark totals.
static var session_enabled := false
static var session_totals: Dictionary = {}
static var session_slow: Array[Dictionary] = []
static var session_dropped := 0
const MAX_SESSION_LABELS := 128
static var session_lifecycle: Array[Dictionary] = []
static var session_lifecycle_dropped := 0

static func _session(label: String, began: int, ended: int, source: Node = null, details: Dictionary = {}) -> void:
	if not session_totals.has(label):
		if session_totals.size() >= MAX_SESSION_LABELS:
			session_dropped += 1
			return
		session_totals[label] = {"calls":0, "total_ms":0.0, "max_ms":0.0, "slow_calls":0}
	if label.begins_with("retire.") and not details.is_empty():
		if session_lifecycle.size() < 64:
			session_lifecycle.append({"label":label, "start_usec":began, "end_usec":ended,
				"process_frame":Engine.get_process_frames(), "details":details.duplicate(true)})
		else: session_lifecycle_dropped += 1
	var ms := float(ended - began) / 1000.0
	var row: Dictionary = session_totals[label]
	row.calls += 1
	row.total_ms += ms
	row.max_ms = maxf(float(row.max_ms), ms)
	if ms >= 2.0:
		row.slow_calls += 1
		var event := {"label":label, "ms":ms, "start_usec":began, "end_usec":ended,
			"process_frame":Engine.get_process_frames(), "physics_frame":Engine.get_physics_frames()}
		if not details.is_empty(): event["details"] = details.duplicate(true)
		if is_instance_valid(source):
			event["node"] = str(source.get_path()) if source.is_inside_tree() else str(source.name)
			var script: Variant = source.get_script()
			if script != null: event["script"] = str(script.resource_path)
		if session_slow.size() < 16:
			session_slow.append(event)
		else:
			var smallest := 0
			for i in session_slow.size():
				if float(session_slow[i].ms) < float(session_slow[smallest].ms): smallest = i
			if ms > float(session_slow[smallest].ms): session_slow[smallest] = event
			session_dropped += 1

static func take_session() -> Dictionary:
	var result := {"systems":session_totals, "slow_spans":session_slow, "dropped":session_dropped, "lifecycle_events":session_lifecycle, "lifecycle_dropped":session_lifecycle_dropped}
	session_lifecycle = []
	session_lifecycle_dropped = 0
	session_totals = {}
	session_slow = []
	session_dropped = 0
	return result

static func start_aggregate() -> void:
	aggregate_totals.clear()
	aggregate_dropped = 0
	aggregate_enabled = true

static func stop_aggregate() -> Dictionary:
	aggregate_enabled = false
	return {"labels":aggregate_totals.duplicate(true), "dropped_calls":aggregate_dropped}

static func _aggregate(label: String, elapsed_usec: int) -> void:
	if not aggregate_totals.has(label):
		if aggregate_totals.size() >= MAX_AGGREGATE_LABELS:
			aggregate_dropped += 1
			return
		aggregate_totals[label] = {"calls":0, "total_usec":0, "max_usec":0}
	var row: Dictionary = aggregate_totals[label]
	row.calls += 1
	row.total_usec += elapsed_usec
	row.max_usec = maxi(int(row.max_usec),elapsed_usec)

static func begin() -> int:
	return Time.get_ticks_usec() if enabled or aggregate_enabled or session_enabled else 0

static func finish(label: String, began: int, details: Dictionary = {}) -> void:
	if began == 0 or (not enabled and not aggregate_enabled and not session_enabled): return
	var ended := Time.get_ticks_usec()
	if session_enabled: _session(label, began, ended, null, details)
	if aggregate_enabled: _aggregate(label,ended-began)
	if not enabled: return
	if events.size() >= MAX_EVENTS:
		dropped += 1
		return
	events.append({"label": label, "start_usec": began, "end_usec": ended,
		"ms": snappedf(float(ended - began) / 1000.0, 0.001),
		"process_frame": Engine.get_process_frames(), "details": details})

static func finish_slow(label: String, began: int, minimum_usec: int = 10000, source: Node = null) -> void:
	if began == 0 or (not enabled and not aggregate_enabled and not session_enabled): return
	var ended := Time.get_ticks_usec()
	if session_enabled: _session(label, began, ended, source)
	# Aggregate even fast calls; the threshold applies only to detailed events.
	if aggregate_enabled: _aggregate(label,ended-began)
	if not enabled: return
	if ended - began < minimum_usec: return
	# Um pico nÃ£o pode desaparecer atrÃ¡s dos eventos rÃ¡pidos de um quadro.
	if events.size() >= MAX_EVENTS:
		for i in events.size():
			if float(events[i].get("ms", 0.0)) < float(minimum_usec) / 1000.0:
				events.remove_at(i)
				dropped += 1
				break
		if events.size() >= MAX_EVENTS:
			dropped += 1
			return
	var details := {}
	if is_instance_valid(source):
		details = {"name": str(source.name), "class": source.get_class(), "id": source.get_instance_id()}
		if source is Node3D: details["position"] = str(source.global_position)
		if "archetype" in source: details["archetype"] = str(source.get("archetype"))
		if "traffic" in source: details["traffic"] = source.get("traffic")
		if "health" in source: details["health"] = source.get("health")
	events.append({"label": label, "start_usec": began, "end_usec": ended,
		"ms": float(ended-began)/1000.0, "process_frame": Engine.get_process_frames(), "details": details})

static func take() -> Array[Dictionary]:
	var result := events
	events = []
	if dropped > 0:
		result.append({"label": "trace.events_dropped", "count": dropped})
		dropped = 0
	return result
