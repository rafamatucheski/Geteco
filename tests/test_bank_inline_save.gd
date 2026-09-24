extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "bank_inline_save"
	arm_watchdog(170)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var room: Node2D = world.get_node("Interiors/InteriorSpaces/BankInterior")
	var building: Node2D = world.get_node("District/NorthFrontage0")
	var saves: Node = root.get_node("SaveManager")
	player.global_position = room.to_global(room.project_floor(Vector2(0,2.2)))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(8)
	check(room._inline_occupied and player.get_meta("harbor_interior",false), "Player occupies the physical bank before saving")
	var saved_position: Vector2 = player.global_position
	var saved_money: int = player.money
	var saved: Dictionary = saves.save_game("bank_inline")
	check(saved.get("success",false), "Bank save writes to isolated disk")
	var loaded: Dictionary = saves.load_game("bank_inline")
	check(loaded.get("success",false), "Bank save reads from isolated disk")
	if loaded.get("success",false):
		var coords: Array = loaded.get("data",{}).get("player",{}).get("position",[])
		check(coords.size()==2 and Vector2(coords[0],coords[1]).distance_to(saved_position)<1.0,"Save stores the real bank coordinates")
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or current_scene == world or not current_scene.get("gameplay_ready"): await process_frame
	await physics_frames(8)
	world = current_scene
	player = world.get_node("Player")
	room = world.get_node("Interiors/InteriorSpaces/BankInterior")
	building = world.get_node("District/NorthFrontage0")
	check(world.loaded_from_save and player.global_position.distance_to(saved_position)<2.0 and player.money==saved_money,"Reload keeps player inside the physical bank")
	check(room._inline_occupied and building.get_meta("bank_inline_occupied",false),"Reload restores the roof cutaway")
	check(player.get_node("Camera").has_meta("compact_interior"),"Reload restores the close camera")
	check(room.exit_door==null and world.get_node("Interiors")._door_configs.has("District/NorthFrontage0/RobberyEntrance")==false,"Reload creates no teleport exit")
	print("BANK INLINE SAVE: %d passed, %d failed" % [passed_count, failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)
