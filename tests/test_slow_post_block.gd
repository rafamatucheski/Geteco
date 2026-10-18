extends "res://tests/tank_control/test_heavy_impacts.gd"
## Poste sem colisor nativo (mobília do CityLook) segura o carro devagar em vez de ser atravessado.

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	street = Street.new()
	world.add_child(street)
	for speed in [0.4, 2.0, 4.0]:
		var pole := Node3D.new()
		world.add_child(pole)
		pole.position = Vector3(0, 0, -2.3)
		FRAGILE.register_node("lamp", pole, world)
		var vehicle := car(1.0)
		vehicle.velocity = Vector3.FORWARD * speed
		vehicle.horizontal_velocity = vehicle.velocity
		vehicle.speed = speed
		street._hit_props(vehicle, vehicle.velocity, vehicle.velocity * 0.5)
		var item: Dictionary = FRAGILE.query(pole.position, 1)[0]
		check(item.state == "standing", "slow car leaves lamp standing at %.1f m/s" % speed)
		check(vehicle.velocity.length() < 0.01, "lamp stops a %.1f m/s car" % speed)
		check(absf(vehicle.speed) < 0.01, "lamp clears drive speed at %.1f m/s" % speed)
		vehicle.velocity = Vector3.RIGHT * speed
		street._hit_props(vehicle, vehicle.velocity, vehicle.velocity * 0.5)
		check(vehicle.velocity.length() > speed * 0.9, "car slides past lamp sideways at %.1f m/s" % speed)
		vehicle.free()
		pole.free()
		FRAGILE.cells.clear()
	print("SLOW_POST_BLOCK checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
