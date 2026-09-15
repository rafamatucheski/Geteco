extends RefCounted
## One officer gives the exit order; the driver keeps control until surrendering.
var phase := "idle"
var elapsed := 0.0
var car: CharacterBody2D
var stop_owner: CharacterBody2D
var approaching_car: CharacterBody2D

func cancel() -> void:
	if is_instance_valid(car) and car.get_meta("police_stop_owner", null) == stop_owner:
		car.remove_meta("police_stop_owner")
	car = null
	stop_owner = null
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
	if not is_instance_valid(car) or wanted.current_stars != 1 or officer.is_dead or officer.is_flying:
		cancel()
		return
	if car.velocity.length() > 12.0 or car.get("is_broken") == true:
		cancel()
		return
	if car.get("is_driven_by_player") != true or officer.target != car:
		cancel()
		return
	elapsed += delta
	if elapsed >= 5.0 and officer._has_target_sight(true):
		give_exit_order(officer)
		elapsed = 0.0

func give_exit_order(officer: CharacterBody2D) -> void:
	var driver = officer.get_tree().get_first_node_in_group("player")
	if driver and driver.has_method("_show_weapon_notice"):
		driver._show_weapon_notice("POLÍCIA: Saia do veículo! Fique parado para se render!" if TranslationServer.get_locale().begins_with("pt") else "POLICE: Step out! Stand still to surrender!")

func approach(officer: CharacterBody2D, vehicle: CharacterBody2D, delta: float) -> void:
	if phase == "command" and car == vehicle:
		officer.velocity = Vector2.ZERO
		return
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
	# Approach the safe side door while leaving the exit action to the driver.
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
	car = vehicle
	stop_owner = officer
	vehicle.set_meta("police_stop_owner", officer)
	phase = "command"
	elapsed = 0.0
	give_exit_order(officer)
