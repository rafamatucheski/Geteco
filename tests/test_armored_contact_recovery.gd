extends "res://tests/test_armored_guard_service_path.gd"
const VEHICLE := preload("res://gameplay/dispatch/DispatchVehicle.gd")
const DRIVER := preload("res://gameplay/armored/ArmoredTrafficDriver.gd")
func _initialize() -> void:
	create_timer(75).timeout.connect(func(): check(false,"bounded physical contact recovery"); quit(3))
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("ARMORED_CONTACT ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func run() -> void:
	for scenario in ["clear","rear_blocked","limit"]:
		var rear_obstacle: bool = scenario == "rear_blocked"
		var world := World.new()
		root.add_child(world)
		current_scene = world
		world.player = Node3D.new()
		world.add_child(world.player)
		world.player.position = Vector3(40,0,40)
		world.gameplay.player = world.player
		var floor_body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var floor_shape := BoxShape3D.new()
		floor_shape.size = Vector3(100,.2,100)
		collision.shape = floor_shape
		floor_body.add_child(collision)
		floor_body.position.y = -.1
		world.add_child(floor_body)
		var car = VEHICLE.new()
		car.archetype = "winter_suv_heavy"
		car.position = Vector3(.7,.04,-1.5)
		car.rotation.y = -2.87
		car.set_meta("armored_transport",true)
		world.add_child(car)
		car.set_physics_process(false)
		var blocker = VEHICLE.new()
		blocker.archetype = "sedan_classic"
		world.add_child(blocker)
		blocker.position = Vector3(0,.001,3.0+blocker.half_length)
		blocker.rotation.y = PI
		blocker.set_physics_process(false)
		# Deixa o servidor de física publicar as transformações de spawn disjuntas antes do
		# primeiro quadro em movimento (CollisionObjects novos registram de início na origem).
		for frame in 3: await physics_frame
		# Estabelece o contato oblíquo dirigindo de verdade em linha reta. Os dois cascos
		# começam disjuntos; a fixture nunca põe um corpo dentro do bloqueador.
		car.set_external_driver(true)
		car.throttle_input = .35
		car.brake_input = false
		car.speed = 3.0
		car.horizontal_velocity = -car.global_basis.z*3.0
		car.set_physics_process(true)
		var prepared_contact := false
		for frame in 180:
			await physics_frame
			for index in car.get_slide_collision_count():
				if car.get_slide_collision(index).get_collider() == blocker: prepared_contact = true
			if prepared_contact: break
		print("ARMORED_CONTACT_SETUP ",JSON.stringify({"point":car.global_position,"blocker":blocker.global_position,"contact":prepared_contact,"sensor":car.obstacle_ahead()}))
		check(prepared_contact,"straight physical approach establishes the oblique bumper contact")
		var rear: StaticBody3D
		if rear_obstacle:
			rear = StaticBody3D.new()
			var rear_collision := CollisionShape3D.new()
			var rear_shape := BoxShape3D.new()
			rear_shape.size = Vector3(6,2,.4)
			rear_collision.shape = rear_shape
			rear.add_child(rear_collision)
			rear.rotation.y = car.rotation.y
			rear.position = car.global_position+car.global_basis.z*(car.half_length+.8)+Vector3.UP
			world.add_child(rear)
		var route := Curve3D.new()
		route.add_point(Vector3(0,0,-12))
		route.add_point(Vector3(0,0,35))
		route.set_meta("traffic_open",true)
		var driver := DRIVER.new()
		driver.setup(car,5.5,4)
		driver.disable_overtaking()
		driver.set_route(route)
		car.bypass_side = -1.0
		car.bypass_blend = 1.0
		car.bypass_start = 12.0
		driver.tick(0.0)
		if scenario == "limit": driver.contact_attempts = DRIVER.CONTACT_ATTEMPTS
		var contact_seen := false
		var reverse_seen := false
		var min_z := 0.0
		var initial_contact := Vector3.INF
		for frame in 900:
			await physics_frame
			driver.tick(1.0/60.0)
			for index in car.get_slide_collision_count():
				var hit = car.get_slide_collision(index)
				if hit.get_collider() == blocker and absf(hit.get_normal().y) < .25 and not car.blocked and car.bypass_side != 0.0:
					contact_seen = true
					if not initial_contact.is_finite(): initial_contact = car.global_position
			if initial_contact.is_finite(): min_z = minf(min_z,car.global_position.z-initial_contact.z)
			if car.speed < -.1: reverse_seen = true
			if frame == 360: print("ARMORED_CONTACT_TRACE ",JSON.stringify({"rear":rear_obstacle,"point":car.global_position,"speed":car.speed,"blocked":car.blocked,"contact":contact_seen,"attempts":driver.contact_attempts,"offset":driver.offset}))
			if scenario != "clear" and frame > 420: break
			if scenario == "clear" and car.global_position.z > 15: break
		check(contact_seen,"native bypass suppresses its blocker while actual bumper contact persists: "+scenario)
		if scenario == "limit":
			check(not reverse_seen and driver.contact_attempts == DRIVER.CONTACT_ATTEMPTS,"three consumed attempts cannot renew while the episode has no forward progress")
		elif rear_obstacle:
			check(not reverse_seen and driver.contact_attempts == 0 and min_z > -.2,"rear obstruction prevents contact-recovery reverse")
		else:
			check(reverse_seen and min_z < -.2,"native physical reverse releases oblique contact after its bounded wait")
			check(car.global_position.z > 15 and car.is_on_floor(),"physical street controller resumes and passes the stopped car")
			check(driver.contact_attempts == 0,"eight metres of real forward progress reset the recovery episode")
		world.free()
	print("ARMORED_CONTACT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
