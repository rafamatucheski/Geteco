extends "res://tests/test_armored_guard_service_path.gd"
const TRUCK := preload("res://gameplay/armored/ArmoredTruck.gd")
func _initialize() -> void:
	create_timer(210).timeout.connect(func(): check(false,"bounded physical vault approach"); quit(3))
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("ARMORED_VAULT_APPROACH ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func run() -> void:
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	for yaw in [PI*.5,-PI*.5]:
		for side in [-1.0,1.0]:
			var world := World.new()
			root.add_child(world)
			current_scene = world
			world.player = Node3D.new()
			world.player.position = Vector3(25,0,25)
			world.add_child(world.player)
			world.gameplay.player = world.player
			var floor_body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(60,.2,60)
			shape.shape = box
			floor_body.add_child(shape)
			floor_body.position.y = -.1
			world.add_child(floor_body)
			var convoy := Convoy.new()
			convoy.session = {"world":world,"state":State.new()}
			convoy.data.phase = "unloading"
			convoy.banks.b.entry_position = Vector3(-4,0,-10)
			if baseline: convoy.banks.b.entry_position = Vector3(-13.54,0,-29.35)
			world.add_child(convoy)
			var truck := TRUCK.new()
			truck.rotation.y = yaw
			truck.position.y = .02
			world.add_child(truck)
			truck.set_physics_process(false)
			convoy.fleet.append(truck)
			var guard := GUARD.new()
			guard.convoy = convoy
			guard.slot = 0
			guard.configure_security(SCHEDULE.security(0))
			guard.position = truck.to_global(Vector3(side*(truck.half_width+1.05),.08,.5))
			var post := guard.position
			var bank: Vector3 = convoy.banks.b.entry_position+Vector3(-.5,.08,1)
			guard.patrol_target = bank if baseline else truck.door_point()
			convoy.add_child(guard)
			var picked_up := baseline
			var reached_bank := false
			var reached_post := false
			var contact_seen := false
			for frame in 2400:
				await physics_frame
				for index in guard.get_slide_collision_count():
					if guard.get_slide_collision(index).get_collider() == truck: contact_seen = true
				if guard.reached_target(.45):
					if not picked_up:
						picked_up = true
						guard.patrol_target = bank
					elif not reached_bank:
						reached_bank = true
						guard.patrol_target = post
					else:
						reached_post = true
						break
				if baseline and frame > 720: break
			print("ARMORED_VAULT_POSE ",JSON.stringify({"yaw":yaw,"side":side,"point":guard.position,"pickup":picked_up,"bank":reached_bank,"post":reached_post,"contact":contact_seen}))
			if baseline:
				check(contact_seen and not reached_bank and guard.position.distance_to(truck.position) < 6.0,"direct bank assignment reproduces persistent truck corner obstruction")
			else:
				check(picked_up and reached_bank and reached_post,"carrier reaches vault, bank and returns to post around real hull in orientation/side %s/%s" % [yaw,side])
				check(guard.health == 110 and not guard.dead,"carrier retains physical health")
			world.free()
			await physics_frame
			if baseline: break
		if baseline: break
	print("ARMORED_VAULT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
