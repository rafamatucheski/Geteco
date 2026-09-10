extends RefCounted
## One officer owns a stop. Uses the actual player/car, never substitute models.
var phase := "idle"
var elapsed := 0.0
var car: CharacterBody2D
var actor: CharacterBody2D
var exit_point := Vector2.ZERO
var seat_point := Vector2.ZERO
var control_before := false
var poses: Dictionary = {}
var approaching_car: CharacterBody2D

func cancel() -> void:
	if is_instance_valid(car): car.remove_meta("police_stop_owner")
	if is_instance_valid(actor) and phase in ["extract", "cuff"]:
		actor.is_control_disabled = control_before
		actor.set_physics_process(true)
		if is_instance_valid(car): actor.remove_collision_exception_with(car)
		for limb in poses:
			if is_instance_valid(limb): limb.rotation = poses[limb]
	poses.clear()
	car = null
	actor = null
	phase = "idle"
	elapsed = 0.0
	approaching_car = null

func corridor_clear(officer: CharacterBody2D, vehicle: CharacterBody2D, point: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(officer.global_position, point, 1 | 2)
	query.exclude = [officer.get_rid()]
	if not officer.get_world_2d().direct_space_state.intersect_ray(query).is_empty(): return false
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	var space := PhysicsShapeQueryParameters2D.new()
	space.shape = shape
	space.transform = Transform2D(0, point)
	space.collision_mask = 1 | 2
	space.exclude = [officer.get_rid(), vehicle.get_rid()]
	return officer.get_world_2d().direct_space_state.intersect_shape(space).is_empty()

func tick(officer: CharacterBody2D, delta: float) -> void:
	var wanted = officer.get_node("/root/WantedManager")
	if phase in ["extract", "cuff"] and (not is_instance_valid(actor) or actor.get("is_dead") == true):
		cancel()
		return
	if not is_instance_valid(car) or wanted.current_stars == 0 or officer.is_dead or officer.is_flying:
		cancel()
		return
	if car.velocity.length() > 12.0 or car.get("is_broken") == true:
		cancel()
		return
	if phase == "open" and car.get("is_driven_by_player") != true:
		cancel()
		return
	officer.velocity = Vector2.ZERO
	elapsed += delta
	if phase == "open" and elapsed >= 0.65:
		if not corridor_clear(officer, car, exit_point):
			cancel()
			return
		actor = officer.get_tree().get_first_node_in_group("player")
		if not is_instance_valid(actor) or actor.is_dead:
			cancel()
			return
		control_before = actor.is_control_disabled
		car.exit_vehicle()
		car._animate_car_door(-1.0 if car.to_local(exit_point).y < 0 else 1.0, 1.2)
		actor.is_control_disabled = true
		actor.set_physics_process(false)
		actor.add_collision_exception_with(car)
		seat_point = car.global_position.lerp(exit_point, 0.35)
		actor.global_position = seat_point
		actor.show()
		phase = "extract"
		elapsed = 0.0
	elif phase == "extract":
		actor.global_position = seat_point.lerp(exit_point, smoothstep(0.0, 0.85, elapsed))
		if elapsed >= 0.85:
			phase = "cuff"
			elapsed = 0.0
			for name in ["left_upper_arm", "right_upper_arm"]:
				var limb = actor.get(name)
				if is_instance_valid(limb):
					poses[limb] = limb.rotation
					limb.rotation.x = -0.65
	elif phase == "cuff" and elapsed >= 1.0:
		var suspect := actor
		cancel()
		suspect.arrest_and_respawn()

func approach(officer: CharacterBody2D, vehicle: CharacterBody2D, delta: float) -> void:
	if approaching_car != vehicle:
		elapsed = 0.0
		approaching_car = vehicle
	if vehicle.get("is_driven_by_player") != true or not vehicle.has_method("exit_vehicle"):
		officer.velocity = Vector2.ZERO
		return
	if vehicle.velocity.length() > 12.0 or vehicle.get_meta("vehicle_boarding", false):
		elapsed = 0.0
		officer.velocity = Vector2.ZERO
		return
	var owner = vehicle.get_meta("police_stop_owner") if vehicle.has_meta("police_stop_owner") else null
	if is_instance_valid(owner) and owner != officer:
		officer.velocity = Vector2.ZERO
		return
	# Restrict extraction to the actual safe side door, never front/rear fallback.
	var point: Vector2 = vehicle._get_safe_exit_position()
	var local_point := vehicle.to_local(point)
	if absf(local_point.y) < 25.0:
		elapsed = 0.0
		officer.velocity = Vector2.ZERO
		return
	if officer.global_position.distance_to(point) > 17.0:
		officer.velocity = officer._navigate_towards(point, officer.speed * 0.75, delta)
		elapsed = 0.0
		return
	officer.velocity = Vector2.ZERO
	if not corridor_clear(officer, vehicle, point):
		elapsed = 0.0
		return
	if elapsed == 0.0:
		var driver = officer.get_tree().get_first_node_in_group("player")
		if driver and driver.has_method("_show_weapon_notice"):
			driver._show_weapon_notice("POLÍCIA: Desligue o motor! Saia do veículo!" if TranslationServer.get_locale().begins_with("pt") else "POLICE: Engine off! Step out of the vehicle!")
	elapsed += delta
	if elapsed >= 1.5:
		car = vehicle
		exit_point = point
		vehicle.set_meta("police_stop_owner", officer)
		if vehicle.has_method("_animate_car_door"):
			vehicle._animate_car_door(-1.0 if local_point.y < 0 else 1.0, 1.2)
		phase = "open"
		elapsed = 0.0
