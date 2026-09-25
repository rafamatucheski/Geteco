extends SceneTree
## Três acidentes não devem incendiar um carro íntegro; colisões ainda causam dano.

const VEHICLE := preload("res://scripts/Vehicle.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func reset_pose(car: CharacterBody3D, point: Vector3) -> void:
	car.place(point, 0)
	for key in ["crash_slide", "crash_spin", "crash_stun"]:
		car.remove_meta(key)
	car.set_physics_process(false)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40, 0.2, 80)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.1
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var street := STREET.new()
	world.add_child(street)
	street.set_physics_process(false)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(8, 3, 0.4)
	wall_shape.shape = wall_box
	wall_shape.position = Vector3(0, 1.5, -8)
	wall.add_child(wall_shape)
	world.add_child(wall)
	for archetype in ["sport_coupe", "sedan_classic"]:
		var car := VEHICLE.new()
		car.archetype = archetype
		car.position = Vector3(0, 0.12, 0)
		world.add_child(car)
		car.set_external_driver(true)
		var other := VEHICLE.new()
		other.archetype = archetype
		other.position = Vector3(12, 0.12, -8)
		world.add_child(other)
		for against_car in [false, true]:
			wall.collision_layer = 0 if against_car else 1
			for impact_speed in [12.0, 35.0]:
				car.repair()
				other.repair()
				var label := "%s %s %.0f m/s" % [archetype, "carro" if against_car else "parede", impact_speed]
				for accident in 3:
					reset_pose(car, Vector3(0, 0.12, 0))
					reset_pose(other, Vector3(0 if against_car else 12, 0.12, -8))
					await physics_frame
					car.set_physics_process(true)
					other.set_physics_process(true)
					car.throttle_input = 0
					car.brake_input = false
					car.speed = impact_speed
					car.horizontal_velocity = Vector3(0, 0, -impact_speed)
					var before: float = car.health
					var other_before: float = other.health
					for frame in 100:
						await physics_frame
						if car.health < before: break
					check(car.health < before, "%s: acidente %d causa dano" % [label, accident + 1])
					if against_car:
						check(other.health < other_before, "%s: atingido também sofre dano" % label)
					# Frear após acertar o outro carro evita uma segunda aproximação real.
					# Contra parede, manter o impulso residual verifica a cobrança duplicada.
					car.brake_input = against_car
					var after: float = car.health
					await create_timer(0.6, true, true).timeout
					check(is_equal_approx(car.health, after), "%s: sem dano repetido no contato" % label)
					car.set_physics_process(false)
					other.set_physics_process(false)
				check(car.health >= car.max_health * 0.6 and not car.damage_look.burning,
					"%s: três acidentes preservam pelo menos 60%% e não incendeiam" % label)
				if against_car:
					check(other.health >= other.max_health * 0.6 and not other.damage_look.burning,
						"%s: atingido também resiste a três acidentes" % label)
				print("ACCIDENT_TOLERANCE ", label, " health=", car.health, "/", car.max_health, " other=", other.health)
		car.queue_free()
		other.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	print("VEHICLE_ACCIDENT_TOLERANCE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
