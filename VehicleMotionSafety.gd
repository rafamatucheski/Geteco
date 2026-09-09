extends RefCounted
## Top-down cars never inherit moving-platform velocity from PathFollow bodies.
const WORLD_LIMIT := 200000.0
const SPEED_LIMIT := 900.0

static func configure(body: CharacterBody2D) -> void:
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	body.platform_floor_layers = 0
	body.platform_wall_layers = 0
	body.platform_on_leave = CharacterBody2D.PLATFORM_ON_LEAVE_DO_NOTHING
	if valid_position(body.global_position):
		body.set_meta("vehicle_safe_position", body.global_position)

static func valid_position(point: Vector2) -> bool:
	return point.is_finite() and absf(point.x) < WORLD_LIMIT and absf(point.y) < WORLD_LIMIT

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
	var before := body.global_position
	var incoming := body.velocity
	# A parked kinematic car must not run penetration recovery against walking
	# bodies. Pedestrians still collide with its layer; it is not their platform.
	if incoming.is_zero_approx():
		body.set_meta("vehicle_safe_position", before)
		return
	var maximum_step := SPEED_LIMIT * body.get_physics_process_delta_time() + 16.0
	body.move_and_slide()
	# A moving kinematic neighbour can leave residual inward velocity after
	# recovery. Consume it once instead of replaying crash/hit-stop every frame.
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		var obstacle := hit.get_collider()
		if is_instance_valid(obstacle) and obstacle.has_method("receive_vehicle_impact"):
			obstacle.receive_vehicle_impact(maxf(0.0,-incoming.dot(hit.get_normal())),incoming.normalized())
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

static func grip(velocity: Vector2, heading: float, drift: float, delta: float, wetness: float = 0.0, handbrake: bool = false) -> Vector2:
	if not velocity.is_finite(): return Vector2.ZERO
	var forward := Vector2.from_angle(heading)
	var lateral := forward.orthogonal()
	# Larger drift values lower grip, but can never create negative damping.
	var damping := lerpf(12.0,4.0,clampf((drift-0.7)/0.5,0.0,1.0))
	damping *= lerpf(1.0,0.65,clampf(wetness,0.0,1.0))
	if handbrake: damping *= 0.22
	return forward*velocity.dot(forward)+lateral*velocity.dot(lateral)*exp(-damping*maxf(0.0,delta))
