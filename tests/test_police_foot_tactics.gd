extends SceneTree

var failures := 0
func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures += 1

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(50.0).timeout.connect(func(): printerr("POLICE_FOOT_TACTICS TIMEOUT"); quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	await physics_frame
	var models := {}
	for index in 10:
		var officer = load("res://police/PoliceOfficer.tscn").instantiate()
		officer.set_meta("quiet_patrol", true)
		officer.set_meta("response_tier_level", 1)
		scene.add_child(officer)
		officer.set_physics_process(false)
		models[officer.appearance_model] = true
		check(officer.speed <= 125.0, "Patrol walking speed does not exceed Dante walking")
		check(officer.collision_shape.shape.radius == 5.0, "Body diversity preserves passage clearance")
		var skin := Color(officer.get_meta("police_appearance").skin)
		# The patrol's bare forearm must match its face, across every skin tone.
		var forearm: MeshInstance3D = officer.left_lower_arm.get_child(0)
		check(forearm.material_override.albedo_color.is_equal_approx(skin), "Consistent exposed skin")
		var grounded := true
		var level := true
		var cycles := 0
		var follows_travel := true
		for frame in 90:
			officer.velocity = (Vector2(112, 0) if frame < 35 else Vector2(-112, 0)) if frame < 65 else Vector2.ZERO
			officer.move_and_slide()
			var previous_phase: float = officer.walk_clock
			officer._animate_walk(1.0 / 60.0)
			if absf(officer.walk_clock - previous_phase) > PI: cycles += 1
			if frame < 65:
				var forward: Vector3 = -officer.left_upper_leg.global_basis.z
				follows_travel = follows_travel and absf(Vector2(forward.x, forward.z).normalized().dot(officer.velocity.normalized())) > .99
			var support := INF
			for leg: Node3D in [officer.left_lower_leg, officer.right_lower_leg]:
				var shoe := leg.get_node("ServiceShoe") as MeshInstance3D
				var sole: float = shoe.global_position.y - .0425 * officer.model_root.scale.y
				grounded = grounded and sole >= -.001
				support = minf(support, sole)
				level = level and absf(shoe.global_basis.orthonormalized().x.y) < .001 and absf(shoe.global_basis.orthonormalized().z.y) < .001
			grounded = grounded and support <= .001
			await physics_frame
		check(grounded and level, "Walking and stopping retain floor contact and level shoes")
		check(cycles >= 2, "Feet take repeated strides during one second of physical travel")
		check(follows_travel, "Legs follow advance and retreat independently of weapon facing")
		var combat: Node = officer.get_node("NPCCombatRig")
		var grips_fit := true
		for weapon in ["pistol", "smg", "m4a1"]:
			combat.equip(weapon)
			for frame in 80: combat.combat_pose.update(combat, 1.0 / 60.0, true, false, 0.0)
			var hand: Vector3 = combat.right_lower_arm.to_global(Vector3(0, -.20, 0))
			grips_fit = grips_fit and hand.distance_to(combat.weapon_mount_node.global_position) < .001
			if combat.POSE.SUPPORT_GRIPS.has(weapon):
				var support: Vector3 = combat.current_gun_mesh.to_global(combat.POSE.SUPPORT_GRIPS[weapon])
				grips_fit = grips_fit and support.distance_to(combat.left_lower_arm.to_global(Vector3(0, -.20, 0))) < .045
		check(grips_fit, "All issued weapons fit both hands across body types")
		officer.free()
	check(models.size() == 10, "Ten consecutive officers have distinct models")
	for stars in range(1, 7):
		var officer = load("res://police/PoliceOfficer.tscn").instantiate()
		officer.set_meta("response_tier_level", stars)
		officer.set_meta("quiet_patrol", true)
		scene.add_child(officer)
		officer.set_physics_process(false)
		check(officer.speed <= 132.0, "Rank %d keeps a human pace" % stars)
		officer.free()
	var car = root.get_node("EmergencyPool").get_vehicle("police")
	car.set_physics_process(false)
	car.position = Vector2(400, 300)
	car.rotation = 0.0
	var target := Node2D.new()
	scene.add_child(target)
	target.position = Vector2(600, 300)
	var officer = load("res://police/PoliceOfficer.tscn").instantiate()
	officer.set_meta("quiet_patrol", true)
	officer.set_meta("response_tier_level", 1)
	officer.begin_service_disembark(car, -1.0, -8.0)
	officer.position = car.to_global(Vector2(-8, -1))
	officer.local_security = true
	officer.security_alert = 2
	officer.target = target
	scene.add_child(officer)
	officer.fire_cooldown = 999.0
	var finished_exit := false
	var used_cover := false
	var max_speed := 0.0
	for frame in 420:
		await physics_frame
		max_speed = maxf(max_speed, officer.velocity.length())
		finished_exit = finished_exit or not officer.service_disembark_active
		used_cover = used_cover or (finished_exit and car._tactical_doors.has(-1.0))
	check(finished_exit, "Officer physically exits cruiser")
	check(used_cover, "Officer uses the cruiser's ballistic door")
	check(officer.car_cover_released and not car._tactical_doors.has(-1.0), "Officer leaves cover and closes its door")
	check(max_speed <= 112.1, "Exit and pursuit have no speed burst")
	officer.set_physics_process(false)
	officer.car_cover_released = false
	officer.car_cover_elapsed = 0.0
	check(not officer._use_car_cover(false, 200, .1), "Lost sight releases cover for alley search")
	# Last-known-position searches must not stop on the street 110px away.
	target.set_meta("police_search_position", true)
	officer.position = Vector2(700, 600)
	target.position = Vector2(780, 600)
	for frame in 100:
		officer._physics_process(1.0 / 60.0)
		await physics_frame
	check(officer.position.distance_to(target.position) <= 13.0, "Search reaches the last seen position inside a passage")
	car._deactivate()
	scene.queue_free()
	await process_frame
	print("POLICE_FOOT_TACTICS failures=", failures)
	quit(1 if failures else 0)
