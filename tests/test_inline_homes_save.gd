extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "inline_homes_save"
	arm_watchdog(320)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var saves: Node = root.get_node("SaveManager")
	var only: String = "keeper" if OS.get_cmdline_user_args().has("--keeper-only") else ""
	for id in ["westgate_garden","quayside_house","canal_north","keeper"]:
		if not only.is_empty() and id!=only: continue
		var player: CharacterBody2D = world.get_node("Player")
		var homes: ResidenceManager = world.get_node("ResidencePrototype")
		var house: Variant = world.get_node("Cemetery/KeeperHouse") if id=="keeper" else homes.properties[id]
		var room: Variant = house.room if id=="keeper" else homes.residence_interiors[id]
		if id!="keeper":
			player.money = 1000000
			check(bool(homes.purchase_home(id).get("affordable",false)),"Residence purchased: "+id)
		player.global_position = room.spawn_point.global_position
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		await physics_frames(14)
		check(room.contains_point(player.global_position) and not house.sprite_3d.visible,"Cutaway active before save: "+id)
		var saved_position: Vector2 = player.global_position
		var saved_money: int = player.money
		var slot: String = "inline_home_"+id
		check(saves.save_game(slot).get("success",false),"Isolated save inside: "+id)
		check(saves.load_game(slot).get("success",false),"Read isolated home save: "+id)
		change_scene_to_file("res://world/harbor/HarborGame.tscn")
		while current_scene == null or current_scene == world or not current_scene.get("gameplay_ready"): await process_frame
		await physics_frames(14)
		world = current_scene
		player = world.get_node("Player")
		homes = world.get_node("ResidencePrototype")
		house = world.get_node("Cemetery/KeeperHouse") if id=="keeper" else homes.properties[id]
		room = house.room if id=="keeper" else homes.residence_interiors[id]
		check(player.global_position.distance_to(saved_position)<2 and player.money==saved_money,"Reload preserves physical position and money: "+id)
		check(room.contains_point(player.global_position) and not house.sprite_3d.visible,"Reload restores roof cutaway: "+id)
		check(player.get_node("Camera").has_meta("compact_interior"),"Reload restores close camera: "+id)
		if id=="canal_north":
			player.global_position = Vector2(52000,20000)+room.project_floor(Vector2(0,.5))
			player.velocity = Vector2.ZERO
			await physics_frames(12)
			check(player.global_position.distance_to(room.spawn_point.global_position)<2,"Legacy off-map save coordinates migrate into physical home")
	print("INLINE HOMES SAVE: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)
