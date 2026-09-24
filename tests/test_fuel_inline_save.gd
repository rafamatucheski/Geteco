extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "fuel_inline_save"
	arm_watchdog(150)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var room: Node2D = world.get_node("Interiors/InteriorSpaces/FuelInterior")
	var reward: Area2D = room.get_node("RoomCash")
	var saves: Node = root.get_node("SaveManager")
	player.global_position = room.to_global(room.project_floor(Vector2(0,.45)))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(8)
	check(room.actor_inside() and not room.inline_store.roof.visible, "Player is physically inside fuel shop before saving")
	var saved_position: Vector2 = player.global_position
	var saved_money: int = player.money
	var saved: Dictionary = saves.save_game("fuel_inline")
	check(saved.get("success",false), "Isolated disk save succeeds inside fuel shop")
	var loaded: Dictionary = saves.load_game("fuel_inline")
	check(loaded.get("success",false), "Isolated disk save can be read")
	if loaded.get("success",false):
		var data: Dictionary = loaded.get("data",{})
		var coords: Array = data.get("player",{}).get("position",[])
		check(coords.size()==2 and Vector2(coords[0],coords[1]).distance_to(saved_position)<1.0, "Disk file keeps physical fuel coordinates")
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or current_scene == world or not current_scene.get("gameplay_ready"): await process_frame
	await physics_frames(8)
	world = current_scene
	player = world.get_node("Player")
	room = world.get_node("Interiors/InteriorSpaces/FuelInterior")
	print("FUEL_SAVE_DIAG saved=",saved_position," restored=",player.global_position," money=",saved_money,"/",player.money," inside=",room.actor_inside()," polygon=",room.contains_point(player.global_position)," roof=",room.inline_store.roof.visible," camera=",player.get_node("Camera").has_meta("compact_interior")," loaded=",world.loaded_from_save)
	check(player.global_position.distance_to(saved_position)<2.0 and player.money==saved_money, "Reload restores player and money in physical shop")
	check(room.actor_inside() and not room.inline_store.roof.visible, "Reload restores cutaway roof")
	check(player.get_node("Camera").has_meta("compact_interior"), "Reload restores close interior camera")
	check(room.get_node_or_null("ExitDoor")==null, "Reload does not create an off-map exit")
	print("FUEL INLINE SAVE: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)
