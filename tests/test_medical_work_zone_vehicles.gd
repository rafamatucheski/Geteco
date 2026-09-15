extends SceneTree
const ZONE := preload("res://world/shared/emergency/MedicalRescueWorkZone.gd")
const FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
var failures: Array[String] = []
var world: Node2D
var source: Rescue
var zone: StaticBody2D

class Rescue extends Node:
	var ambulance: Node2D
	var patient: CharacterBody2D
	var crew: Array = []
	var phase := "treat"
	var stretcher: CharacterBody2D
	var carrying := false
	var delivered := false
	var hospital_delivery := false
	func rear_point() -> Vector2: return ambulance.global_position + Vector2(-78, 0)

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func _place(point: Vector2) -> void:
	source.phase = "treat"
	source.patient.position = point
	source.stretcher.position = point + Vector2(0, 18)
	for i in 2:
		source.crew[i].position = point + Vector2(-20 + i * 40, 30)
		source.crew[i].show()
		source.crew[i].collision_layer = 4
	zone.sync(source)

func _board_team() -> void:
	source.phase = "transport"
	for medic in source.crew:
		medic.hide()
		medic.collision_layer = 0
	zone.sync(source)

func run() -> void:
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	source = Rescue.new()
	world.add_child(source)
	source.ambulance = CharacterBody2D.new()
	world.add_child(source.ambulance)
	source.ambulance.position = Vector2(-500, -500)
	source.patient = CharacterBody2D.new()
	world.add_child(source.patient)
	source.stretcher = preload("res://world/shared/emergency/MedicalStretcher.gd").new()
	world.add_child(source.stretcher)
	source.stretcher.set_physics_process(false)
	for i in 2:
		var medic := load("res://Paramedic.tscn").instantiate() as CharacterBody2D
		world.add_child(medic)
		medic.set_physics_process(false)
		source.crew.append(medic)
	zone = ZONE.new()
	world.add_child(zone)
	_place(Vector2(350, 0))
	await physics_frame
	await physics_frame
	var initial_health: int = source.crew[0].health
	var hitter := CharacterBody2D.new()
	world.add_child(hitter)
	check(not preload("res://world/shared/combat/VehiclePersonImpact.gd").hit(hitter, source.crew[0], Vector2(900, 0)) and source.crew[0].health == initial_health, "Direct bumper impacts cannot injure protected working medics")
	hitter.queue_free()
	for archetype in ["route_city", "bike_urban", "local_bus"]:
		await _lane_case(archetype)
	await _coach_case(false)
	await _coach_case(true)
	for bike in [false, true]: await _player_case(bike)
	# An abort leaves the surviving crew walking back: their clearance persists.
	_place(Vector2(350, 0))
	zone.detach_sequence()
	check(zone.active and source.crew[0].get_meta("medical_vehicle_protected", false), "Abort preserves protection for crew returning on foot")
	for medic in source.crew: medic.hide()
	await physics_frame
	await physics_frame
	check(not is_instance_valid(zone), "Last medic boarding clears detached protection")
	print("MEDICAL_WORK_ZONE_VEHICLES failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _lane_case(archetype: String) -> void:
	_place(Vector2(350, 0))
	var lane := FACTORY.create_lane(world, "MedicalApproach", PackedVector2Array([Vector2.ZERO, Vector2(1000, 0)]))
	var vehicle: CharacterBody2D
	if archetype == "local_bus":
		var follow := PathFollow2D.new()
		follow.loop = false
		lane.add_child(follow)
		vehicle = load("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
		vehicle.set_script(preload("res://world/harbor/HarborTransitBus.gd"))
		vehicle.speed = 180
		follow.add_child(vehicle)
		vehicle.dwelling = false
		vehicle.speed = 180
	else: vehicle = FACTORY.spawn_moving_vehicle(lane, "Approaching", archetype, 0, 180, 0)
	vehicle.set_process(false)
	vehicle.set_physics_process(false)
	var clear := true
	var slowed := false
	for frame in 450:
		vehicle.advance_on_lane(1.0 / 60.0)
		clear = clear and not ZONE.blocks_hull(vehicle, vehicle.collision.shape, vehicle.collision.global_transform)
		if vehicle.global_position.x > 40 and vehicle._lane_motion_speed < 120: slowed = true
		await physics_frame
	var stopped := vehicle.global_position
	check(clear and slowed and vehicle._lane_motion_speed < 1.0 and stopped.x > 100, archetype + " brakes with its entire hull outside the rescue")
	_board_team()
	for frame in 180:
		vehicle.advance_on_lane(1.0 / 60.0)
		await physics_frame
	check(vehicle.global_position.x > stopped.x + 90, archetype + " resumes when the team boards")
	lane.queue_free()
	await physics_frame
	await physics_frame

func _coach_case(curved: bool) -> void:
	var service := preload("res://world/harbor/terminal/HarborTerminalCoachService.gd").new()
	service.operations = world
	world.add_child(service)
	service.set_physics_process(false)
	for person in service.passenger_service.people: person.set_physics_process(false)
	service.state = "road"
	var route := Curve2D.new()
	route.add_point(Vector2.ZERO)
	if curved:
		route.add_point(Vector2(180, 0))
		service._arc(route, Vector2(180, 100), 100, -PI / 2, 0)
		route.add_point(Vector2(280, 800))
		_place(Vector2(305, 220))
	else:
		route.add_point(Vector2(1000, 0))
		_place(Vector2(350, 0))
	service._set_route(route)
	service.coach.position = Vector2.ZERO
	service.heading = Vector2.RIGHT
	service.coach_shape.shape = service._shape_for_heading(Vector2.RIGHT)
	service.current_speed = 180.0
	var clear := true
	for frame in 600:
		service._advance(1.0 / 60.0)
		clear = clear and not ZONE.blocks_hull(service.coach, service.coach_shape.shape, service.coach.global_transform)
		await physics_frame
	var stopped := service.route_progress
	check(clear and service.current_speed < 1 and stopped > 60, "Terminal coach high-speed " + ("curve" if curved else "approach") + " preserves crew/cot clearance")
	_board_team()
	for frame in 180:
		service._advance(1.0 / 60.0)
		await physics_frame
	check(service.route_progress > stopped + 60, "Terminal coach resumes " + ("around the curve" if curved else "on the street"))
	service.queue_free()
	await physics_frame
	await physics_frame

func _player_case(bike: bool) -> void:
	_place(Vector2(450, 0))
	var car: CharacterBody2D
	if bike: car = FACTORY.spawn_parked_vehicle(world, "PlayerMotorcycle", Vector2.ZERO, 0, "bike_urban", 0)
	else:
		car = load("res://world/shared/traffic/SavedPlayerCar.tscn").instantiate()
		world.add_child(car)
	car.set_process(false)
	car.set_physics_process(false)
	var collision := car.get_node("Collision") as CollisionShape2D
	car.position = Vector2(450, 57 + collision.shape.get_rect().size.y * 0.5 + 8)
	preload("res://VehicleMotionSafety.gd").configure(car)
	var before_turn := car.position
	car.rotation = PI / 2
	car.velocity = Vector2.ZERO
	preload("res://VehicleMotionSafety.gd").move(car)
	check(not ZONE.blocks_hull(car, collision.shape, collision.global_transform) and car.position.distance_to(before_turn) < .001, "Stationary steering cannot swing a vehicle's side into the medical team")
	car.position = Vector2.ZERO
	car.rotation = 0
	preload("res://VehicleMotionSafety.gd").configure(car)
	var clear := true
	for frame in 180:
		car.velocity = Vector2(900, 0)
		preload("res://VehicleMotionSafety.gd").move(car)
		clear = clear and not ZONE.blocks_hull(car, collision.shape, collision.global_transform)
		await physics_frame
	var stopped := car.position
	check(clear and stopped.x > 100 and stopped.x < 420 and car.velocity.length() < 1, "Player " + ("motorcycle" if bike else "car") + " cannot force through the crew at 900px/s")
	# Activation around an already stopped car must not invoke solver recovery.
	_place(car.position)
	car.velocity = Vector2(900, 0)
	preload("res://VehicleMotionSafety.gd").move(car)
	check(car.position.distance_to(stopped) < .001, "New work clearance never shoves an overlapping vehicle")
	_board_team()
	for frame in 30:
		car.velocity = Vector2(100, 0)
		preload("res://VehicleMotionSafety.gd").move(car)
		await physics_frame
	check(car.position.x > stopped.x + 20, "Player vehicle resumes after medical work ends")
	car.queue_free()
	await physics_frame
	await physics_frame
