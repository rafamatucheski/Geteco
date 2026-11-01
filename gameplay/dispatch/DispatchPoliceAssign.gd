extends RefCounted
## Despacho da polícia: relógio de reforço por estrelas, viatura de averiguação, troca por van/tanque,
## escolha do ponto de nascimento (inclusive à frente de quem foge de carro), busca em leque e o rádio
## da central. Separado de DispatchController.gd em 01/11 só para o dono caber na leitura. O estado
## (relógios, contadores, pontos de busca, rádio, investigation_unit) e o sinal continuam no dono,
## porque testes e DispatchUnit leem esses campos lá; o dono mantém cada função antiga como delegação
## de uma linha. `g` fica como Node3D, e não como o script do dono, para não criar preload cíclico;
## até as chamadas entre funções deste arquivo passam por `g.`. Spans TRACE/STALL_WORK iguais.

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")
const RADIO := preload("res://gameplay/dispatch/PursuitRadio.gd")
const RADIO_AUDIO := preload("res://gameplay/dispatch/PursuitRadioAudio.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _dispatch_police(delta: float) -> void:
	var stars: int = g.gameplay.stars
	if stars <= 0:
		g.deployed_this_pursuit = 0
		g._last_stars = 0
		g._investigation_clock = maxf(0.0, g._investigation_clock - delta)
		var investigating: bool = g.gameplay.has_method("police_investigation_active") and g.gameplay.police_investigation_active()
		# A viatura de averiguação não pode aparecer no instante do tiro/explosão.
		if investigating and not g._investigation_seen: g._investigation_clock = RULES.INVESTIGATION_DELAY
		g._investigation_seen = investigating
		if investigating and g._investigation_clock <= 0.0:
			g._investigation_clock = 20.0
			if (g.investigation_unit == null or g.investigation_unit.finished) and g._active_police().is_empty():
				var responder: RefCounted = g.dispatch_police_to(g.gameplay.police_investigation_point(), true)
				if responder != null:
					g.investigation_unit = responder
					responder._set_siren(false)
					responder._set_state("investigating")
		return
	g.investigation_unit = null
	if g.gameplay.has_method("police_surrendering") and g.gameplay.police_surrendering(): return
	if g._last_stars == 0: g._police_clock = RULES.INITIAL_DELAY[stars]
	elif stars > g._last_stars: g._police_clock = maxf(g._police_clock, RULES.INITIAL_DELAY[stars])
	g._last_stars = stars
	g._police_clock -= delta
	if g._police_clock > 0.0: return
	# Como em WantedManager._process: o intervalo reinicia mesmo sem despachar.
	g._police_clock = RULES.INTERVAL[stars]
	# Reforços de alerta alto continuam enquanto a perseguição está ativa. Os limites de unidades
	# vivas e de agentes a pé continuam valendo; limpar a primeira onda não pode esvaziar 6 estrelas.
	if (stars < 5 and g.deployed_this_pursuit >= RULES.DEPLOYMENT[stars]) or not g.gameplay.last_known_valid: return
	if g.units.size() >= RULES.MAX_UNITS: return
	var anchor: Vector3 = g.gameplay.last_known
	if g.player_position_override != Vector3.INF:
		anchor = g.player_position_override
	else:
		var target: Variant = g.gameplay.pursuit_target()
		if is_instance_valid(target) and g.gameplay.contact_age <= 1.0: anchor = target.global_position
	g.dispatch_police_to(anchor)

## Seleciona uma equipe comum para uma van de alerta alto que falta ou, quando a cota de
## vans está cumprida, o apoio blindado de seis estrelas que falta. Os limites ativos não mudam.
func _tactical_van_replacement(level: int, active: Array, responding: Array, armor_support := false) -> RefCounted:
	var vans := RULES.tactical_van_count(responding)
	if armor_support:
		if level < 6 or vans < RULES.tactical_van_limit(level): return null
		if responding.filter(func(u): return u.variant == "tank").size() >= RULES.MAX_TANKS: return null
	elif vans >= RULES.tactical_van_limit(level): return null
	var candidate: RefCounted
	for unit in active:
		if unit.wrecked or unit.suspended or unit.state in ["recall","departing"] or unit.variant == "tank": continue
		if unit.vehicle == null or unit.vehicle.archetype == "police_transport": continue
		if candidate == null or unit.level < candidate.level or (unit.level == candidate.level and unit.serial < candidate.serial): candidate = unit
	return candidate

## Despacha uma viatura que nasce em faixa, fora da vista, a 32,5–112,5 m de `anchor`.
func dispatch_police_to(anchor: Vector3, investigation: bool = false) -> RefCounted:
	var level: int = 1 if investigation else g.gameplay.stars
	if level <= 0 or g.units.size() >= RULES.MAX_UNITS: return null
	var active: Array = g._active_police()
	# Uma equipe voltando ao carro ou saindo da cena não consegue cumprir a
	# cota de van/tanque da próxima resposta. Equipes destruídas ou suspensas também não.
	var responding := active.filter(func(u): return not u.wrecked and not u.suspended and u.state not in ["recall","departing"])
	var variant := "patrol" if investigation else RULES.response_variant(level, responding)
	var archetype := RULES.response_archetype(level,variant)
	var replacement: RefCounted
	var active_limit: int = RULES.MAX_ACTIVE[clampi(level,0,6)]
	if active.size() >= active_limit:
		# Uma escalada direta de quatro para seis pode preencher a última vaga com a
		# primeira van. A prioridade do tanque não pode deixar a segunda van sem vez para sempre.
		if variant == "tank" and RULES.tactical_van_count(responding) < RULES.tactical_van_limit(level):
			variant = "tactical"
			archetype = RULES.response_archetype(level,variant)
		var armor_support := level >= 6 and variant == "tank"
		if investigation or active.size() > active_limit or (archetype != "police_transport" and not armor_support): return null
		replacement = g._tactical_van_replacement(level,active,responding,armor_support)
		if replacement == null: return null
	var dispatch_began := TRACE.begin()
	var size: Vector3 = g._archetype_size(archetype)
	var checked := 0
	var planned := 0
	var occupied := 0
	var step := TRACE.begin()
	var candidates: Array[Dictionary] = g._depot_candidates("police", anchor)
	var ahead: Dictionary = g._spawn_ahead_direction(investigation)
	if ahead.is_empty():
		candidates.append_array(g.router.spawn_candidates(anchor, RULES.SPAWN_MIN, RULES.SPAWN_MAX))
	else:
		# Alvo fugindo de carro: o reforço nasce à frente, onde ele estará em ~2,5 s, de preferência
		# virado para ele. Do mais próximo ao mais distante, quase sempre nascia atrás e nunca alcançava.
		var speed: float = ahead.speed
		var reach := clampf(RULES.SPAWN_MAX + speed, RULES.SPAWN_MAX, PURSUIT.SPAWN_AHEAD_MAX)
		var found: Array[Dictionary] = g.router.spawn_candidates(anchor, RULES.SPAWN_MIN, reach)
		var direction: Vector3 = ahead.direction
		for candidate in found: candidate["score"] = PURSUIT.spawn_score(candidate.point, candidate.yaw, anchor, direction, speed)
		found.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.score < y.score)
		candidates.append_array(found)
	TRACE.end("police.candidates", step, {"count": candidates.size(), "ahead": not ahead.is_empty()})
	for candidate in candidates:
		if checked >= g.POLICE_CLEARANCE_CANDIDATES or planned >= g.SPAWN_CANDIDATES_CHECKED: break
		var point: Vector3 = candidate.point
		if g.is_visible_to_player(point): continue
		checked += 1
		step = TRACE.begin()
		var clear: bool = g._space_clear(size, point, candidate.yaw, g.no_exclusions)
		TRACE.end("police.clearance", step)
		if not clear:
			occupied += 1
			continue
		var heading := Vector3(-sin(candidate.yaw), 0.0, -cos(candidate.yaw))
		planned += 1
		step = TRACE.begin()
		var plan: Dictionary = g.router.plan(point, anchor, heading)
		TRACE.end("police.plan", step)
		if not plan.ok: continue
		# Mudanças de composição usam o recolhimento/partida normal, preservando a
		# equipe e o retorno físico dela. Só libera uma vaga depois que existem um spawn
		# e uma rota válidos; uma via bloqueada não pode dispensar a resposta atual.
		if replacement != null:
			replacement.abort_response()
			if g._active_police().size() >= active_limit: return null
			var replacement_event := "armored_support_replacement" if variant == "tank" else "tactical_van_replacement"
			g.emit_dispatch_event(replacement_event, {"unit":replacement,"level":level})
		g._serial += 1
		g.deployed_this_pursuit += 1
		var car: CharacterBody3D = g._create_vehicle("police", point, candidate.yaw, archetype)
		var unit: RefCounted = g._make_unit("police", car, RULES.speed_cap(variant), RULES.STUCK_POLICE)
		unit.crew_capacity = RULES.crew_size(archetype)
		unit.crew_remaining = unit.crew_capacity
		unit.serial = g._serial
		unit.level = level
		unit.variant = variant
		unit.role = RULES.pursuit_role(g._serial)
		if PURSUIT.enabled and not investigation:
			# Papéis por prioridade: a primeira viatura ativa persegue (PIT), depois flanco, bloqueio...
			var roles: Array = []
			for other in g._active_police():
				if other != unit: roles.append(other.role)
			unit.role = PURSUIT.next_role(roles)
		unit.driver.set_route(plan.curve)
		unit.set_route_goal(anchor)
		unit.set_siren_on()
		if not ahead.is_empty(): g.count_pursuit("spawn_ahead")
		g.emit_dispatch_event("dispatched", {"unit": unit, "distance": candidate.distance, "variant": variant})
		TRACE.end("police.dispatch_to", dispatch_began, {"outcome": "dispatched", "archetype": archetype})
		return unit
	g.emit_dispatch_event("spawn_failed", {"service": "police", "checked": checked, "occupied": occupied, "planned": planned, "archetype": archetype})
	TRACE.end("police.dispatch_to", dispatch_began, {"outcome": "spawn_failed", "archetype": archetype})
	return null

## Direção e velocidade do alvo para o nascimento à frente, ou vazio (alvo a pé, parado, sem
## contato, averiguação ou perseguição GTA desligada).
func _spawn_ahead_direction(investigation: bool) -> Dictionary:
	if not PURSUIT.enabled or investigation or g.player_position_override != Vector3.INF or g.gameplay.contact_age > 1.0: return {}
	var target: Variant = g.gameplay.pursuit_target()
	if not is_instance_valid(target) or not "horizontal_velocity" in target: return {}
	var velocity: Vector3 = target.horizontal_velocity
	velocity.y = 0.0
	if velocity.length() < PURSUIT.SPAWN_MOVING_SPEED: return {}
	return {"direction": velocity.normalized(), "speed": velocity.length()}

## Fala atual do rádio da central para o HUD ("" sem fala recente).
func radio_line() -> String:
	return g.radio.current(g._clock) if PURSUIT.enabled else ""

func count_pursuit(key: String) -> void:
	g.pursuit_stats[key] = int(g.pursuit_stats.get(key, 0)) + 1

## Viatura deixada para trás numa perseguição (DispatchUnit._outrun): some fora da vista, devolve a
## vaga e o orçamento de despacho (ela não falhou, só ficou para trás) e adianta o próximo reforço,
## que nasce à frente.
func recycle_outrun(unit: RefCounted) -> void:
	g.count_pursuit("outrun")
	g.deployed_this_pursuit = maxi(0, g.deployed_this_pursuit - 1)
	g._police_clock = minf(g._police_clock, 1.0)
	g.emit_dispatch_event("outrun", {"unit": unit})
	unit.finish("outrun")

## Ponto de rua para a viatura vasculhar na busca em leque: dentro do raio de busca em volta da
## última posição conhecida, longe da própria viatura e dos pontos das outras. INF sem candidatos.
func search_point_for(unit: RefCounted) -> Vector3:
	var center: Vector3 = g.gameplay.last_known
	var stars: int = g.gameplay.stars
	if g._search_center == Vector3.INF or g._search_center.distance_to(center) > 10.0 or g._search_stars != stars:
		var traced := TRACE.begin()
		var spanned := STALL_WORK.begin()
		g._search_center = center
		g._search_stars = stars
		g._search_points.clear()
		var radius := PURSUIT.search_radius(stars)
		for candidate in g.router.spawn_candidates(center, 0.0, radius, PURSUIT.SEARCH_POINT_SPACING):
			g._search_points.append(candidate.point)
		g._search_rng.seed = hash(Vector3i(roundi(center.x), roundi(center.z), stars))
		STALL_WORK.finish_slow("dispatch.search_points", spanned, 3000, g)
		TRACE.end("pursuit.search_points", traced, {"count": g._search_points.size()})
	if g._search_points.is_empty(): return Vector3.INF
	var taken: Array[Vector3] = []
	for other in g.units:
		if other != unit and other.is_police() and other.search_point != Vector3.INF: taken.append(other.search_point)
	var fallback: Vector3 = g._search_points[g._search_rng.randi_range(0, g._search_points.size() - 1)]
	for attempt in 8:
		var candidate: Vector3 = g._search_points[g._search_rng.randi_range(0, g._search_points.size() - 1)]
		if candidate.distance_to(unit.vehicle.global_position) < 25.0: continue
		var crowded := false
		for point in taken:
			if point.distance_to(candidate) < 20.0: crowded = true
		if not crowded: return candidate
	return fallback

## Fala do rádio: linha no HUD e a mesma fala em voz (pedaços gravados, PursuitRadioAudio).
func announce(event: String, street := "", heading := "", urgent := false) -> bool:
	var settings: Node = g.get_node_or_null("/root/V2Settings")
	g.radio.english = settings != null and str(settings.get("text_language")).begins_with("en")
	if not g.radio.announce(event, g._clock, street, heading, urgent): return false
	g._speak(urgent)
	return true

func _speak(urgent: bool) -> void:
	if g.radio.clips.is_empty(): return
	if g.radio_voice == null:
		g.radio_voice = RADIO_AUDIO.new()
		g.add_child(g.radio_voice)
	g.radio_voice.say(g.radio.clips, urgent)

## Rádio da central e o lado (carro/a pé) do último contato. Só lê o estado; não despacha nada.
func _tick_pursuit_awareness() -> void:
	var stars: int = g.gameplay.stars
	if stars <= 0:
		if g._radio_stars > 0: g.announce("evaded", "", "", true)
		g._radio_stars = 0
		g._had_contact = false
		return
	var target: Variant = g.gameplay.pursuit_target()
	var contact: bool = g.gameplay.contact_age <= 1.0 and is_instance_valid(target)
	if contact:
		g.pursuit_in_car = "horizontal_velocity" in target
		g.pursuit_velocity = target.horizontal_velocity if g.pursuit_in_car else Vector3.ZERO
	if stars > g._radio_stars:
		g.announce("wanted" if g._radio_stars == 0 else "escalated", "", "", true)
	g._radio_stars = stars
	if contact and not g._had_contact:
		var street: String = RADIO.place(g.router, target.global_position)
		if not street.is_empty(): g.announce("spotted", street)
	elif not contact and g._had_contact:
		g.announce("lost", RADIO.place(g.router, g.gameplay.last_known))
	elif contact and g.pursuit_in_car:
		if g.radio.fleeing(g.router, target.global_position, target.horizontal_velocity, g._clock): g._speak(false)
	g._had_contact = contact

func retain_investigator(unit: RefCounted) -> bool:
	if not g.gameplay.has_method("police_investigation_active") or not g.gameplay.police_investigation_active(): return false
	if unit.variant in ["tank","motorcycle"] or unit.wrecked or unit.finished: return false
	if unit.crew_remaining <= 0 and unit.officers.all(func(o): return not is_instance_valid(o) or o.dead): return false
	if g.investigation_unit == null or g.investigation_unit.finished: g.investigation_unit = unit
	return g.investigation_unit == unit
