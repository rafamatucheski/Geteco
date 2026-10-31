extends CharacterBody3D
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const NAVIGATION_QUEUE := preload("res://gameplay/navigation/PoliceNavigationQueue.gd")

const MODEL = preload("res://gameplay/PoliceModel.gd")
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const AUDIO = preload("res://gameplay/CombatAudio.gd")
## Vida (30/10/2026). Playtest: "as polícias morrem muito fácil, só 2 tiros". A farda tinha 50 (metade
## de um civil, que tem 100) e a bala não olhava a zona: pistola (34) e AK (42) matavam com 2 tiros em
## qualquer lugar. Farda e FBI agora passam do civil e usam colete macio (VEST_*); SWAT e Exército
## ficam com a vida e as placas de antes.
const TIER_HEALTH := [100.0, 115.0, 95.0, 110.0, 130.0]
## Placas balísticas das unidades pesadas: SWAT e Exército. O FBI de terno
## e os policiais de farda (inclusive os de biotipo robusto) não usam essas placas.
const TIER_ARMOR := [0.0, 0.0, 80.0, 0.0, 110.0]
## Colete macio de quem não tem placa (farda, FBI por baixo do terno, motociclista). Só a bala passa
## por ele (Gameplay._damage_bullet -> scale_bullet_damage); explosão, fogo, soco e carro não. Segura bem
## munição de mão e pouco a de fuzil/chumbo, por isso a pistola cai mais que a AK. À queima-roupa, no
## tronco: farda 100 = pistola 6 tiros (17 cada), AK 3 (33,6); patamar 1 (115) e FBI (110) = 7 e 4.
## Pernas e braços contam como corpo (a zona é só cabeça × resto).
const VEST_HANDGUN_SCALE := 0.5
const VEST_RIFLE_SCALE := 0.8
const HANDGUN_AMMO := ["9mm", "44"]
## Cabeça fica fora do colete e das placas e leva 2,5×: a mira é recompensada. Farda: pistola 2 (85),
## AK 1 (105); SWAT/Exército: 2 de pistola ou de AK. Altura medida dos pés (cápsula vai a 1,71 m).
const HEAD_SCALE := 2.5
const HEAD_MIN_HEIGHT := 1.45
## Quadro de física em que scale_bullet_damage viu tiro na cabeça: receive_damage desse mesmo quadro
## pula as placas. Fica preso ao quadro para um tiro barrado (invulnerável) não vazar para o próximo dano.
var _head_hit_frame := -1
const TIER_WEAPONS := ["pistol", "smg", "m4a1", "m4a1", "m4a1"]
const TIER_DAMAGE := [6.0, 6.0, 8.0, 8.0, 8.0]
const TIER_INTERVAL := [0.85, 0.40, 0.32, 0.32, 0.32]
const TIER_BURST := [2, 3, 3, 3, 3]
const BURST_PAUSE := Vector2(1.7, 2.5)
var controller: Node3D
signal durability_changed(health: float, max_health: float, armor: float, max_armor: float)
var health := 50.0
var max_health := 50.0
var armor := 0.0
var max_armor := 0.0
var last_damage_time := -INF
var tier := 0
var motorcycle_officer := false
var visual: Node3D
var cooldown := 0.0
var sensor := 0.0
var sees_player := false
var dead := false
var last_known := Vector3.ZERO
var gait := 0.0
var navigation := PackedVector3Array()
var nav_index := 0
var repath := 0.0
var weapon_id := "pistol"
var visible_aim_time := 0.0
var response_aggression := 0.0
var arrest_warning_elapsed := 0.0
var arrest_timer := 0.0
var arrest_warning_given := false
var magazine := 0
var reload_timer := 0.0
var burst_shots := 0
var burst_pause := 0.0
var _rng := RandomNumberGenerator.new()
var _progress_point := Vector3.INF
var _progress_distance := INF
var _stuck_time := 0.0
## Desvio local (passo lateral ao encostar em alguém, troca de lado se travar). O roteador não enxerga corpos
## em movimento, então sem isto dois agentes no mesmo corredor se empurravam até o replano, que dava a mesma rota.
var _steering := preload("res://gameplay/crowd/PedestrianSteering.gd").new()
var _tactics := preload("res://gameplay/police_response/tactics/PoliceTactics.gd").new()
var _tactic_goal := Vector3.INF
var _tactic_hold := false
var _tactic_speed := 3.3
var _tactic_hostile := false
var _tactic_clock := 0.0
var tactic_name := "approach"
var _navigation_queue: Node
var _navigation_waiting := false
var _navigation_generation := 0
var _navigation_replan_interval := 1.2

const AIM_SECONDS := 0.65
const ATTACK_RANGE := 360.0 / 16.0
const HOLD_RANGE := 112.0 / 16.0
const ARREST_RANGE := 34.0 / 16.0
## Ferimento (27/10/2026). Antes o tiro só inclinava o tronco 0,36 s e o policial seguia andando
## e atirando como se nada fosse ("atira no policial e ele nem sente"). Agora o tiro tira ele do
## eixo: recua no sentido da bala e perde a mira por 0,22-0,6 s (sem atirar). Abaixo de metade da
## vida manca (mais lento, passo curto de um lado) e segura o ferimento com a mão livre; com a
## vida no fim, um tiro forte o faz curvar de dor por pouco mais de 1 s.
const HURT_STAGGER := Vector2(0.22, 0.6)
const HURT_PUSH := 2.6
const HURT_DOUBLE_OVER := 1.2
const WOUNDED_RATIO := 0.5
const CRITICAL_RATIO := 0.3
const WOUNDED_SPEED := 0.62
const HURT_RECOVERY := 0.9
const HURT_MIN_DAMAGE := 4.0
## GETECO_POLICE_HURT=0 desliga tranco, mancar e curvar (só a inclinação antiga do tronco), para A/B.
static var hurt_reactions := OS.get_environment("GETECO_POLICE_HURT") != "0"
var hurt_time := 0.0
var _double_over := 0.0
var _hurt_push := Vector3.ZERO
var _hurt_ready_at := -INF

func _ready() -> void:
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = 0.3
	set_meta("gameplay_role", "police")
	if not has_meta("police_place_id"): set_meta("police_place_id", "")
	if not has_meta("police_tactic_slot"): set_meta("police_tactic_slot", get_tree().get_nodes_in_group("v2_police_officers").size() % 6)
	add_to_group("v2_police_officers")
	add_to_group("v2_damageable")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.86
	add_child(shape)
	visual = MODEL.new()
	visual.tier = tier
	visual.motorcycle_officer = motorcycle_officer
	add_child(visual)
	var safe_tier := clampi(tier, 0, TIER_WEAPONS.size() - 1)
	initialize_durability()
	weapon_id = TIER_WEAPONS[safe_tier]
	magazine = _magazine_size()
	_rng.randomize()
	visual.equip(weapon_id)
	add_child(preload("res://gameplay/PoliceOcclusionSilhouette.gd").new())

## Chamado somente na criação do policial. Reentrada de área e retorno à
## viatura preservam as reservas; não há recarga automática da armadura.
func initialize_durability() -> void:
	var safe_tier := clampi(tier, 0, TIER_HEALTH.size() - 1)
	max_health = TIER_HEALTH[safe_tier]
	max_armor = 0.0 if motorcycle_officer else TIER_ARMOR[safe_tier]
	health = max_health
	armor = max_armor

func get_durability_state() -> Dictionary:
	return {"health": health, "max_health": max_health, "armor": armor,
		"max_armor": max_armor, "dead": dead, "heavy_armor": max_armor > 0.0}

func _exit_tree() -> void:
	_cancel_navigation()

func _physics_process(delta: float) -> void:
	var began := STALL_WORK.begin()
	_stall_physics_tick(delta)
	STALL_WORK.finish_slow("police.physics", began, 10000, self)

func _stall_physics_tick(delta: float) -> void:
	if dead or not is_instance_valid(controller): return
	cooldown = maxf(0, cooldown - delta)
	burst_pause = maxf(0.0, burst_pause - delta)
	if reload_timer > 0.0:
		reload_timer = maxf(0.0, reload_timer - delta)
		if reload_timer <= 0.0: magazine = _magazine_size()
	response_aggression = maxf(0.0, response_aggression - delta)
	sensor -= delta
	repath -= delta
	_tactic_clock -= delta
	if hurt_time > 0.0:
		_tick_hurt(delta)
		return
	var target := _pursuit_target()
	var wanted: bool = controller.stars > 0
	if not _shares_player_context():
		sees_player = false
		visible_aim_time = 0.0
		_reset_arrest()
		var interior := _interior_pursuit()
		var access := Vector3.INF
		if wanted and interior != null: access = interior.exterior_access_for(self)
		if access.is_finite(): approach_exterior_access(access, delta)
		elif wanted and str(get_meta("police_place_id", "")).is_empty() and last_known.is_finite() and global_position.distance_to(last_known) < 120.0:
			approach_exterior_access(last_known, delta)
		else:
			_cancel_navigation()
			_move(Vector3.ZERO, delta)
		return
	var hostile := _force_authorized()
	if sensor <= 0:
		sensor = 0.15
		sees_player = wanted and target != null and controller.police_can_see(self)
		if sees_player:
			last_known = target.global_position
			controller.report_contact(last_known)
		elif controller.last_known_valid and _shared_contact_matches_context():
			last_known = controller.last_known
		if not wanted or not controller.last_known_valid:
			navigation.clear()
			nav_index = 0
	if not wanted or not controller.last_known_valid:
		_cancel_navigation()
		sees_player = false
		visible_aim_time = 0.0
		_move(Vector3.ZERO, delta)
		return
	if _tactic_clock <= 0.0 or hostile != _tactic_hostile or not _tactic_goal.is_finite():
		_tactic_clock = .85
		_tactic_hostile = hostile
		var tactical_target := last_known
		var interior := _interior_pursuit()
		if not sees_player and interior != null and not str(get_meta("police_place_id", "")).is_empty():
			if not _shared_contact_matches_context() or global_position.distance_to(last_known) < 1.3:
				tactical_target = interior.search_destination(self)
		var plan := _tactics.plan(self, tactical_target, hostile and sees_player, float(Time.get_ticks_msec()) * .001)
		var next_goal: Vector3 = plan.goal
		if not _tactic_goal.is_finite() or _tactic_goal.distance_to(next_goal) > 1.0: repath = 0.0
		_tactic_goal = next_goal
		_tactic_hold = bool(plan.hold)
		_tactic_speed = float(plan.speed)
		tactic_name = str(plan.doctrine)
	if repath <= 0.0 and _plan_navigation(_tactic_goal):
		repath = _navigation_replan_interval
	var distance := Vector2(global_position.x - last_known.x, global_position.z - last_known.z).length()
	var destination: Vector3 = navigation[-1] if not navigation.is_empty() else global_position
	if nav_index < navigation.size():
		destination = navigation[nav_index]
		if global_position.distance_to(destination) < 0.65:
			nav_index += 1
	var direction := destination - global_position
	direction.y = 0
	_update_arrest(sees_player, distance, hostile, delta)
	if sees_player:
		var aim := last_known - global_position
		aim.y = 0
		if aim.length_squared() > 0.01:
			# Gira o tronco em vez de estalar; o tiro espera o peito alinhar (_facing_target).
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-aim.x, -aim.z) - global_rotation.y, 1.0 - exp(-12.0 * delta))
		visible_aim_time += delta
		if hostile and distance <= ATTACK_RANGE and visible_aim_time >= AIM_SECONDS and cooldown <= 0 and controller.health > 0:
			_try_fire()
	else:
		visible_aim_time = 0.0
		if direction.length_squared() > 0.1: visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z) - global_rotation.y, 1.0 - exp(-10.0 * delta))
	var move := direction.normalized() * _tactic_speed * (WOUNDED_SPEED if hurt_reactions and wounded() else 1.0)
	# Unidades táticas podem se mover de lado ou recuar a curta distância; uma parada global
	# a sete metros apagaria o comportamento de flanco e contenção.
	if _tactic_hold or direction.length() < .45 or (sees_player and not hostile and distance <= ARREST_RANGE): move = Vector3.ZERO
	_track_progress(destination, move, delta)
	_move(move, delta)

func _force_authorized() -> bool:
	if controller.has_method("police_surrendering") and controller.police_surrendering(): return false
	if controller.has_method("police_force_authorized"): return controller.police_force_authorized()
	# Fixtures legadas e cenas visuais avulsas são anteriores ao objeto de política.
	return controller.stars >= 2 or response_aggression > 0.0

func _can_arrest() -> bool:
	if controller.has_method("police_can_arrest"): return controller.police_can_arrest()
	return controller.stars == 1

func _shares_player_context() -> bool:
	if not "state" in controller or controller.state == null or not "place_id" in controller.state: return true
	return str(get_meta("police_place_id", "")) == str(controller.state.place_id)

func _shared_contact_matches_context() -> bool:
	var place := str(get_meta("police_place_id", ""))
	if controller.has_meta("police_contact_place_id"):
		return place == str(controller.get_meta("police_contact_place_id")) and (place.is_empty() or global_position.distance_to(controller.last_known) < 120.0)
	# Protege os controladores legados de passar coordenadas técnicas do exterior para
	# um visitante admitido antes do primeiro avistamento real no interior.
	return place.is_empty() or global_position.distance_to(controller.last_known) < 120.0

func _interior_pursuit() -> Node3D:
	if not controller.has_meta("police_interior_pursuit"): return null
	var manager: Variant = controller.get_meta("police_interior_pursuit")
	return manager as Node3D if is_instance_valid(manager) else null

func _plan_navigation(goal: Vector3) -> bool:
	_navigation_replan_interval = 1.2
	# Um pedido pendente é consultado a cada tick de física. A varredura de caminho direto
	# já foi feita na admissão; repeti-la aqui escaparia do orçamento de busca.
	if not _navigation_waiting and _tactics.segment_clear(self, global_position, goal):
		_cancel_navigation()
		navigation = PackedVector3Array([goal])
		nav_index = 0
		return true
	var interior := _interior_pursuit()
	if interior != null and not str(get_meta("police_place_id", "")).is_empty():
		_cancel_navigation()
		navigation = interior.path_for(self, goal)
	else:
		if not is_instance_valid(_navigation_queue) or _navigation_queue.get("gameplay") != controller:
			_cancel_navigation()
			_navigation_queue = controller.get_node_or_null("PoliceNavigationQueue")
			if _navigation_queue == null:
				_navigation_queue = NAVIGATION_QUEUE.new()
				_navigation_queue.name = "PoliceNavigationQueue"
				_navigation_queue.gameplay = controller
				controller.add_child(_navigation_queue)
		_navigation_waiting = true
		var response: Dictionary = _navigation_queue.request(self, goal)
		# Keep a previously validated route while waiting. With no route, callers
		# hold position; a pending search never permits movement through a solid.
		if not response.ready: return false
		_navigation_waiting = false
		navigation = response.path
		if response.get("refresh", false): _navigation_replan_interval = .15
	nav_index = 0
	# Caminho vazio significa rota bloqueada fisicamente, não permissão para andar
	# direto através do obstáculo enquanto um replanejamento futuro está pendente.
	if navigation.is_empty(): navigation.append(global_position)
	else:
		# O policial pode continuar andando na rota antiga enquanto este pedido roda.
		# Pula o prefixo já percorrido só quando uma varredura física admite esse passo.
		var nearest := 0
		var distance := global_position.distance_squared_to(navigation[0])
		for index in range(1, navigation.size()):
			var candidate := global_position.distance_squared_to(navigation[index])
			if candidate < distance:
				distance = candidate
				nearest = index
		if nearest > 0 and distance <= 1.0 and absf(navigation[nearest].y - global_position.y) <= .3 and _tactics.segment_clear(self, global_position, navigation[nearest]): nav_index = nearest
	return true

func _cancel_navigation() -> void:
	_navigation_waiting = false
	_navigation_generation += 1
	if is_instance_valid(_navigation_queue): _navigation_queue.cancel(self)

func reset_pursuit_context(place_id: String, known_point: Vector3) -> void:
	_cancel_navigation()
	set_meta("police_place_id", place_id)
	last_known = known_point
	sees_player = false
	visible_aim_time = 0.0
	sensor = 0.0
	repath = 0.0
	_tactic_clock = 0.0
	_tactic_goal = Vector3.INF
	navigation.clear()
	nav_index = 0
	_reset_arrest()

func approach_exterior_access(point: Vector3, delta: float) -> void:
	sees_player = false
	visible_aim_time = 0.0
	if repath <= 0.0 and _plan_navigation(point):
		repath = _navigation_replan_interval
	var destination: Vector3 = navigation[-1] if not navigation.is_empty() else global_position
	if nav_index < navigation.size():
		destination = navigation[nav_index]
		if global_position.distance_to(destination) < .65: nav_index += 1
	var direction := destination - global_position
	direction.y = 0.0
	var move := direction.normalized() * 3.3
	if Vector2(global_position.x - point.x, global_position.z - point.z).length() <= 1.25 or direction.length() < .15: move = Vector3.ZERO
	if move.length_squared() > .01: visual.rotation.y = atan2(-move.x, -move.z) - global_rotation.y
	_track_progress(destination, move, delta)
	_move(move, delta)

func _update_arrest(p_visible: bool, distance: float, hostile: bool, delta: float) -> void:
	if hostile or not _can_arrest() or not p_visible or controller.health <= 0:
		_reset_arrest()
		return
	if distance > 220.0/16.0:
		_reset_arrest()
		return
	if not arrest_warning_given:
		arrest_warning_given = true
		if controller.has_method("police_arrest_warning"): controller.police_arrest_warning(self)
	arrest_warning_elapsed += delta
	var target := _pursuit_target()
	var target_speed := Vector2(target.velocity.x,target.velocity.z).length() if target is CharacterBody3D else INF
	if distance <= ARREST_RANGE and arrest_warning_elapsed >= 3.0 and target_speed <= 10.0/16.0:
		arrest_timer += delta
		if arrest_timer >= 2.0 and controller.has_method("arrest_player"):
			arrest_timer = 0.0
			controller.arrest_player()
	else:
		arrest_timer = 0.0

func _reset_arrest() -> void:
	arrest_warning_elapsed = 0.0
	arrest_timer = 0.0
	arrest_warning_given = false

func _pursuit_target() -> Node3D:
	var target: Variant = controller.pursuit_target()
	return target as Node3D if is_instance_valid(target) else null

func _track_progress(destination: Vector3, movement: Vector3, delta: float) -> void:
	if movement.length_squared() < 0.01:
		_stuck_time = 0.0
		_progress_point = Vector3.INF
		_progress_distance = INF
		return
	var remaining := Vector2(global_position.x - destination.x, global_position.z - destination.z).length()
	if _progress_point == Vector3.INF or _progress_point.distance_to(destination) > 0.5:
		_progress_point = destination
		_progress_distance = remaining
		_stuck_time = 0.0
	elif remaining < _progress_distance - 0.2:
		_progress_distance = remaining
		_stuck_time = 0.0
	else:
		_stuck_time += delta
	if _stuck_time >= 0.9:
		# Obstáculos dinâmicos de propósito não ficam no cache de Gameplay.find_path.
		# Pede uma rota limitada nova; CharacterBody3D continua sendo a autoridade de colisão.
		repath = 0.0
		navigation.clear()
		nav_index = 0
		_stuck_time = 0.0

func _move(move: Vector3, delta: float) -> void:
	if move.length_squared() > 0.01: move = _steering.steer(self, move.normalized(), delta) * move.length()
	velocity.x = move.x
	velocity.z = move.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20 * delta
	var move_began := STALL_WORK.begin()
	move_and_slide()
	STALL_WORK.finish_slow("police.move_and_slide", move_began, 10000, self)
	gait += Vector2(velocity.x, velocity.z).length() * delta * 3.4
	visual.left_upper_leg.rotation.x = sin(gait) * 0.55
	visual.right_upper_leg.rotation.x = -sin(gait) * 0.55
	visual.update_pose(delta, sees_player, reload_timer > 0.0,
		1.0 - reload_timer / maxf(AUDIO.MIN_RELOAD, AUDIO.reload_seconds(weapon_id)), gait)

func _magazine_size() -> int:
	return maxi(1, int(CATALOG.get_weapon(weapon_id).get("magazine_size", 1)))

func _start_reload() -> void:
	if reload_timer > 0.0: return
	reload_timer = maxf(AUDIO.MIN_RELOAD, AUDIO.reload_seconds(weapon_id))
	cooldown = 0.0
	burst_shots = 0
	burst_pause = 0.0
	if is_instance_valid(controller) and controller.has_method("police_reload"):
		controller.police_reload(self, weapon_id)

## Só dispara com o peito do modelo (-Z) a até 35° do último ponto visto; virando, a arma ainda aponta para outro lado.
func _facing_target() -> bool:
	if not is_instance_valid(visual): return true
	var facing := -visual.global_basis.z
	var toward := last_known - global_position
	facing.y = 0.0
	toward.y = 0.0
	if facing.length_squared() < 0.0001 or toward.length_squared() < 0.0001: return true
	return facing.normalized().dot(toward.normalized()) >= cos(deg_to_rad(35.0))

func _try_fire() -> bool:
	if dead or reload_timer > 0.0 or burst_pause > 0.0 or not is_instance_valid(controller): return false
	if controller.has_method("police_force_authorized") and not _force_authorized(): return false
	if not _facing_target(): return false
	if magazine <= 0:
		_start_reload()
		return false
	var safe_tier := clampi(tier, 0, TIER_DAMAGE.size() - 1)
	magazine -= 1
	burst_shots += 1
	cooldown = TIER_INTERVAL[safe_tier] + _rng.randf_range(0.0, 0.2)
	controller.police_shoot(self, TIER_DAMAGE[safe_tier], weapon_id)
	if magazine <= 0:
		_start_reload()
	elif burst_shots >= TIER_BURST[safe_tier]:
		burst_shots = 0
		burst_pause = _rng.randf_range(BURST_PAUSE.x, BURST_PAUSE.y)
	return true

func wounded() -> bool:
	return not dead and max_health > 0.0 and health / max_health < WOUNDED_RATIO

## `direction`: sentido da bala no plano. `wound`: o que passou da placa; `absorbed`: o que ela segurou.
func _react_to_wound(direction: Vector3, wound: float, absorbed: float) -> void:
	if not hurt_reactions: return
	_sync_wound_pose()
	var now := float(Time.get_ticks_msec()) * 0.001
	# Depois de um tranco ele aguenta os tiros seguintes por HURT_RECOVERY s (só o tronco balança):
	# uma rajada de SMG não pode deixar o policial travado sem nunca atirar de volta. Arranhão (estilhaço,
	# chumbo de longe) também só balança o tronco.
	if hurt_time > 0.0 or now < _hurt_ready_at or wound + absorbed < HURT_MIN_DAMAGE: return
	# A placa segura o furo, não o tranco: tiro no colete ainda tira a mira, por menos tempo.
	var severity := clampf(wound / 30.0, 0.2 if absorbed > 0.0 else 0.0, 1.0)
	var seconds := lerpf(HURT_STAGGER.x, HURT_STAGGER.y, severity)
	if health / maxf(max_health, 1.0) < CRITICAL_RATIO and wound >= 15.0 and _double_over <= 0.0 and _rng.randf() < 0.55:
		_double_over = HURT_DOUBLE_OVER
		seconds = HURT_DOUBLE_OVER
	hurt_time = seconds
	_hurt_ready_at = now + seconds + HURT_RECOVERY
	# Recuo de ~13 cm (tiro fraco) a ~37 cm (forte): o passo para trás aparece na câmera alta.
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.0001: _hurt_push = flat.normalized() * HURT_PUSH * lerpf(0.6, 1.0, severity)
	# A mira volta pela metade: o próximo tiro dele sai um pouco depois de se recompor.
	visible_aim_time = minf(visible_aim_time, AIM_SECONDS * 0.5)
	burst_shots = 0
	_sync_wound_pose()

func _tick_hurt(delta: float) -> void:
	hurt_time = maxf(0.0, hurt_time - delta)
	_double_over = maxf(0.0, _double_over - delta)
	_reset_arrest()
	# O recuo morre em ~0,25 s; o resto do tempo ele fica no lugar se recompondo.
	_hurt_push = _hurt_push.move_toward(Vector3.ZERO, delta * 9.0)
	velocity.x = _hurt_push.x
	velocity.z = _hurt_push.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20 * delta
	move_and_slide()
	gait += Vector2(velocity.x, velocity.z).length() * delta * 3.4
	_sync_wound_pose()
	visual.update_pose(delta, false, reload_timer > 0.0,
		1.0 - reload_timer / maxf(AUDIO.MIN_RELOAD, AUDIO.reload_seconds(weapon_id)), gait)

## Pose de ferido no corpo visível: mancar e segurar o ferimento (vida abaixo da metade) e curvar
## de dor (`_double_over`). Só escreve quando muda; o corpo interpola.
func _sync_wound_pose() -> void:
	if not is_instance_valid(visual): return
	var bend := 1.0 if _double_over > 0.0 else 0.0
	var limp := clampf((WOUNDED_RATIO - health / maxf(max_health, 1.0)) / WOUNDED_RATIO * 1.6, 0.0, 1.0) if not dead else 0.0
	if visual.has_method("set_wound_pose"): visual.set_wound_pose(limp, bend)

## Zona da bala, chamada por Gameplay._damage_bullet antes de receive_damage. `hit_point` infinito
## (chamada sem raio) conta como corpo; `weapon` vazio conta como fuzil (o colete segura menos).
func scale_bullet_damage(amount: float, hit_point: Vector3, weapon: Dictionary) -> float:
	if dead or not is_finite(amount) or amount <= 0.0: return amount
	if hit_point.is_finite() and hit_point.y - global_position.y >= HEAD_MIN_HEIGHT:
		_head_hit_frame = Engine.get_physics_frames()
		return amount * HEAD_SCALE
	# Placa (SWAT/Exército) já é a proteção do tronco: não soma colete por cima.
	if max_armor > 0.0: return amount
	var handgun := String(weapon.get("ammo_family", "")) in HANDGUN_AMMO
	return amount * (VEST_HANDGUN_SCALE if handgun else VEST_RIFLE_SCALE)

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0: return
	last_damage_time = float(Time.get_ticks_msec()) * 0.001
	var vehicle_source: bool = is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source()
	if is_instance_valid(controller) and is_instance_valid(source):
		var target := _pursuit_target()
		if source == target or source == controller.player:
			response_aggression = 12.0
			last_known = (source as Node3D).global_position
			controller.report_contact(last_known)
			cooldown = minf(cooldown, 0.4)
	# Uma única absorção para qualquer fonte (bala, explosão, fogo, impacto):
	# esgotar as placas não mata; somente o excesso chega à vida, sem redução dupla.
	# Tiro na cabeça (marcado por scale_bullet_damage neste quadro) passa por cima das placas.
	var head_hit := _head_hit_frame == Engine.get_physics_frames()
	_head_hit_frame = -1
	var absorbed := 0.0 if head_hit else minf(armor, amount)
	armor = maxf(0.0, armor - absorbed)
	health = maxf(0.0, health - (amount - absorbed))
	# Gameplay._impact_sound troca o estalo de carne pelo baque da placa neste quadro.
	if absorbed > 0.0: set_meta("armor_hit_frame", Engine.get_physics_frames())
	if health <= 0:
		dead = true
		_cancel_navigation()
		visual.flash_time = 0.0
		visual.muzzle_flash_3d.hide()
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		var impact_dir: Vector3 = (global_position - (source as Node3D).global_position).normalized() if source is Node3D else Vector3.ZERO
		preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self, visual, impact_dir)
		if controller.has_method("drop_dead_weapon"): controller.drop_dead_weapon(self, weapon_id)
		else: controller.drop_ammo(global_position, weapon_id)
	else:
		var hit_dir: Vector3 = (global_position - (source as Node3D).global_position).normalized() if source is Node3D else Vector3.ZERO
		preload("res://gameplay/CharacterFallPresentation3D.gd").apply_hit(self, visual, hit_dir, amount)
		_react_to_wound(hit_dir, amount - absorbed, absorbed)
	durability_changed.emit(health, max_health, armor, max_armor)
	# O veículo é a fonte real. Gameplay confirma se ele está sob controle do
	# jogador; tráfego, viatura e autoria desconhecida não são convertidos em crime.
	if vehicle_source and is_instance_valid(controller) and controller.has_method("report_vehicle_assault"):
		controller.report_vehicle_assault(self, source)
