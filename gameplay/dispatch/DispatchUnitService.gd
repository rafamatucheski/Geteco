extends RefCounted
## Atendimento dos serviços de emergência (ambulância, bombeiro, legista): rota até a ocorrência,
## parada, descida do Responder, perda da fonte ou da equipe, troca de paramédico para legista e
## liberação pedida pela ponte. Separado de DispatchUnit.gd em 01/11 só para o dono caber na leitura.
## O estado (incident_id, actor, crew, retasked, _actor_loss_handled, _check_clock, _exit_wait)
## continua em DispatchUnit, porque testes, DispatchController e a ponte leem esses campos lá; o dono
## mantém cada função antiga como delegação de uma linha com a mesma assinatura. Tudo estático: a
## unidade é RefCounted, e um auxiliar com `var g` guardado faria ciclo de referência que nunca é
## liberado. Cada função recebe a unidade em `g` (RefCounted, e não o script do dono, para não criar
## preload cíclico) e passa por `g.` até nas chamadas entre funções deste arquivo.

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")

static func _tick_service(g: RefCounted, delta: float) -> void:
	match g.state:
		"enroute": g._service_enroute(delta)
		"parked": g._service_parked(delta)
		"working": g._service_working(delta)
		"departing": g._tick_departing(delta)

static func incident_valid(g: RefCounted) -> bool:
	var emergency: Node3D = g.controller.gameplay.emergency
	if emergency == null or not emergency.incidents.has(g.incident_id): return false
	var record: Dictionary = emergency.incidents[g.incident_id]
	var current: Variant = record.get("actor")
	if not is_instance_valid(current) or current != g.actor or current.is_queued_for_deletion(): return false
	if g.service == "fire" and "intensity" in g.actor and g.actor.intensity <= 0.0: return false
	# Paciente que morreu vira ocorrência de legista: quem veio como paramédico não a atende.
	if record.role != g.service: return false
	if g.service == "medic" and g.actor.get("dead") == true: return false
	return true

static func _service_enroute(g: RefCounted, delta: float) -> void:
	if not is_instance_valid(g.actor):
		g.controller.emit_dispatch_event("incident_invalid", {"unit": g})
		g._begin_departure()
		return
	g._check_clock -= delta
	if g._check_clock <= 0.0:
		g._check_clock = 0.5
		if not g.incident_valid():
			g.controller.emit_dispatch_event("incident_invalid", {"unit": g})
			g._begin_departure()
			return
		if g.age > RULES.UNANSWERED_SECONDS:
			g.controller.emit_dispatch_event("response_timeout", {"unit": g})
			g._begin_departure()
			return
	# Recuperação de ultrapassagem sem progresso: encerra o atendimento antes do prazo de 120 s.
	var stall_cause: String = g._recovery_stall_cause()
	if stall_cause != "":
		g._end_assignment_for_recovery(stall_cause)
		return
	var flat: float = Vector2(g.vehicle.global_position.x - g.actor.global_position.x, g.vehicle.global_position.z - g.actor.global_position.z).length()
	var at_end: bool = g.driver.at_route_end()
	if g.stop_planner.curve != null or flat <= RULES.FOOT_RANGE+20.0:
		g.driver.hold(g.driver.pending_recovery())
		if g.stop_planner.tick(g,g.actor.global_position,delta):
			g._park_reset()
			g.vehicle.set_meta("dispatch_needs_room",false)
			g._set_state("parked")
		else: g._park_pending(delta)
	elif at_end:
		# A rua termina longe demais para a equipe seguir a pé: sem acesso.
		g.controller.emit_dispatch_event("no_road_access", {"unit": g, "gap": flat})
		g._begin_departure()
		return
	else:
		g._park_reset()
		g.driver.hold(false)
	g.driver.tick(delta)

static func _service_parked(g: RefCounted, delta: float) -> void:
	g.driver.hold(true)
	g.driver.tick(delta)
	g._set_siren(false)
	if not g.incident_valid():
		g._begin_departure()
		return
	if g.driver.pending_recovery():
		# Recuperação de ultrapassagem pendente: nada de desembarcar a equipe.
		g._set_state("enroute")
		return
	if g.state_age < 0.6 or not g.driver.settled(): return
	# O Responder original volta ao lado direito; a saída é sempre por ele.
	var nobody: Array[Vector3] = []
	var exit: Dictionary = g.controller.exit_point(g.vehicle, nobody, true)
	if exit.is_empty():
		g._exit_wait += delta
		if g._exit_wait > 8.0:
			g.controller.emit_dispatch_event("no_exit", {"unit": g})
			g._begin_departure()
		return
	g.crew = g.controller.spawn_responder(g, exit.point)
	g.controller.claim_incident(g)
	g._set_state("working")

static func _service_working(g: RefCounted, delta: float) -> void:
	g.driver.hold(true)
	g.driver.tick(delta)
	# A fuga não pode ser convertida em retorno por perda da fonte da ocorrência.
	if g.service == "mortician" and is_instance_valid(g.crew) and not g.crew.dead and g.crew.mode == "flee": return
	# Se a entidade fonte saiu da árvore, não deixe a unidade depender do próximo
	# scan do EmergencyManager ou de uma referência já liberada no Responder.
	if not is_instance_valid(g.actor) or g.actor.is_queued_for_deletion():
		# Uma vez só. Com a equipe ainda a pé `_begin_departure` mantém o estado "working"
		# (ela volta andando): repetido a cada quadro físico, reemitia o evento (centenas por
		# atendimento, esvaziando o registro de 64), zerava `crew.age` sem parar e escondia
		# equipe morta ou presa, que nunca chegava aos testes abaixo. Depois da primeira
		# detecção valem só o teste de equipe e o prazo total do atendimento.
		if not g._actor_loss_handled:
			g._actor_loss_handled = true
			g.controller.emit_dispatch_event("incident_invalid", {"unit": g, "reason": "actor_removed"})
			g._begin_departure()
			return
	if not is_instance_valid(g.crew) or g.crew.dead:
		g.controller.emit_dispatch_event("crew_lost", {"unit": g})
		# Solta a ocorrência enquanto `crew` ainda identifica o dono do registro.
		g._release_incident()
		g.crew = null
		g._begin_departure()
		return
	if not g.retasked and g._patient_changed(): g._retask()
	if g.state_age > RULES.MAX_INCIDENT_SECONDS:
		g.controller.emit_dispatch_event("incident_abandoned", {"unit": g})
		g._release_incident()
		if is_instance_valid(g.crew): g.crew.queue_free()
		g.crew = null
		g._begin_departure()

static func _patient_changed(g: RefCounted) -> bool:
	if g.service != "medic" or not is_instance_valid(g.actor): return false
	var record: Dictionary = g.controller.gameplay.emergency.incidents.get(g.incident_id, {})
	if record.is_empty(): return false
	return record.role != "medic" or g.actor.get("dead") == true

## O paciente morreu durante o atendimento: o paramédico para e volta, a
## ocorrência passa a legista e fica livre para a viatura dele.
static func _retask(g: RefCounted) -> void:
	g.retasked = true
	g.controller.emit_dispatch_event("patient_died", {"unit": g})
	g.controller.gameplay.emergency.report_injury(g.actor, true)
	g._release_incident()
	g.crew.mode = "return"
	g.crew.age = 0.0

## Chamado pela ponte quando o Responder termina (ou expira) e pede liberação.
static func on_crew_released(g: RefCounted, released: CharacterBody3D) -> void:
	if released != g.crew: return
	if released.mode == "flee":
		g._release_incident()
		released.queue_free()
		g.crew = null
		g.controller.emit_dispatch_event("crew_fled", {"unit": g})
		if not is_instance_valid(g.vehicle): g.finish("vehicle_lost")
		elif g.wrecked: g.finish("wrecked")
		else: g._begin_departure()
		return
	var door: Vector3 = g.vehicle.to_global(Vector3(g.vehicle.half_width + 0.8, 0.0, 0.0))
	var aboard: bool = released.global_position.distance_to(door) < 2.5 and absf(g.vehicle.speed) < 0.6
	if not aboard and not g.vehicle.health <= 0.0:
		# Prazo do Responder venceu longe da viatura: continua voltando a pé.
		released.age = 0.0
		released.mode = "return"
		return
	released.queue_free()
	g.crew = null
	g.controller.emit_dispatch_event("crew_boarded", {"unit": g})
	if g.wrecked: g.finish("wrecked")
	else: g._begin_departure()
