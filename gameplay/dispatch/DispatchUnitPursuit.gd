extends RefCounted
## Perseguição estilo GTA de uma viatura de polícia: rota em perseguição, guiamento final (cola atrás,
## PIT, emparelha, fecha de frente), bloqueio de cruzamento, busca em leque, visão, tiro a partir da
## viatura, espera de estacionar com ultrapassagem pendente e encerramento por recuperação sem
## progresso. Separado de DispatchUnit.gd em 01/11 (Onda 3 de
## docs/plano-divisao-arquivos-grandes-20261101.md) só para o dono caber na leitura. O estado
## (pursuing, guide_mode, block_point, search_point, _guide_cooldown, _pit_cooldown, _since_plan,
## _plan_clock, _boosted, target_offroad, recovery_total...) continua em DispatchUnit, onde testes,
## DispatchController e os outros DispatchUnit* o leem; o dono mantém cada função antiga como
## delegação de uma linha com a mesma assinatura (on_overtake_* continuam sendo os Callables dos
## sinais do piloto). Tudo estático: a unidade é RefCounted, e um auxiliar com `var g` guardado
## faria ciclo de referência que nunca é liberado. Cada função recebe a unidade em `g` (RefCounted,
## e não o script do dono, para não criar preload cíclico) e passa por `g.` até nas chamadas entre
## funções deste arquivo: tests/dispatch/test_police_foot_stop.gd sobrescreve `_target` e
## `_sees_target`. Roda por quadro por viatura em perseguição: nada alocado aqui além do que já era
## (os dicionários de evento e de plano do roteador são os mesmos de antes).

const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const PURSUIT := preload("res://gameplay/dispatch/PursuitRules.gd")
const PATH := preload("res://gameplay/dispatch/PursuitPath.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const TANK_WEAPON := preload("res://gameplay/police_response/ground/PoliceTankWeapon.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

## Rota em perseguição (PursuitRules.enabled). Carro à vista: rota aberta à frente dele, papéis e
## guiamento final. Carro sumido: busca em leque pela área. A pé: o mesmo de antes.
static func _gta_enroute(g: RefCounted, delta: float, target: Node3D, in_car: bool, car_search: bool, anchor: Vector3, velocity: Vector3) -> void:
	var traced := TRACE.begin()
	g._guide_cooldown = maxf(0.0, g._guide_cooldown - delta)
	g._pit_cooldown = maxf(0.0, g._pit_cooldown - delta)
	g._since_plan += delta
	if in_car or car_search:
		g.driver.speed_cap = PURSUIT.speed_cap(g.variant)
		g.driver.curvature_limit = true
	if in_car:
		g.search_point = Vector3.INF
		g._chase_car(delta, target, anchor, velocity)
	elif car_search:
		g.block_point = Vector3.INF
		g._search_area(delta)
	else:
		# Alvo a pé: direção e parada de antes (teto e curva antigos). O planejador de parada foi
		# calibrado para eles; a 30 m/s a viatura passava do ponto e parava fora da rua.
		g._calm_driving()
		g._goal = anchor
		g._goal_valid = true
		g._replan_towards(g._goal, delta, 2.5 + float(g.serial % 4) * 0.4)
	TRACE.end("unit.gta_enroute", traced)

static func _set_pursuit(g: RefCounted, active: bool, target: CollisionObject3D) -> void:
	if not active and g.pursuing:
		g._boosted = false
		g.driver.set_boost(1.0)
	g.pursuing = active
	if not active: g.guide_mode = ""
	g.driver.set_pursuit(active, target)

## Volta à direção de serviço comum (partida, averiguação): teto e curva originais.
static func _calm_driving(g: RefCounted) -> void:
	g._set_pursuit(false, null)
	g.block_point = Vector3.INF
	g.search_point = Vector3.INF
	g.driver.speed_cap = RULES.speed_cap(g.variant)
	g.driver.curvature_limit = false

static func _chase_car(g: RefCounted, delta: float, target: Node3D, anchor: Vector3, velocity: Vector3) -> void:
	var flat: float = _flat(g.vehicle.global_position, anchor)
	if g.role == PURSUIT.ROLE_BLOCKER and g._blocker_tick(delta, anchor, velocity, flat): return
	g._set_pursuit(true, target as CollisionObject3D)
	# Alvo parado ou lento: a rota termina nele com frenagem, para o planejador de parada assumir
	# sem a viatura chegar a 30 m/s; rota aberta só com ele fugindo.
	g.driver.open_route = Vector2(velocity.x, velocity.z).length() > PURSUIT.OPEN_ROUTE_MIN_TARGET_SPEED
	g._update_boost(flat)
	# Moto só cola atrás; o tanque segue a rota e usa o canhão (PoliceTankWeapon).
	var ram: bool = PURSUIT.ram_allowed(g.controller.gameplay) and g.variant != "motorcycle"
	g._offroad_clock -= delta
	if g._offroad_clock <= 0.0:
		g._offroad_clock = PURSUIT.OFFROAD_CHECK
		var road: Dictionary = g.controller.router.nearest_edge(anchor)
		g.target_offroad = road.is_empty() or float(road.distance) > PURSUIT.OFFROAD_DISTANCE
	if g.variant == "tank":
		g.driver.guidance = false
		g.guide_mode = ""
	elif g._guidance_tick(target, anchor, velocity, flat, ram): g._pit_check(target)
	var direction := Vector3(velocity.x, 0.0, velocity.z)
	direction = direction.normalized() if direction.length_squared() > 1.0 else -target.global_basis.z
	var goal := PURSUIT.chase_goal(anchor, velocity)
	var goal_heading := direction
	# Interceptor à frente do alvo: vem de frente pela faixa contrária para fechar o caminho.
	if g.role == PURSUIT.ROLE_INTERCEPTOR and ram and (g.vehicle.global_position - anchor).dot(direction) > 12.0:
		goal = anchor + direction * clampf(flat * 0.5, 10.0, 60.0)
		goal_heading = -direction
	g._goal = goal
	g._goal_valid = true
	g._pursuit_replan(delta, goal, goal_heading, target)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Recuperação fora da câmera: longe do alvo e sem ser vista, a viatura ganha teto e aceleração;
## perto ou à vista, volta ao normal (nada de alcançar o jogador "no grito" na frente dele).
static func _update_boost(g: RefCounted, flat: float) -> void:
	var unseen: bool = g.controller.is_unseen(g.vehicle.global_position)
	if not g._boosted and flat > PURSUIT.BOOST_DISTANCE and unseen: g._boosted = true
	elif g._boosted and (flat < PURSUIT.BOOST_RELEASE_DISTANCE or not unseen): g._boosted = false
	g.driver.set_boost(PURSUIT.BOOST if g._boosted else 1.0)

static func _overtake_idle(g: RefCounted) -> bool:
	return g.driver.overtake == null or (g.driver.overtake.state == "idle" and not g.driver.overtake.unresolved)

## Guiamento final perto do alvo: sai da rota e mira um ponto no carro dele (cola atrás, PIT,
## emparelha e raspa, ou para atravessado de frente). Devolve se está guiando.
static func _guidance_tick(g: RefCounted, target: Node3D, anchor: Vector3, velocity: Vector3, flat: float, ram: bool) -> bool:
	var forward: Vector3 = -g.vehicle.global_basis.z
	var to_target: Vector3 = anchor - g.vehicle.global_position
	to_target.y = 0.0
	var target_forward := -target.global_basis.z
	var oncoming := target_forward.dot(forward) < -0.3
	# Alvo fora da rua e à vista: o guiamento vale de mais longe (a rota só chega à ponta da rua).
	var reach := PURSUIT.OFFROAD_GUIDE_RANGE if g.target_offroad else PURSUIT.GUIDE_RANGE
	var seen: bool = g._target_line if g.target_offroad else g._target_visible
	# Alvo parado ou lento: na rua quem estaciona e desce é o planejador de parada (PIT num carro
	# parado o empurrava e zerava o "parado há 1,5 s", e ninguém descia); fora da rua só encosta.
	var slow := Vector2(velocity.x, velocity.z).length() < PURSUIT.OPEN_ROUTE_MIN_TARGET_SPEED
	if slow and not g.target_offroad: seen = false
	if slow: ram = false
	var allowed: bool = flat <= reach and seen and g._guide_cooldown <= 0.0 and g._overtake_idle() and not g.driver.reversing
	if allowed and not g.target_offroad and to_target.length_squared() > 0.01 and forward.angle_to(to_target.normalized()) > PURSUIT.GUIDE_CONE: allowed = false
	# De frente só o interceptor com força autorizada fecha o caminho; os outros seguem a rota.
	if allowed and oncoming and not g.target_offroad and not (ram and g.role == PURSUIT.ROLE_INTERCEPTOR): allowed = false
	if allowed and g.driver.guidance and g.driver.blocked_ahead:
		# Algo que não é o alvo no caminho (parede, trânsito): volta à rota por um tempo.
		g._guide_cooldown = PURSUIT.GUIDE_COOLDOWN
		allowed = false
	if not allowed:
		g.driver.guidance = false
		g.guide_mode = ""
		return false
	var plan: Dictionary
	if oncoming:
		plan = {"point": anchor + velocity * 0.6, "speed": clampf(flat * 0.35 - 2.0, 0.0, 10.0), "mode": "block"}
	else:
		var half_width := float(target.get("half_width")) if target.get("half_width") != null else 1.0
		var half_length := float(target.get("half_length")) if target.get("half_length") != null else 2.2
		plan = PURSUIT.guide(g.role, ram, g.vehicle.global_position, anchor, target_forward, velocity, half_width, half_length, g.vehicle.half_width)
	g.driver.guidance = true
	g.driver.guide_point = plan.point
	g.driver.guide_speed = plan.speed
	# Contador, não evento: a troca de modo é frequente e encheria o registro de 64 eventos.
	if g.guide_mode != plan.mode:
		g.controller.count_pursuit("guide_" + str(plan.mode))
		if flat > PURSUIT.GUIDE_RANGE: g.controller.count_pursuit("guide_offroad")
	g.guide_mode = plan.mode
	return true

## PIT: a viatura bateu na traseira lateral do alvo em movimento. O StreetPhysics já aplica o
## impulso da batida; aqui entra o giro que faz o carro rodar (o da batida dá ~5°).
static func _pit_check(g: RefCounted, target: Node3D) -> void:
	if g._pit_cooldown > 0.0 or g.guide_mode != "pit": return
	var body := target as CharacterBody3D
	if body == null or body.get("half_width") == null: return
	# Carro protegido (DamageProtection) não leva batida do StreetPhysics; o giro do PIT também não.
	if PROTECTION.is_protected(body): return
	var target_velocity: Vector3 = body.horizontal_velocity
	if Vector2(target_velocity.x, target_velocity.z).length() < PURSUIT.PIT_MIN_TARGET_SPEED: return
	for index in g.vehicle.get_slide_collision_count():
		var collision: KinematicCollision3D = g.vehicle.get_slide_collision(index)
		if collision.get_collider() != body: continue
		var push: Vector3 = g.vehicle.horizontal_velocity - target_velocity
		var spin := PURSUIT.pit_spin(body.to_local(collision.get_position()), push, body.global_basis, body.half_width, body.half_length)
		if absf(spin) < 0.2: return
		var current := float(body.get_meta("crash_spin", 0.0))
		body.set_meta("crash_spin", clampf(current + spin, -PURSUIT.PIT_SPIN_MAX, PURSUIT.PIT_SPIN_MAX))
		# Sem `crash_stun` o StreetPhysics não aplica o giro guardado (`_update_slide`).
		body.set_meta("crash_stun", maxf(float(body.get_meta("crash_stun", 0.0)), 1.2))
		g._pit_cooldown = PURSUIT.PIT_COOLDOWN
		g.controller.count_pursuit("pit")
		g.controller.emit_dispatch_event("pit", {"unit": g, "spin": snappedf(spin, 0.01)})
		return

## Replanejamento por evento: rota acabando, alvo fora do corredor dela ou rota velha demais;
## nunca mais que uma vez por REPLAN_MIN (defasado por viatura) e nunca durante a ré.
static func _pursuit_replan(g: RefCounted, delta: float, goal: Vector3, goal_heading: Vector3, target: Node3D) -> void:
	g._plan_clock -= delta
	if g._plan_clock > 0.0 or g.driver.reversing: return
	var need: bool = g.driver.route == null or g._since_plan >= PURSUIT.REPLAN_MAX or g.driver.remaining < PURSUIT.replan_remaining(g.vehicle.speed)
	if not need and is_instance_valid(target):
		var closest: Vector3 = g.driver.route.get_closest_point(target.global_position)
		need = _flat(closest, target.global_position) > PURSUIT.REPLAN_CORRIDOR
	if not need:
		g._plan_clock = 0.25
		return
	g._plan_clock = PURSUIT.REPLAN_MIN + float(g.serial % 4) * PURSUIT.REPLAN_STAGGER
	g._since_plan = 0.0
	g._last_planned_goal = goal
	var traced := TRACE.begin()
	var spanned := STALL_WORK.begin()
	var result: Dictionary = g.controller.router.plan(g.vehicle.global_position, goal, -g.vehicle.global_basis.z, goal_heading)
	STALL_WORK.finish_slow("dispatch.unit.gta_plan", spanned, 3000, g.vehicle)
	TRACE.end("router.plan:gta_pursuit", traced)
	if result.ok:
		g._failed_plans = 0
		g.driver.set_route(result.curve)
		return
	g._failed_plans += 1
	if g._failed_plans >= 4:
		g.controller.emit_dispatch_event("no_route", {"unit": g, "reason": result.reason})
		g._failed_plans = 0
		g._begin_departure()

## Bloqueador: vai a um cruzamento à frente do alvo (só se chega antes dele) e para lá até o alvo
## passar, chegar perto ou o tempo acabar. Devolve true enquanto cuida do bloqueio.
static func _blocker_tick(g: RefCounted, delta: float, anchor: Vector3, velocity: Vector3, flat: float) -> bool:
	g._block_retry -= delta
	var direction := Vector3(velocity.x, 0.0, velocity.z)
	if g.block_point == Vector3.INF:
		if g._block_retry > 0.0 or direction.length() < 6.0 or flat < 40.0: return false
		g._block_retry = PURSUIT.BLOCK_RETRY
		var picked: Vector3 = g._pick_block_point(anchor, velocity)
		if picked == Vector3.INF: return false
		var traced := TRACE.begin()
		var result: Dictionary = g.controller.router.plan(g.vehicle.global_position, picked, -g.vehicle.global_basis.z)
		TRACE.end("router.plan:block", traced)
		if not result.ok: return false
		g.block_point = picked
		g._block_hold = 0.0
		g._set_pursuit(false, null)
		g.driver.set_route(result.curve)
		g.controller.count_pursuit("block_planned")
		g.controller.emit_dispatch_event("block_planned", {"unit": g, "point": picked})
	var passed: bool = direction.length() > 1.0 and (anchor - g.block_point).dot(direction.normalized()) > 6.0
	if passed or flat < PURSUIT.BLOCK_RELEASE_DISTANCE or g._block_hold > PURSUIT.BLOCK_HOLD_MAX:
		g.controller.count_pursuit("block_held" if g._block_hold > 0.0 else "block_released_early")
		g.block_point = Vector3.INF
		# Vira perseguidor por um tempo antes de tentar outro cruzamento.
		g._block_retry = 6.0
		g._since_plan = PURSUIT.REPLAN_MAX
		g._plan_clock = 0.0
		return false
	if g.driver.at_route_end() or (g.driver.route != null and g.driver.remaining < 3.0 and g.driver.is_stopped()):
		g._block_hold += delta
		g.guide_mode = "block"
	return true

## Primeiro cruzamento do caminho previsto do alvo em que a viatura chega antes dele, com folga.
static func _pick_block_point(g: RefCounted, anchor: Vector3, velocity: Vector3) -> Vector3:
	var traced := TRACE.begin()
	var spanned := STALL_WORK.begin()
	var speed := Vector2(velocity.x, velocity.z).length()
	var prediction := PATH.predict(g.controller.routes, g.controller.router, anchor, velocity, PURSUIT.BLOCK_MAX_DISTANCE)
	var cap := maxf(1.0, PURSUIT.speed_cap(g.variant) * 0.75)
	var best := Vector3.INF
	for index: int in prediction.junctions:
		var distance: float = prediction.distances[index]
		if distance < PURSUIT.BLOCK_MIN_DISTANCE: continue
		var point: Vector3 = prediction.points[index]
		var police_eta: float = _flat(g.vehicle.global_position, point) * 1.35 / cap
		if police_eta + PURSUIT.BLOCK_ETA_MARGIN < distance / speed:
			best = point
			break
	STALL_WORK.finish_slow("dispatch.unit.block_pick", spanned, 3000, g.vehicle)
	TRACE.end("unit.block_pick", traced, {"junctions": prediction.junctions.size()})
	return best

## Busca em leque: cada viatura vasculha um ponto de rua dentro da área de busca, e outro ao chegar.
static func _search_area(g: RefCounted, delta: float) -> void:
	# Sem contato não há para onde guiar: o ponto do guiamento seria o de antes de perder o alvo.
	g.driver.guidance = false
	var gameplay: Node3D = g.controller.gameplay
	var seen_velocity: Vector3 = g.controller.pursuit_velocity
	seen_velocity.y = 0.0
	if gameplay.contact_age <= PURSUIT.SEARCH_PURSUE_SECONDS and seen_velocity.length() > PURSUIT.OPEN_ROUTE_MIN_TARGET_SPEED:
		# Dobrou a esquina: segue para onde ele estaria agora, de rota aberta, ainda sem leque.
		g._set_pursuit(true, null)
		g.search_point = Vector3.INF
		var lead := clampf(seen_velocity.length() * gameplay.contact_age + PURSUIT.SEARCH_PURSUE_LEAD, PURSUIT.SEARCH_PURSUE_LEAD, PURSUIT.SEARCH_PURSUE_MAX)
		g._goal = gameplay.last_known + seen_velocity.normalized() * lead
		g._goal_valid = true
		if g.guide_mode != "dead_reckoning":
			g.guide_mode = "dead_reckoning"
			g.controller.count_pursuit("search_pursue")
		g._pursuit_replan(delta, g._goal, seen_velocity.normalized(), null)
		return
	g._set_pursuit(false, null)
	var arrived: bool = g.search_point != Vector3.INF and (_flat(g.vehicle.global_position, g.search_point) < PURSUIT.SEARCH_POINT_REACHED or g.driver.at_route_end())
	if g.search_point == Vector3.INF or arrived or g.driver.route == null:
		var next: Vector3 = g.controller.search_point_for(g)
		if next != Vector3.INF and next != g.search_point:
			g.search_point = next
			g._plan_clock = 0.0
			g.controller.count_pursuit("search_point")
	g._goal = g.search_point if g.search_point != Vector3.INF else g.controller.gameplay.last_known
	g._goal_valid = true
	g._replan_towards(g._goal, delta, 2.0)

static func _sees_target(g: RefCounted, target: Node3D) -> bool:
	if g.controller.player_position_override != Vector3.INF: return false
	var gameplay: Node3D = g.controller.gameplay
	if target == null or gameplay.health <= 0 or not gameplay.state.weapons_allowed() or not target.visible: return false
	if PURSUIT.enabled:
		# Cone frontal de 70 m somado ao círculo antigo de 40,6 m (nunca enxerga menos que antes).
		if not PURSUIT.in_vision(g.vehicle.global_position, -g.vehicle.global_basis.z, target.global_position): return false
	elif g.vehicle.global_position.distance_to(target.global_position) > RULES.SIGHT_RANGE: return false
	return g._line_of_sight(target)

## Raio da viatura até o alvo sem nada no meio (só física; distância e cone são de quem chama).
static func _line_of_sight(g: RefCounted, target: Node3D) -> bool:
	var traced := TRACE.begin()
	var ray := PhysicsRayQueryParameters3D.create(g.vehicle.global_position + Vector3.UP * 1.4, target.global_position + Vector3.UP, 7, [g.vehicle.get_rid()])
	var hit: Dictionary = g.vehicle.get_world_3d().direct_space_state.intersect_ray(ray)
	TRACE.end("unit.sees_target", traced)
	return hit.is_empty() or hit.collider == target

## Tiro a partir da viatura (police/PoliceVehicleCombat.gd): dois ou mais
## patamares, alvo em veículo dirigido pelo jogador, equipe ainda a bordo.
static func _vehicle_combat(g: RefCounted, delta: float, target: Node3D) -> void:
	var gameplay: Node3D = g.controller.gameplay
	if g.variant == "tank":
		if g._tank_weapon == null: g._tank_weapon = TANK_WEAPON.new()
		g._tank_weapon.tick(g,delta,target)
		return
	g._shot_cooldown = maxf(0.0, g._shot_cooldown - delta)
	var driven: bool = g.controller.world.get("driving") != null and g.controller.world.driving.occupied
	g._sync_gameplay_caps(gameplay)
	var authorized: bool = gameplay.police_force_authorized() if g._gameplay_has_force else gameplay.stars >= 2
	var surrendering: bool = g._gameplay_has_surrender and gameplay.police_surrendering()
	if not authorized or surrendering or not driven or target == null or g.crew_remaining < RULES.OFFICERS_PER_CAR or not g.officers.is_empty() or not gameplay.state.weapons_allowed():
		g._aim = 0.0
		return
	if g.vehicle.global_position.distance_to(target.global_position) > RULES.SHOT_RANGE or not g._sees_target(target):
		g._aim = 0.0
		return
	g._aim += delta
	if g._aim < RULES.SHOT_AIM_SECONDS or g._shot_cooldown > 0.0: return
	g._burst += 1
	g._shot_cooldown = RULES.SHOT_COOLDOWN if g._burst < 2 else RULES.SHOT_BURST_COOLDOWN
	if g._burst >= 2: g._burst = 0
	gameplay.police_vehicle_shoot(g.vehicle, RULES.SHOT_DAMAGE)

## Parada só concluída com o piloto sem recuperação pendente. Com ultrapassagem
## pendente a unidade volta a "enroute", que mantém o freio (`hold`) e espera o
## piloto terminar a volta à faixa antes de tentar estacionar de novo.
static func _park_pending(g: RefCounted, delta: float) -> void:
	g._park_wait += delta
	if not g._park_notified and g.driver.pending_recovery():
		g._park_notified = true
		g.controller.emit_dispatch_event("park_deferred", {"unit": g, "status": g.driver.stop_status(), "reason": g.driver.overtake.last_reason, "needs": g.driver.overtake.exit_condition()})
	if not g._park_stalled and g._park_wait > 30.0 and g.driver.pending_recovery():
		g._park_stalled = true
		g.controller.emit_dispatch_event("park_recovery_stalled", {"unit": g, "status": g.driver.stop_status(), "reason": g.driver.overtake.last_reason, "needs": g.driver.overtake.exit_condition()})

static func _park_reset(g: RefCounted) -> void:
	g._park_wait = 0.0
	g._park_notified = false
	g._park_stalled = false

## Recuperação FÍSICA em curso ou declarada sem solução. Não inclui passagem normal
## (`passing`), espera (`waiting`) nem ociosidade: isso é perseguição/viagem normal.
static func _recovery_blocked(g: RefCounted) -> bool:
	var overtake: RefCounted = g.driver.overtake if g.driver != null else null
	return overtake != null and (overtake.in_recovery() or overtake.unresolved)

## Acumulador cumulativo do atendimento (`recovery_total`).
##   inicia/avança: a cada tick não suspenso e não destruído em que `_recovery_blocked()`;
##   pausa: fora de recuperação (passando, esperando, ociosa, estacionada) e durante a
##          suspensão distante (a unidade nem chega a este método);
##   não zera: por troca de rota, de estado da unidade, de episódio, por voltar ao eixo,
##          por `resume_pursuit` ou por partir; só some com a unidade.
## Serve para episódios curtos e repetidos, que o `episode_age` (relógio de UM episódio)
## nunca somaria.
static func _track_recovery(g: RefCounted, delta: float) -> void:
	if g._recovery_blocked(): g.recovery_total += delta

## Causa de encerrar o atendimento por recuperação sem progresso, ou "" se não há.
##   recovery_stalled:    UM episódio longo demais, ou `unresolved` e episódio passou do prazo curto
##                        (relógio do episódio; `_park_reset` zeraria `_park_wait` a cada oscilação)
##   recovery_cumulative: orçamento cumulativo do atendimento esgotado E há recuperação em
##                        curso agora. Com a viatura já recuperada e livre, o orçamento
##                        esgotado só se cobra no próximo episódio (não interrompe uma
##                        unidade que voltou ao eixo)
static func _recovery_stall_cause(g: RefCounted) -> String:
	var overtake: RefCounted = g.driver.overtake if g.driver != null else null
	if overtake == null: return ""
	if overtake.episode_age >= RULES.RECOVERY_GIVE_UP_SECONDS: return "recovery_stalled"
	if overtake.unresolved and overtake.episode_age >= RULES.RECOVERY_GIVE_UP_UNRESOLVED_SECONDS: return "recovery_stalled"
	if g.recovery_total >= RULES.RECOVERY_CUMULATIVE_SECONDS and overtake.in_recovery(): return "recovery_cumulative"
	return ""

## Encerra o ATENDIMENTO, não a recuperação física. A ocorrência é solta (outra
## viatura pode assumir), a sirene apaga e a unidade passa a "departing"; o veículo
## continua no piloto, que só se move por curva validada (`cancel_overtaking` dentro de
## `_begin_departure` preserva a recuperação em curso). Nada aqui desembarca equipe,
## teleporta ou remove o veículo: a remoção, se houver, é `_tick_departing`.
static func _end_assignment_for_recovery(g: RefCounted, cause: String) -> void:
	var overtake: RefCounted = g.driver.overtake
	var detail: String = overtake.unresolved_reason if overtake.unresolved else overtake.last_reason
	g.controller.emit_dispatch_event("assignment_released", {"unit": g, "cause": cause, "status": g.driver.stop_status(), "reason": detail, "needs": overtake.exit_condition(), "recovery_total": snappedf(g.recovery_total, 0.1), "episode_age": snappedf(overtake.episode_age, 0.1)})
	g._begin_departure()

static func on_overtake_unresolved(g: RefCounted, unresolved: bool, reason: String) -> void:
	var needs: String = g.driver.overtake.exit_condition() if unresolved and g.driver != null and g.driver.overtake != null else ""
	g.controller.emit_dispatch_event("overtake_unresolved", {"unit": g, "unresolved": unresolved, "reason": reason, "needs": needs})

static func on_overtake_state(g: RefCounted, next: String, reason: String) -> void:
	# Só o que importa para recuperação; o resto seria ruído no registro de 64 eventos.
	if next in ["holding_oncoming", "recovering", "returning"]:
		g.controller.emit_dispatch_event("overtake_state", {"unit": g, "state": next, "reason": reason})
