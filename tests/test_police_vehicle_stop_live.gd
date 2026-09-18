extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 35: await process_frame
	while not current_scene.gameplay_ready: await process_frame
	var player = current_scene.get_node("Player")
	var car = current_scene.get_node("PersonalCarManager").car
	car.global_position = Vector2(4500,-950)
	car.rotation = 0
	player.global_position = car.global_position + Vector2(0,-45)
	car.enter_vehicle(player)
	await create_timer(2).timeout
	var wanted = root.get_node("WantedManager")
	wanted.current_stars = 1
	# Keep this fixture to one real cruiser, without automatic reinforcement.
	wanted.set_process(false)
	var cruiser = root.get_node("EmergencyPool").get_vehicle("police")
	cruiser.global_position = car.global_position + Vector2(-105,-65)
	cruiser.target = car
	cruiser.set_meta("police_player_pursuit",true)
	cruiser.is_returning_to_base = false
	cruiser.is_acting = false
	cruiser.officer_deployed = false
	var deadline := Time.get_ticks_msec() + 15000
	var stop_officer: CharacterBody2D = null
	while not is_instance_valid(stop_officer) and Time.get_ticks_msec() < deadline:
		for crew in get_nodes_in_group("police_officer"):
			if crew.vehicle_stop.phase == "command": stop_officer = crew
		await physics_frame
	check(cruiser.deployed_officers > 0, "Crew deploys for seated stationary suspect")
	check(is_instance_valid(stop_officer), "Officer reaches the door and orders voluntary exit")
	if not is_instance_valid(stop_officer):
		quit(1)
		return
	await create_timer(6).timeout
	check(car.is_driven_by_player and not player.is_arrested, "Waiting inside never forces extraction or arrest")
	check(stop_officer.is_police_aiming(), "One-star officer keeps weapon aimed during the order")
	check(absf(stop_officer.get_node("NPCCombatRig").combat_pose._carry_pitch) < 0.05, "Combat rig raises the weapon into its actual aiming pose")
	var toward: Vector2 = stop_officer.global_position.direction_to(car.global_position)
	check(absf(angle_difference(stop_officer.model_root.rotation.y, -atan2(toward.y, toward.x) - PI * 0.5)) < 0.15, "Officer faces the driver while waiting")
	check(stop_officer.response_aggression == 0.0 and stop_officer.fire_cooldown == 0.0, "Order does not open fire on a passive driver")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/police-surrender-live-0911.png")
	car.exit_vehicle()
	while car.get_meta("vehicle_boarding", false): await physics_frame
	await physics_frame
	check(player.is_physics_processing() and not player.is_control_disabled and not player.is_arrested, "Voluntary exit leaves movement and weapons available")
	player._respawn_grace_active = true
	player.weapon_inventory["pistol"] = true
	player.weapon_ammo["pistol"] = {"clip": 12, "reserve": 24}
	player.equip_weapon("pistol")
	player._shoot_towards(player.global_position + Vector2(0, -300))
	await create_timer(0.4).timeout
	check(player.weapon_ammo["pistol"]["clip"] == 11, "Player can actually fire after stepping out")
	check(stop_officer.response_aggression > 0.0 and not player.is_arrested, "Firing interrupts surrender and triggers armed resistance")
	wanted.dismiss_all_police()
	# Positive contact: walking into the parked cruiser must not move it.
	cruiser = root.get_node("EmergencyPool").get_vehicle("police")
	cruiser.set_physics_process(false)
	cruiser.get_node("CollisionShape2D").disabled = false
	cruiser.collision_layer = 2
	cruiser.global_position = Vector2(4500,-700)
	cruiser.velocity = Vector2.ZERO
	var before: Vector2 = cruiser.global_position
	var walker := CharacterBody2D.new()
	walker.collision_layer = 4
	walker.collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8
	shape.shape = circle
	walker.add_child(shape)
	current_scene.add_child(walker)
	walker.global_position = before + Vector2(0,-30)
	await physics_frame
	for i in 120:
		walker.velocity = Vector2(0,100)
		walker.move_and_slide()
		preload("res://cars/VehicleMotionSafety.gd").move(cruiser)
		await physics_frame
	check(cruiser.global_position.distance_to(before) < 0.1, "Pedestrian contact does not push stationary cruiser")
	check(walker.global_position.y < before.y, "Pedestrian still blocked by cruiser")
	await create_timer(4).timeout
	car.global_position = Vector2(4500,-950)
	player.global_position = car.global_position + Vector2(0,-45)
	car.enter_vehicle(player)
	await create_timer(2).timeout
	wanted.current_stars = 1
	var officer = load("res://police/PoliceOfficer.tscn").instantiate()
	current_scene.add_child(officer)
	officer.set_physics_process(false)
	officer.global_position = car.global_position + Vector2(0,-55)
	officer.target = car
	car.set_physics_process(false)
	car.velocity = Vector2(100,0)
	for i in 30: officer.vehicle_stop.approach(officer,car,0.1)
	check(officer.vehicle_stop.phase == "idle" and car.is_driven_by_player, "Moving driver cannot be extracted")
	car.velocity = Vector2.ZERO
	for i in 16: officer.vehicle_stop.approach(officer,car,0.1)
	check(officer.vehicle_stop.phase == "command", "Stationary driver receives an exit order")
	car.velocity = Vector2(100,0)
	officer.vehicle_stop.tick(officer,0.1)
	check(officer.vehicle_stop.phase == "idle" and not car.has_meta("police_stop_owner") and car.is_driven_by_player, "Driving away cancels the stop and releases its owner")
	car.velocity = Vector2.ZERO
	var wall := StaticBody2D.new()
	var wall_col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40,4)
	wall_col.shape = rect
	wall.add_child(wall_col)
	current_scene.add_child(wall)
	wall.global_position = car.global_position + Vector2(0,-50)
	await physics_frame
	check(not officer.vehicle_stop.corridor_clear(officer, car, car.global_position + Vector2(0,-45)), "Wall prevents door interaction")
	wall.queue_free()
	await physics_frame
	car.exit_vehicle()
	while car.get_meta("vehicle_boarding", false): await physics_frame
	check(not player.is_arrested and not player.is_control_disabled, "A second voluntary exit still allows a surrender choice")
	officer.set_physics_process(true)
	var foot_deadline := Time.get_ticks_msec() + 9000
	while not player.is_arrested and Time.get_ticks_msec() < foot_deadline: await physics_frame
	check(player.is_arrested, "Voluntary exit retargets the driver and arrests without an attack")
	await create_timer(4).timeout
	var station := current_scene.get_node("District/Police/Entrance/OutsideReturn") as Node2D
	check(player.global_position.distance_to(station.global_position) < 30.0, "Surrender respawns at the police station")
	check(not player.is_arrested and not player.is_recovering and not player.is_control_disabled and player.is_physics_processing(), "Station return restores player control")
	print("POLICE VEHICLE STOP LIVE: ",failures)
	quit(0 if failures.is_empty() else 1)
