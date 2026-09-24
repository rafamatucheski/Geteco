extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

const FACTORY = preload("res://emergency/ModernTrafficFactory.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "inline_harbor_complexes_save"
	arm_watchdog(260)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var saves: Node = root.get_node("SaveManager")
	for id in ["maciota","fire","boss"]:
		var player: CharacterBody2D = world.get_node("Player")
		var manager: HarborInteriorManager = world.get_node("Interiors")
		var room = manager.garage_interior if id=="maciota" else (manager.fire_station_interior if id=="fire" else world.get_node("Interiors/InteriorSpaces/PortBossGarage"))
		if id=="boss": room.build_interior()
		player.global_position = room.spawn_point.global_position
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		await physics_frames(14)
		var view: Sprite2D = room.sprite_3d if id!="boss" else room.showroom.sprite_3d
		check(room.contains_point(player.global_position) and view.visible,"Physical room cutaway before save: "+id)
		var position: Vector2 = player.global_position
		var money: int = player.money
		var slot: String = "inline_complex_"+id
		check(saves.save_game(slot).get("success",false),"Disk save inside: "+id)
		check(saves.load_game(slot).get("success",false),"Read save inside: "+id)
		change_scene_to_file("res://world/harbor/HarborGame.tscn")
		while current_scene==null or current_scene==world or not current_scene.get("gameplay_ready"): await process_frame
		await physics_frames(15)
		world=current_scene
		player=world.get_node("Player")
		manager=world.get_node("Interiors")
		room=manager.garage_interior if id=="maciota" else (manager.fire_station_interior if id=="fire" else world.get_node("Interiors/InteriorSpaces/PortBossGarage"))
		view=room.sprite_3d if id!="boss" else room.showroom.sprite_3d
		check(player.global_position.distance_to(position)<3 and player.money==money,"Position and money restore: "+id)
		check(room.contains_point(player.global_position) and view.visible,"Roof cutaway restores: "+id)
		check(player.get_node("Camera").has_meta("compact_interior") and player.has_meta("interior_actor_presentation"),"Camera and actor depth restore: "+id)
	var garage = world.get_node("Interiors").garage_interior
	var player: CharacterBody2D = world.get_node("Player")
	var car: CharacterBody2D = FACTORY.spawn_parked_vehicle(world,"InlineGarageSaveCar",garage.get_vehicle_bay_position(),PI/2,"sport_coupe",0)
	player.global_position = car.global_position+Vector2(0,45)
	await physics_frames(4)
	car.enter_vehicle(player)
	await physics_frames(180)
	check(car.is_driven_by_player and garage.contains_point(car.global_position),"Driven car occupies Maciota bay")
	var car_position: Vector2 = car.global_position
	check(saves.save_game("inline_maciota_car").get("success",false),"Disk save while driving in Maciota")
	check(saves.load_game("inline_maciota_car").get("success",false),"Read driven-car save")
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene==null or current_scene==world or not current_scene.get("gameplay_ready"): await process_frame
	await physics_frames(160)
	world=current_scene
	garage=world.get_node("Interiors").garage_interior
	player=world.get_node("Player")
	car=root.get_node("RegionTravel").controlled_car() as CharacterBody2D
	check(is_instance_valid(car) and car.global_position.distance_to(car_position)<8,"Driven car position restores in physical bay")
	check(is_instance_valid(car) and garage.contains_point(car.global_position) and garage.inline_car_presentation!=null,"Vehicle depth and roof restore after reload")
	check(player.torso_node.name=="TorsoNode" and player.model_root.get_node_or_null("TorsoNode")==player.torso_node,"Reload keeps one correctly named torso rig")
	var occupant: Node = car.body_model.get_node_or_null("DanteCabinOccupant") if is_instance_valid(car) else null
	var cabin_rig: Node = occupant.get("rig") if is_instance_valid(occupant) else null
	check(is_instance_valid(cabin_rig) and cabin_rig.get_node_or_null("TorsoNode")!=null,"Driven car restores named cabin torso")
	print("INLINE HARBOR COMPLEXES SAVE: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)
