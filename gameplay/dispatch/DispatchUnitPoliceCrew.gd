extends RefCounted
## Equipe da viatura de polícia: estacionada esperando a parada e a porta, desembarque em levas por
## pontos livres, trabalho a pé, recolhimento (com volta à perseguição) e embarque de quem voltou com
## os ferimentos guardados. Separado de DispatchUnit.gd em 01/11 só para o dono caber na leitura. O
## estado (officers, crew_remaining, _seated_durability, _exit_points, _exit_wait, _recall_age,
## resume_pursuit) e as constantes da espera (CREW_EXIT_DELAY, DOOR_WARM_WAIT, quick_exit) continuam
## em DispatchUnit, porque testes, DispatchController e DispatchOfficer leem esses campos lá; o dono
## mantém cada função antiga como delegação de uma linha com a mesma assinatura (on_officer_boarded
## continua sendo o Callable ligado ao sinal `boarded` do policial). Tudo estático: a unidade é
## RefCounted, e um auxiliar com `var g` guardado faria ciclo de referência que nunca é liberado.
## Cada função recebe a unidade em `g` (RefCounted, e não o script do dono, para não criar preload
## cíclico) e passa por `g.` até nas chamadas entre funções deste arquivo:
## tests/dispatch/test_police_foot_stop.gd sobrescreve `_target` e `_sees_target`.

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")

static func _police_parked(g: RefCounted, delta: float) -> void:
	g.driver.hold(true)
	g.driver.tick(delta)
	var moving_target: Node3D = g._target()
	if g.variant != "tank" and g._target_in_car(moving_target) and g._target_velocity(moving_target).length() > 3.0 and g.controller.gameplay.contact_age < 1.0:
		g.stop_planner.reset()
		g._park_reset()
		g._plan_clock = 0.0
		g._since_plan = PURSUIT.REPLAN_MAX
		g._set_state("enroute")
		return
	if g.variant == "tank" and g.controller.gameplay.stars > 0:
		var target: Node3D = g._target()
		g._sync_gameplay_caps(g.controller.gameplay)
		var surrendering: bool = g._gameplay_has_surrender and g.controller.gameplay.police_surrendering()
		if not surrendering:
			g._vehicle_combat(delta,target)
			if target != null and g.vehicle.global_position.distance_to(target.global_position) > 25.0: g._set_state("enroute")
			return
	if g.driver.pending_recovery():
		g._set_state("enroute")
		return
	if g.state_age < (g.CREW_EXIT_DELAY if g.get_script().quick_exit else 0.6) or not g.driver.settled(): return
	# Porta ainda em preparo fatiado: descer agora terminaria o recorte (dezenas de ms) num quadro só.
	# O controlador prioriza esta viatura; passado DOOR_WARM_WAIT desce mesmo assim (reserva antiga).
	if g.get_script().quick_exit and not g._doors_ready() and g.state_age < g.DOOR_WARM_WAIT: return
	if g.crew_remaining <= 0 and g.officers.is_empty():
		g._police_crew_depleted()
		return
	if g._deploy_police_crew():
		g._set_siren(false)
		g._set_state("working")
		return
	# Continua bloqueando enquanto não há saída/vaga segura disponível.
	if g.crew_remaining <= 0: return
	if g.controller.gameplay.contact_age < 1.0 and g._target_velocity(g._target()).length() > 3.0 and g._target_in_car(g._target()):
		g._set_state("enroute")
	elif g.state_age > 8.0:
		g._set_state("enroute")

static func _doors_ready(g: RefCounted) -> bool:
	if not is_instance_valid(g.vehicle) or g.vehicle.get_meta("dispatch_doors_warmed", false): return true
	# Moto, buggy e afins não têm folha para recortar.
	return g.vehicle.has_method("boarding_class") and g.vehicle.boarding_class() in ["open", "bus"]

static func _deploy_police_crew(g: RefCounted) -> bool:
	# Com 0 estrelas a averiguação usa o limite de 1 estrela (FOOT_LIMIT[0] é 0: a equipe nunca descia).
	var limit: int = RULES.FOOT_LIMIT[clampi(maxi(g.controller.gameplay.stars, 1), 0, 6)]
	var free_slots: int = mini(mini(g.crew_remaining, limit - g.controller.foot_officer_count()), RULES.OFFICERS_DEPLOY_BURST)
	var deployed := false
	# Pontos já usados nas levas anteriores (o camburão desce de 2 em 2): quem desceu ainda está
	# saindo de dentro do casco e não ocupa o ponto na consulta física, então os 6 saíam do mesmo lugar.
	var taken: Array[Vector3] = []
	for point in g._exit_points:
		taken.append(g.vehicle.to_global(point))
	var traced := TRACE.begin()
	for index in maxi(0, free_slots):
		var exit: Dictionary = g.controller.exit_point(g.vehicle, taken, false)
		if exit.is_empty(): break
		g._exit_points.append(g.vehicle.to_local(exit.point))
		taken.append(exit.point)
		var officer: CharacterBody3D = g.controller.spawn_officer(g, exit.point, float(exit.side))
		g._restore_seated_durability(officer)
		g.officers.append(officer)
		g.crew_remaining -= 1
		deployed = true
	g._sync_motorcycle_rider()
	TRACE.end("crew.deploy_police", traced, {"free_slots": free_slots})
	return deployed

static func _police_working(g: RefCounted, delta: float) -> void:
	g.driver.hold(true)
	g.driver.tick(delta)
	g.officers = g.officers.filter(func(o): return is_instance_valid(o) and not o.dead)
	g._exit_wait -= delta
	if g.crew_remaining > 0 and g._exit_wait <= 0.0 and g.driver.settled():
		g._exit_wait = .5
		g._deploy_police_crew()
	if g.officers.is_empty():
		# A dupla que desceu caiu. Sem ninguém a bordo a viatura não repõe policiais
		# (o orçamento de despacho só se gasta com viaturas novas); se sobrou
		# alguém dentro, volta à perseguição.
		if g.crew_remaining <= 0: g._police_crew_depleted()
		else: g._set_state("enroute")
		return
	var target: Node3D = g._target()
	if g._target_in_car(target) and g._target_velocity(target).length() > 4.0 and g.vehicle.global_position.distance_to(target.global_position) > 30.0 and g.controller.gameplay.contact_age < 2.0:
		g._begin_recall(true)

static func _police_crew_depleted(g: RefCounted) -> void:
	g.controller.emit_dispatch_event("crew_depleted", {"unit": g})
	# Não sobrou ninguém para dirigir. Mantém um carro estacionado roubável, recicla só fora de vista.
	g.vehicle.set_external_driver(false)
	g.vehicle.speed = 0.0
	g.vehicle.horizontal_velocity = Vector3.ZERO
	g.vehicle.velocity.x = 0.0
	g.vehicle.velocity.z = 0.0
	g.vehicle.remove_meta("dispatch_unit")
	g.vehicle.player_damage_attribution = true
	g.finish("crew_depleted")

static func _begin_recall(g: RefCounted, resume: bool) -> void:
	g.resume_pursuit = resume
	g._recall_age = 0.0
	g.officers = g.officers.filter(func(o): return is_instance_valid(o) and not o.dead)
	for officer in g.officers: officer.begin_return(g.vehicle)
	g._set_state("recall")

static func _police_recall(g: RefCounted, delta: float) -> void:
	# Um alvo a pé que volta durante o recolhimento ainda é confrontado por esta mesma
	# equipe; não termina o embarque para logo recriar os policiais.
	var target: Node3D = g._target()
	if g.resume_pursuit and g.controller.gameplay.stars > 0 and target != null and not g._target_in_car(target) and g.controller.gameplay.contact_age < 1.0:
		for officer in g.officers:
			if is_instance_valid(officer) and not officer.dead: officer.resume_combat()
		g._set_state("working")
		return
	g._recall_age += delta
	g.driver.hold(true)
	g.driver.tick(delta)
	for officer in g.officers.duplicate():
		if not is_instance_valid(officer) or officer.dead:
			g.officers.erase(officer)
	if g._recall_age > 30.0 and g.controller.is_unseen(g.vehicle.global_position):
		# Prazo esgotado: quem não chegou é liberado fora da vista, sem sumir na frente do jogador.
		for officer in g.officers:
			if is_instance_valid(officer) and g.controller.is_unseen(officer.global_position): officer.queue_free()
		g.officers = g.officers.filter(func(o): return is_instance_valid(o) and not o.is_queued_for_deletion())
	if g.officers.is_empty() or g._recall_age > 90.0:
		for officer in g.officers:
			if is_instance_valid(officer): officer.queue_free()
		g.officers.clear()
		if g.resume_pursuit and g.controller.gameplay.stars > 0:
			if g.crew_remaining <= 0:
				g._police_crew_depleted()
				return
			g._set_siren(true)
			g._set_state("enroute")
		else:
			g._begin_departure()

static func on_officer_boarded(g: RefCounted, officer: CharacterBody3D) -> void:
	if not is_instance_valid(officer) or officer.dead or not g.officers.has(officer): return
	g._seated_durability.append({"health":officer.health,"armor":officer.armor})
	g.officers.erase(officer)
	g.crew_remaining = mini(g.crew_capacity, g.crew_remaining + 1)
	if is_instance_valid(officer): officer.queue_free()
	g.controller.emit_dispatch_event("officer_boarded", {"unit": g})

static func _restore_seated_durability(g: RefCounted, officer: CharacterBody3D) -> void:
	if g._seated_durability.is_empty(): return
	var saved: Dictionary = g._seated_durability.pop_front()
	officer.health = clampf(float(saved.health), 0.0, officer.max_health)
	officer.armor = clampf(float(saved.armor), 0.0, officer.max_armor)
	officer.durability_changed.emit(officer.health,officer.max_health,officer.armor,officer.max_armor)
