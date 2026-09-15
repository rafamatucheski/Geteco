extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1100, 760)
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	for i in 20: await process_frame
	var player = world.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector2(1055, 2065)
	var pedestrian = load("res://AnimatedPedestrian3D.gd").new()
	world.add_child(pedestrian)
	pedestrian.set_physics_process(false)
	pedestrian.global_position = Vector2(1090, 2065)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(1005, 1960)
	camera.zoom = Vector2.ONE * 1.85
	camera.set_meta("mountain_fixed_framing", true)
	camera.make_current()
	for layer in world.find_children("", "CanvasLayer", true, false): layer.hide()
	for i in 8: await process_frame
	for car in world.get_node("PatrolParking").get_children():
		if not car is CharacterBody2D: continue
		assert(car.is_3d_vehicle and car.visual.texture is ViewportTexture)
		assert(car.lightbar_3d.lamps.size() == 2)
		print("PARKED_3D ", car.name, " model=", car.body_model.get_script().resource_path)
	print("PLAYER size=", player.viewport_3d.size, " scale=", player.sprite_3d_display.scale)
	await RenderingServer.frame_post_draw
	var suffix := "before" if OS.get_cmdline_user_args().has("--before") else "after"
	DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/patrol-side-parking-0910")
	root.get_texture().get_image().save_png("D:/geteco/artifacts/patrol-side-parking-0910/" + suffix + ".png")
	world.queue_free()
	await process_frame
	quit()
