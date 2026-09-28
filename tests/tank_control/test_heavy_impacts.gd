extends SceneTree
## Exercita colisão nativa, subida, proteção e reparo, além das relações de massa.
const CRUSH := preload("res://gameplay/street_physics/HeavyVehicleCrush.gd")
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
const FLIGHT := preload("res://gameplay/street_physics/BodyFlight3D.gd")

class Street extends "res://gameplay/street_physics/StreetPhysics.gd":
	var shakes := 0
	func _ready() -> void:
		set_physics_process(false)
	func _shake_if_player(_vehicle: Node, _strength: float) -> void:
		shakes += 1

class Car extends "res://scripts/Vehicle.gd":
	var dimensions := Vector3(2.0, 1.4, 4.0)
	func _ready() -> void:
		set_physics_process(false)
		collision_layer = 4
		collision_mask = 7
		floor_snap_length = 0.4
		half_width = dimensions.x * 0.5
		half_length = dimensions.z * 0.5
		body_height = dimensions.y
		shape = CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = dimensions
		shape.shape = box
		shape.position.y = dimensions.y * 0.5
		add_child(shape)
		rotation_shape.size = dimensions - Vector3(0, 0.15, 0)
		visual = Node3D.new()
		add_child(visual)
		add_to_group("drivable")

class Person extends CharacterBody3D:
	var health := 100.0
	var dead := false
	var visual: Node3D
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 7
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.28
		capsule.height = 1.7
		shape.shape = capsule
		shape.position.y = 0.85
		add_child(shape)
		visual = Node3D.new()
		add_child(visual)
	func receive_damage(amount: float, _source: Node = null) -> void:
		health -= amount
		dead = health <= 0

var failures: Array[String] = []
var checks := 0
var world: Node3D
var street: Street

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func car(weight: float, size := Vector3(2.0, 1.4, 4.0), position := Vector3.ZERO) -> Car:
	var result := Car.new()
	result.dimensions = size
	result.handling.mass = weight
	world.add_child(result)
	result.global_position = position
	return result

func solid(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.global_position = position
	return body

func step(vehicle: Car, delta := 1.0 / 60.0) -> void:
	vehicle.velocity.x = vehicle.horizontal_velocity.x
	vehicle.velocity.z = vehicle.horizontal_velocity.z
	vehicle.velocity.y = -1.0 if vehicle.is_on_floor() else vehicle.velocity.y - 20.0 * delta
	street._pre_move(vehicle, delta)
	var incoming := Vector3(vehicle.velocity.x, 0, vehicle.velocity.z)
	vehicle.move_and_slide()
	if vehicle.is_on_wall(): CRUSH.set_planar(vehicle, Vector3(vehicle.velocity.x, 0, vehicle.velocity.z))
	street._post_move(vehicle, incoming, delta)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	street = Street.new()
	world.add_child(street)
	solid(Vector3(80, 0.2, 100), Vector3(0, -0.1, -20))
	await physics_frame
	await test_people_and_props()
	await test_drive_over(30.0, Vector3(3.18, 2.85, 5.3), 12.0, "tanque")
	await test_drive_over(3.0, Vector3(3.44, 2.37, 7.125), 10.0, "caminhão limpa-neves")
	await test_drive_over(1.4, Vector3(2.1, 1.4, 4.8), 25.0, "carro rápido")
	await test_drive_over(30.0, Vector3(3.18, 2.85, 5.3), 12.0, "tanque contra SUV alto", Vector3(2.6568, 2.3976, 5.5404), 1.85)
	await test_legacy_crushed_save()
	test_target_classes()
	await test_boundaries()
	world.queue_free()
	await process_frame
	print("HEAVY_IMPACTS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func test_people_and_props() -> void:
	for profile in [[30.0, 12.0], [3.0, 10.0], [1.0, 25.0]]:
		var vehicle := car(profile[0])
		CRUSH.set_planar(vehicle, Vector3(0, 0, -profile[1]))
		var person := Person.new()
		world.add_child(person)
		person.position = Vector3(0, 0.002, -2.4)
		street._people_cache = [person]
		street.shakes = 0
		await physics_frame
		street._hit_people(vehicle, vehicle.horizontal_velocity, Vector3(0, 0, -0.5))
		check(person.has_meta("street_flying"), "pessoa atingida recebe voo real")
		check(is_equal_approx(vehicle.speed, profile[1]) and street.shakes == 0, "peso/velocidade atravessa pessoa sem perda percentual nem shake")
		person.free()
		street._people_cache.clear()
		var prop := Node3D.new()
		world.add_child(prop)
		prop.position = Vector3(0, 0, -2.3)
		FRAGILE.register_node("lamp", prop, world)
		street._hit_props(vehicle, vehicle.horizontal_velocity, Vector3(0, 0, -0.5))
		check(FRAGILE.query(prop.position, 1.0).is_empty(), "poste realmente derrubado")
		check(is_equal_approx(vehicle.speed, profile[1]) and vehicle.health == vehicle.max_health and street.shakes == 0,
			"peso/velocidade passa poste sem tranco ou dano próprio")
		vehicle.free()
		prop.free()
		FRAGILE.cells.clear()
	var vehicle := car(30.0)
	var protected_parent := Node3D.new()
	protected_parent.set_meta("invulnerable", true)
	world.add_child(protected_parent)
	var protected := Person.new()
	protected_parent.add_child(protected)
	protected.position = Vector3(0, 0.002, -2.4)
	street._people_cache = [protected]
	await physics_frame
	street._hit_people(vehicle, Vector3(0, 0, -12), Vector3(0, 0, -0.5))
	check(not protected.has_meta("street_flying") and protected.collision_layer == 2 and protected.health == 100,
		"Maciota/mecânico protegidos inclusive por ancestral não são arremessados")
	check(FLIGHT.launch(protected, Vector3.FORWARD * 12, true, street, vehicle) == null, "lançamento direto também respeita proteção")
	street._people_cache.clear()
	protected_parent.free()
	vehicle.free()

func test_drive_over(weight: float, size: Vector3, speed: float, label: String, target_size := Vector3(1.9, 1.4, 4.0), target_mass := 0.85) -> void:
	var vehicle := car(weight, size, Vector3(0, 0.002, 0))
	var target := car(target_mass, target_size, Vector3(0, 0.002, -8))
	var original_shape := target.shape.shape
	var destructions: Array[int] = [0]
	target.destroyed.connect(func(): destructions[0] += 1)
	CRUSH.set_planar(vehicle, Vector3.FORWARD * speed)
	var peak := vehicle.position.y
	var biggest_step := 0.0
	var minimum_speed := speed
	for frame in 115:
		await physics_frame
		var previous_y := vehicle.position.y
		step(vehicle)
		step(target)
		peak = maxf(peak, vehicle.position.y)
		biggest_step = maxf(biggest_step, absf(vehicle.position.y - previous_y))
		minimum_speed = minf(minimum_speed, absf(vehicle.speed))
	print("CRUSH_PATH ", label, " z=", vehicle.position.z, " peak=", peak, " max_step=", biggest_step, " min_speed=", minimum_speed, " target_y=", target.position.y)
	check(target.has_meta(CRUSH.RATIO_META) and target.shape.shape is ConvexPolygonShape3D and target.body_height < 0.61, label + ": casco/colisor esmagados")
	check(target.engine_disabled and target.health == 0 and destructions[0] == 1,
		label + ": esmagamento destrói o carro uma única vez")
	check(not target.crush(vehicle) and destructions[0] == 1, label + ": recontato não repete destruição/explosão")
	check(vehicle.position.z < -13.0 and peak > 0.2, label + ": passa por cima fisicamente")
	check(biggest_step < 0.24, label + ": trajetória vertical contínua sem teleporte")
	check(minimum_speed > speed * 0.9 and vehicle.health == vehicle.max_health, label + ": mantém avanço sem autodestruição")
	check(vehicle.get_collision_exceptions().is_empty() and target.collision_layer == 4, label + ": nenhum veículo perde colisão")
	target.repair()
	check(target.shape.shape == original_shape and is_equal_approx(target.body_height, target_size.y)
		and target.visual.scale.is_equal_approx(Vector3.ONE) and not target.engine_disabled and target.health == target.max_health,
		label + ": reparo restaura casco, altura, visual e vida")
	vehicle.free()
	target.free()

func test_legacy_crushed_save() -> void:
	var vehicle := car(30.0, Vector3(3.18, 2.85, 5.3), Vector3(0, 0.002, 0))
	var target := car(0.85, Vector3(1.9, 1.4, 4.0), Vector3(0, 0.002, -7))
	var destructions: Array[int] = [0]
	target.destroyed.connect(func(): destructions[0] += 1)
	CRUSH.apply_saved(target, 0.26)
	target.health = target.max_health * 0.42
	check(target.health > 0 and destructions[0] == 0, "save achatado legado carrega sem explodir")
	for pass_index in 2:
		vehicle.position = Vector3(0, 0.002, 0)
		vehicle.velocity = Vector3.ZERO
		CRUSH.set_planar(vehicle, Vector3.FORWARD * 12)
		for frame in 75:
			await physics_frame
			step(vehicle)
			step(target)
		check(target.health == 0 and destructions[0] == 1,
			"save achatado legado destrói na passagem e mantém recontato quieto: %d" % pass_index)
	vehicle.free()
	target.free()

func test_target_classes() -> void:
	var tank := car(30.0, Vector3(3.18, 2.85, 5.3))
	var catalog: Dictionary = preload("res://runtime/FleetCatalog.gd").all()
	for id in ["cargo_flatbed_truck", "snow_plow_truck", "towmaster", "boxrunner", "route_city", "rescue_pumper", "army_tank"]:
		var spec: Dictionary = catalog[id]
		var bounds: Array = spec.bounds_size
		var target := car(float(spec.mass), Vector3(bounds[0], bounds[1], bounds[2]))
		target.archetype = id
		check(CRUSH.is_large_target(target) and not CRUSH.eligible(tank, target, 13.0), id + ": veículo grande imune a esmagamento")
		target.free()
	for id in ["police_suv", "summit_suv", "polar_van", "atlas_crew_pickup"]:
		var spec: Dictionary = catalog[id]
		var bounds: Array = spec.bounds_size
		var target := car(float(spec.mass), Vector3(bounds[0], bounds[1], bounds[2]))
		target.archetype = id
		check(not CRUSH.is_large_target(target) and CRUSH.eligible(tank, target, 13.0), id + ": veículo comum cede ao tanque")
		target.free()
	var wide := car(2.0, Vector3(3.08, 2.42, 6.1))
	check(CRUSH.eligible(tank, wide, 13.0), "carro comum largo não fica imune por relação de área")
	wide.free()
	tank.free()

func test_boundaries() -> void:
	for scenario in ["lento", "protegido", "alto", "parede", "teto"]:
		var vehicle := car(30.0, Vector3(3.18, 2.85, 5.3), Vector3(0, 0.002, 0))
		var target := car(0.85, Vector3(1.9, 3.0 if scenario == "alto" else 1.4, 4), Vector3(0, 0.002, -5.5))
		var barrier: StaticBody3D
		if scenario == "protegido": target.set_meta("invulnerable", true)
		if scenario == "parede":
			target.position.x = 8
			barrier = solid(Vector3(10, 5, 0.5), Vector3(0, 2.5, -4))
		if scenario == "teto": barrier = solid(Vector3(10, 0.3, 12), Vector3(0, 3.02, -3))
		CRUSH.set_planar(vehicle, Vector3.FORWARD * (1.0 if scenario == "lento" else 10.0))
		for frame in 100:
			await physics_frame
			step(vehicle)
		check(not target.has_meta(CRUSH.RATIO_META), scenario + ": não permite esmagamento indevido")
		check(vehicle.position.z > -3.0, scenario + ": obstáculo continua bloqueando")
		if scenario == "protegido": check(target.health == target.max_health, "veículo invulnerável não sofre dano")
		if is_instance_valid(barrier): barrier.free()
		vehicle.free()
		target.free()
