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
const TANK_WEAPON := preload("res://gameplay/police_response/ground/PoliceTankWeapon.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

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
## instance_id -> [corpo, layer, mask] das equipes a pé durante a suspensão
var _suspended_bodies: Dictionary = {}
var _departure_clock := 0.0
var _stranded := 0.0
# Espera por parada concluída (ultrapassagem pendente impede estacionar)
var _park_wait := 0.0
var _park_notified := false
var _park_stalled := false
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

# --- Ciclo de vida ----------------------------------------------------------

func tick(delta: float) -> void:
	if finished: return
	if not is_instance_valid(vehicle):
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
	state = next
	state_age = 0.0
	controller.emit_dispatch_event("unit_state", {"unit": self, "state": next})

func finish(reason: String) -> void:
	if finished: return
	finished = true
	end_reason = reason
	_sync_motorcycle_rider()
	# Remoção imediata: o veículo será liberado, não há recuperação física a fazer.
	if driver != null:
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
	if driver != null:
		driver.discard_overtaking("stolen")
		_detach_driver()
	_set_siren(false)
	_release_incident()
	for exit in exits:
		var officer: CharacterBody3D = controller.spawn_officer(self, exit.point, float(exit.side))
		officers.append(officer)
		crew_remaining -= 1
	for officer in officers:
		if not is_instance_valid(officer): continue
		if officer.boarded.is_connected(on_officer_boarded): officer.boarded.disconnect(on_officer_boarded)
		if officer.dead: continue
		if officer.mode == "return": officer.mode = "combat"
		if not controller.gameplay.police.has(officer): controller.gameplay.police.append(officer)
		# Gameplay owns this same agent now; the finished unit cannot admit it.
		# Keep vehicle until physical disembarkation and door closure complete.
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
		suspended = true
		suspended_for = 0.0
		_resume_clear_time = 0.0
		_saved_layer = vehicle.collision_layer
		_saved_mask = vehicle.collision_mask
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
		vehicle.collision_layer = _saved_layer
		vehicle.collision_mask = _saved_mask
		vehicle.set_physics_process(true)
		vehicle.show()
		_resume_bodies()
		controller.emit_dispatch_event("unit_resumed", {"unit": self})
		return false
	if suspended_for >= RULES.SUSPEND_RECYCLE_SECONDS:
		finish("suspended_too_long")
	return true

## Policiais e socorristas a pé saem da física junto com a viatura: sem camada,
## sem máscara, sem processamento e sem vista.
func _suspend_bodies() -> void:
	_suspended_bodies.clear()
	var bodies: Array = officers.duplicate()
	if crew != null: bodies.append(crew)
	for body in bodies:
		if not is_instance_valid(body): continue
		_suspended_bodies[body.get_instance_id()] = [body, body.collision_layer, body.collision_mask]
		body.collision_layer = 0
		body.collision_mask = 0
		body.velocity = Vector3.ZERO
		body.set_physics_process(false)
		body.hide()

## Cada pessoa viva precisa de cápsula livre no ponto onde ficou; senão a
## unidade inteira continua suspensa em vez de sobrepor um sólido novo.
func _bodies_clear() -> bool:
	for entry in _suspended_bodies.values():
		var body: CharacterBody3D = entry[0]
		if not is_instance_valid(body) or int(entry[1]) == 0: continue
		var exclude: Array[RID] = [vehicle.get_rid(), body.get_rid()]
		if not controller.capsule_clear(body.global_position, exclude): return false
	return true

func _resume_bodies() -> void:
	for entry in _suspended_bodies.values():
		var body: CharacterBody3D = entry[0]
		if not is_instance_valid(body): continue
		body.collision_layer = int(entry[1])
		body.collision_mask = int(entry[2])
		body.set_physics_process(true)
		body.show()
	_suspended_bodies.clear()

# --- Veículo destruído --------------------------------------------------------

func _on_wrecked() -> void:
	wrecked = true
	if driver != null:
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
	# Enquanto a equipe ainda age a pé a carcaça fica (Vehicle faz o fade de carcaças depois de 30 s).
	if is_instance_valid(vehicle):
		var crew_alive: bool = (is_police() and not officers.is_empty()) or (not is_police() and is_instance_valid(crew) and not crew.dead)
		vehicle.set_meta("wreck_hold", crew_alive)
	if is_police():
		officers = officers.filter(func(o): return is_instance_valid(o) and not o.dead)
		if controller.gameplay.stars == 0 and state_age > 1.0 or officers.is_empty():
			if officers.is_empty() or controller.is_unseen(vehicle.global_position):
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
	# Investigation deliberately never calls _sees_target or report_contact.
	# The same crew visits the reported scene, not the hidden player's position.
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
		if _sees_target(target): gameplay.report_contact(target.global_position)
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
	var may_stop := (not in_car) or target_still >= RULES.TARGET_STOPPED_SECONDS
	if may_stop and flat <= stop_distance:
		driver.hold(true)
		if driver.settled():
			_park_reset()
			_set_state("parked")
		else: _park_pending(delta)
		driver.tick(delta)
		return
	_park_reset()
	driver.hold(false)
	var forward: Vector3 = -target.global_basis.z if (target != null and in_car) else (anchor - vehicle.global_position)
	_goal = RULES.formation_goal(role, anchor, velocity, forward, stop_distance) if in_car else anchor
	_goal_valid = true
	# Cada plano custa ~2,2 ms (medido 2026-09-23); intervalos defasados por viatura
	# evitam que várias replanejem no mesmo quadro. Travamento continua replanejando na hora.
	_replan_towards(_goal, delta, 2.5 + float(serial % 4) * 0.4)
	_vehicle_combat(delta, target)
	driver.tick(delta)

func _sees_target(target: Node3D) -> bool:
	if controller.player_position_override != Vector3.INF: return false
	var gameplay: Node3D = controller.gameplay
	if target == null or gameplay.health <= 0 or not gameplay.state.weapons_allowed() or not target.visible: return false
	if vehicle.global_position.distance_to(target.global_position) > RULES.SIGHT_RANGE: return false
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
	gameplay.police_shoot(vehicle, RULES.SHOT_DAMAGE)

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
	if state_age < 0.6 or not driver.settled(): return
	if crew_remaining <= 0 and officers.is_empty():
		_police_crew_depleted()
		return
	if _deploy_police_crew():
		_set_siren(false)
		_set_state("working")
		return
	# Keep blocking while no safe exit/slot is available.
	if crew_remaining <= 0: return
	if controller.gameplay.contact_age < 1.0 and _target_velocity(_target()).length() > 3.0 and _target_in_car(_target()):
		_set_state("enroute")
	elif state_age > 8.0:
		_set_state("enroute")

func _deploy_police_crew() -> bool:
	# Com 0 estrelas a averiguação usa o limite de 1 estrela (FOOT_LIMIT[0] é 0: a equipe nunca descia).
	var limit: int = RULES.FOOT_LIMIT[clampi(maxi(controller.gameplay.stars, 1), 0, 6)]
	var free_slots: int = mini(mini(crew_remaining, limit - controller.foot_officer_count()), RULES.OFFICERS_DEPLOY_BURST)
	var deployed := false
	var taken: Array[Vector3] = []
	var traced := TRACE.begin()
	for index in maxi(0, free_slots):
		var exit: Dictionary = controller.exit_point(vehicle, taken, false)
		if exit.is_empty(): break
		taken.append(exit.point)
		var officer: CharacterBody3D = controller.spawn_officer(self, exit.point, float(exit.side))
		officers.append(officer)
		crew_remaining -= 1
		deployed = true
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
	# Nobody remains to drive. Retain a stealable parked car, recycle only unseen.
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
	officers.erase(officer)
	crew_remaining = mini(crew_capacity, crew_remaining + 1)
	if is_instance_valid(officer): officer.queue_free()
	controller.emit_dispatch_event("officer_boarded", {"unit": self})

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
	var arrival := RULES.arrival_radius(service)
	var at_end: bool = driver.at_route_end()
	if flat <= arrival or (at_end and flat <= RULES.FOOT_RANGE):
		driver.hold(true)
		if driver.settled():
			_park_reset()
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
		driver.set_route(result.curve)
		_stranded = 0.0
	else:
		driver.set_route(null)
		_stranded += 1.0
		controller.emit_dispatch_event("departure_blocked", {"unit": self, "reason": result.reason})

func _tick_departing(delta: float) -> void:
	_departure_clock += delta
	driver.hold(driver.route == null)
	driver.tick(delta)
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
	# A blocked junction must not make a police car abandon the pursuit and join
	# the traffic jam.  Officers can finish the last short approach on foot; the
	# cap stays below ordinary off-screen spawn distance.
	var reach := RULES.SPAWN_MAX if is_police() else RULES.FOOT_RANGE
	if flat <= reach:
		driver.hold(true)
		_set_state("parked")
		return
	controller.emit_dispatch_event("route_blocked", {"unit": self})
	_begin_departure()
