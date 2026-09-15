extends RefCounted
## Top-down cars never inherit moving-platform velocity from PathFollow bodies.
const WORLD_LIMIT := 200000.0
const SPEED_LIMIT := 900.0

## Cosmetic scrapes start before structural damage. The normal closing speed
## excludes tangential motion along a wall; repeated contacts are gated by callers.
static func collision_damage(closing_speed: float) -> int:
	if not is_finite(closing_speed) or closing_speed <= 180.0: return 0
	return clampi(roundi((closing_speed - 180.0) * 0.045), 1, 32)

static func configure(body: CharacterBody2D) -> void:
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	body.platform_floor_layers = 0
	body.platform_wall_layers = 0
	body.platform_on_leave = CharacterBody2D.PLATFORM_ON_LEAVE_DO_NOTHING
	if valid_position(body.global_position):
		body.set_meta("vehicle_safe_position", body.global_position)
		body.set_meta("vehicle_safe_transform", body.global_transform)

static func valid_position(point: Vector2) -> bool:
	return point.is_finite() and absf(point.x) < WORLD_LIMIT and absf(point.y) < WORLD_LIMIT

static func rotate_clear(body: CharacterBody2D, target_rotation: float) -> void:
	# move_and_slide sweeps translation, not the corners rotated beforehand.
	# Reject a turn into another hull before penetration recovery can shove it.
	var hull := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if hull == null: hull = body.get_node_or_null("Collision") as CollisionShape2D
	if not body.is_inside_tree() or hull == null:
		body.rotation = target_rotation
		return
	if hull.disabled or hull.shape == null: return
	var turn := angle_difference(body.rotation, target_rotation)
	if absf(turn) < 0.0001: return
	var steps := maxi(1, ceili(absf(turn) / 0.06))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = hull.shape
	query.collision_mask = body.collision_mask
	var excluded: Array[RID] = [body.get_rid()]
	for other in body.get_collision_exceptions():
		if is_instance_valid(other): excluded.append(other.get_rid())
	query.exclude = excluded
	query.margin = 0.1
	var original := body.rotation
	for step in range(1, steps + 1):
		var candidate := original + turn * float(step) / steps
		var local := Transform2D(candidate, body.scale, body.skew, body.position)
		var parent := body.get_parent() as Node2D
		query.transform = (parent.global_transform * local if parent else local) * hull.transform
		if not body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): return
		body.rotation = candidate

static func sanitize(body: CharacterBody2D) -> void:
	if not valid_position(body.global_position):
		body.global_position = body.get_meta("vehicle_safe_position", Vector2.ZERO)
		body.velocity = Vector2.ZERO
		# Recolocacao e teleporte: sem descartar o transform anterior a interpolacao
		# de fisica desenharia o carro deslizando da posicao invalida ate a segura.
		body.reset_physics_interpolation()
		body.set_meta("motion_recoveries", int(body.get_meta("motion_recoveries",0))+1)
	if not is_finite(body.rotation): body.rotation = 0.0
	if not body.velocity.is_finite(): body.velocity = Vector2.ZERO
	body.velocity = body.velocity.limit_length(SPEED_LIMIT)

static func move(body: CharacterBody2D) -> void:
	sanitize(body)
	preload("res://world/shared/emergency/MedicalRescueWorkZone.gd").limit_player_motion(body)
	var before := body.global_position
	var incoming := body.velocity
	# A parked kinematic car must not run penetration recovery against walking
	# bodies. Pedestrians still collide with its layer; it is not their platform.
	if incoming.is_zero_approx():
		body.set_meta("vehicle_safe_position", before)
		body.set_meta("vehicle_safe_transform", body.global_transform)
		return
	var maximum_step := SPEED_LIMIT * body.get_physics_process_delta_time() + 16.0
	var people := preload("res://guns/combat/VehiclePersonImpact.gd").prepare_motion(body, incoming)
	body.move_and_slide()
	# Sliding against a moving car can inject that collider's velocity even in
	# floating mode. Keep only this vehicle's own motion for subsequent frames.
	body.velocity = incoming
	for person in people:
		if is_instance_valid(person): body.remove_collision_exception_with(person)
	# A moving kinematic neighbour can leave residual inward velocity after
	# recovery. Consume it once instead of replaying crash/hit-stop every frame.
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		var obstacle := hit.get_collider()
		if is_instance_valid(obstacle) and obstacle.has_method("receive_vehicle_contact"):
			obstacle.receive_vehicle_contact(maxf(0.0,-incoming.dot(hit.get_normal())),incoming.normalized(),body)
		elif is_instance_valid(obstacle) and obstacle.has_method("receive_vehicle_impact"):
			obstacle.receive_vehicle_impact(maxf(0.0,-incoming.dot(hit.get_normal())),incoming.normalized())
		# Yielding poles do not consume the remaining forward velocity.
		if is_instance_valid(obstacle) and obstacle.is_in_group("fragile_road_post") and obstacle.get("broken") == true:
			continue
		var normal := body.get_slide_collision(i).get_normal()
		if normal.is_finite() and not normal.is_zero_approx():
			body.velocity -= normal * minf(0.0,body.velocity.dot(normal))
	if not valid_position(body.global_position) or body.global_position.distance_to(before) > maximum_step:
		body.global_position = before
		body.velocity = Vector2.ZERO
		body.reset_physics_interpolation()
		body.set_meta("motion_recoveries", int(body.get_meta("motion_recoveries",0))+1)
	sanitize(body)
	body.set_meta("vehicle_safe_position", body.global_position)
	body.set_meta("vehicle_safe_transform", body.global_transform)

## Catalog mass is relative to a compact car. Fractional exponents retain the
## engine/brake tuning while making added weight noticeable under player input.
static func drive_mass_scale(mass: float) -> float:
	return pow(clampf(mass, 0.5, 8.0), -0.42)

static func brake_mass_scale(mass: float) -> float:
	return pow(clampf(mass, 0.5, 8.0), -0.30)

static func coast_mass_scale(mass: float) -> float:
	return pow(clampf(mass, 0.5, 8.0), -0.65)

static func steering_rate(previous: float, input: float, speed: float, turn: float, mass: float, delta: float) -> float:
	var weight := clampf(mass, 0.5, 8.0)
	# Speed-dependent radius and yaw inertia: trucks cannot snap into a turn.
	var response := 11.0 / pow(weight, 0.65)
	var high_speed := 1.0 / (1.0 + pow(absf(speed) / 320.0, 2.0) * pow(weight, 0.4))
	var target := input * turn * clampf(speed / 150.0, -1.0, 1.0) * high_speed
	if absf(speed) < 2.0: return 0.0
	return lerpf(previous, target, 1.0 - exp(-response * maxf(delta, 0.0)))

static func grip(velocity: Vector2, heading: float, drift: float, delta: float, wetness: float = 0.0, handbrake: bool = false, mass: float = 1.0) -> Vector2:
	if not velocity.is_finite(): return Vector2.ZERO
	var forward := Vector2.from_angle(heading)
	var lateral := forward.orthogonal()
	# Larger drift values lower grip, but can never create negative damping.
	var damping := lerpf(12.0,4.0,clampf((drift-0.7)/0.5,0.0,1.0))
	damping /= pow(clampf(mass, 0.5, 8.0), 0.35)
	damping *= lerpf(1.0,0.65,clampf(wetness,0.0,1.0))
	if handbrake: damping *= 0.22
	return forward*velocity.dot(forward)+lateral*velocity.dot(lateral)*exp(-damping*maxf(0.0,delta))
