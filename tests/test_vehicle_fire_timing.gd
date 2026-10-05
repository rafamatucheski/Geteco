extends SceneTree
## O incêndio sozinho precisa dar tempo de reagir, desembarcar e fugir,
## inclusive quando a primeira colisão deixa pouquíssima vida no veículo.
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func burn(car: CharacterBody3D, seconds: float) -> void:
	for tick in roundi(seconds * 60):
		car.damage_look._physics_process(1.0 / 60.0)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var car := VEHICLE.new()
	world.add_child(car)
	car.set_physics_process(false)
	var destroyed := [0]
	car.destroyed.connect(func(): destroyed[0] += 1)
	for ratio: float in [.2, .15, .01, .0001]:
		car.repair()
		car.restore_health(car.max_health * ratio)
		car.damage_look.set_physics_process(false)
		var before: int = destroyed[0]
		burn(car, 5.0)
		check(car.health > 0 and destroyed[0] == before, "%.4f: alive after reaction and dismount" % ratio)
		# Repeated refreshes and flame hits must not restart the burning interval.
		car.damage_look.refresh()
		car.damage_look.ignite()
		burn(car, 4.9)
		check(car.health > 0 and destroyed[0] == before, "%.4f: fire leaves almost ten seconds to escape" % ratio)
		burn(car, .15)
		check(car.health <= 0 and destroyed[0] == before + 1, "%.4f: fire still destroys once after ten seconds" % ratio)
		car.damage_look.set_physics_process(false)
	car.repair()
	car.restore_health(car.max_health * .01)
	car.damage_look.set_physics_process(false)
	burn(car, 5.0)
	car.repair()
	check(not car.damage_look.burning and not car.damage_look.is_physics_processing(), "repair cancels burning")
	car.restore_health(car.max_health * .15)
	car.damage_look.set_physics_process(false)
	burn(car, 9.9)
	check(car.health > 0, "a new fire after repair receives the full escape interval")
	car.repair()
	car.damage_resistance = .4
	car.restore_health(car.max_health * .01)
	car.damage_look.set_physics_process(false)
	burn(car, 10.0)
	check(car.health > 0, "armor continues to resist burn damage")
	car.repair()
	car.damage_resistance = 1.0
	car.damage_look.ignite()
	car.damage_look.set_physics_process(false)
	burn(car, 10.0)
	check(car.health > 0 and car.damage_look.burning, "flames on a healthy engine do not shorten its existing durability")
	car.repair()
	car.restore_health(car.max_health * .01)
	car.damage_look.set_physics_process(false)
	car.receive_damage(car.max_health)
	check(car.health <= 0, "additional lethal impacts remain lethal during a fire")
	world.free()
	await process_frame
	print("VEHICLE_FIRE_TIMING checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
