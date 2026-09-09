extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	var scene = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(12)
	var mission = scene.campaign_controller
	var quick_review := OS.get_cmdline_user_args().has("--skip-opening-review")
	if quick_review:
		mission.skip_cinematic()
	await create_timer(1.0).timeout
	if not quick_review:
		await shot("D:/geteco/harbor-campaign-opening.png")
	# Real-time playback, no accelerated timeline or direct completion callback.
	var deadline := Time.get_ticks_msec() + 55000
	var captured_reaction := false
	while mission.phase in ["arrival", "disembark"] and Time.get_ticks_msec() < deadline:
		await process_frame
		var opening: Node = mission.get("_opening")
		if is_instance_valid(opening) and int(opening.get("_shot_index")) == 3 and not captured_reaction:
			await create_timer(1.0).timeout
			await shot("D:/geteco/harbor-campaign-opening-dialogue.png")
			captured_reaction = true
	assert(mission.phase == "phone", "Full photographic opening must reach the phone")
	print("CAMPAIGN_VISUAL arrival=phone mode=%s" % ("skip" if quick_review else "natural"))
	await frames(8)
	await shot("D:/geteco/harbor-campaign-phone.png")
	for i in 4:
		mission.advance_dialogue()
	var player = scene.get_node("Player")
	var garage = scene.get_node("Interiors").garage_interior
	player.global_position = garage.jager_npc.global_position + Vector2(0, 45)
	await frames(20)
	garage.jager_npc._open_dialogue()
	await frames(35)
	await shot("D:/geteco/harbor-campaign-maciota.png")
	# Diagnostic portrait of the actual rig, not concept art. Restore game scale.
	var npc = garage.jager_npc
	var original_size: Vector2i = npc.viewport_3d.size
	var original_scale: Vector2 = npc.sprite_3d_display.scale
	npc.viewport_3d.size = Vector2i(448, 448)
	npc.sprite_3d_display.scale = original_scale * float(original_size.x) / 448.0
	await frames(4)
	await RenderingServer.frame_post_draw
	npc.viewport_3d.get_texture().get_image().save_png("D:/geteco/maciota-refined-3d.png")
	npc.viewport_3d.size = original_size
	npc.sprite_3d_display.scale = original_scale
	for i in 4:
		garage.jager_npc._advance_dialogue()
	player.global_position = garage.mission_board.global_position + Vector2(0, 30)
	await frames(10)
	garage.mission_board.open_chalkboard()
	await frames(5)
	await shot("D:/geteco/harbor-campaign-board.png")
	scene.queue_free()
	await frames(4)
	quit()
