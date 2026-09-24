extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag="inline_harbor_services_save"
	arm_watchdog(190)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var saves: Node = root.get_node("SaveManager")
	for id in ["police","clinic"]:
		var player: CharacterBody2D = world.get_node("Player")
		var manager: HarborInteriorManager = world.get_node("Interiors")
		var room = manager.police_interior if id=="police" else manager.clinic_interior
		player.global_position=room.spawn_point.global_position
		player.velocity=Vector2.ZERO
		player.reset_physics_interpolation()
		await physics_frames(12)
		check(room.contains_point(player.global_position) and room.room_display.visible,"Cutaway before save: "+id)
		var saved_position: Vector2 = player.global_position
		var saved_money: int = player.money
		var slot: String = "inline_service_"+id
		check(saves.save_game(slot).get("success",false),"Isolated save: "+id)
		check(saves.load_game(slot).get("success",false),"Read isolated save: "+id)
		change_scene_to_file("res://world/harbor/HarborGame.tscn")
		while current_scene==null or current_scene==world or not current_scene.get("gameplay_ready"): await process_frame
		await physics_frames(12)
		world=current_scene
		player=world.get_node("Player")
		manager=world.get_node("Interiors")
		room=manager.police_interior if id=="police" else manager.clinic_interior
		check(player.global_position.distance_to(saved_position)<2 and player.money==saved_money,"Position and money reload inside: "+id)
		check(room.contains_point(player.global_position) and room.room_display.visible,"Cutaway restores on reload: "+id)
		check(player.get_node("Camera").has_meta("compact_interior") and player.has_meta("interior_actor_presentation"),"Camera and depth restore on reload: "+id)
	print("INLINE HARBOR SERVICES SAVE: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)
