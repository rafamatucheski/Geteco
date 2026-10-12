extends "res://runtime/RobberyActor.gd"
## Finite convoy crew. The transport owns crime attribution, radio and persistence.
const MODEL := preload("res://gameplay/armored/ArmoredGuardModel.gd")
const APRON := preload("res://gameplay/armored/ArmoredBankApron.gd")
var convoy
var slot := 0
var tier := 1
var patrol_target := Vector3.ZERO
var cargo_carrying := false
var security: Dictionary = {}
var gait := 0.0
var _scan_clock := 0.0
var _sees_target := false
var _last_seen := Vector3.ZERO
var _memory := 0.0
var _engaged := false
var _reaction := 0.0
var _rounds := 12
var _reload_left := 0.0
var _support_clock := 0.0
var _safe_direction := Vector3.ZERO
var _waiting_for_traffic := false
var _steering := preload("res://gameplay/crowd/PedestrianSteering.gd").new()
var _service_final := Vector3.INF
var _service_corner := Vector3.INF
var _service_frontage := Vector3.INF
var _service_corner_passed := false
var _service_waypoints: Array[Vector3] = []
var _service_waypoint := 0

func configure_security(profile: Dictionary) -> void:
	security = profile.duplicate(true)
	tier = 2 if str(security.get("weapon", "pistol")) != "pistol" else 1
	# Restore saved health after configuring, before admission to the tree.
	if not is_inside_tree(): health = float(security.get("guard_health", 110.0))
	_rounds = 12 if tier == 1 else 24

func _ready() -> void:
	guard = true
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .4
	# Radio belongs to the convoy. Civilian witness scans would otherwise create
	# their own 2.5-second call and bypass the authored rural/adaptive delay.
	set_meta("gameplay_role", "security")
	set_meta("local_security", true)
	set_meta("police_place_id", "")
	add_to_group("v2_damageable")
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .28
	shape.height = 1.75
	collider.shape = shape
	collider.position.y = .875
	add_child(collider)
	visual = MODEL.new()
	visual.appearance_index = slot
	add_child(visual)
	visual.equip(str(security.get("weapon", "pistol")))
	weapon = visual.weapon
	_scan_clock = float(slot % 5) * .04
	if health <= 0: _fall(true)

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0: return
	if is_instance_valid(convoy): convoy.provoke(source)
	super.receive_damage(amount, source)
	if dead and is_instance_valid(visual): visual.drop_case()

func reached_target(radius := .45) -> bool:
	var offset := patrol_target - global_position
	return Vector2(offset.x, offset.z).length() <= radius and absf(offset.y) < .65

func _service_navigation_target() -> Vector3:
	# Bank frontage, rear vault and lateral post form a finite walking path.
	# Every hull crossing happens behind the truck, including the last return
	# to the post after unloading; the final action target remains transport-owned.
	var corner := Vector3.INF
	var service_vehicle: Node3D
	var door := Vector3.INF
	var target_bank := false
	var target_door := false
	var target_post := false
	if slot < 2 and is_instance_valid(convoy) and not bool(convoy.data.get("hostile", false)) and convoy.data.get("phase", "") in ["loading", "unloading", "boarding"]:
		var definitions: Variant = convoy.get("banks")
		var vehicles: Variant = convoy.get("fleet")
		var bank_id: String = str(convoy.data.get("destination", "")) if convoy.data.phase == "unloading" else str(convoy.data.get("origin", ""))
		if definitions is Dictionary and definitions.has(bank_id) and vehicles is Array and slot < vehicles.size() and is_instance_valid(vehicles[slot]):
			var definition: Dictionary = definitions[bank_id]
			var bank: Variant = definition.get("entry_position")
			if bank is Vector3 and vehicles[slot].has_method("door_point"):
				service_vehicle = vehicles[slot]
				door = service_vehicle.door_point()
				var bank_target: Vector3 = bank + Vector3(float(slot) - .5, .08, 1.0)
				var local_target: Vector3 = service_vehicle.to_local(patrol_target)
				target_bank = patrol_target.distance_to(bank_target) < 1.0
				target_door = patrol_target.distance_to(door) < .6
				target_post = "half_width" in service_vehicle and "half_length" in service_vehicle and absf(local_target.x) > float(service_vehicle.half_width)+.5 and absf(local_target.x) < float(service_vehicle.half_width)+1.7 and absf(local_target.z) < float(service_vehicle.half_length) and absf(local_target.y) < .7
				if target_bank or target_door or target_post:
					corner = Vector3(door.x, bank.y + .08, bank.z + 1.0)
	if corner == Vector3.INF:
		_service_final = Vector3.INF
		_service_corner = Vector3.INF
		_service_frontage = Vector3.INF
		_service_corner_passed = false
		_service_waypoints.clear()
		return patrol_target
	# Reassigning the same patrol target every service tick must not send the
	# carrier back to a corner already passed. Ignore stopped-vehicle jitter.
	if _service_final == Vector3.INF or _service_final.distance_to(patrol_target) > .2 or _service_frontage.distance_to(corner) > .2:
		_service_final = patrol_target
		_service_frontage = corner
		_service_waypoints.clear()
		_service_waypoint = 0
		var local: Vector3 = service_vehicle.to_local(global_position)
		var rear: Vector3 = service_vehicle.to_local(door)
		var near_vehicle := false
		if "half_width" in service_vehicle and "half_length" in service_vehicle:
			var beside_hull: bool = absf(local.x) >= float(service_vehicle.half_width)+.5 and absf(local.x) <= float(service_vehicle.half_width)+1.7 and local.z >= -float(service_vehicle.half_length)-.5
			near_vehicle = global_position.distance_to(service_vehicle.global_position) < 8.0 and (local.z >= rear.z-.2 or beside_hull)
		var rear_side: Vector3 = service_vehicle.to_global(Vector3(local.x,.08,rear.z))
		if APRON.contains(service_vehicle.global_position):
			_service_waypoints = APRON.carrier_path(service_vehicle,global_position,patrol_target,corner,target_bank,target_door)
		elif not reached_target(.45):
			if target_bank:
				if near_vehicle and local.z < rear.z-.2: _service_waypoints.append_array([rear_side,door])
				_service_waypoints.append(corner)
			elif target_door:
				if near_vehicle and local.z < rear.z-.2: _service_waypoints.append(rear_side)
				elif not near_vehicle: _service_waypoints.append(corner)
			elif target_post:
				var post: Vector3 = service_vehicle.to_local(patrol_target)
				if not near_vehicle: _service_waypoints.append_array([corner,door])
				elif local.z < rear.z-.2 and local.x*post.x < 0: _service_waypoints.append_array([rear_side,door])
				_service_waypoints.append(service_vehicle.to_global(Vector3(post.x,.08,rear.z)))
		_support_clock = 0.0
	while _service_waypoint < _service_waypoints.size():
		_service_corner = _service_waypoints[_service_waypoint]
		var offset := _service_corner - global_position
		if Vector2(offset.x, offset.z).length() <= .38 and absf(offset.y) < .65:
			_service_waypoint += 1
			_support_clock = 0.0
		else: break
	_service_corner_passed = _service_waypoint >= _service_waypoints.size()
	return patrol_target if _service_corner_passed else _service_corner

func _exterior_combat_allowed() -> bool:
	return is_instance_valid(convoy) and convoy.crew_operational() \
		and convoy.session.state.place_id.is_empty() and convoy.session.state.weapons_allowed()

func can_see_player() -> bool:
	if dead or not _exterior_combat_allowed(): return false
	var gameplay = convoy.session.world.gameplay
	var target: Node3D = gameplay.pursuit_target()
	if not is_instance_valid(target) or not target.is_visible_in_tree(): return false
	var reach := minf(26.875, float(security.get("detection_range", 24.0)))
	if global_position.distance_squared_to(target.global_position) > reach * reach: return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.4, target.global_position + Vector3.UP, 7, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target

func player_is_aiming_at_me() -> bool:
	if not _exterior_combat_allowed(): return false
	var gameplay = convoy.session.world.gameplay
	if not gameplay.aiming or convoy.session.state.equipped_weapon in ["", "fists"]: return false
	var offset: Vector3 = global_position - convoy.session.world.player.global_position
	offset.y = 0
	var aim: Vector3 = gameplay._aim_direction()
	return aim.normalized().dot(offset.normalized()) > .94 and can_see_player()

func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(convoy) or not convoy.crew_operational(): return
	var gameplay = convoy.session.world.gameplay
	var combat_allowed := _exterior_combat_allowed()
	_scan_clock -= delta
	_memory = maxf(0.0, _memory - delta)
	if _scan_clock <= 0:
		_scan_clock = .2
		_sees_target = can_see_player()
		if not bool(convoy.data.hostile) and _sees_target and player_is_aiming_at_me():
			convoy.provoke(convoy.session.world.player)
		if bool(convoy.data.hostile) and _sees_target:
			_last_seen = gameplay.pursuit_target().global_position
			_memory = 3.5
	var hostile: bool = convoy.data.hostile and combat_allowed
	if hostile and not _engaged:
		_reaction = float(security.get("reaction_time", .8)) + float(slot % 3) * .08
		visual.drop_case()
	_engaged = hostile
	if not hostile: _sees_target = false
	_reaction = maxf(0.0, _reaction - delta)
	cooldown = maxf(0.0, cooldown - delta)
	_reload_left = maxf(0.0, _reload_left - delta)
	var target: Vector3 = _last_seen if hostile and _memory > 0 else _service_navigation_target()
	var direction := target - global_position
	direction.y = 0
	var stop_distance := 9.0 if hostile and _sees_target else .35
	var moving := direction.length() > stop_distance
	# Never track Dante through a wall, into a building or indefinitely across town.
	if hostile and (_memory <= 0 or global_position.distance_to(patrol_target) > 35.0): moving = false
	if _reload_left > 0: moving = false
	var desired := _steering.steer(self, direction.normalized() if moving else Vector3.ZERO, delta)
	_support_clock -= delta
	if _support_clock <= 0:
		_support_clock = .15
		_waiting_for_traffic = not hostile and moving and _service_corner != Vector3.INF and not _service_traffic_clear(target)
		_safe_direction = Vector3.ZERO if _waiting_for_traffic else _supported_direction(desired)
	if not moving: _safe_direction = Vector3.ZERO
	if _waiting_for_traffic: moving = false
	var pace := float(security.get("move_speed", 2.6)) if hostile else 1.35
	velocity.x = _safe_direction.x * pace
	velocity.z = _safe_direction.z * pace
	velocity.y = -1.0 if is_on_floor() else maxf(-20.0, velocity.y - 20.0 * delta)
	move_and_slide()
	if direction.length_squared() > .01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-10.0 * delta))
	gait += delta * (7.0 if moving else 0.0)
	visual.carrying = cargo_carrying and not hostile
	# PoliceModel expects aiming, RELOADING, reload progress, gait.
	visual.update_pose(delta, hostile and _sees_target, _reload_left > 0, 1.0 - _reload_left / 2.0, gait)
	if not hostile or not _sees_target or _reaction > 0 or cooldown > 0 or _reload_left > 0: return
	if not can_see_player(): return
	if _rounds <= 0:
		_reload_left = 2.0
		_rounds = 12 if tier == 1 else 24
		gameplay.police_reload(self, str(security.get("weapon", "pistol")))
		return
	gameplay.police_shoot(self, float(security.get("shot_damage", 8.0)), str(security.get("weapon", "pistol")))
	_rounds -= 1
	cooldown = maxf(.15, float(security.get("shot_interval", .95)))

func _service_traffic_clear(target: Vector3) -> bool:
	# Only the two neutral carriers call this, at the existing support scan rate.
	# Predict the crossing against moving vehicle hulls, including their rear end;
	# waiting changes the pedestrian's movement, never traffic or damage rules.
	var path := target - global_position
	path.y = 0.0
	if path.length() < .4: return true
	var pace := 1.35
	var horizon := minf(8.0, path.length() / pace)
	var walk := path.normalized() * pace
	for car in get_tree().get_nodes_in_group("drivable"):
		if not is_instance_valid(car) or not car is Node3D or not car.has_method("driver_seat_anchor"): continue
		if not car.is_physics_processing() or absf(float(car.speed)) < .4: continue
		var offset: Vector3 = global_position - car.global_position
		if absf(offset.y) > 2.0 or offset.length_squared() > 85.0 * 85.0: continue
		var inverse: Basis = car.global_basis.inverse()
		var relative: Vector3 = inverse * offset
		var bounds := Vector2(float(car.half_width) + .65, float(car.half_length) + .9)
		# Once inside a lane, finish crossing rather than stopping under a car.
		if absf(relative.x) <= bounds.x: continue
		var rate: Vector3 = inverse * walk - Vector3(0.0, 0.0, -float(car.speed))
		var first := 0.0
		var last := horizon
		for axis in [0, 2]:
			var extent := bounds.x if axis == 0 else bounds.y
			if absf(rate[axis]) < .001:
				if absf(relative[axis]) > extent:
					last = -1.0
					break
				continue
			var entry: float = (-extent - relative[axis]) / rate[axis]
			var leaving: float = (extent - relative[axis]) / rate[axis]
			first = maxf(first, minf(entry, leaving))
			last = minf(last, maxf(entry, leaving))
		if first <= last: return false
	return true

func _supported_direction(desired: Vector3) -> Vector3:
	if desired.is_zero_approx(): return desired
	var next := global_position + desired * .65
	var ray := PhysicsRayQueryParameters3D.create(next + Vector3.UP * .4, next - Vector3.UP * .7, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < .65 or absf(hit.position.y - global_position.y) > .45: return Vector3.ZERO
	return desired
