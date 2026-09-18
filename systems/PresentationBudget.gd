extends Node
## O orçamento limita trabalho entre entidades; um rig individual é indivisível.
## budget_usec só é conferido antes de escolher e depois de construir: uma
## construção longa NÃO é interrompida. get_stats() expõe esse custo real,
## as violações e a espera por relevância para que a fila seja verificável.
var pending: Array[Node2D] = []
var max_builds_per_frame := 1
var budget_usec := 2000

const LATENCY_SAMPLES := 256
var _requested_msec: Dictionary = {}
# Espera relevante: começa quando o ator entra na margem de construção (visível ou
# prestes a entrar). A idade desde o pedido inclui o tempo em que ele estava longe
# da câmera e sozinha não mede atraso de apresentação.
var _relevant_msec: Dictionary = {}
var _stats := {"requests": 0, "builds": 0, "cancelled": 0, "over_budget_builds": 0, "max_build_usec": 0}
var _by_kind: Dictionary = {}
var _latency: Dictionary = {"visible": [], "near": []}
var _oldest_msec: Dictionary = {"visible": 0, "near": 0, "far": 0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func request(actor: Node2D) -> void:
	if not pending.has(actor):
		pending.append(actor)
		_requested_msec[actor.get_instance_id()] = Time.get_ticks_msec()
		_stats.requests += 1

func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	var now_msec := Time.get_ticks_msec()
	for iteration in max_builds_per_frame:
		if Time.get_ticks_usec() - started >= budget_usec:
			return
		var best: Node2D
		var best_distance := INF
		var best_class := "near"
		var oldest := {"visible": 0, "near": 0, "far": 0}
		for index in range(pending.size() - 1, -1, -1):
			var actor := pending[index]
			if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.is_queued_for_deletion():
				pending.remove_at(index)
				_stats.cancelled += 1
				continue
			var age: int = now_msec - int(_requested_msec.get(actor.get_instance_id(), now_msec))
			if not actor.is_visible_in_tree() or actor.get_meta("proximity_sleeping", false):
				oldest.far = maxi(oldest.far, age)
				continue
			var screen := actor.get_global_transform_with_canvas().origin
			var rect := actor.get_viewport_rect()
			if not rect.grow(220).has_point(screen):
				oldest.far = maxi(oldest.far, age)
				continue
			var kind := "visible" if rect.has_point(screen) else "near"
			var actor_id := actor.get_instance_id()
			if not _relevant_msec.has(actor_id): _relevant_msec[actor_id] = now_msec
			oldest[kind] = maxi(oldest[kind], now_msec - int(_relevant_msec[actor_id]))
			var distance := screen.distance_squared_to(rect.get_center())
			if distance < best_distance:
				best = actor
				best_distance = distance
				best_class = kind
		_oldest_msec = oldest
		_forget_released()
		if best == null:
			return
		pending.erase(best)
		var id := best.get_instance_id()
		var since_request: int = now_msec - int(_requested_msec.get(id, now_msec))
		var waited: int = now_msec - int(_relevant_msec.get(id, now_msec))
		_requested_msec.erase(id)
		_relevant_msec.erase(id)
		var kind_name := best.name + " (" + best.get_class() + ")"
		if best.get_script() != null and not String(best.get_script().resource_path).is_empty():
			kind_name = String(best.get_script().resource_path).get_file()
		# Veículos com modelo adiado: separar por classe de modelo, pois primeiro
		# exemplar e exemplares repetidos têm custos muito diferentes.
		var pending_spec = best.get("_pending_spec")
		if pending_spec is Dictionary and pending_spec.has("model_class"):
			kind_name += ":" + String(pending_spec.model_class).get_file()
		var build_started := Time.get_ticks_usec()
		best.ensure_presentation()
		var build_usec := Time.get_ticks_usec() - build_started
		if build_usec > 5000:
			print("PB_BUILD: %s took %.2f ms" % [kind_name, build_usec / 1000.0])
		_record_build(kind_name, build_usec, best_class, waited, since_request)
		if Time.get_ticks_usec() - started >= budget_usec:
			return

func _record_build(kind_name: String, usec: int, relevance: String, waited_msec: int, since_request_msec: int) -> void:
	_stats.max_age_since_request_msec = maxi(int(_stats.get("max_age_since_request_msec", 0)), since_request_msec)
	_stats.builds += 1
	_stats.max_build_usec = maxi(_stats.max_build_usec, usec)
	if usec > budget_usec: _stats.over_budget_builds += 1
	if not _by_kind.has(kind_name): _by_kind[kind_name] = {"builds": 0, "total_usec": 0, "max_usec": 0, "over_budget": 0}
	var entry: Dictionary = _by_kind[kind_name]
	entry.builds += 1
	entry.total_usec += usec
	entry.max_usec = maxi(entry.max_usec, usec)
	if usec > budget_usec: entry.over_budget += 1
	var samples: Array = _latency[relevance]
	samples.append(waited_msec)
	if samples.size() > LATENCY_SAMPLES: samples.pop_front()

func _forget_released() -> void:
	# Pedidos liberados por troca de cena deixam carimbos órfãos; limpar em lote.
	if _requested_msec.size() + _relevant_msec.size() <= 2 * pending.size() + 64: return
	var alive := {}
	for actor in pending:
		if is_instance_valid(actor): alive[actor.get_instance_id()] = true
	for id in _requested_msec.keys():
		if not alive.has(id): _requested_msec.erase(id)
	for id in _relevant_msec.keys():
		if not alive.has(id): _relevant_msec.erase(id)

func get_stats() -> Dictionary:
	var latency := {}
	for relevance in _latency:
		var ordered: Array = (_latency[relevance] as Array).duplicate()
		ordered.sort()
		latency[relevance] = {"samples": ordered.size(),
			"p50_msec": ordered[ordered.size() / 2] if not ordered.is_empty() else null,
			"p95_msec": ordered[mini(ordered.size() - 1, int(ordered.size() * 0.95))] if not ordered.is_empty() else null,
			"max_msec": ordered[-1] if not ordered.is_empty() else null}
	return {"budget_usec": budget_usec, "pending": pending.size(), "totals": _stats.duplicate(), "by_kind": _by_kind.duplicate(true),
		"wait_since_relevant_msec": latency, "oldest_pending_msec": _oldest_msec.duplicate(),
		"oldest_note": "visible/near: desde que ficou relevante; far: desde o pedido"}
