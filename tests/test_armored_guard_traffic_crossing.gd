extends "res://tests/test_armored_guard_service_path.gd"
## Controlador de trânsito real do Vehicle e locomoção/colisões reais do guarda.
## Duas mãos de trânsito cruzam o caminho de serviço do carregador de dinheiro.

func run() -> void:
	for direction in [1.0, -1.0]:
		var world := World.new()
		root.add_child(world)
		current_scene = world
		var floor_body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(140, .2, 40)
		collision.shape = box
		floor_body.add_child(collision)
		floor_body.position.y = -.1
		world.add_child(floor_body)
		world.player = Node3D.new()
		world.add_child(world.player)
		world.player.position = Vector3(0, 0, 15)
		world.gameplay.player = world.player
		var convoy := Convoy.new()
		convoy.session = {"world":world, "state":State.new()}
		convoy.banks.a.entry_position = Vector3(.5, 0, -6)
		world.add_child(convoy)
		var truck := Car.new()
		world.add_child(truck)
		truck.position = Vector3(0, 0, 4)
		convoy.fleet.append(truck)
		var guard := GUARD.new()
		guard.convoy = convoy
		guard.configure_security(SCHEDULE.security(6))
		guard.position = Vector3(0, .08, -5)
		guard.patrol_target = truck.door_point()
		guard.cargo_carrying = true
		convoy.add_child(guard)
		guard.set_physics_process(false)
		var traffic := preload("res://scripts/Vehicle.gd").new()
		traffic.archetype = "sedan_classic"
		traffic.position = Vector3(-23 * direction, .04, 0)
		traffic.rotation.y = -PI / 2.0 * direction
		traffic.route = Curve3D.new()
		traffic.route.add_point(Vector3(-35 * direction, 0, 0))
		traffic.route.add_point(Vector3(60 * direction, 0, 0))
		traffic.route.set_meta("traffic_open", true)
		traffic.traffic = true
		traffic.speed = 5.5
		world.add_child(traffic)
		for frame in 3: await physics_frame
		var target: Vector3 = guard._service_navigation_target()
		check(not guard._service_traffic_clear(target), "approaching physical traffic conflicts with the intended crossing, direction %s" % direction)
		guard.set_physics_process(true)
		var initial_health: float = guard.health
		for frame in 30: await physics_frame
		check(guard.global_position.z < -4.8 and guard._waiting_for_traffic, "carrier waits outside the road instead of walking in front of traffic, direction %s" % direction)
		check(traffic.global_position.x * direction > -21.5, "traffic continues moving while only the carrier waits, direction %s" % direction)
		var safe_entry := true
		var entered := false
		for frame in 630:
			await physics_frame
			if not entered and guard.global_position.z > -traffic.half_width - .35:
				entered = true
				safe_entry = traffic.global_position.x * direction > traffic.half_length + .35
			if guard.reached_target(): break
		check(entered and safe_entry, "carrier enters the lane after the vehicle's rear has passed, direction %s" % direction)
		check(guard.reached_target() and guard.is_on_floor() and guard.health == initial_health and not guard.dead, "carrier resumes and physically completes the cash trip without a collision, direction %s" % direction)
		world.free()
	print("ARMORED_GUARD_TRAFFIC_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
