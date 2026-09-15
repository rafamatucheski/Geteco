extends RefCounted
## Shared by cars, motorcycles and lane traffic. People never use metal crashes.
const MIN_SPEED := 60.0

static func is_person(body: Object) -> bool:
	return is_instance_valid(body) and body is Node2D and body.has_method("get_run_over") and not body.is_in_group("vehicle") and not body.is_in_group("ambient_traffic")

static func hit(vehicle: CharacterBody2D, actor: Node2D, incoming: Vector2) -> bool:
	if not is_person(actor) or not incoming.is_finite(): return false
	if actor.get_meta("medical_vehicle_protected", false): return false
	var driven: bool = vehicle.get("is_driven_by_player") == true
	if driven and actor.is_in_group("player"): return false
	if actor.get("is_dead") == true or actor.get("is_incapacitated") == true or actor.get("is_recovering") == true: return false
	var minimum := 35.0 if vehicle.get("active_archetype_id") == "port_forklift" else MIN_SPEED
	if incoming.length() < minimum: return false
	if incoming.dot(actor.global_position - vehicle.global_position) < -1.0: return false
	var now := Time.get_ticks_msec()
	if now - int(actor.get_meta("last_vehicle_injury_ms", -10000)) < 600: return false
	var old_health = actor.get("health")
	actor.get_run_over(incoming, driven)
	var injured: bool = actor.get("is_dead") == true or actor.get("is_incapacitated") == true or actor.get("is_recovering") == true or actor.get("is_flying") == true
	if old_health != null and actor.get("health") != null:
		injured = injured or actor.get("health") < old_health
	if not injured: return false
	actor.set_meta("last_vehicle_injury_ms", now)
	if now - int(actor.get_meta("vehicle_feedback_ms", -10000)) > 100:
		# Other actors keep their existing voice/impact audio.
		feedback(actor, incoming, actor.get("is_dead") == true)
	if vehicle.has_method("_activate_bloody_tires"): vehicle._activate_bloody_tires()
	return true

static func feedback(actor: Node2D, incoming: Vector2, lethal: bool, sound := true) -> void:
	actor.set_meta("vehicle_feedback_ms", Time.get_ticks_msec())
	var effects := actor.get_tree().get_first_node_in_group("weapon_effects")
	if effects == null:
		effects = preload("res://guns/combat/WeaponEffects.gd").new()
		actor.get_parent().add_child(effects)
	effects.spawn_vehicle_splash(actor.global_position, incoming, lethal)
	if not lethal: preload("res://guns/combat/GroundBlood.gd").spawn(actor, false)
	if not sound: return
	var audio := AudioStreamPlayer2D.new()
	audio.name = "VehicleBodyImpact"
	audio.stream = preload("res://audio/VehicleBodyAudio.gd").sound()
	audio.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	audio.volume_db = lerpf(-8.0, -1.5, clampf((incoming.length() - MIN_SPEED) / 280.0, 0.0, 1.0))
	audio.pitch_scale = randf_range(0.94, 1.04)
	audio.max_distance = 700.0
	actor.get_parent().add_child(audio)
	audio.global_position = actor.global_position
	audio.finished.connect(audio.queue_free)
	audio.play()

static func prepare_motion(vehicle: CharacterBody2D, incoming: Vector2, motion := Vector2.INF) -> Array[PhysicsBody2D]:
	var bypass: Array[PhysicsBody2D] = []
	if incoming.length() < MIN_SPEED: return bypass
	if not motion.is_finite(): motion = incoming * vehicle.get_physics_process_delta_time()
	# Sweep the actual vehicle shape before the physics solver removes its speed.
	# Repeat only after yielding a person so an obstacle behind them still stops us.
	for attempt in 8:
		var contact := KinematicCollision2D.new()
		if not vehicle.test_move(vehicle.global_transform, motion, contact): break
		var actor := contact.get_collider() as Node2D
		if not is_person(actor) or not actor is PhysicsBody2D or bypass.has(actor): break
		if actor.get_meta("medical_vehicle_protected", false): break
		if vehicle.get("is_driven_by_player") == true and actor.is_in_group("player"): break
		var down: bool = actor.get("is_dead") == true or actor.get("is_incapacitated") == true or actor.get("is_recovering") == true
		# An already fallen body must not become a wall while its collider is
		# waiting for a deferred disable. Damage and physical yielding differ.
		if not down and not hit(vehicle, actor, incoming): break
		vehicle.add_collision_exception_with(actor)
		bypass.append(actor)
	return bypass

static func move_falling_body(actor: Node2D, incoming: Vector2, delta: float) -> Vector2:
	var destination := actor.global_position + incoming * delta
	if incoming.length_squared() > 1.0:
		var ray := PhysicsRayQueryParameters2D.create(actor.global_position, destination + incoming.normalized() * 4.0, 1)
		if actor is CollisionObject2D: ray.exclude = [actor.get_rid()]
		var obstruction := actor.get_world_2d().direct_space_state.intersect_ray(ray)
		if not obstruction.is_empty():
			actor.global_position = obstruction.position - incoming.normalized() * 4.0
			return Vector2.ZERO
	actor.global_position = destination
	return incoming.move_toward(Vector2.ZERO, 950.0 * delta)
