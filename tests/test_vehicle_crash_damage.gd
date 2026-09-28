extends SceneTree
## A real vehicle collision must dent both cars without draining health every contact frame.

const VEHICLE := preload("res://scripts/Vehicle.gd")
class CollisionStreet extends "res://gameplay/street_physics/StreetPhysics.gd":
	func _ready() -> void:
		instance = self
		set_physics_process(false)

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(16, 0.2, 24)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.1
	floor.add_child(floor_shape)
	world.add_child(floor)
	var street := CollisionStreet.new()
	world.add_child(street)
	street.set_physics_process(false) # The fixture has no player to observe.
	var striking := VEHICLE.new()
	striking.archetype = "sport_coupe"
	world.add_child(striking)
	striking.place(Vector3(0, 0.12, 0), 0)
	var struck := VEHICLE.new()
	struck.archetype = "sport_coupe"
	world.add_child(struck)
	struck.place(Vector3(0, 0.12, -8), 0)
	striking.set_external_driver(true)
	striking.throttle_input = 0.0
	striking.speed = 12.0
	striking.horizontal_velocity = Vector3(0, 0, -12)
	var contact := false
	for frame in 120:
		await physics_frame
		if struck.health < struck.max_health:
			contact = true
			break
	check(contact, "carros colidem e ambos recebem dano")
	if contact:
		check(striking.horizontal_velocity.z <= 0 and struck.horizontal_velocity.z < 0,
			"batida traseira transfere movimento para frente sem ricochete")
		print("CRASH_HEALTH striking=", striking.health, " struck=", struck.health)
		check(striking.health < striking.max_health, "carro que bate também sofre dano")
		check(striking.health > striking.max_health * 0.5 and struck.health > struck.max_health * 0.5,
			"uma batida a 12 m/s não consome metade da vida")
	for frame in 60: await physics_frame
	check(striking.health > 0 and struck.health > 0 and not striking.damage_look.burning and not struck.damage_look.burning,
		"contato após a batida não provoca explosão rápida")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(6, 2, 0.4)
	wall_shape.shape = wall_box
	wall_shape.position = Vector3(0, 1, -6)
	wall.add_child(wall_shape)
	world.add_child(wall)
	striking.repair()
	striking.place(Vector3(0, 0.12, 0), 0)
	struck.place(Vector3(6, 0.12, -8), 0)
	striking.speed = 12.0
	striking.horizontal_velocity = Vector3(0, 0, -12)
	var wall_hit := false
	for frame in 90:
		await physics_frame
		if striking.health < striking.max_health:
			wall_hit = true
			break
	check(wall_hit, "impacto contra parede causa dano")
	if wall_hit:
		print("WALL_HEALTH striking=", striking.health)
		check(striking.health > striking.max_health * 0.5 and not striking.damage_look.burning,
			"batida a 12 m/s contra parede não provoca explosão rápida")
		for frame in 60: await physics_frame
		check(striking.health > striking.max_health * 0.5 and not striking.damage_look.burning,
			"contato com a parede não drena vida quadro a quadro")
	striking.repair()
	striking.place(Vector3(0, 0.12, 0), 0)
	striking.speed = 35.0
	striking.horizontal_velocity = Vector3(0, 0, -35)
	for frame in 60:
		await physics_frame
		if striking.health < striking.max_health: break
	check(striking.health < striking.max_health and striking.health >= striking.max_health * 0.7 and not striking.damage_look.burning,
		"batida forte contra parede não incendeia um carro íntegro")
	wall.queue_free()
	await physics_frame
	striking.repair()
	struck.repair()
	striking.place(Vector3(0, 0.12, 0), 0)
	struck.place(Vector3(0, 0.12, -12), 0)
	striking.speed = 35.0
	striking.horizontal_velocity = Vector3(0, 0, -35)
	for frame in 60:
		await physics_frame
		if struck.health < struck.max_health: break
	check(struck.health < struck.max_health and striking.health >= striking.max_health * 0.7
		and struck.health >= struck.max_health * 0.7 and not striking.damage_look.burning and not struck.damage_look.burning,
		"batida forte entre carros danifica ambos sem incêndio imediato")
	world.queue_free()
	await process_frame
	print("VEHICLE_CRASH_DAMAGE checks=10 failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
