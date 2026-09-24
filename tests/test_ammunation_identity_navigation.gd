extends "res://tests/claude_gameplay_audit/AuditCommon.gd"
func _initialize() -> void: run.call_deferred()
func release_movement() -> void:
	for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
func walk_to(actor: CharacterBody2D, target: Vector2, max_frames: int = 240, tolerance: float = 10.0) -> bool:
	for i in max_frames:
		var delta := target-actor.global_position
		if delta.length()<=tolerance:
			release_movement()
			return true
		var direction := delta.normalized()
		for pair in [["move_right",direction.x],["move_left",-direction.x],["move_down",direction.y],["move_up",-direction.y]]:
			if pair[1]>.15: Input.action_press(pair[0])
			else: Input.action_release(pair[0])
		await physics_frame
		release_movement()
	return actor.global_position.distance_to(target)<=tolerance
func shot(path: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var dir := OS.get_temp_dir().path_join("geteco-ammunation-cutaway-0922")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(path+".png"))
func run() -> void:
	_tag = "ammunation_identity_navigation"
	arm_watchdog(180)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	root.size = Vector2i(1280,720)
	var player: CharacterBody2D = world.get_node("Player")
	var manager = world.get_node("Interiors")
	var room = manager.ammunation_interior
	var entrance = world.get_node("District/NorthFrontage2/AmmunationEntrance")
	var camera: Camera2D = player.get_node("Camera")
	player.global_position = entrance.get_node("OutsideReturn").global_position+Vector2(45,65)
	player.velocity = Vector2.ZERO
	camera.reset_smoothing()
	await physics_frames(10)
	check(await walk_to(player,entrance.get_node("OutsideReturn").global_position+Vector2(45,0),180,8),"Walk around street lamp on approach")
	check(await walk_to(player,entrance.get_node("OutsideReturn").global_position,180,8),"Exterior approach is physically accessible")
	await physics_frames(5)
	check(entrance.is_actor_in_range(player),"Real exterior sensor detects player")
	await shot("harbor-exterior")
	if not entrance.is_actor_in_range(player):
		quit(1)
		return
	check(await walk_to(player,room.spawn_point.global_position,180,8),"Walking through the door enters the real building")
	await physics_frames(5)
	check(room.contains_point(player.global_position) and room._occupied,"Entry stays at the exterior building")
	check(await walk_to(player,room.to_global(room.merchant_point),240,8),"Walk from spawn to gunsmith")
	await shot("interior-gameplay")
	await press_key(KEY_E)
	check(room.active and player.is_in_dialogue,"E talks to Vance and opens catalog")
	player.money = 20000
	for id in ["shotgun","grenade","armor"]:
		if id=="armor": player.armor=0
		else: player.weapon_inventory.erase(id)
		room.selection=room.stock.find(id)
		room.change_selection(0)
		var before: int = player.money
		var achievements_before: Array[String] = player.unlocked_achievements.duplicate()
		room.buy.pressed.emit()
		var achievement_cash := 0
		for achievement_id in player.unlocked_achievements:
			if achievement_id not in achievements_before:
				achievement_cash += preload("res://economy/AchievementCatalog.gd").cash_reward(achievement_id)
		var paid_balance := before-int(room._data().price)+achievement_cash
		check(player.money==paid_balance,"Charges correct price: "+id)
		check(player.armor==player.max_armor if id=="armor" else player.weapon_inventory.get(id,false),"Purchase grants: "+id)
		room.purchase()
		check(player.money==paid_balance,"Duplicate purchase prevented: "+id)
		await shot("catalog-"+id)
	room.selection=room.stock.find("grenade")
	room.change_selection(0)
	var reserve: int = player.weapon_ammo.grenade.reserve
	room.ammo_button.pressed.emit()
	check(player.weapon_ammo.grenade.reserve>reserve,"Explosive ammunition replenishment")
	player.money=0
	room.selection=room.stock.find("ak47")
	player.weapon_inventory.erase("ak47")
	room.change_selection(0)
	check(room.buy.disabled,"Insufficient funds disables purchase")
	room.selection=room.stock.find("hunting_rifle")
	room.change_selection(0)
	check(room.buy.disabled,"Discovery lock preserved")
	await press_key(KEY_ESCAPE)
	check(not room.active and not player.is_in_dialogue,"Escape closes catalog and restores movement")
	# Each wall and display must physically stop the player before its far side.
	for route in [
		[Vector2(0,.1),Vector2(0,-1.8),"counter"],
		[Vector2(-2.8,1.5),Vector2(-2.8,3.7),"south wall"],
		[Vector2(-2.5,.2),Vector2(-3.8,.2),"armor display"],
		[Vector2(2.5,.2),Vector2(3.8,.2),"explosives display"],
		[Vector2(-2.8,1.3),Vector2(-4.8,1.3),"west wall"],
		[Vector2(2.8,1.3),Vector2(4.8,1.3),"east wall"],
		[Vector2(2.8,-.4),Vector2(2.8,-2.2),"staff boundary"]
	]:
		# Start points isolate one obstacle; movement toward each uses production input.
		player.global_position=room.to_global(room.floor_point(route[0]))
		player.velocity=Vector2.ZERO
		await physics_frames(3)
		var reached := await walk_to(player,room.to_global(room.floor_point(route[1])),75,8)
		check(not reached and room.contains_point(player.global_position),"Geodata blocks "+route[2])
	player.global_position=room.spawn_point.global_position
	await physics_frames(5)
	check(await walk_to(player,entrance.get_node("OutsideReturn").global_position,160,7),"Walk back through the same door")
	await physics_frames(4)
	check(not room.contains_point(player.global_position),"Exit stays beside the original branch entrance")
	check(not player.is_in_dialogue and not camera.has_meta("compact_interior"),"Exterior controls and camera restored")
	# Build a real mountain manager and branch at an isolated test location.
	var mountain = preload("res://world/mountain_pass/MountainInteriorManager.gd").new()
	# In production these managers live in separate region transforms.
	mountain.position=Vector2(60000,0)
	world.add_child(mountain)
	while not mountain.region_ready: await process_frame
	var facade = preload("res://world/mountain_pass/MountainGunShopFacade.gd").new()
	facade.position=Vector2(48000,10000)
	world.add_child(facade)
	facade.install_entrance(mountain)
	player.set_meta("police_exterior_position",facade.global_position)
	player.global_position=facade.to_global(facade.project_floor(Vector2(0,4.5)))
	player.reset_physics_interpolation()
	camera.global_position=player.global_position
	camera.reset_smoothing()
	await physics_frames(5)
	check(await walk_to(player,facade.entrance.get_node("InteractionArea").global_position,180,8),"Mountain branch approach")
	await shot("mountain-exterior")
	room=mountain.ammunation_interior
	check(await walk_to(player,room.spawn_point.global_position,240,10),"Mountain door enters in place by walking")
	check(room.contains_point(player.global_position),"Mountain player remains in the same building")
	check(await walk_to(player,room.to_global(room.merchant_point),240,10),"Mountain circulation reaches gunsmith")
	await press_key(KEY_E)
	check(room.active and player.is_in_dialogue,"Mountain gunsmith opens same catalog")
	await press_key(KEY_ESCAPE)
	check(await walk_to(player,facade.to_global(facade.project_floor(Vector2(0,4.5))),240,8),"Mountain walk back out")
	await physics_frames(5)
	check(player.global_position.distance_to(facade.to_global(facade.project_floor(Vector2(0,4.5))))<8,"Mountain exit returns to correct branch")
	check(not player.is_in_dialogue and not camera.has_meta("compact_interior"),"Mountain camera and movement restored")
	print("AMMUNATION IDENTITY: %d passed, %d failed"%[passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)
