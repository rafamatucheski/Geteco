extends CharacterBody3D

const MODEL = preload("res://gameplay/PoliceModel.gd")
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const AUDIO = preload("res://gameplay/CombatAudio.gd")
const TIER_HEALTH := [50.0, 75.0, 95.0, 110.0, 130.0]
const TIER_WEAPONS := ["pistol", "smg", "m4a1", "m4a1", "m4a1"]
const TIER_DAMAGE := [6.0, 6.0, 8.0, 8.0, 8.0]
const TIER_INTERVAL := [0.85, 0.40, 0.32, 0.32, 0.32]
const TIER_BURST := [2, 3, 3, 3, 3]
const BURST_PAUSE := Vector2(1.7, 2.5)
var controller: Node3D
var health := 50.0
var tier := 0
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

const AIM_SECONDS := 0.65
const ATTACK_RANGE := 360.0 / 16.0
const HOLD_RANGE := 112.0 / 16.0
const ARREST_RANGE := 34.0 / 16.0

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
	add_child(visual)
	var safe_tier := clampi(tier, 0, TIER_WEAPONS.size() - 1)
	health = TIER_HEALTH[safe_tier]
	weapon_id = TIER_WEAPONS[safe_tier]
	magazine = _magazine_size()
	_rng.randomize()
	visual.equip(weapon_id)
	add_child(preload("res://gameplay/PoliceOcclusionSilhouette.gd").new())

func _physics_process(delta: float) -> void:
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
		else: _move(Vector3.ZERO, delta)
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
	if repath <= 0.0:
		repath = 1.2
		_plan_navigation(_tactic_goal)
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
			visual.rotation.y = atan2(-aim.x, -aim.z)
		visible_aim_time += delta
		if hostile and distance <= ATTACK_RANGE and visible_aim_time >= AIM_SECONDS and cooldown <= 0 and controller.health > 0:
			_try_fire()
	else:
		visible_aim_time = 0.0
		if direction.length_squared() > 0.1: visual.rotation.y = atan2(-direction.x, -direction.z)
	var move := direction.normalized() * _tactic_speed
	# Tactical units may move laterally or retreat at close range; a global
	# seven-metre hold would erase flanking and containment behavior.
	if _tactic_hold or direction.length() < .45 or (sees_player and not hostile and distance <= ARREST_RANGE): move = Vector3.ZERO
	_track_progress(destination, move, delta)
	_move(move, delta)

func _force_authorized() -> bool:
	if controller.has_method("police_surrendering") and controller.police_surrendering(): return false
	if controller.has_method("police_force_authorized"): return controller.police_force_authorized()
	# Legacy fixtures and standalone visual scenes predate the policy object.
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
	# Protect legacy controllers from passing exterior technical coordinates to
	# an admitted visitor before the first real interior sighting.
	return place.is_empty() or global_position.distance_to(controller.last_known) < 120.0

func _interior_pursuit() -> Node3D:
	if not controller.has_meta("police_interior_pursuit"): return null
	var manager: Variant = controller.get_meta("police_interior_pursuit")
	return manager as Node3D if is_instance_valid(manager) else null

func _plan_navigation(goal: Vector3) -> void:
	navigation.clear()
	nav_index = 0
	if _tactics.segment_clear(self, global_position, goal):
		navigation.append(goal)
		return
	var interior := _interior_pursuit()
	if interior != null and not str(get_meta("police_place_id", "")).is_empty():
		navigation = interior.path_for(self, goal)
	else:
		navigation = controller.find_path(global_position, goal)
	# An empty path means a physically blocked route, not permission to walk
	# directly through the obstacle while a future replanning is pending.
	if navigation.is_empty(): navigation.append(global_position)

func reset_pursuit_context(place_id: String, known_point: Vector3) -> void:
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
	if repath <= 0.0:
		repath = 1.2
		_plan_navigation(point)
	var destination: Vector3 = navigation[-1] if not navigation.is_empty() else global_position
	if nav_index < navigation.size():
		destination = navigation[nav_index]
		if global_position.distance_to(destination) < .65: nav_index += 1
	var direction := destination - global_position
	direction.y = 0.0
	var move := direction.normalized() * 3.3
	if Vector2(global_position.x - point.x, global_position.z - point.z).length() <= 1.25 or direction.length() < .15: move = Vector3.ZERO
	if move.length_squared() > .01: visual.rotation.y = atan2(-move.x, -move.z)
	_track_progress(destination, move, delta)
	_move(move, delta)

func _update_arrest(visible: bool, distance: float, hostile: bool, delta: float) -> void:
	if hostile or not _can_arrest() or not visible or controller.health <= 0:
		_reset_arrest()
		return
	if distance > 220.0/16.0:
		_reset_arrest()
		return
	if not arrest_warning_given:
		arrest_warning_given = true
		if controller.has_method("police_arrest_warning"): controller.police_arrest_warning()
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
		# Dynamic obstacles are intentionally not cached by Gameplay.find_path.
		# Ask for a new bounded route; CharacterBody3D remains the collision authority.
		repath = 0.0
		navigation.clear()
		nav_index = 0
		_stuck_time = 0.0

func _move(move: Vector3, delta: float) -> void:
	if move.length_squared() > 0.01: move = _steering.steer(self, move.normalized(), delta) * move.length()
	velocity.x = move.x
	velocity.z = move.z
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20 * delta
	move_and_slide()
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

func _try_fire() -> bool:
	if dead or reload_timer > 0.0 or burst_pause > 0.0 or not is_instance_valid(controller): return false
	if controller.has_method("police_force_authorized") and not _force_authorized(): return false
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

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0: return
	var vehicle_source: bool = is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source()
	if is_instance_valid(controller) and is_instance_valid(source):
		var target := _pursuit_target()
		if source == target or source == controller.player:
			response_aggression = 12.0
			last_known = (source as Node3D).global_position
			controller.report_contact(last_known)
			cooldown = minf(cooldown, 0.4)
	health = maxf(0, health - amount)
	if health <= 0:
		dead = true
		visual.flash_time = 0.0
		visual.muzzle_flash_3d.hide()
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		var impact_dir: Vector3 = (global_position - (source as Node3D).global_position).normalized() if source is Node3D else Vector3.ZERO
		preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self, visual, impact_dir)
		controller.drop_ammo(global_position, weapon_id)
		get_tree().create_timer(15.0).timeout.connect(queue_free)
	# O veículo é a fonte real. Gameplay confirma se ele está sob controle do
	# jogador; tráfego, viatura e autoria desconhecida não são convertidos em crime.
	if vehicle_source and is_instance_valid(controller) and controller.has_method("report_vehicle_assault"):
		controller.report_vehicle_assault(self, source)
