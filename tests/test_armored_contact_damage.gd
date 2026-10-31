extends "res://tests/test_armored_guard_service_path.gd"
const TRUCK := preload("res://gameplay/armored/ArmoredTruck.gd")
const VEHICLE := preload("res://gameplay/dispatch/DispatchVehicle.gd")
const CRUSH := preload("res://gameplay/street_physics/HeavyVehicleCrush.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
func run() -> void:
	var world := World.new()
	root.add_child(world)
	current_scene = world
	var truck := TRUCK.new()
	world.add_child(truck)
	truck.set_physics_process(false)
	var car := VEHICLE.new()
	car.archetype = "sedan_classic"
	car.position = Vector3(0,0,-6)
	world.add_child(car)
	car.set_physics_process(false)
	var tank := VEHICLE.new()
	tank.archetype = "army_tank"
	tank.position = Vector3(20,0,0)
	world.add_child(tank)
	tank.set_physics_process(false)
	for frame in 3: await physics_frame
	for speed in [2.5,4.0,10.0,24.0]:
		check(not CRUSH.eligible(truck,car,speed),"cash carrier cannot instantly crush a healthy car at %s m/s" % speed)
	check(CRUSH.eligible(tank,car,4.0),"tank retains its separate physical overrun mechanic")
	var street := STREET.new()
	# A resposta normal a impacto continua viva; blindagem não é invulnerabilidade.
	var health_before := car.health
	street._crash(truck,car,Vector3.BACK,4.0,Vector3(0,1,-3),Vector3.FORWARD*4.0)
	check(car.health < health_before and car.health > health_before*.8,"low-speed collision damages without exploding the car")
	check(truck.health < truck.max_health and truck.health > 0,"armored truck still receives ordinary collision damage")
	check(not car.has_meta("heavy_crush_ratio") and not car.damage_look.wrecked,"minor impact creates no flattened wreck")
	street.free()
	world.free()
	print("ARMORED_CONTACT_DAMAGE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
