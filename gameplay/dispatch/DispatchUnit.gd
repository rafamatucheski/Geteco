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
## Blocos separados em 01/11 (docs/plano-divisao-arquivos-grandes-20261101.md, Onda 2). São só
## funções estáticas que recebem esta unidade: guardar um auxiliar com `var g` faria ciclo de
## referência entre dois RefCounted. O estado continua todo aqui.
const SUSPENSION := preload("res://gameplay/dispatch/DispatchUnitSuspension.gd")
const POLICE_CREW := preload("res://gameplay/dispatch/DispatchUnitPoliceCrew.gd")
const SERVICE := preload("res://gameplay/dispatch/DispatchUnitService.gd")
const DEPARTURE := preload("res://gameplay/dispatch/DispatchUnitDeparture.gd")
const PURSUIT_UNIT := preload("res://gameplay/dispatch/DispatchUnitPursuit.gd")
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

## Distante do jogador o veículo congela, some da vista e sai da colisão (reciclada se ficou para trás
## numa perseguição): corpo em DispatchUnitSuspension.gd (delegação de uma linha; mesmo nome e padrões).
func _tick_suspension(delta: float) -> bool: return SUSPENSION._tick_suspension(self, delta)
func _outrun(distance: float) -> bool: return SUSPENSION._outrun(self, distance)
func _suspend_bodies() -> void: SUSPENSION._suspend_bodies(self)
func _bodies_clear() -> bool: return SUSPENSION._bodies_clear(self)
func _resume_bodies() -> void: SUSPENSION._resume_bodies(self)

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

## Rota em perseguição, guiamento, PIT, bloqueio, busca, visão, tiro da viatura, espera de estacionar
## e recuperação: corpo em DispatchUnitPursuit.gd (delegação de uma linha; mesmo nome e padrões;
## testes chamam _pick_block_point, o de pé sobrescreve _sees_target, e os outros DispatchUnit* e
## o DispatchController chamam vários).
func _gta_enroute(delta: float, target: Node3D, in_car: bool, car_search: bool, anchor: Vector3, velocity: Vector3) -> void: PURSUIT_UNIT._gta_enroute(self, delta, target, in_car, car_search, anchor, velocity)
func _set_pursuit(active: bool, target: CollisionObject3D) -> void: PURSUIT_UNIT._set_pursuit(self, active, target)
func _calm_driving() -> void: PURSUIT_UNIT._calm_driving(self)
func _chase_car(delta: float, target: Node3D, anchor: Vector3, velocity: Vector3) -> void: PURSUIT_UNIT._chase_car(self, delta, target, anchor, velocity)
func _flat(a: Vector3, b: Vector3) -> float: return PURSUIT_UNIT._flat(a, b)
func _update_boost(flat: float) -> void: PURSUIT_UNIT._update_boost(self, flat)
func _overtake_idle() -> bool: return PURSUIT_UNIT._overtake_idle(self)
func _guidance_tick(target: Node3D, anchor: Vector3, velocity: Vector3, flat: float, ram: bool) -> bool: return PURSUIT_UNIT._guidance_tick(self, target, anchor, velocity, flat, ram)
func _pit_check(target: Node3D) -> void: PURSUIT_UNIT._pit_check(self, target)
func _pursuit_replan(delta: float, goal: Vector3, goal_heading: Vector3, target: Node3D) -> void: PURSUIT_UNIT._pursuit_replan(self, delta, goal, goal_heading, target)
func _blocker_tick(delta: float, anchor: Vector3, velocity: Vector3, flat: float) -> bool: return PURSUIT_UNIT._blocker_tick(self, delta, anchor, velocity, flat)
func _pick_block_point(anchor: Vector3, velocity: Vector3) -> Vector3: return PURSUIT_UNIT._pick_block_point(self, anchor, velocity)
func _search_area(delta: float) -> void: PURSUIT_UNIT._search_area(self, delta)
func _sees_target(target: Node3D) -> bool: return PURSUIT_UNIT._sees_target(self, target)
func _line_of_sight(target: Node3D) -> bool: return PURSUIT_UNIT._line_of_sight(self, target)
func _vehicle_combat(delta: float, target: Node3D) -> void: PURSUIT_UNIT._vehicle_combat(self, delta, target)
func _park_pending(delta: float) -> void: PURSUIT_UNIT._park_pending(self, delta)
func _park_reset() -> void: PURSUIT_UNIT._park_reset(self)
func _recovery_blocked() -> bool: return PURSUIT_UNIT._recovery_blocked(self)
func _track_recovery(delta: float) -> void: PURSUIT_UNIT._track_recovery(self, delta)
func _recovery_stall_cause() -> String: return PURSUIT_UNIT._recovery_stall_cause(self)
func _end_assignment_for_recovery(cause: String) -> void: PURSUIT_UNIT._end_assignment_for_recovery(self, cause)
func on_overtake_unresolved(unresolved: bool, reason: String) -> void: PURSUIT_UNIT.on_overtake_unresolved(self, unresolved, reason)
func on_overtake_state(next: String, reason: String) -> void: PURSUIT_UNIT.on_overtake_state(self, next, reason)

## Equipe da polícia (estacionada, desembarque, a pé, recolhimento, embarque): corpo em
## DispatchUnitPoliceCrew.gd (delegação de uma linha; mesmo nome e padrões; testes chamam várias).
func _police_parked(delta: float) -> void: POLICE_CREW._police_parked(self, delta)
func _doors_ready() -> bool: return POLICE_CREW._doors_ready(self)
func _deploy_police_crew() -> bool: return POLICE_CREW._deploy_police_crew(self)
func _police_working(delta: float) -> void: POLICE_CREW._police_working(self, delta)
func _police_crew_depleted() -> void: POLICE_CREW._police_crew_depleted(self)
func _begin_recall(resume: bool) -> void: POLICE_CREW._begin_recall(self, resume)
func _police_recall(delta: float) -> void: POLICE_CREW._police_recall(self, delta)
func on_officer_boarded(officer: CharacterBody3D) -> void: POLICE_CREW.on_officer_boarded(self, officer)
func _restore_seated_durability(officer: CharacterBody3D) -> void: POLICE_CREW._restore_seated_durability(self, officer)

# --- Serviços de emergência ---------------------------------------------------

## Atendimento de ambulância, bombeiro e legista: corpo em DispatchUnitService.gd (delegação de uma
## linha; mesmo nome e padrões; on_crew_released é chamado pela ponte quando o Responder termina).
func _tick_service(delta: float) -> void: SERVICE._tick_service(self, delta)
func incident_valid() -> bool: return SERVICE.incident_valid(self)
func _service_enroute(delta: float) -> void: SERVICE._service_enroute(self, delta)
func _service_parked(delta: float) -> void: SERVICE._service_parked(self, delta)
func _service_working(delta: float) -> void: SERVICE._service_working(self, delta)
func _patient_changed() -> bool: return SERVICE._patient_changed(self)
func _retask() -> void: SERVICE._retask(self)
func on_crew_released(released: CharacterBody3D) -> void: SERVICE.on_crew_released(self, released)

# --- Partida -----------------------------------------------------------------

## Partida (soltar a ocorrência, esperar a equipe, rota de saída, fuga de travamento, remoção):
## corpo em DispatchUnitDeparture.gd (delegação de uma linha; mesmo nome e padrões).
func _begin_departure() -> void: DEPARTURE._begin_departure(self)
func _plan_departure() -> void: DEPARTURE._plan_departure(self)
func _tick_departing(delta: float) -> void: DEPARTURE._tick_departing(self, delta)

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

# O Gameplay de verdade tem police_force_authorized/police_surrendering; gameplays falsos dos testes
# podem não ter. A resposta fica guardada por instância em vez de has_method por nome a cada quadro.
var _caps_gameplay_id := 0
var _gameplay_has_force := false
var _gameplay_has_surrender := false

func _sync_gameplay_caps(gameplay: Object) -> void:
	var id: int = gameplay.get_instance_id()
	if id == _caps_gameplay_id: return
	_caps_gameplay_id = id
	_gameplay_has_force = gameplay.has_method("police_force_authorized")
	_gameplay_has_surrender = gameplay.has_method("police_surrendering")
