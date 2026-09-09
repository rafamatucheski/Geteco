extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	seed(907)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://district/harbor_preview/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await create_timer(2.0).timeout
	var player = world.get_node("Player")
	player.global_position = Vector2(740, 1250)
	player.set_physics_process(false)
	var camera: Camera2D = player.get_node("Camera")
	camera.make_current()
	camera.reset_smoothing()
	await create_timer(6.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/gameplay-review-20260907/city.png")
	var bridge = world.get_node("CobraCampaign")
	bridge.ledger.data.completed["cobra_contact"] = true
	bridge._journal.show()
	bridge._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/gameplay-review-20260907/journal.png")
	print("GAMEPLAY_REVIEW_CAPTURE complete")
	quit()
