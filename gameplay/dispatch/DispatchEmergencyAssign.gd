extends RefCounted
## Despacho dos serviços de emergência (médico, rabecão, bombeiros): escolha da ocorrência mais antiga,
## garagens projetadas na faixa e `dispatch_service_to`, com a busca de ponto de partida fatiada por
## orçamento entre quadros. Separado de DispatchController.gd em 01/11 só para o dono caber na leitura.
## O estado (_service_clock, _scan_clock, _search_pending, _fire_lockout_until, depots, units) continua
## no dono; o dono mantém cada função antiga como delegação de uma linha. `g` fica como Node3D, e não
## como o script do dono, para não criar preload cíclico; até as chamadas entre funções deste arquivo
## passam por `g.`. Spans TRACE iguais.

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _dispatch_emergency(delta: float) -> void:
	g._service_clock = maxf(0.0, g._service_clock - delta)
	g._scan_clock -= delta
	if g._scan_clock > 0.0: return
	g._scan_clock = 0.5
	var legacy_crews: int = g.gameplay.emergency.crews.filter(func(crew): return is_instance_valid(crew) and not crew.dead).size()
	if g._service_clock > 0.0 or g._active_services().size()+legacy_crews >= RULES.MAX_CREWS or g.units.size() >= RULES.MAX_UNITS: return
	var emergency: Node3D = g.gameplay.emergency
	var best_key := -1
	var best_age := -1.0
	var fire_trucks: int = g.units.filter(func(u): return u.service == "fire" and not u.finished).size()
	for key in emergency.incidents.keys():
		var record: Dictionary = emergency.incidents[key]
		var actor: Variant = record.get("actor")
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			emergency.incidents.erase(key)
			if is_instance_valid(g.bridge): g.bridge.roles.erase(key)
			g.emit_dispatch_event("incident_invalid", {"incident": key, "reason": "actor_removed"})
			continue
		if record.assigned or record.role not in ["medic", "mortician", "fire"]: continue
		if record.role == "mortician" and not emergency.mortician_dispatch_allowed(key):
			# Se as estrelas subirem durante a busca, abandonamos os candidatos.
			# A ocorrência permanece disponível para quando a situação acalmar.
			record.erase("search")
			continue
		if record.role == "medic" and float(record.age) < RULES.medic_response_delay(int(key)): continue
		# Um caminhão de bombeiros por vez, só depois de 10-15 s de fogo, e 30-45 s de pausa se o anterior foi destruído.
		if record.role == "fire":
			if fire_trucks >= RULES.MAX_FIRE_TRUCKS or g._clock < g._fire_lockout_until: continue
			if float(record.age) < RULES.fire_response_delay(int(key)): continue
		if g.distance_to_player(actor.global_position) > RULES.RESPONSE_RADIUS: continue
		# Uma busca já em andamento tem prioridade, para não trocar de ocorrência no meio.
		var priority: float = record.age + (100000.0 if record.has("search") else 0.0)
		if priority > best_age:
			best_age = priority
			best_key = key
	if best_key < 0: return
	if g.dispatch_service_to(best_key, g.SERVICE_SEARCH_BUDGET) != null: g._service_clock = RULES.DISPATCH_COOLDOWN
	elif g._search_pending: g._scan_clock = 0.0
	else: g._service_clock = 3.0

## Garagens registradas com set_depots, projetadas na faixa mais próxima.
func _depot_candidates(service: String, target: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for depot in g.depots.get(service, []):
		var edge: Dictionary = g.router.nearest_edge(depot)
		if edge.is_empty(): continue
		var direction: Vector3 = (g.routes.vertices[edge.edge.to] - g.routes.vertices[edge.edge.from]).normalized()
		result.append({"point": edge.closest, "yaw": atan2(-direction.x, -direction.z), "distance": depot.distance_to(target), "depot": true})
	return result

## Despacha a viatura da ocorrência `key` do EmergencyManager, sem teleporte:
## nasce em garagem (`depots`) ou faixa fora da vista e chega dirigindo.
func dispatch_service_to(key: int, budget: int = -1) -> RefCounted:
	# `budget` >= 0 reparte a busca de ponto de partida em vários quadros: no máx. `budget`
	# candidatos planejados por chamada, com o estado guardado em `record.search`.
	# Tudo num quadro só custava 40-80 ms na 1ª ocorrência (varredura do grafo de ruas +
	# até 8 planos de rota; tests/measure/probe_first_emergency.gd). Sem orçamento (-1)
	# roda até o fim na hora, como antes.
	g._search_pending = false
	var emergency: Node3D = g.gameplay.emergency
	if not emergency.incidents.has(key): return null
	var record: Dictionary = emergency.incidents[key]
	var actor: Variant = record.get("actor")
	if record.assigned or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		record.erase("search")
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			emergency.incidents.erase(key)
			if is_instance_valid(g.bridge): g.bridge.roles.erase(key)
			g.emit_dispatch_event("incident_invalid", {"incident": key, "reason": "actor_removed"})
		return null
	var service: String = record.role
	var point: Vector3 = actor.global_position
	var size: Vector3 = g._archetype_size(RULES.archetype_for(service))
	var state: Dictionary = record.get("search", {})
	if state.is_empty():
		var sweep := TRACE.begin()
		var found: Array[Dictionary] = g._depot_candidates(service, point)
		found.append_array(g.router.spawn_candidates(point, RULES.SERVICE_SPAWN_MIN, RULES.SERVICE_SPAWN_MAX))
		TRACE.end("service.candidates", sweep, {"count": found.size()})
		state = {"candidates": found, "index": 0, "checked": 0, "best": {}, "best_length": INF}
		if budget >= 0:
			# A coleta de candidatos já é o trabalho deste quadro.
			record.search = state
			g._search_pending = true
			return null
	var candidates: Array = state.candidates
	var work := 0
	# Escolhe a rota mais curta entre os candidatos checados. O primeiro válido às
	# vezes nascia numa faixa apontada para longe e o caminhão dava a volta no
	# quarteirão: 50 a 140 s para um incêndio a 33 m (sonda de 2026-09-24).
	while state.index < candidates.size() and state.checked < g.SPAWN_CANDIDATES_CHECKED_SERVICE:
		if budget >= 0 and work >= budget:
			record.search = state
			g._search_pending = true
			return null
		var candidate: Dictionary = candidates[state.index]
		state.index += 1
		var start: Vector3 = candidate.point
		# Sair da garagem é crível mesmo perto; surgir no meio da rua, não.
		if g.is_visible_to_player(start) or (not candidate.get("depot", false) and g.distance_to_player(start) < RULES.SERVICE_SPAWN_PLAYER_CLEARANCE): continue
		state.checked += 1
		work += 1
		var probe := TRACE.begin()
		var start_clear: bool = g._space_clear(size, start, candidate.yaw, g.no_exclusions)
		TRACE.end("service.clearance", probe)
		if not start_clear: continue
		var heading := Vector3(-sin(candidate.yaw), 0.0, -cos(candidate.yaw))
		probe = TRACE.begin()
		var candidate_plan: Dictionary = g.router.plan(start, point, heading)
		TRACE.end("service.plan", probe)
		if not candidate_plan.ok or candidate_plan.end_gap > RULES.FOOT_RANGE: continue
		var length: float = candidate_plan.curve.get_baked_length()
		if length < state.best_length:
			state.best_length = length
			state.best = {"candidate": candidate, "plan": candidate_plan}
	record.erase("search")
	var best: Dictionary = state.best
	if not best.is_empty() and budget >= 0:
		# O ponto foi escolhido quadros atrás: confirma que ainda está livre e fora da vista.
		var chosen: Dictionary = best.candidate
		if g.is_visible_to_player(chosen.point) or (not chosen.get("depot", false) and g.distance_to_player(chosen.point) < RULES.SERVICE_SPAWN_PLAYER_CLEARANCE) or not g._space_clear(size, chosen.point, chosen.yaw, g.no_exclusions): best = {}
	if not best.is_empty():
		var candidate: Dictionary = best.candidate
		var plan: Dictionary = best.plan
		var start: Vector3 = candidate.point
		g._serial += 1
		var car: CharacterBody3D = g._create_vehicle(service, start, candidate.yaw)
		var unit: RefCounted = g._make_unit(service, car, RULES.SPEED_PATROL, RULES.STUCK_SERVICE)
		unit.serial = g._serial
		unit.incident_id = key
		unit.actor = actor
		unit.driver.set_route(plan.curve)
		unit.set_route_goal(point)
		unit.set_siren_on()
		record.assigned = true
		record.crew = car
		if service != "fire" and is_instance_valid(actor): actor.set_meta("emergency_attended", true)
		if service == "mortician": emergency.mortician_clock = RULES.MORTICIAN_COOLDOWN
		g.emit_dispatch_event("dispatched", {"unit": unit, "distance": candidate.distance, "end_gap": plan.end_gap})
		return unit
	g.emit_dispatch_event("spawn_failed", {"service": service, "checked": state.checked, "incident": key})
	return null
