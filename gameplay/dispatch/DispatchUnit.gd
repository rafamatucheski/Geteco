extends RefCounted
## Uma viatura de despacho (polícia, ambulância, caminhão de bombeiros ou
## carro do legista) com seu piloto e sua equipe. Máquina de estados:
##
##   enroute -> parked -> working -> [recall] -> departing -> (removida)
##
## "working" é a equipe a pé: policiais (DispatchOfficer) ou o Responder
## original. Uma ocorrência só é dada como atendida por quem a atende: o
## Responder chama EmergencyManager.complete depois de chegar e ter linha de
## visão. Nenhum cronômetro daqui conclui atendimento.

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")
const PATH := preload("res://gameplay/dispatch/PursuitPath.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const TANK_WEAPON := preload("res://gameplay/police_response/ground/PoliceTankWeapon.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Viatura parada sem acostamento planejado: estaciona depois disto no ramo de parada (era 3 s).
const PARK_SETTLE_SECONDS := 1.0
## Estacionada e parada: a equipe começa a descer depois disto (era 0,6 s).
const CREW_EXIT_DELAY := 0.25
const DOOR_WARM_WAIT := 1.2
## GETECO_POLICE_QUICK_EXIT=0 volta às esperas antigas (3 s e 0,6 s, sem esperar a porta), para A/B
## no mesmo build (DispatchOfficer e DispatchController leem o mesmo interruptor).
static var quick_exit := OS.get_environment("GETECO_POLICE_QUICK_EXIT") != "0"

var controller: Node3D
var service := ""
var vehicle: CharacterBody3D
var driver: RefCounted
var state := "enroute"
var age := 0.0
var state_age := 0.0
var finished := false
var end_reason := ""
var suspended := false
var suspended_for := 0.0
var _resume_clear_time := 0.0
var wrecked := false
var siren_wanted := true

# Polícia
var serial := 0
var level := 1
var variant := "patrol"
var role := 0
var officers: Array = []
## Policiais ainda a bordo. A dupla é fixa: quem morreu fora da viatura não é reposto.
var crew_remaining := RULES.OFFICERS_PER_CAR
var crew_capacity := RULES.OFFICERS_PER_CAR
## Returned crew retain their wounds and spent armor across node recreation.
var _seated_durability: Array[Dictionary] = []
var target_still := 0.0
var resume_pursuit := false
var _aim := 0.0
var _shot_cooldown := 1.2
var _burst := 0
var _contact_clock := 0.0
var _goal := Vector3.ZERO
var _goal_valid := false
var _last_planned_goal := Vector3(INF, INF, INF)
var _plan_clock := 0.0
var _failed_plans := 0
var _recall_age := 0.0
var _tank_weapon: RefCounted
var _moto_rider_visible := false
## Calculado a cada tick em rota (DispatchRules.door_warm_near); lido por door_warm_wanted.
var _door_warm_near := false

# Perseguição estilo GTA (PursuitRules); só com PursuitRules.enabled
## Rota aberta e alvo fora do sensor ligados no piloto (perseguindo um carro).
var pursuing := false
## Modo do guiamento final agora: "", follow, pit, flank, swipe, block (testes e depuração).
var guide_mode := ""
var _target_visible := false
var _guide_cooldown := 0.0
var _pit_cooldown := 0.0
var _since_plan := 0.0
var _boosted := false
## Alvo longe de qualquer rua (PursuitRules.OFFROAD_DISTANCE), medido a cada OFFROAD_CHECK.
var target_offroad := false
var _offroad_clock := 0.0
## Linha de visão livre até o alvo fora da rua (sem cone), para o guiamento de longe.
var _target_line := false
## Cruzamento que o bloqueador segura (INF = nenhum).
var block_point := Vector3.INF
var _block_hold := 0.0
var _block_retry := 0.0
## Ponto de rua que esta viatura vasculha na busca em leque (INF = nenhum).
var search_point := Vector3.INF

# Serviço médico / bombeiros / legista
var incident_id := 0
var actor: Node3D
var crew: CharacterBody3D
var retasked := false
## A perda da fonte da ocorrência já foi tratada (ver `_service_working`).
var _actor_loss_handled := false
var _exit_wait := 0.0
var _scene_clock := 0.0
var _check_clock := 0.0

var _saved_layer := 0
var _saved_mask := 0
var _saved_physics := false
## instance_id -> estado compartilhado do corpo e seu dono de movimento durante a suspensão
var _suspended_bodies: Dictionary = {}
var _departure_clock := 0.0
var _stranded := 0.0
var _departure_stall := 0.0
var _departure_anchor := Vector3.INF
var _departure_origin := Vector3.INF
var _departure_best := 0.0
var _escape_retry := 0.0
var _retirement := 0.0
# Espera por parada concluída (ultrapassagem pendente impede estacionar)
var _park_wait := 0.0
## Pontos de desembarque já usados (espaço da viatura), para cada leva sair num lugar diferente.
var _exit_points: Array[Vector3] = []
var _park_notified := false
var _park_stalled := false
const STOP_PLANNER := preload("res://gameplay/dispatch/DispatchStopPlanner.gd")
var stop_planner := STOP_PLANNER.new()
## Segundos acumulados em recuperação física de ultrapassagem durante ESTE atendimento
## (a vida da unidade). Não zera com troca de rota, de estado intermediário, de
## episódio, nem por voltar ao eixo; pausa fora de recuperação e com a unidade suspensa.
## Ver `_track_recovery`.
var recovery_total := 0.0
## Partindo com recuperação física ainda pendente: há quanto tempo (remoção fora da
## vista e liberação de vaga). Zera quando a recuperação sai ou a partida recomeça.
var stranded_age := 0.0
## `stranded_age` passou de STRANDED_SLOT_SECONDS: candidata a ter a vaga de
## MAX_ACTIVE/MAX_CREWS liberada pelo controlador (limitada; MAX_UNITS não muda).
var stranded := false

func is_police() -> bool:
	return service == "police"

func label() -> String:
	return "%s#%d" % [service, serial if is_police() else incident_id]

## Vale a pena preparar a porta desta viatura agora (P9, só com DispatchController.fast)?
## Só a polícia usa a porta: DispatchOfficer anima a porta ao descer e ao voltar. Ambulância,
## bombeiro e rabecão descem o Responder sem animar porta e não são dirigíveis pelo jogador;
## o recorte deles (~25-45 chamadas de 1-9 ms por veículo) era trabalho perdido.
## O roubo da viatura não depende disto: Driving prepara a porta do carro ao alcance.
func door_warm_wanted() -> bool:
	if not is_police(): return false
	if state != "enroute": return true
	return _door_warm_near

# --- Ciclo de vida ----------------------------------------------------------

func tick(delta: float) -> void:
	if finished: return
	if not is_instance_valid(vehicle):
		if wrecked:
			state_age += delta
			_tick_wrecked(delta)
			return
		if service == "mortician" and is_instance_valid(crew) and not crew.dead:
			_release_incident()
			crew.begin_escape(actor.global_position if is_instance_valid(actor) else crew.global_position)
			return
		finish("vehicle_lost")
		return
	age += delta
	state_age += delta
	var traced := STALL_WORK.begin()
	var paused := _tick_suspension(delta)
	STALL_WORK.finish_slow("dispatch.unit.suspension", traced, 5000, vehicle)
	if paused: return
	if vehicle.health <= 0.0 and not wrecked: _on_wrecked()
	if wrecked:
		_sync_motorcycle_rider()
		_tick_wrecked(delta)
		return
	traced = STALL_WORK.begin()
	_track_recovery(delta)
	STALL_WORK.finish_slow("dispatch.unit.recovery", traced, 5000, vehicle)
	traced = STALL_WORK.begin()
	if is_police(): _tick_police(delta)
	else: _tick_service(delta)
	STALL_WORK.finish_slow("dispatch.unit.state", traced, 5000, vehicle)
	traced = STALL_WORK.begin()
	_sync_motorcycle_rider()
	STALL_WORK.finish_slow("dispatch.unit.rider", traced, 5000, vehicle)

func _sync_motorcycle_rider() -> void:
	if variant != "motorcycle" or not is_instance_valid(vehicle): return
	var seated: bool = crew_remaining > 0 and not wrecked and not finished
	if seated == _moto_rider_visible: return
	_moto_rider_visible = seated
	for part in vehicle._motorcycle_rider_parts:
		if is_instance_valid(part): part.visible = seated

func _set_state(next: String) -> void:
	if state == next: return
	if next == "parked": _exit_points.clear()
	state = next
	state_age = 0.0
	controller.emit_dispatch_event("unit_state", {"unit": self, "state": next})

func finish(reason: String) -> void:
	if finished: return
	finished = true
	end_reason = reason
	_sync_motorcycle_rider()
	# Remoção imediata: o veículo será liberado, não há recuperação física a fazer.
	if is_instance_valid(driver):
		driver.discard_overtaking("removed:" + reason)
		_detach_driver()
	_release_incident()
	_set_siren(false)
	for officer in officers:
		if is_instance_valid(officer): officer.queue_free()
	officers.clear()
	if is_instance_valid(crew) and reason != "left": crew.queue_free()
	crew = null
	if is_instance_valid(vehicle):
		if (wrecked and reason == "wrecked") or reason == "crew_depleted": controller.adopt_wreck(vehicle)
		else: vehicle.queue_free()
	controller.emit_dispatch_event("unit_finished", {"unit": self, "reason": reason})

## O jogador tomou a viatura parada. Todos os ocupantes saem por pontos livres;
## policiais que já estavam a pé continuam a busca sob o ciclo de vida do Gameplay.
## A viatura passa a ser do jogador: não some nem volta à base.
func surrender_vehicle(exits: Array[Dictionary]) -> void:
	if finished: return
	if is_instance_valid(vehicle): vehicle.fade_traffic_retirement(0)
	if is_instance_valid(driver):
		driver.discard_overtaking("stolen")
		_detach_driver()
	_set_siren(false)
	_release_incident()
	for exit in exits:
		var officer: CharacterBody3D = controller.spawn_officer(self, exit.point, float(exit.side))
		_restore_seated_durability(officer)
		officers.append(officer)
		crew_remaining -= 1
	for officer in officers:
		if not is_instance_valid(officer): continue
		if officer.boarded.is_connected(on_officer_boarded): officer.boarded.disconnect(on_officer_boarded)
		if officer.dead: continue
		if officer.mode == "return": officer.mode = "combat"
		if not controller.gameplay.police.has(officer): controller.gameplay.police.append(officer)
		# Gameplay agora é dono deste mesmo agente; a unidade encerrada não pode admiti-lo.
		# Mantém o veículo até o desembarque físico e o fechamento da porta terminarem.
		officer.dispatch_controller = null
	officers.clear()
	if service == "mortician" and is_instance_valid(crew) and not crew.dead:
		# A unidade sai do controlador após o roubo; o gerente assume a fuga a pé.
		crew.begin_escape(vehicle.global_position)
		crew.manager = controller.gameplay.emergency
		crew.vehicle = null
		controller.gameplay.emergency.crews.append(crew)
		crew = null
	finished = true
	end_reason = "stolen"
	_sync_motorcycle_rider()
	controller.emit_dispatch_event("unit_finished", {"unit": self, "reason": "stolen"})

## Solta as ligações unidade <-> piloto <-> ultrapassagem (o controlador as cria em
## `_make_unit`). Sem isto, os Callables dos sinais mantêm unidade e piloto (RefCounted)
## referenciando um ao outro depois da remoção, e nada os libera. Não toca nos carros
## ambiente: a ultrapassagem só lê `traffic_yield_state` e não guarda referência a eles.
func _detach_driver() -> void:
	for signal_name in ["overtake_state_changed", "overtake_unresolved_changed", "replan_requested", "gave_up"]:
		for connection in driver.get_signal_connection_list(signal_name):
			driver.disconnect(signal_name, connection.callable)
	driver.disable_overtaking()

## Devolve a ocorrência ao gerente real se ainda for nossa.
func _release_incident() -> void:
	if incident_id == 0: return
	if is_instance_valid(controller) and is_instance_valid(controller.bridge):
		controller.bridge.roles.erase(incident_id)
	if not is_instance_valid(controller) or not is_instance_valid(controller.gameplay): return
	var emergency: Node3D = controller.gameplay.emergency
	if not is_instance_valid(emergency) or not emergency.incidents.has(incident_id): return
	var record: Dictionary = emergency.incidents[incident_id]
	var owner: Variant = record.get("crew")
	if owner == vehicle or owner == crew:
		record.assigned = false
		record.erase("crew")

func _set_siren(on: bool) -> void:
	if not is_instance_valid(vehicle): return
	var equipment: Node = vehicle.equipment
	if equipment == null or not is_instance_valid(equipment): return
	equipment.siren_on = on and siren_wanted and not wrecked and not equipment.beacons.is_empty()

# --- Suspensão distante ------------------------------------------------------

## Distante do jogador o veículo congela, some da vista e sai da colisão para
## não virar obstáculo invisível. Depois de SUSPEND_RECYCLE_SECONDS é liberado.
func _tick_suspension(delta: float) -> bool:
	var distance: float = controller.distance_to_player(vehicle.global_position)
	if not suspended:
		if distance <= RULES.SUSPEND_DISTANCE: return false
		if _outrun(distance):
			# Deixada para trás numa perseguição: some fora da vista e libera a vaga para uma
			# nova nascer à frente. Congelada, ela segurava a vaga por até 45 s.
			controller.recycle_outrun(self)
			return true
		suspended = true
		suspended_for = 0.0
		_resume_clear_time = 0.0
		_saved_layer = vehicle.collision_layer
		_saved_mask = vehicle.collision_mask
		_saved_physics = vehicle.is_physics_processing()
		if is_instance_valid(vehicle.damage_look): vehicle.damage_look.suspend_for_dispatch()
		else:
			vehicle.collision_layer = 0
			vehicle.collision_mask = 0
		vehicle.velocity = Vector3.ZERO
		vehicle.speed = 0.0
		vehicle.set_physics_process(false)
		vehicle.hide()
		_suspend_bodies()
		controller.emit_dispatch_event("unit_suspended", {"unit": self})
		return true
	suspended_for += delta
	if _outrun(distance):
		# Suspensa numa pausa do contato e a perseguição voltou com ela longe: recicla agora,
		# em vez de segurar a vaga até os 45 s.
		controller.recycle_outrun(self)
		return true
	var traced := TRACE.begin()
	var resume_clear: bool = distance <= RULES.RESUME_DISTANCE and controller.footprint_clear(vehicle, vehicle.global_position, vehicle.rotation.y) and _bodies_clear()
	TRACE.end("unit.resume_check", traced)
	if resume_clear:
		# Corpos estáticos recém-carregados entram no servidor de física no fim do
		# quadro. Exigir espaço livre por uma janela curta impede retomar sobre um
		# sólido que ainda não apareceu na primeira consulta do streaming.
		_resume_clear_time += delta
	else:
		_resume_clear_time = 0.0
	if _resume_clear_time >= 0.12:
		suspended = false
		if is_instance_valid(vehicle.damage_look): vehicle.damage_look.resume_from_dispatch()
		else:
			vehicle.collision_layer = _saved_layer
			vehicle.collision_mask = _saved_mask
			vehicle.set_physics_process(_saved_physics)
		vehicle.show()
		_resume_bodies()
		controller.emit_dispatch_event("unit_resumed", {"unit": self})
		return false
	if suspended_for >= RULES.SUSPEND_RECYCLE_SECONDS:
		finish("suspended_too_long")
	return true

## Viatura em perseguição ativa (contato recente), sem equipe a pé, longe e fora da vista.
func _outrun(distance: float) -> bool:
	if not PURSUIT.enabled or not is_police() or state != "enroute" or variant == "tank": return false
	if not officers.is_empty() or controller.gameplay.stars <= 0: return false
	if controller.gameplay.contact_age > PURSUIT.RECYCLE_CONTACT_AGE: return false
	# Longe também da última posição conhecida: quem está na área da busca fica (suspensa, como
	# antes). Sem isto, perder o contato longe dela reciclava as viaturas da busca e as novas,
	# que nascem perto dela, eram recicladas de novo (ciclo de criação de veículos).
	# Só na busca (contato perdido): com contato vivo a última posição é o próprio alvo, alguns metros
	# atrás dele, e a viatura deixada para trás ficaria "perto" dela (o laboratório pegou isso).
	if controller.gameplay.contact_age > 1.0 and controller.gameplay.last_known_valid and _flat(vehicle.global_position, controller.gameplay.last_known) <= RULES.SUSPEND_DISTANCE: return false
	return distance > RULES.SUSPEND_DISTANCE and controller.is_unseen(vehicle.global_position)

## Policiais e socorristas a pé saem da física junto com a viatura: sem camada,
## sem máscara, sem processamento e sem vista.
func _suspend_bodies() -> void:
	_suspended_bodies.clear()
	var bodies: Array = officers.duplicate()
	if crew != null: bodies.append(crew)
	for body in bodies:
		if not is_instance_valid(body): continue
		var body_state := {"body":body,"layer":body.collision_layer,"mask":body.collision_mask,
			"physics":body.is_physics_processing(),"owner":null}
		_suspended_bodies[body.get_instance_id()] = body_state
		var motion: Node = body.get_node_or_null("BodyFlight3D")
		if is_instance_valid(motion) and motion.has_method("suspend_for_dispatch"):
			motion.suspend_for_dispatch(body_state)
		body.collision_layer = 0
		body.collision_mask = 0
		body.velocity = Vector3.ZERO
		body.set_physics_process(false)
		body.hide()

## Cada pessoa viva precisa de cápsula livre no ponto onde ficou; senão a
## unidade inteira continua suspensa em vez de sobrepor um sólido novo.
func _bodies_clear() -> bool:
	for body_state in _suspended_bodies.values():
		# As referências podem ter sido liberadas por um efeito filho enquanto a unidade dormia.
		var body: Variant = body_state.body
		if not is_instance_valid(body) or body.is_queued_for_deletion() or body.dead: continue
		var exclude: Array[RID] = [vehicle.get_rid(), body.get_rid()]
		var motion: Node = body_state.owner.get_ref() if body_state.owner != null else null
		if is_instance_valid(motion):
			if not motion.suspension_clear(exclude): return false
		elif int(body_state.layer) != 0 and not controller.capsule_clear(body.global_position, exclude): return false
	return true

func _resume_bodies() -> void:
	for body_state in _suspended_bodies.values():
		var body: Variant = body_state.body
		if not is_instance_valid(body) or body.is_queued_for_deletion(): continue
		var motion: Node = body_state.owner.get_ref() if body_state.owner != null else null
		# A dead actor must release a paused child owner too; it cannot tick itself.
		if is_instance_valid(motion): motion.resume_from_dispatch()
		if body.dead:
			# Preserva o estado de colisão da morte; mantém o cadáver para o agente funerário.
			body.set_physics_process(false)
			body.show()
			continue
		body.collision_layer = int(body_state.layer)
		body.collision_mask = int(body_state.mask)
		body.set_physics_process(bool(body_state.physics))
		body.show()
	_suspended_bodies.clear()

# --- Veículo destruído --------------------------------------------------------

func _on_wrecked() -> void:
	wrecked = true
	if is_instance_valid(driver):
		driver.discard_overtaking("wrecked")
		vehicle.external_input = false
		vehicle.controlled = false
	_set_siren(false)
	# O legista abandona a coleta quando perde o transporte; a ocorrência volta à fila.
	if service == "mortician" and is_instance_valid(crew) and not crew.dead:
		_release_incident()
		crew.begin_escape(vehicle.global_position)
	for officer in officers:
		if is_instance_valid(officer) and officer.mode == "return": officer.mode = "combat"
	controller.emit_dispatch_event("unit_wrecked", {"unit": self})

func _tick_wrecked(_delta: float) -> void:
	if is_police():
		officers = officers.filter(func(o): return is_instance_valid(o) and not o.dead)
		if controller.gameplay.stars == 0 and state_age > 1.0 or officers.is_empty():
			if officers.is_empty() or (not is_instance_valid(vehicle) and officers.all(func(o): return controller.is_unseen(o.global_position))) or (is_instance_valid(vehicle) and controller.is_unseen(vehicle.global_position)):
				finish("wrecked")
		return
	if is_instance_valid(crew) and not crew.dead:
		# O legista foge; os outros serviços mantêm seu comportamento de emergência.
		if state_age > RULES.MAX_INCIDENT_SECONDS: finish("wrecked")
		return
	finish("wrecked")

# --- Polícia -----------------------------------------------------------------

func _tick_police(delta: float) -> void:
	var gameplay: Node3D = controller.gameplay
	if gameplay.stars == 0 and state in ["enroute", "parked", "working"]:
		if controller.retain_investigator(self):
			for officer in officers:
				if is_instance_valid(officer) and not officer.dead: officer.begin_return(vehicle)
			_set_state("investigating")
		else: _begin_recall(false)
	match state:
		"enroute": _police_enroute(delta)
		"parked": _police_parked(delta)
		"working": _police_working(delta)
		"recall": _police_recall(delta)
		"departing": _tick_departing(delta)
		"investigating": _police_investigating(delta)

func _police_investigating(delta: float) -> void:
	var gameplay: Node3D = controller.gameplay
	if gameplay.stars > 0:
		_set_siren(true)
		_set_state("enroute")
		return
	if not gameplay.police_investigation_active():
		_begin_recall(false)
		return
	officers = officers.filter(func(o): return is_instance_valid(o) and not o.dead)
	_set_siren(false)
	if pursuing or driver.curvature_limit: _calm_driving()
	if not officers.is_empty():
		driver.hold(true)
		driver.tick(delta)
		# A equipe olhou em volta o bastante: volta para a viatura e vai embora.
		_scene_clock += delta
		if _scene_clock >= RULES.INVESTIGATION_LINGER: _begin_recall(false)
		return
	var point: Vector3 = gameplay.police_investigation_point()
	if not point.is_finite():
		_begin_recall(false)
		return
	# A investigação de propósito nunca chama _sees_target nem report_contact.
	# A mesma equipe visita a cena denunciada, não a posição do jogador escondido.
	var arrived := vehicle.global_position.distance_to(point) < 10.0
	driver.hold(arrived)
	if not arrived: _replan_towards(point,delta,4.0)
	elif crew_remaining > 0 and driver.settled(): _deploy_police_crew()
	elif crew_remaining <= 0:
		# Sem ninguém para descer (equipe esgotada): fica um tempo no local e parte.
		_scene_clock += delta
		if _scene_clock >= RULES.INVESTIGATION_LINGER: _begin_recall(false)
	driver.tick(delta)

func _target() -> Node3D:
	if controller.player_position_override != Vector3.INF: return null
	var target: Variant = controller.gameplay.pursuit_target()
	return target as Node3D if is_instance_valid(target) else null

func _target_in_car(target: Node3D) -> bool:
	return target != null and "horizontal_velocity" in target

func _target_velocity(target: Node3D) -> Vector3:
	if target == null: return Vector3.ZERO
	if "horizontal_velocity" in target: return target.horizontal_velocity
	if target is CharacterBody3D: return Vector3(target.velocity.x, 0.0, target.velocity.z)
	return Vector3.ZERO

func _police_enroute(delta: float) -> void:
	var traced := STALL_WORK.begin()
	_stall_police_enroute(delta)
	STALL_WORK.finish_slow("dispatch.unit.police_enroute", traced, 5000, vehicle)

func _stall_police_enroute(delta: float) -> void:
	# Recuperação de ultrapassagem sem progresso: sem isto a viatura ficaria segurando a
	# vaga de perseguição para sempre (polícia não tem prazo de resposta como os serviços).
	var stall_cause := _recovery_stall_cause()
	if stall_cause != "":
		_end_assignment_for_recovery(stall_cause)
		return
	var gameplay: Node3D = controller.gameplay
	var target := _target()
	# Sem contato há mais de um segundo a viatura persegue a última posição conhecida.
	var searching: bool = gameplay.contact_age > 1.0 or target == null
	_contact_clock -= delta
	if _contact_clock <= 0.0:
		_contact_clock = 0.25
		_target_visible = _sees_target(target)
		if _target_visible: gameplay.report_contact(target.global_position)
		# Fora da rua a viatura parada na ponta dela costuma estar de lado para o alvo: o guiamento
		# de longe pede só linha de visão livre, sem o cone (o contato continua pelo cone acima).
		_target_line = PURSUIT.enabled and target_offroad and target != null and target.visible and _flat(vehicle.global_position, target.global_position) <= PURSUIT.OFFROAD_GUIDE_RANGE and _line_of_sight(target)
	var in_car := _target_in_car(target) and not searching
	var velocity := _target_velocity(target) if not searching else Vector3.ZERO
	var anchor: Vector3 = target.global_position if (target != null and not searching) else gameplay.last_known
	if controller.player_position_override != Vector3.INF: anchor = controller.player_position_override
	if not searching and controller.distance_to_player(anchor) > RULES.SUSPEND_DISTANCE * 2.0:
		# Alvo em outro lugar (interior, outra região): só a última posição vale.
		anchor = gameplay.last_known
		searching = true
	var stop_distance := RULES.stop_radius(serial)
	if in_car and velocity.length() < 0.75: target_still += delta
	elif in_car: target_still = 0.0
	else: target_still = RULES.TARGET_STOPPED_SECONDS
	var flat := Vector2(vehicle.global_position.x - anchor.x, vehicle.global_position.z - anchor.z).length()
	# Quem fugiu de carro e sumiu é procurado em leque pela área, sem a viatura parar e descer
	# no último ponto conhecido (a pé, como antes).
	var car_search: bool = PURSUIT.enabled and searching and controller.pursuit_in_car and target != null
	var may_stop := not car_search and ((not in_car) or target_still >= RULES.TARGET_STOPPED_SECONDS)
	# Uma parada pertence à perseguição a pé. Quando o alvo sai dirigindo, descarta
	# a rota antiga de estacionamento antes que ela possa deixar a equipe perseguidora para trás.
	if not may_stop and stop_planner.curve != null:
		stop_planner.reset()
		_park_reset()
		_plan_clock = 0.0
		_since_plan = PURSUIT.REPLAN_MAX
	_door_warm_near = RULES.door_warm_near(flat, stop_distance, in_car, velocity.length(), stop_planner.curve != null)
	if stop_planner.curve != null or (may_stop and flat <= stop_distance+10.0):
		# Parar exige a frenagem até o fim da rota de parada: sai do modo perseguição.
		_set_pursuit(false, null)
		block_point = Vector3.INF
		driver.hold(driver.pending_recovery())
		# Sem curva de parada (cruzamento, rua estreita) a viatura já parada perto do alvo
		# estaciona onde está: antes ela ficava em rota para sempre e a equipe às vezes nunca descia.
		var arrived := stop_planner.tick(self,anchor,delta)
		# Sem curva de acostamento utilizável: freia na trajetória física atual.
		# Continuar a rota de perseguição anterior deixava o fallback parado
		# inalcançável, com carros e motos rodando em volta do pedestre.
		if stop_planner.curve == null: driver.hold(true)
		var unused_exits: Array[Vector3] = []
		# 27/10: eram 3 s de espera fixa com a viatura já parada ao lado do alvo, e a equipe "demorava
		# a sair do carro". A parada física (`settled`) continua sendo a condição de verdade.
		var parked_here: bool = _park_wait > (PARK_SETTLE_SECONDS if quick_exit else 3.0) and driver.settled() and flat <= stop_distance + 12.0 and not controller.exit_point(vehicle, unused_exits, false).is_empty()
		if arrived or parked_here:
			_park_reset()
			vehicle.set_meta("dispatch_needs_room",false)
			_set_state("parked")
		else: _park_pending(delta)
		driver.tick(delta)
		return
	_park_reset()
	stop_planner.reset()
	driver.hold(false)
	if PURSUIT.enabled:
		_gta_enroute(delta, target, in_car, car_search, anchor, velocity)
		_vehicle_combat(delta, target)
		driver.tick(delta)
		return
	var forward: Vector3 = -target.global_basis.z if (target != null and in_car) else (anchor - vehicle.global_position)
	_goal = RULES.formation_goal(role, anchor, velocity, forward, stop_distance) if in_car else anchor
	_goal_valid = true
	# Cada plano custa ~2,2 ms (medido 2026-09-23); intervalos defasados por viatura
	# evitam que várias replanejem no mesmo quadro. Travamento continua replanejando na hora.
	_replan_towards(_goal, delta, 2.5 + float(serial % 4) * 0.4)
	_vehicle_combat(delta, target)
	driver.tick(delta)

# --- Perseguição estilo GTA ---------------------------------------------------------

## Rota em perseguição (PursuitRules.enabled). Carro à vista: rota aberta à frente dele, papéis e
## guiamento final. Carro sumido: busca em leque pela área. A pé: o mesmo de antes.
func _gta_enroute(delta: float, target: Node3D, in_car: bool, car_search: bool, anchor: Vector3, velocity: Vector3) -> void:
	var traced := TRACE.begin()
	_guide_cooldown = maxf(0.0, _guide_cooldown - delta)
	_pit_cooldown = maxf(0.0, _pit_cooldown - delta)
	_since_plan += delta
	if in_car or car_search:
		driver.speed_cap = PURSUIT.speed_cap(variant)
		driver.curvature_limit = true
	if in_car:
		search_point = Vector3.INF
		_chase_car(delta, target, anchor, velocity)
	elif car_search:
		block_point = Vector3.INF
		_search_area(delta)
	else:
		# Alvo a pé: direção e parada de antes (teto e curva antigos). O planejador de parada foi
		# calibrado para eles; a 30 m/s a viatura passava do ponto e parava fora da rua.
		_calm_driving()
		_goal = anchor
		_goal_valid = true
		_replan_towards(_goal, delta, 2.5 + float(serial % 4) * 0.4)
	TRACE.end("unit.gta_enroute", traced)

func _set_pursuit(active: bool, target: CollisionObject3D) -> void:
	if not active and pursuing:
		_boosted = false
		driver.set_boost(1.0)
	pursuing = active
	if not active: guide_mode = ""
	driver.set_pursuit(active, target)

## Volta à direção de serviço comum (partida, averiguação): teto e curva originais.
func _calm_driving() -> void:
	_set_pursuit(false, null)
	block_point = Vector3.INF
	search_point = Vector3.INF
	driver.speed_cap = RULES.speed_cap(variant)
	driver.curvature_limit = false

func _chase_car(delta: float, target: Node3D, anchor: Vector3, velocity: Vector3) -> void:
	var flat := _flat(vehicle.global_position, anchor)
	if role == PURSUIT.ROLE_BLOCKER and _blocker_tick(delta, anchor, velocity, flat): return
	_set_pursuit(true, target as CollisionObject3D)
	# Alvo parado ou lento: a rota termina nele com frenagem, para o planejador de parada assumir
	# sem a viatura chegar a 30 m/s; rota aberta só com ele fugindo.
	driver.open_route = Vector2(velocity.x, velocity.z).length() > PURSUIT.OPEN_ROUTE_MIN_TARGET_SPEED
	_update_boost(flat)
	# Moto só cola atrás; o tanque segue a rota e usa o canhão (PoliceTankWeapon).
	var ram: bool = PURSUIT.ram_allowed(controller.gameplay) and variant != "motorcycle"
	_offroad_clock -= delta
	if _offroad_clock <= 0.0:
		_offroad_clock = PURSUIT.OFFROAD_CHECK
		var road: Dictionary = controller.router.nearest_edge(anchor)
		target_offroad = road.is_empty() or float(road.distance) > PURSUIT.OFFROAD_DISTANCE
	if variant == "tank":
		driver.guidance = false
		guide_mode = ""
	elif _guidance_tick(target, anchor, velocity, flat, ram): _pit_check(target)
	var direction := Vector3(velocity.x, 0.0, velocity.z)
	direction = direction.normalized() if direction.length_squared() > 1.0 else -target.global_basis.z
	var goal := PURSUIT.chase_goal(anchor, velocity)
	var goal_heading := direction
	# Interceptor à frente do alvo: vem de frente pela faixa contrária para fechar o caminho.
	if role == PURSUIT.ROLE_INTERCEPTOR and ram and (vehicle.global_position - anchor).dot(direction) > 12.0:
		goal = anchor + direction * clampf(flat * 0.5, 10.0, 60.0)
		goal_heading = -direction
	_goal = goal
	_goal_valid = true
	_pursuit_replan(delta, goal, goal_heading, target)

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Recuperação fora da câmera: longe do alvo e sem ser vista, a viatura ganha teto e aceleração;
## perto ou à vista, volta ao normal (nada de alcançar o jogador "no grito" na frente dele).
func _update_boost(flat: float) -> void:
	var unseen: bool = controller.is_unseen(vehicle.global_position)
	if not _boosted and flat > PURSUIT.BOOST_DISTANCE and unseen: _boosted = true
	elif _boosted and (flat < PURSUIT.BOOST_RELEASE_DISTANCE or not unseen): _boosted = false
	driver.set_boost(PURSUIT.BOOST if _boosted else 1.0)

func _overtake_idle() -> bool:
	return driver.overtake == null or (driver.overtake.state == "idle" and not driver.overtake.unresolved)

## Guiamento final perto do alvo: sai da rota e mira um ponto no carro dele (cola atrás, PIT,
## emparelha e raspa, ou para atravessado de frente). Devolve se está guiando.
func _guidance_tick(target: Node3D, anchor: Vector3, velocity: Vector3, flat: float, ram: bool) -> bool:
	var forward := -vehicle.global_basis.z
	var to_target := anchor - vehicle.global_position
	to_target.y = 0.0
	var target_forward := -target.global_basis.z
	var oncoming := target_forward.dot(forward) < -0.3
	# Alvo fora da rua e à vista: o guiamento vale de mais longe (a rota só chega à ponta da rua).
	var reach := PURSUIT.OFFROAD_GUIDE_RANGE if target_offroad else PURSUIT.GUIDE_RANGE
	var seen: bool = _target_line if target_offroad else _target_visible
	# Alvo parado ou lento: na rua quem estaciona e desce é o planejador de parada (PIT num carro
	# parado o empurrava e zerava o "parado há 1,5 s", e ninguém descia); fora da rua só encosta.
	var slow := Vector2(velocity.x, velocity.z).length() < PURSUIT.OPEN_ROUTE_MIN_TARGET_SPEED
	if slow and not target_offroad: seen = false
	if slow: ram = false
	var allowed: bool = flat <= reach and seen and _guide_cooldown <= 0.0 and _overtake_idle() and not driver.reversing
	if allowed and not target_offroad and to_target.length_squared() > 0.01 and forward.angle_to(to_target.normalized()) > PURSUIT.GUIDE_CONE: allowed = false
	# De frente só o interceptor com força autorizada fecha o caminho; os outros seguem a rota.
	if allowed and oncoming and not target_offroad and not (ram and role == PURSUIT.ROLE_INTERCEPTOR): allowed = false
	if allowed and driver.guidance and driver.blocked_ahead:
		# Algo que não é o alvo no caminho (parede, trânsito): volta à rota por um tempo.
		_guide_cooldown = PURSUIT.GUIDE_COOLDOWN
		allowed = false
	if not allowed:
		driver.guidance = false
		guide_mode = ""
		return false
	var plan: Dictionary
	if oncoming:
		plan = {"point": anchor + velocity * 0.6, "speed": clampf(flat * 0.35 - 2.0, 0.0, 10.0), "mode": "block"}
	else:
		var half_width := float(target.get("half_width")) if target.get("half_width") != null else 1.0
		var half_length := float(target.get("half_length")) if target.get("half_length") != null else 2.2
		plan = PURSUIT.guide(role, ram, vehicle.global_position, anchor, target_forward, velocity, half_width, half_length, vehicle.half_width)
	driver.guidance = true
	driver.guide_point = plan.point
	driver.guide_speed = plan.speed
	# Contador, não evento: a troca de modo é frequente e encheria o registro de 64 eventos.
	if guide_mode != plan.mode:
		controller.count_pursuit("guide_" + str(plan.mode))
		if flat > PURSUIT.GUIDE_RANGE: controller.count_pursuit("guide_offroad")
	guide_mode = plan.mode
	return true

## PIT: a viatura bateu na traseira lateral do alvo em movimento. O StreetPhysics já aplica o
## impulso da batida; aqui entra o giro que faz o carro rodar (o da batida dá ~5°).
func _pit_check(target: Node3D) -> void:
	if _pit_cooldown > 0.0 or guide_mode != "pit": return
	var body := target as CharacterBody3D
	if body == null or body.get("half_width") == null: return
	# Carro protegido (DamageProtection) não leva batida do StreetPhysics; o giro do PIT também não.
	if PROTECTION.is_protected(body): return
	var target_velocity: Vector3 = body.horizontal_velocity
	if Vector2(target_velocity.x, target_velocity.z).length() < PURSUIT.PIT_MIN_TARGET_SPEED: return
	for index in vehicle.get_slide_collision_count():
		var collision := vehicle.get_slide_collision(index)
		if collision.get_collider() != body: continue
		var push: Vector3 = vehicle.horizontal_velocity - target_velocity
		var spin := PURSUIT.pit_spin(body.to_local(collision.get_position()), push, body.global_basis, body.half_width, body.half_length)
		if absf(spin) < 0.2: return
		var current := float(body.get_meta("crash_spin", 0.0))
		body.set_meta("crash_spin", clampf(current + spin, -PURSUIT.PIT_SPIN_MAX, PURSUIT.PIT_SPIN_MAX))
		# Sem `crash_stun` o StreetPhysics não aplica o giro guardado (`_update_slide`).
		body.set_meta("crash_stun", maxf(float(body.get_meta("crash_stun", 0.0)), 1.2))
		_pit_cooldown = PURSUIT.PIT_COOLDOWN
		controller.count_pursuit("pit")
		controller.emit_dispatch_event("pit", {"unit": self, "spin": snappedf(spin, 0.01)})
		return

## Replanejamento por evento: rota acabando, alvo fora do corredor dela ou rota velha demais;
## nunca mais que uma vez por REPLAN_MIN (defasado por viatura) e nunca durante a ré.
func _pursuit_replan(delta: float, goal: Vector3, goal_heading: Vector3, target: Node3D) -> void:
	_plan_clock -= delta
	if _plan_clock > 0.0 or driver.reversing: return
	var need: bool = driver.route == null or _since_plan >= PURSUIT.REPLAN_MAX or driver.remaining < PURSUIT.replan_remaining(vehicle.speed)
	if not need and is_instance_valid(target):
		var closest: Vector3 = driver.route.get_closest_point(target.global_position)
		need = _flat(closest, target.global_position) > PURSUIT.REPLAN_CORRIDOR
	if not need:
		_plan_clock = 0.25
		return
	_plan_clock = PURSUIT.REPLAN_MIN + float(serial % 4) * PURSUIT.REPLAN_STAGGER
	_since_plan = 0.0
	_last_planned_goal = goal
	var traced := TRACE.begin()
	var spanned := STALL_WORK.begin()
	var result: Dictionary = controller.router.plan(vehicle.global_position, goal, -vehicle.global_basis.z, goal_heading)
	STALL_WORK.finish_slow("dispatch.unit.gta_plan", spanned, 3000, vehicle)
	TRACE.end("router.plan:gta_pursuit", traced)
	if result.ok:
		_failed_plans = 0
		driver.set_route(result.curve)
		return
	_failed_plans += 1
	if _failed_plans >= 4:
		controller.emit_dispatch_event("no_route", {"unit": self, "reason": result.reason})
		_failed_plans = 0
		_begin_departure()

## Bloqueador: vai a um cruzamento à frente do alvo (só se chega antes dele) e para lá até o alvo
## passar, chegar perto ou o tempo acabar. Devolve true enquanto cuida do bloqueio.
func _blocker_tick(delta: float, anchor: Vector3, velocity: Vector3, flat: float) -> bool:
	_block_retry -= delta
	var direction := Vector3(velocity.x, 0.0, velocity.z)
	if block_point == Vector3.INF:
		if _block_retry > 0.0 or direction.length() < 6.0 or flat < 40.0: return false
		_block_retry = PURSUIT.BLOCK_RETRY
		var picked := _pick_block_point(anchor, velocity)
		if picked == Vector3.INF: return false
		var traced := TRACE.begin()
		var result: Dictionary = controller.router.plan(vehicle.global_position, picked, -vehicle.global_basis.z)
		TRACE.end("router.plan:block", traced)
		if not result.ok: return false
		block_point = picked
		_block_hold = 0.0
		_set_pursuit(false, null)
		driver.set_route(result.curve)
		controller.count_pursuit("block_planned")
		controller.emit_dispatch_event("block_planned", {"unit": self, "point": picked})
	var passed: bool = direction.length() > 1.0 and (anchor - block_point).dot(direction.normalized()) > 6.0
	if passed or flat < PURSUIT.BLOCK_RELEASE_DISTANCE or _block_hold > PURSUIT.BLOCK_HOLD_MAX:
		controller.count_pursuit("block_held" if _block_hold > 0.0 else "block_released_early")
		block_point = Vector3.INF
		# Vira perseguidor por um tempo antes de tentar outro cruzamento.
		_block_retry = 6.0
		_since_plan = PURSUIT.REPLAN_MAX
		_plan_clock = 0.0
		return false
	if driver.at_route_end() or (driver.route != null and driver.remaining < 3.0 and driver.is_stopped()):
		_block_hold += delta
		guide_mode = "block"
	return true

## Primeiro cruzamento do caminho previsto do alvo em que a viatura chega antes dele, com folga.
func _pick_block_point(anchor: Vector3, velocity: Vector3) -> Vector3:
	var traced := TRACE.begin()
	var spanned := STALL_WORK.begin()
	var speed := Vector2(velocity.x, velocity.z).length()
	var prediction := PATH.predict(controller.routes, controller.router, anchor, velocity, PURSUIT.BLOCK_MAX_DISTANCE)
	var cap := maxf(1.0, PURSUIT.speed_cap(variant) * 0.75)
	var best := Vector3.INF
	for index: int in prediction.junctions:
		var distance: float = prediction.distances[index]
		if distance < PURSUIT.BLOCK_MIN_DISTANCE: continue
		var point: Vector3 = prediction.points[index]
		var police_eta := _flat(vehicle.global_position, point) * 1.35 / cap
		if police_eta + PURSUIT.BLOCK_ETA_MARGIN < distance / speed:
			best = point
			break
	STALL_WORK.finish_slow("dispatch.unit.block_pick", spanned, 3000, vehicle)
	TRACE.end("unit.block_pick", traced, {"junctions": prediction.junctions.size()})
	return best

## Busca em leque: cada viatura vasculha um ponto de rua dentro da área de busca, e outro ao chegar.
func _search_area(delta: float) -> void:
	# Sem contato não há para onde guiar: o ponto do guiamento seria o de antes de perder o alvo.
	driver.guidance = false
	var gameplay: Node3D = controller.gameplay
	var seen_velocity: Vector3 = controller.pursuit_velocity
	seen_velocity.y = 0.0
	if gameplay.contact_age <= PURSUIT.SEARCH_PURSUE_SECONDS and seen_velocity.length() > PURSUIT.OPEN_ROUTE_MIN_TARGET_SPEED:
		# Dobrou a esquina: segue para onde ele estaria agora, de rota aberta, ainda sem leque.
		_set_pursuit(true, null)
		search_point = Vector3.INF
		var lead := clampf(seen_velocity.length() * gameplay.contact_age + PURSUIT.SEARCH_PURSUE_LEAD, PURSUIT.SEARCH_PURSUE_LEAD, PURSUIT.SEARCH_PURSUE_MAX)
		_goal = gameplay.last_known + seen_velocity.normalized() * lead
		_goal_valid = true
		if guide_mode != "dead_reckoning":
			guide_mode = "dead_reckoning"
			controller.count_pursuit("search_pursue")
		_pursuit_replan(delta, _goal, seen_velocity.normalized(), null)
		return
	_set_pursuit(false, null)
	var arrived: bool = search_point != Vector3.INF and (_flat(vehicle.global_position, search_point) < PURSUIT.SEARCH_POINT_REACHED or driver.at_route_end())
	if search_point == Vector3.INF or arrived or driver.route == null:
		var next: Vector3 = controller.search_point_for(self)
		if next != Vector3.INF and next != search_point:
			search_point = next
			_plan_clock = 0.0
			controller.count_pursuit("search_point")
	_goal = search_point if search_point != Vector3.INF else controller.gameplay.last_known
	_goal_valid = true
	_replan_towards(_goal, delta, 2.0)

func _sees_target(target: Node3D) -> bool:
	if controller.player_position_override != Vector3.INF: return false
	var gameplay: Node3D = controller.gameplay
	if target == null or gameplay.health <= 0 or not gameplay.state.weapons_allowed() or not target.visible: return false
	if PURSUIT.enabled:
		# Cone frontal de 70 m somado ao círculo antigo de 40,6 m (nunca enxerga menos que antes).
		if not PURSUIT.in_vision(vehicle.global_position, -vehicle.global_basis.z, target.global_position): return false
	elif vehicle.global_position.distance_to(target.global_position) > RULES.SIGHT_RANGE: return false
	return _line_of_sight(target)

## Raio da viatura até o alvo sem nada no meio (só física; distância e cone são de quem chama).
func _line_of_sight(target: Node3D) -> bool:
	var traced := TRACE.begin()
	var ray := PhysicsRayQueryParameters3D.create(vehicle.global_position + Vector3.UP * 1.4, target.global_position + Vector3.UP, 7, [vehicle.get_rid()])
	var hit: Dictionary = vehicle.get_world_3d().direct_space_state.intersect_ray(ray)
	TRACE.end("unit.sees_target", traced)
	return hit.is_empty() or hit.collider == target

## Tiro a partir da viatura (police/PoliceVehicleCombat.gd): dois ou mais
## patamares, alvo em veículo dirigido pelo jogador, equipe ainda a bordo.
func _vehicle_combat(delta: float, target: Node3D) -> void:
	var gameplay: Node3D = controller.gameplay
	if variant == "tank":
		if _tank_weapon == null: _tank_weapon = TANK_WEAPON.new()
		_tank_weapon.tick(self,delta,target)
		return
	_shot_cooldown = maxf(0.0, _shot_cooldown - delta)
	var driven: bool = controller.world.get("driving") != null and controller.world.driving.occupied
	var authorized: bool = gameplay.police_force_authorized() if gameplay.has_method("police_force_authorized") else gameplay.stars >= 2
	var surrendering: bool = gameplay.has_method("police_surrendering") and gameplay.police_surrendering()
	if not authorized or surrendering or not driven or target == null or crew_remaining < RULES.OFFICERS_PER_CAR or not officers.is_empty() or not gameplay.state.weapons_allowed():
		_aim = 0.0
		return
	if vehicle.global_position.distance_to(target.global_position) > RULES.SHOT_RANGE or not _sees_target(target):
		_aim = 0.0
		return
	_aim += delta
	if _aim < RULES.SHOT_AIM_SECONDS or _shot_cooldown > 0.0: return
	_burst += 1
	_shot_cooldown = RULES.SHOT_COOLDOWN if _burst < 2 else RULES.SHOT_BURST_COOLDOWN
	if _burst >= 2: _burst = 0
	gameplay.police_vehicle_shoot(vehicle, RULES.SHOT_DAMAGE)

## Parada só concluída com o piloto sem recuperação pendente. Com ultrapassagem
## pendente a unidade volta a "enroute", que mantém o freio (`hold`) e espera o
## piloto terminar a volta à faixa antes de tentar estacionar de novo.
func _park_pending(delta: float) -> void:
	_park_wait += delta
	if not _park_notified and driver.pending_recovery():
		_park_notified = true
		controller.emit_dispatch_event("park_deferred", {"unit": self, "status": driver.stop_status(), "reason": driver.overtake.last_reason, "needs": driver.overtake.exit_condition()})
	if not _park_stalled and _park_wait > 30.0 and driver.pending_recovery():
		_park_stalled = true
		controller.emit_dispatch_event("park_recovery_stalled", {"unit": self, "status": driver.stop_status(), "reason": driver.overtake.last_reason, "needs": driver.overtake.exit_condition()})

func _park_reset() -> void:
	_park_wait = 0.0
	_park_notified = false
	_park_stalled = false

## Recuperação FÍSICA em curso ou declarada sem solução. Não inclui passagem normal
## (`passing`), espera (`waiting`) nem ociosidade: isso é perseguição/viagem normal.
func _recovery_blocked() -> bool:
	var overtake: RefCounted = driver.overtake if driver != null else null
	return overtake != null and (overtake.in_recovery() or overtake.unresolved)

## Acumulador cumulativo do atendimento (`recovery_total`).
##   inicia/avança: a cada tick não suspenso e não destruído em que `_recovery_blocked()`;
##   pausa: fora de recuperação (passando, esperando, ociosa, estacionada) e durante a
##          suspensão distante (a unidade nem chega a este método);
##   não zera: por troca de rota, de estado da unidade, de episódio, por voltar ao eixo,
##          por `resume_pursuit` ou por partir; só some com a unidade.
## Serve para episódios curtos e repetidos, que o `episode_age` (relógio de UM episódio)
## nunca somaria.
func _track_recovery(delta: float) -> void:
	if _recovery_blocked(): recovery_total += delta

## Causa de encerrar o atendimento por recuperação sem progresso, ou "" se não há.
##   recovery_stalled:    UM episódio longo demais, ou `unresolved` e episódio passou do prazo curto
##                        (relógio do episódio; `_park_reset` zeraria `_park_wait` a cada oscilação)
##   recovery_cumulative: orçamento cumulativo do atendimento esgotado E há recuperação em
##                        curso agora. Com a viatura já recuperada e livre, o orçamento
##                        esgotado só se cobra no próximo episódio (não interrompe uma
##                        unidade que voltou ao eixo)
func _recovery_stall_cause() -> String:
	var overtake: RefCounted = driver.overtake if driver != null else null
	if overtake == null: return ""
	if overtake.episode_age >= RULES.RECOVERY_GIVE_UP_SECONDS: return "recovery_stalled"
	if overtake.unresolved and overtake.episode_age >= RULES.RECOVERY_GIVE_UP_UNRESOLVED_SECONDS: return "recovery_stalled"
	if recovery_total >= RULES.RECOVERY_CUMULATIVE_SECONDS and overtake.in_recovery(): return "recovery_cumulative"
	return ""

## Encerra o ATENDIMENTO, não a recuperação física. A ocorrência é solta (outra
## viatura pode assumir), a sirene apaga e a unidade passa a "departing"; o veículo
## continua no piloto, que só se move por curva validada (`cancel_overtaking` dentro de
## `_begin_departure` preserva a recuperação em curso). Nada aqui desembarca equipe,
## teleporta ou remove o veículo: a remoção, se houver, é `_tick_departing`.
func _end_assignment_for_recovery(cause: String) -> void:
	var overtake: RefCounted = driver.overtake
	var detail: String = overtake.unresolved_reason if overtake.unresolved else overtake.last_reason
	controller.emit_dispatch_event("assignment_released", {"unit": self, "cause": cause, "status": driver.stop_status(), "reason": detail, "needs": overtake.exit_condition(), "recovery_total": snappedf(recovery_total, 0.1), "episode_age": snappedf(overtake.episode_age, 0.1)})
	_begin_departure()

func on_overtake_unresolved(unresolved: bool, reason: String) -> void:
	var needs: String = driver.overtake.exit_condition() if unresolved and driver != null and driver.overtake != null else ""
	controller.emit_dispatch_event("overtake_unresolved", {"unit": self, "unresolved": unresolved, "reason": reason, "needs": needs})

func on_overtake_state(next: String, reason: String) -> void:
	# Só o que importa para recuperação; o resto seria ruído no registro de 64 eventos.
	if next in ["holding_oncoming", "recovering", "returning"]:
		controller.emit_dispatch_event("overtake_state", {"unit": self, "state": next, "reason": reason})

func _police_parked(delta: float) -> void:
	driver.hold(true)
	driver.tick(delta)
	var moving_target := _target()
	if variant != "tank" and _target_in_car(moving_target) and _target_velocity(moving_target).length() > 3.0 and controller.gameplay.contact_age < 1.0:
		stop_planner.reset()
		_park_reset()
		_plan_clock = 0.0
		_since_plan = PURSUIT.REPLAN_MAX
		_set_state("enroute")
		return
	if variant == "tank" and controller.gameplay.stars > 0:
		var target := _target()
		var surrendering: bool = controller.gameplay.has_method("police_surrendering") and controller.gameplay.police_surrendering()
		if not surrendering:
			_vehicle_combat(delta,target)
			if target != null and vehicle.global_position.distance_to(target.global_position) > 25.0: _set_state("enroute")
			return
	if driver.pending_recovery():
		_set_state("enroute")
		return
	if state_age < (CREW_EXIT_DELAY if quick_exit else 0.6) or not driver.settled(): return
	# Porta ainda em preparo fatiado: descer agora terminaria o recorte (dezenas de ms) num quadro só.
	# O controlador prioriza esta viatura; passado DOOR_WARM_WAIT desce mesmo assim (reserva antiga).
	if quick_exit and not _doors_ready() and state_age < DOOR_WARM_WAIT: return
	if crew_remaining <= 0 and officers.is_empty():
		_police_crew_depleted()
		return
	if _deploy_police_crew():
		_set_siren(false)
		_set_state("working")
		return
	# Continua bloqueando enquanto não há saída/vaga segura disponível.
	if crew_remaining <= 0: return
	if controller.gameplay.contact_age < 1.0 and _target_velocity(_target()).length() > 3.0 and _target_in_car(_target()):
		_set_state("enroute")
	elif state_age > 8.0:
		_set_state("enroute")

func _doors_ready() -> bool:
	if not is_instance_valid(vehicle) or vehicle.get_meta("dispatch_doors_warmed", false): return true
	# Moto, buggy e afins não têm folha para recortar.
	return vehicle.has_method("boarding_class") and vehicle.boarding_class() in ["open", "bus"]

func _deploy_police_crew() -> bool:
	# Com 0 estrelas a averiguação usa o limite de 1 estrela (FOOT_LIMIT[0] é 0: a equipe nunca descia).
	var limit: int = RULES.FOOT_LIMIT[clampi(maxi(controller.gameplay.stars, 1), 0, 6)]
	var free_slots: int = mini(mini(crew_remaining, limit - controller.foot_officer_count()), RULES.OFFICERS_DEPLOY_BURST)
	var deployed := false
	# Pontos já usados nas levas anteriores (o camburão desce de 2 em 2): quem desceu ainda está
	# saindo de dentro do casco e não ocupa o ponto na consulta física, então os 6 saíam do mesmo lugar.
	var taken: Array[Vector3] = []
	for point in _exit_points:
		taken.append(vehicle.to_global(point))
	var traced := TRACE.begin()
	for index in maxi(0, free_slots):
		var exit: Dictionary = controller.exit_point(vehicle, taken, false)
		if exit.is_empty(): break
		_exit_points.append(vehicle.to_local(exit.point))
		taken.append(exit.point)
		var officer: CharacterBody3D = controller.spawn_officer(self, exit.point, float(exit.side))
		_restore_seated_durability(officer)
		officers.append(officer)
		crew_remaining -= 1
		deployed = true
	_sync_motorcycle_rider()
	TRACE.end("crew.deploy_police", traced, {"free_slots": free_slots})
	return deployed

func _police_working(delta: float) -> void:
	driver.hold(true)
	driver.tick(delta)
	officers = officers.filter(func(o): return is_instance_valid(o) and not o.dead)
	_exit_wait -= delta
	if crew_remaining > 0 and _exit_wait <= 0.0 and driver.settled():
		_exit_wait = .5
		_deploy_police_crew()
	if officers.is_empty():
		# A dupla que desceu caiu. Sem ninguém a bordo a viatura não repõe policiais
		# (o orçamento de despacho só se gasta com viaturas novas); se sobrou
		# alguém dentro, volta à perseguição.
		if crew_remaining <= 0: _police_crew_depleted()
		else: _set_state("enroute")
		return
	var target := _target()
	if _target_in_car(target) and _target_velocity(target).length() > 4.0 and vehicle.global_position.distance_to(target.global_position) > 30.0 and controller.gameplay.contact_age < 2.0:
		_begin_recall(true)

func _police_crew_depleted() -> void:
	controller.emit_dispatch_event("crew_depleted", {"unit": self})
	# Não sobrou ninguém para dirigir. Mantém um carro estacionado roubável, recicla só fora de vista.
	vehicle.set_external_driver(false)
	vehicle.speed = 0.0
	vehicle.horizontal_velocity = Vector3.ZERO
	vehicle.velocity.x = 0.0
	vehicle.velocity.z = 0.0
	vehicle.remove_meta("dispatch_unit")
	vehicle.player_damage_attribution = true
	finish("crew_depleted")

func _begin_recall(resume: bool) -> void:
	resume_pursuit = resume
	_recall_age = 0.0
	officers = officers.filter(func(o): return is_instance_valid(o) and not o.dead)
	for officer in officers: officer.begin_return(vehicle)
	_set_state("recall")

func _police_recall(delta: float) -> void:
	# Um alvo a pé que volta durante o recolhimento ainda é confrontado por esta mesma
	# equipe; não termina o embarque para logo recriar os policiais.
	var target := _target()
	if resume_pursuit and controller.gameplay.stars > 0 and target != null and not _target_in_car(target) and controller.gameplay.contact_age < 1.0:
		for officer in officers:
			if is_instance_valid(officer) and not officer.dead: officer.resume_combat()
		_set_state("working")
		return
	_recall_age += delta
	driver.hold(true)
	driver.tick(delta)
	for officer in officers.duplicate():
		if not is_instance_valid(officer) or officer.dead:
			officers.erase(officer)
	if _recall_age > 30.0 and controller.is_unseen(vehicle.global_position):
		# Prazo esgotado: quem não chegou é liberado fora da vista, sem sumir na frente do jogador.
		for officer in officers:
			if is_instance_valid(officer) and controller.is_unseen(officer.global_position): officer.queue_free()
		officers = officers.filter(func(o): return is_instance_valid(o) and not o.is_queued_for_deletion())
	if officers.is_empty() or _recall_age > 90.0:
		for officer in officers:
			if is_instance_valid(officer): officer.queue_free()
		officers.clear()
		if resume_pursuit and controller.gameplay.stars > 0:
			if crew_remaining <= 0:
				_police_crew_depleted()
				return
			_set_siren(true)
			_set_state("enroute")
		else:
			_begin_departure()

func on_officer_boarded(officer: CharacterBody3D) -> void:
	if not is_instance_valid(officer) or officer.dead or not officers.has(officer): return
	_seated_durability.append({"health":officer.health,"armor":officer.armor})
	officers.erase(officer)
	crew_remaining = mini(crew_capacity, crew_remaining + 1)
	if is_instance_valid(officer): officer.queue_free()
	controller.emit_dispatch_event("officer_boarded", {"unit": self})

func _restore_seated_durability(officer: CharacterBody3D) -> void:
	if _seated_durability.is_empty(): return
	var saved: Dictionary = _seated_durability.pop_front()
	officer.health = clampf(float(saved.health), 0.0, officer.max_health)
	officer.armor = clampf(float(saved.armor), 0.0, officer.max_armor)
	officer.durability_changed.emit(officer.health,officer.max_health,officer.armor,officer.max_armor)

# --- Serviços de emergência ---------------------------------------------------

func _tick_service(delta: float) -> void:
	match state:
		"enroute": _service_enroute(delta)
		"parked": _service_parked(delta)
		"working": _service_working(delta)
		"departing": _tick_departing(delta)

func incident_valid() -> bool:
	var emergency: Node3D = controller.gameplay.emergency
	if emergency == null or not emergency.incidents.has(incident_id): return false
	var record: Dictionary = emergency.incidents[incident_id]
	var current: Variant = record.get("actor")
	if not is_instance_valid(current) or current != actor or current.is_queued_for_deletion(): return false
	if service == "fire" and "intensity" in actor and actor.intensity <= 0.0: return false
	# Paciente que morreu vira ocorrência de legista: quem veio como paramédico não a atende.
	if record.role != service: return false
	if service == "medic" and actor.get("dead") == true: return false
	return true

func _service_enroute(delta: float) -> void:
	if not is_instance_valid(actor):
		controller.emit_dispatch_event("incident_invalid", {"unit": self})
		_begin_departure()
		return
	_check_clock -= delta
	if _check_clock <= 0.0:
		_check_clock = 0.5
		if not incident_valid():
			controller.emit_dispatch_event("incident_invalid", {"unit": self})
			_begin_departure()
			return
		if age > RULES.UNANSWERED_SECONDS:
			controller.emit_dispatch_event("response_timeout", {"unit": self})
			_begin_departure()
			return
	# Recuperação de ultrapassagem sem progresso: encerra o atendimento antes do prazo de 120 s.
	var stall_cause := _recovery_stall_cause()
	if stall_cause != "":
		_end_assignment_for_recovery(stall_cause)
		return
	var flat := Vector2(vehicle.global_position.x - actor.global_position.x, vehicle.global_position.z - actor.global_position.z).length()
	var at_end: bool = driver.at_route_end()
	if stop_planner.curve != null or flat <= RULES.FOOT_RANGE+20.0:
		driver.hold(driver.pending_recovery())
		if stop_planner.tick(self,actor.global_position,delta):
			_park_reset()
			vehicle.set_meta("dispatch_needs_room",false)
			_set_state("parked")
		else: _park_pending(delta)
	elif at_end:
		# A rua termina longe demais para a equipe seguir a pé: sem acesso.
		controller.emit_dispatch_event("no_road_access", {"unit": self, "gap": flat})
		_begin_departure()
		return
	else:
		_park_reset()
		driver.hold(false)
	driver.tick(delta)

func _service_parked(delta: float) -> void:
	driver.hold(true)
	driver.tick(delta)
	_set_siren(false)
	if not incident_valid():
		_begin_departure()
		return
	if driver.pending_recovery():
		# Recuperação de ultrapassagem pendente: nada de desembarcar a equipe.
		_set_state("enroute")
		return
	if state_age < 0.6 or not driver.settled(): return
	# O Responder original volta ao lado direito; a saída é sempre por ele.
	var nobody: Array[Vector3] = []
	var exit: Dictionary = controller.exit_point(vehicle, nobody, true)
	if exit.is_empty():
		_exit_wait += delta
		if _exit_wait > 8.0:
			controller.emit_dispatch_event("no_exit", {"unit": self})
			_begin_departure()
		return
	crew = controller.spawn_responder(self, exit.point)
	controller.claim_incident(self)
	_set_state("working")

func _service_working(delta: float) -> void:
	driver.hold(true)
	driver.tick(delta)
	# A fuga não pode ser convertida em retorno por perda da fonte da ocorrência.
	if service == "mortician" and is_instance_valid(crew) and not crew.dead and crew.mode == "flee": return
	# Se a entidade fonte saiu da árvore, não deixe a unidade depender do próximo
	# scan do EmergencyManager ou de uma referência já liberada no Responder.
	if not is_instance_valid(actor) or actor.is_queued_for_deletion():
		# Uma vez só. Com a equipe ainda a pé `_begin_departure` mantém o estado "working"
		# (ela volta andando): repetido a cada quadro físico, reemitia o evento (centenas por
		# atendimento, esvaziando o registro de 64), zerava `crew.age` sem parar e escondia
		# equipe morta ou presa, que nunca chegava aos testes abaixo. Depois da primeira
		# detecção valem só o teste de equipe e o prazo total do atendimento.
		if not _actor_loss_handled:
			_actor_loss_handled = true
			controller.emit_dispatch_event("incident_invalid", {"unit": self, "reason": "actor_removed"})
			_begin_departure()
			return
	if not is_instance_valid(crew) or crew.dead:
		controller.emit_dispatch_event("crew_lost", {"unit": self})
		# Solta a ocorrência enquanto `crew` ainda identifica o dono do registro.
		_release_incident()
		crew = null
		_begin_departure()
		return
	if not retasked and _patient_changed(): _retask()
	if state_age > RULES.MAX_INCIDENT_SECONDS:
		controller.emit_dispatch_event("incident_abandoned", {"unit": self})
		_release_incident()
		if is_instance_valid(crew): crew.queue_free()
		crew = null
		_begin_departure()

func _patient_changed() -> bool:
	if service != "medic" or not is_instance_valid(actor): return false
	var record: Dictionary = controller.gameplay.emergency.incidents.get(incident_id, {})
	if record.is_empty(): return false
	return record.role != "medic" or actor.get("dead") == true

## O paciente morreu durante o atendimento: o paramédico para e volta, a
## ocorrência passa a legista e fica livre para a viatura dele.
func _retask() -> void:
	retasked = true
	controller.emit_dispatch_event("patient_died", {"unit": self})
	controller.gameplay.emergency.report_injury(actor, true)
	_release_incident()
	crew.mode = "return"
	crew.age = 0.0

## Chamado pela ponte quando o Responder termina (ou expira) e pede liberação.
func on_crew_released(released: CharacterBody3D) -> void:
	if released != crew: return
	if released.mode == "flee":
		_release_incident()
		released.queue_free()
		crew = null
		controller.emit_dispatch_event("crew_fled", {"unit": self})
		if not is_instance_valid(vehicle): finish("vehicle_lost")
		elif wrecked: finish("wrecked")
		else: _begin_departure()
		return
	var door: Vector3 = vehicle.to_global(Vector3(vehicle.half_width + 0.8, 0.0, 0.0))
	var aboard: bool = released.global_position.distance_to(door) < 2.5 and absf(vehicle.speed) < 0.6
	if not aboard and not vehicle.health <= 0.0:
		# Prazo do Responder venceu longe da viatura: continua voltando a pé.
		released.age = 0.0
		released.mode = "return"
		return
	released.queue_free()
	crew = null
	controller.emit_dispatch_event("crew_boarded", {"unit": self})
	if wrecked: finish("wrecked")
	else: _begin_departure()

# --- Partida -----------------------------------------------------------------

func _begin_departure() -> void:
	stop_planner.reset()
	if is_instance_valid(vehicle): vehicle.set_meta("dispatch_needs_room",true)
	if is_police() and driver != null: _calm_driving()
	if is_police() and crew_remaining <= 0 and officers.is_empty():
		_police_crew_depleted()
		return
	_release_incident()
	_set_siren(false)
	_departure_clock = 0.0
	_stranded = 0.0
	stranded_age = 0.0
	stranded = false
	if is_instance_valid(crew):
		# Equipe ainda a pé: cancelamento. Volta à viatura e a viatura só parte com ela.
		crew.mode = "return"
		crew.age = 0.0
		if state != "working": _set_state("working")
		return
	if not officers.is_empty():
		_begin_recall(false)
		return
	_set_state("departing")
	driver.hold(false)
	# Redirecionamento com o veículo em jogo: recuperação física (para e volta à
	# faixa com curva validada), nunca descarte que o deixe atravessado.
	driver.cancel_overtaking("departure")
	_plan_departure()

func _plan_departure() -> void:
	var player_position: Vector3 = controller.player_position()
	var heading: Vector3 = -vehicle.global_basis.z
	var traced := TRACE.begin()
	var result: Dictionary = controller.router.plan_departure(vehicle.global_position, player_position, RULES.RECYCLE_DISTANCE + 25.0, heading)
	TRACE.end("router.plan_departure", traced)
	if result.ok:
		var departure: Curve3D = stop_planner.departure_curve(vehicle,result.curve)
		driver.set_route(departure)
		if departure==null: controller.emit_dispatch_event("departure_merge_blocked",{"unit":self})
		_stranded = 0.0
	else:
		driver.set_route(null)
		_stranded += 1.0
		controller.emit_dispatch_event("departure_blocked", {"unit": self, "reason": result.reason})

func _tick_departing(delta: float) -> void:
	_departure_clock += delta
	driver.hold(driver.route == null)
	driver.tick(delta)
	if _departure_origin==Vector3.INF: _departure_origin=vehicle.global_position
	var departure_progress := vehicle.global_position.distance_to(_departure_origin)
	if departure_progress>_departure_best+3:
		_departure_best=departure_progress
		_departure_anchor=vehicle.global_position
		_departure_stall=0
		_retirement=0
		vehicle.fade_traffic_retirement(0)
	elif absf(vehicle.speed)<.6: _departure_stall+=delta
	_escape_retry-=delta
	if _departure_stall>6 and _escape_retry<=0 and driver.route!=null and not driver.pending_recovery():
		_escape_retry=2
		var escape: Curve3D=preload("res://gameplay/TrafficEscapePlanner.gd").plan(vehicle,driver.route)
		if escape!=null:
			driver.discard_overtaking("departure_escape")
			driver.set_route(escape)
			vehicle.set_meta("dispatch_escape_active",true)
			controller.emit_dispatch_event("departure_escape",{"unit":self})
	if vehicle.get_meta("dispatch_escape_active",false) and driver.route!=null and driver.offset>=float(driver.route.get_meta("traffic_escape_until",0)):
		vehicle.remove_meta("dispatch_escape_active")
	# Uma resposta partindo e desocupada pode ser aposentada à vista como último recurso,
	# como pedido: o casco sólido fica até o fim do fade curto.
	if _departure_stall>=28 or _departure_clock>=45:
		_retirement+=delta
		driver.hold(true)
		vehicle.fade_traffic_retirement(minf(1,_retirement))
		if _retirement>=1:
			finish("departure_escape_removed")
			return
	var unseen: bool = controller.is_unseen(vehicle.global_position)
	var distance: float = controller.distance_to_player(vehicle.global_position)
	if unseen and distance > RULES.RECYCLE_DISTANCE:
		finish("left")
		return
	# Partida travada por recuperação física que não sai (faixa contrária, motor bloqueado,
	# rota nula): sem isto a viatura ocuparia a vaga de unidade até `departure_timeout`.
	# A recuperação continua enquanto ela existir; só a REMOÇÃO IMEDIATA acontece, e
	# apenas fora da vista, para não sumir na frente do jogador.
	if _recovery_blocked(): stranded_age += delta
	else: stranded_age = 0.0
	stranded = stranded_age >= RULES.STRANDED_SLOT_SECONDS
	if stranded_age >= RULES.STRANDED_REMOVAL_SECONDS and unseen and distance > 25.0:
		controller.emit_dispatch_event("recovery_stranded", {"unit": self, "status": driver.stop_status(), "reason": driver.overtake.unresolved_reason if driver.overtake.unresolved else driver.overtake.last_reason, "needs": driver.overtake.exit_condition()})
		finish("recovery_stranded")
		return
	if driver.route == null or driver.at_route_end():
		_stranded += delta
		if _stranded >= 3.0:
			_stranded = 0.0
			_plan_departure()
	if _departure_clock > 180.0 and distance > 25.0 and unseen:
		finish("departure_timeout")

# --- Rotas -------------------------------------------------------------------

func set_route_goal(goal: Vector3) -> void:
	_goal = goal
	_last_planned_goal = goal
	_goal_valid = true

func set_siren_on() -> void:
	siren_wanted = true
	_set_siren(true)

## Cancelamento pedido de fora (ocorrência anulada): a equipe volta e a viatura parte.
func abort_response() -> void:
	if finished or state == "departing" or state == "recall": return
	_begin_departure()

func _replan_towards(goal: Vector3, delta: float, interval: float) -> void:
	_plan_clock -= delta
	if _plan_clock > 0.0: return
	_plan_clock = interval
	# Objetivo praticamente parado e rota longa ainda válida: não gasta busca.
	if driver.route != null and driver.remaining > 12.0 and goal.distance_to(_last_planned_goal) < 3.0: return
	_last_planned_goal = goal
	var traced := TRACE.begin()
	var result: Dictionary = controller.router.plan(vehicle.global_position, goal, -vehicle.global_basis.z)
	TRACE.end("router.plan:pursuit", traced)
	if result.ok:
		_failed_plans = 0
		driver.set_route(result.curve)
	else:
		_failed_plans += 1
		if _failed_plans >= 4:
			controller.emit_dispatch_event("no_route", {"unit": self, "reason": result.reason})
			_failed_plans = 0
			_begin_departure()

## O piloto pediu novo plano por travamento: bloqueia o trecho atual e busca outro.
func on_replan_requested(_reason: String) -> void:
	if state not in ["enroute", "departing"]: return
	controller.router.block_edge_near(vehicle.global_position, 20.0, -vehicle.global_basis.z)
	if state == "departing":
		_plan_departure()
		return
	var goal := _goal if _goal_valid else (actor.global_position if is_instance_valid(actor) else vehicle.global_position)
	var traced := TRACE.begin()
	var result: Dictionary = controller.router.plan(vehicle.global_position, goal, -vehicle.global_basis.z)
	TRACE.end("router.plan:stuck", traced)
	controller.emit_dispatch_event("replanned", {"unit": self, "ok": result.ok})
	if result.ok: driver.set_route(result.curve)

## Sem saída depois de várias ré: se ainda está perto o bastante, a equipe segue a pé.
func on_gave_up(_reason: String) -> void:
	if state != "enroute": return
	var anchor: Vector3 = _goal if _goal_valid else vehicle.global_position
	if is_instance_valid(actor): anchor = actor.global_position
	var flat := Vector2(vehicle.global_position.x - anchor.x, vehicle.global_position.z - anchor.z).length()
	# Um cruzamento bloqueado não pode fazer uma viatura abandonar a perseguição e entrar
	# no engarrafamento. Os policiais podem terminar a última aproximação curta a pé; o
	# limite fica abaixo da distância comum de spawn fora da tela.
	var reach := RULES.SPAWN_MAX if is_police() else RULES.FOOT_RANGE
	if flat <= reach:
		# Falha de rota não autoriza descarregar numa faixa de trânsito ativa.
		stop_planner.tick(self,anchor,.8)
		# 27/10: sem nenhum acostamento possível (parede ou obra fechando a rua) a viatura ficava
		# presa replanejando para sempre e a equipe nunca descia (regressão de 12/10; em setembro ela
		# estacionava). Rua que o piloto desistiu de atravessar não é faixa viva: parada e com porta
		# livre, estaciona ali e a dupla segue a pé.
		if STOP_PLANNER.stop_fix and stop_planner.curve == null and driver.settled():
			var exits: Array[Vector3] = []
			if not controller.exit_point(vehicle, exits, false).is_empty():
				driver.hold(true)
				_set_state("parked")
		return
	controller.emit_dispatch_event("route_blocked", {"unit": self})
	_begin_departure()
